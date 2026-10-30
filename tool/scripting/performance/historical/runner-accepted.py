"""Run already-built macOS release apps against one loopback HTTP fixture.

Every process uses its own Hive directory. Results include raw samples; nearest
rank p95 and repeated-batch alerts never silently discard outliers or failures.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import http.server
import json
import math
import os
from pathlib import Path
import platform
import queue
import secrets
import statistics
import subprocess
import tempfile
import threading
import time

from foreground import activate_pid


def validate_samples(values, count):
    if len(values) != count or any(type(v) is not int or v < 0 for v in values):
        raise ValueError(f'Expected {count} nonnegative integer samples')


def summarize(values):
    validate_samples(values, len(values))
    if not values:
        raise ValueError('Empty samples')
    ordered = sorted(values)
    return {'samples': len(values), 'median_us': statistics.median(ordered),
            'p95_us': ordered[math.ceil(len(ordered) * .95) - 1],
            'min_us': ordered[0], 'max_us': ordered[-1]}


def regression(before, after):
    if len(before) != 2 or len(after) != 2:
        raise ValueError('Two independent batches are required')
    ratios = []
    for baseline, current in zip(before, after):
        if len(baseline) < 30 or len(current) < 30:
            raise ValueError('At least 30 samples per batch are required')
        old, new = summarize(baseline)['p95_us'], summarize(current)['p95_us']
        if old <= 0:
            raise ValueError('Baseline p95 must be positive')
        ratios.append(new / old)
    exceeded = [ratio > 1.1 for ratio in ratios]
    status = ('investigate_regression' if all(exceeded) else
              'repeat_inconsistent' if any(exceeded) else 'within_threshold')
    return {'status': status, 'threshold_percent': 10,
            'p95_change_percent': [(r - 1) * 100 for r in ratios]}


def validate_report(report, mode, received):
    validate_samples(report['no_script_us'], 30)
    expected = {'plain': 40, 'script': 571, 'script_cold': 41}[mode]
    if report['warmup_count'] != 10 or report['http_requests'] != expected or received != expected:
        raise ValueError(f'HTTP count mismatch: expected {expected}, received {received}')
    if mode == 'script_cold':
        validate_samples([report['script_first_us']], 1)
        if 'native_before' in report or report['native_after'] != {'controls': 0, 'runtimes': 0}:
            raise ValueError('Cold script must omit the early probe and release all native ownership')
    if mode == 'script':
        validate_samples([report['script_first_us']], 1)
        validate_samples(report['script_warm_us'], 500)
        for key in ('native_before', 'native_after'):
            if report[key] != {'controls': 0, 'runtimes': 0}:
                raise ValueError(f'Native ownership not empty: {key}={report[key]}')
        if report['script_warmup_count'] != 30:
            raise ValueError('Expected 30 script warmups')
        checkpoints = report['ownership_after_each_100']
        if [v['send'] for v in checkpoints] != [100, 200, 300, 400, 500]:
            raise ValueError('Missing ownership checkpoints')
        if any(v['controls'] != 0 or v['runtimes'] != 0 for v in checkpoints):
            raise ValueError('Native ownership retained between sends')


class Fixture(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path != '/echo/' + self.server.token:
            self.send_error(404)
            return
        self.server.received += 1
        expected_header = '42' if self.server.mode.startswith('script') and self.server.received > 40 else None
        if self.headers.get('X-Answer') != expected_header:
            self.send_error(422, 'Pre-request script header missing, unexpected or incorrect')
            return
        body = b'{"ok":true,"answer":42}'
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def read_body(self):
        if self.headers.get('Transfer-Encoding', '').lower() != 'chunked':
            return self.rfile.read(int(self.headers['Content-Length']))
        body = bytearray()
        while True:
            size = int(self.rfile.readline().split(b';', 1)[0].strip(), 16)
            if size == 0:
                while self.rfile.readline() not in (b'\r\n', b''):
                    pass
                return bytes(body)
            if size < 0 or len(body) + size > 1024 * 1024:
                raise ValueError('Telemetry exceeds 1 MiB')
            body.extend(self.rfile.read(size))
            if self.rfile.read(2) != b'\r\n':
                raise ValueError('Invalid chunk delimiter')

    def do_POST(self):
        if self.path != '/report/' + self.server.token:
            self.send_error(404)
            return
        payload = json.loads(self.read_body())
        self.server.reports.put((time.perf_counter_ns(), payload))
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()


def app_metadata(executable):
    app = Path(executable).resolve().parents[2]
    files = [p for p in app.rglob('*') if p.is_file() and not p.is_symlink()]
    aot = app / 'Contents/Frameworks/App.framework/Versions/A/App'
    return {'dart_aot_sha256': hashlib.sha256(aot.read_bytes()).hexdigest(), 'executable': str(Path(executable).resolve()),
            'bundle_bytes': sum(p.stat().st_size for p in files),
            'executable_sha256': hashlib.sha256(Path(executable).read_bytes()).hexdigest()}


def sample(server, executable, mode, log_path):
    server.token = secrets.token_hex(16)
    server.received = 0
    server.mode = mode
    env = dict(os.environ, GETMAN_BENCH_URL=f'http://127.0.0.1:{server.server_port}',
               GETMAN_BENCH_TOKEN=server.token, GETMAN_BENCH_MODE=mode)
    started = time.perf_counter_ns()
    with open(log_path, 'wb') as log:
        process = subprocess.Popen([executable], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            stamp, first = server.reports.get(timeout=90)
            if first.get('event') != 'first_frame':
                raise ValueError(f'Expected first frame, got {first}')
            if not activate_pid(process.pid):
                raise ValueError(f'Unable to activate benchmark PID {process.pid}')
            _, report = server.reports.get(timeout=120)
            if 'error' in report:
                raise ValueError(report['error'])
            process.wait(timeout=30)
            if process.returncode != 0:
                raise ValueError(f'Application exited {process.returncode}; see {log_path}')
            validate_report(report, mode, server.received)
            return {**report, 'foreground_activation_confirmed': True, 'dart_main_to_first_raster_us': first['elapsed_us'],
                    'host_launch_to_first_frame_report_us': (stamp-started)//1000}
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--current', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--baseline-revision', required=True)
    parser.add_argument('--current-revision', required=True)
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Fixture)
    server.daemon_threads = True
    server.reports = queue.Queue()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    logs = Path(tempfile.mkdtemp(prefix='getman-performance-logs-'))
    harness_hash = hashlib.sha256()
    for name in ('runner.py', 'prepare.py', 'app.dart.template', 'foreground.py'):
        harness_hash.update(name.encode())
        harness_hash.update(Path(__file__).with_name(name).read_bytes())
    result = {'harness_sha256': harness_hash.hexdigest(), 'started_at_utc': datetime.now(timezone.utc).isoformat(), 'environment': {'platform': platform.platform(), 'machine': platform.machine()},
              'metric': 'Fresh process, isolated empty Hive; Dart main to first rasterized frame. '
                        'Host launch metric additionally includes telemetry transport. '
                        'HTTP is TabsBloc SEND through Dio and history to loopback JSON.',
              'build_mode': 'release', 'activation': 'AppKit exact child PID after first-frame telemetry', 'boot_warmups_per_revision': 3,
              'http_warmups_per_process': 10, 'logs': str(logs),
              'baseline_revision': args.baseline_revision, 'current_revision': args.current_revision,
              'artifacts': {key: app_metadata(getattr(args, key)) for key in ('baseline', 'current')},
              'batches': []}
    try:
        for i in range(3):
            for key in ('baseline', 'current'):
                sample(server, getattr(args, key), 'plain', logs / f'warmup-{key}-{i}.log')
        for batch_id in range(2):
            batch = {'baseline': [], 'current': []}
            result['batches'].append(batch)
            for i in range(30):
                order = ('baseline', 'current') if (i + batch_id) % 2 == 0 else ('current', 'baseline')
                for key in order:
                    batch[key].append(sample(server, getattr(args, key), 'plain', logs / f'{batch_id}-{i}-{key}.log'))
                output.write_text(json.dumps(result, indent=2) + '\n')
                print(f'batch {batch_id+1}/2 pair {i+1}/30', flush=True)
        result['scripted'] = sample(server, args.current, 'script', logs / 'scripted.log')
        result['script_cold_first'] = sample(server, args.current, 'script_cold', logs / 'script-cold-first.log')
        result['summary'] = {}
        for metric in ('dart_main_to_first_raster_us', 'host_launch_to_first_frame_report_us', 'no_script_us'):
            samples = {}
            for key in ('baseline', 'current'):
                samples[key] = [([value for run in batch[key] for value in run[metric]]
                                 if metric == 'no_script_us' else [run[metric] for run in batch[key]])
                                for batch in result['batches']]
            result['summary'][metric] = {key: [summarize(v) for v in samples[key]] for key in samples}
            result['summary'][metric]['comparison'] = regression(samples['baseline'], samples['current'])
        result['summary']['script_warm'] = summarize(result['scripted']['script_warm_us'])
        result['completed_at_utc'] = datetime.now(timezone.utc).isoformat()
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result['summary'], indent=2), flush=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()

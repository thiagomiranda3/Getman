"""Fresh-process release measurements; all reports checkpointed, no outlier removal."""
import argparse
import hashlib
import http.server
import json
import os
from pathlib import Path
import platform
import queue
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripting' / 'performance'))
from foreground import activate_pid
from runner import Fixture, app_metadata


class Reports(Fixture):
    def do_GET(self):
        name = self.path.removeprefix('/')
        if name not in ('client.pem', 'client.key'):
            self.send_error(404)
            return
        body = (self.server.credentials / name).read_bytes()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        value = json.loads(self.read_body())
        self.server.reports.put((time.perf_counter_ns(), value))
        self.send_response(204)
        self.send_header('Content-Length', '0')
        self.end_headers()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('executable')
    parser.add_argument('output')
    parser.add_argument('--runs', type=int, default=10)
    parser.add_argument('--revision', required=True)
    parser.add_argument('--counts', type=int, nargs='+', default=[0, 500])
    parser.add_argument('--skip-workloads', action='store_true')
    parser.add_argument('--baseline')
    parser.add_argument('--sample-editors', action='store_true')
    args = parser.parse_args()
    output = Path(args.output)
    result = {'revision': args.revision, 'machine': platform.platform(),
              'app': app_metadata(args.executable), 'runs': [],
              'scope': 'release; warm filesystem; synthetic data; real shell; loopback telemetry'}
    if args.baseline:
        result['baseline_app'] = app_metadata(args.baseline)
    result['harness_sha256'] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                for p in (Path(__file__), Path(__file__).with_name('app.dart'))}
    logs = Path(tempfile.mkdtemp(prefix='getman-perf-logs-'))
    repo = Path(__file__).resolve().parents[2]
    result['source_sha256'] = {str(p.relative_to(repo)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((repo / 'lib').rglob('*.dart'))}
    result['logs'] = str(logs)
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Reports)
    server.reports = queue.Queue()
    server.credentials = logs
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                    '-keyout', str(logs / 'client.key'), '-out', str(logs / 'client.pem'),
                    '-days', '1', '-subj', '/CN=getman-synthetic-benchmark'],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    threading.Thread(target=server.serve_forever, daemon=True).start()

    def checkpoint():
        output.write_text(json.dumps(result, indent=2))

    def launch(mode, executable=None, **variables):
        executable = executable or args.executable
        record = {'mode': mode, 'executable': executable, 'variables': variables, 'reports': []}
        result['runs'].append(record)
        checkpoint()
        env = dict(os.environ, GETMAN_PERF_URL=f'http://127.0.0.1:{server.server_port}', GETMAN_PERF_MODE=mode)
        env.update({f'GETMAN_PERF_{k}': str(v) for k, v in variables.items()})
        start = time.perf_counter_ns()
        with (logs / f'{len(result["runs"])}-{mode}.log').open('wb') as log:
            proc = subprocess.Popen([executable], env=env, stdout=log, stderr=log)
            try:
                while True:
                    stamp, report = server.reports.get(timeout=120)
                    report['host_elapsed_us'] = (stamp - start) // 1000
                    record['reports'].append(report)
                    checkpoint()
                    if args.sample_editors and report.get('name') == 'mtls_configure' and sum(p.get('name') == 'mtls_configure' for p in record['reports']) == 5:
                        def diagnostic():
                            time.sleep(2)
                            subprocess.run(['sample', str(proc.pid), '5', '-file', str(logs / 'editor-stacks.txt')], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        threading.Thread(target=diagnostic, daemon=True).start()
                    if report['event'] == 'error':
                        raise RuntimeError(report['error'])
                    if report['event'] == 'first_frame':
                        # Raster telemetry can precede AppKit launch readiness.
                        # Retry the activation request itself, not just isActive.
                        record['foreground'] = False
                        for attempt in range(5):
                            if activate_pid(proc.pid, timeout=.15):
                                record['foreground'] = True
                                break
                            time.sleep(.05)
                        record['foreground_attempts'] = attempt + 1
                        if not record['foreground']:
                            raise RuntimeError('Could not foreground measured process')
                    if report['event'] in ('seed', 'done', 'cleanup'):
                        break
                if proc.wait(timeout=15):
                    raise RuntimeError('App failed')
                record['complete'] = True
                checkpoint()
                return record
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
    try:
        for count in args.counts:
            seeded = launch('seed', TABS=count)
            root = seeded['reports'][0]['directory']
            for i in range(args.runs):
                variants = [args.baseline, args.executable] if args.baseline else [args.executable]
                for executable in (variants if i % 2 == 0 else variants[::-1]):
                    launch('startup', executable=executable, STORAGE=root, TABS=count, SAMPLE=i)
            if count == 0 and not args.skip_workloads:
                launch('workloads', STORAGE=root)
            launch('cleanup', STORAGE=root)
        result['complete'] = True
        checkpoint()
    except BaseException as error:
        result['failure'] = repr(error)
        checkpoint()
        raise
    finally:
        server.shutdown()


if __name__ == '__main__':
    main()

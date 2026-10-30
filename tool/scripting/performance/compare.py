"""Small causal A/B: six alternating app pairs before the full regression gate.

Uses the unchanged release harness and HTTP fixture, preserving every sample.
This isolates one source change; the standard runner remains the final gate.
"""
import argparse
from datetime import datetime, timezone
import http.server
import json
from pathlib import Path
import queue
import tempfile
import threading

import runner


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--before', required=True)
    parser.add_argument('--after', required=True)
    parser.add_argument('--change-sha256', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), runner.Fixture)
    server.daemon_threads = True
    server.reports = queue.Queue()
    threading.Thread(target=server.serve_forever, daemon=True).start()
    logs = Path(tempfile.mkdtemp(prefix='getman-response-controller-ab-'))
    result = {'started_at_utc': datetime.now(timezone.utc).isoformat(), 'change_sha256': args.change_sha256, 'warmup_processes_per_variant': 3,
              'logs': str(logs), 'before': [], 'after': [], 'artifacts': {}}
    output = Path(args.output)
    try:
        for key in ('before', 'after'):
            executable = getattr(args, key)
            artifact = runner.app_metadata(executable)
            result['artifacts'][key] = artifact
        for i in range(3):
            for key in ('before', 'after'):
                runner.sample(server, getattr(args, key), 'plain', logs / f'warmup-{key}-{i}.log')
        for i in range(6):
            order = ('before', 'after') if i % 2 == 0 else ('after', 'before')
            for key in order:
                result[key].append(runner.sample(server, getattr(args, key), 'plain', logs / f'{i}-{key}.log'))
                output.write_text(json.dumps(result, indent=2) + '\n')
        result['summary'] = {key: runner.summarize([value for sample in result[key]
                                                   for value in sample['no_script_us']])
                             for key in ('before', 'after')}
        result['completed_at_utc'] = datetime.now(timezone.utc).isoformat()
        output.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result['summary'], indent=2), flush=True)
    finally:
        server.shutdown()
        server.server_close()


if __name__ == '__main__':
    main()

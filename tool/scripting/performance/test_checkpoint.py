"""Persist successful telemetry even when the next application sample fails.

Application launches are replaced at their boundary: these tests exercise the
real collection loops and JSON writes without Flutter, GUI apps or HTTP ports.
"""
from contextlib import ExitStack, redirect_stdout
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import compare
import runner


class CheckpointTest(unittest.TestCase):
    def run_until_failure(self, module, failure_log):
        temporary = tempfile.TemporaryDirectory(prefix='getman-checkpoint-test-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        output = root / 'result.json'
        if module is runner:
            arguments = ['runner.py', '--baseline', 'synthetic-before',
                         '--current', 'synthetic-after', '--baseline-revision', 'before',
                         '--current-revision', 'after', '--output', str(output)]
        else:
            arguments = ['compare.py', '--before', 'synthetic-before',
                         '--after', 'synthetic-after', '--change-sha256', 'synthetic-change',
                         '--output', str(output)]

        def application_sample(_server, _executable, mode, log_path):
            name = Path(log_path).name
            if name == failure_log:
                raise RuntimeError('synthetic second application failure')
            report = {'synthetic_sample': name, 'no_script_us': [123] * 30,
                      'dart_main_to_first_raster_us': 111,
                      'host_launch_to_first_frame_report_us': 222}
            if mode == 'script':
                report['script_warm_us'] = [333] * 500
            return report

        with ExitStack() as stack:
            stack.enter_context(patch('sys.argv', arguments))
            stack.enter_context(patch.object(runner, 'sample', application_sample))
            stack.enter_context(patch.object(runner, 'app_metadata', return_value={'synthetic': True}))
            stack.enter_context(patch.object(module.http.server, 'ThreadingHTTPServer'))
            stack.enter_context(patch.object(module.threading, 'Thread'))
            stack.enter_context(patch.object(module.tempfile, 'mkdtemp', return_value=str(root)))
            stack.enter_context(redirect_stdout(io.StringIO()))
            with self.assertRaisesRegex(RuntimeError, 'second application failure'):
                module.main()
        self.assertTrue(output.exists(), 'The first successful sample must survive the next failure')
        return json.loads(output.read_text())

    def test_runner_preserves_first_process_when_second_in_pair_fails(self):
        data = self.run_until_failure(runner, '0-0-current.log')
        self.assertEqual(len(data['batches']), 1)
        self.assertEqual(data['batches'][0]['baseline'][0]['synthetic_sample'], '0-0-baseline.log')
        self.assertEqual(data['batches'][0]['baseline'][0]['no_script_us'], [123] * 30)
        self.assertEqual(data['batches'][0]['current'], [])
        self.assertNotIn('summary', data)
        self.assertNotIn('completed_at_utc', data)

    def test_compare_preserves_first_process_when_second_in_pair_fails(self):
        data = self.run_until_failure(compare, '0-after.log')
        self.assertEqual(data['before'][0]['synthetic_sample'], '0-before.log')
        self.assertEqual(data['before'][0]['no_script_us'], [123] * 30)
        self.assertEqual(data['after'], [])
        self.assertNotIn('summary', data)
        self.assertNotIn('completed_at_utc', data)

    def test_runner_preserves_500_script_sends_when_cold_script_process_fails(self):
        data = self.run_until_failure(runner, 'script-cold-first.log')
        self.assertEqual([len(batch['baseline']) for batch in data['batches']], [30, 30])
        self.assertEqual([len(batch['current']) for batch in data['batches']], [30, 30])
        self.assertTrue('scripted' in data, 'The completed 500-send report must be checkpointed before the cold run')
        self.assertEqual(data['scripted']['synthetic_sample'], 'scripted.log')
        self.assertEqual(data['scripted']['script_warm_us'], [333] * 500)
        self.assertNotIn('script_cold_first', data)
        self.assertNotIn('summary', data)
        self.assertNotIn('completed_at_utc', data)


if __name__ == '__main__':
    unittest.main()

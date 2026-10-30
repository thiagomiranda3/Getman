"""Tests reject misleading percentiles, incomplete samples and failed HTTP runs."""
import unittest
import runner


class StatisticsTest(unittest.TestCase):
    def test_nearest_rank_p95_and_even_median(self):
        result = runner.summarize(list(range(30, 0, -1)))
        self.assertEqual(result['p95_us'], 29)
        self.assertEqual(result['median_us'], 15.5)
        self.assertEqual(result['samples'], 30)

    def test_repeated_regression_requires_both_batches(self):
        baseline = [100] * 30
        self.assertEqual(runner.regression([baseline, baseline], [[111]*30, [109]*30])['status'], 'repeat_inconsistent')
        self.assertEqual(runner.regression([baseline, baseline], [[111]*30, [120]*30])['status'], 'investigate_regression')
        self.assertEqual(runner.regression([baseline, baseline], [[110]*30, [110]*30])['status'], 'within_threshold')

    def test_incomplete_or_invalid_samples_are_not_accepted(self):
        for values in ([], [1] * 29, [1] * 29 + [-1], [1] * 29 + [True]):
            with self.subTest(values=values), self.assertRaises(ValueError):
                runner.validate_samples(values, 30)

    def test_http_count_and_script_handles_must_match(self):
        report = {'no_script_us': [1] * 30, 'warmup_count': 10, 'http_requests': 40}
        runner.validate_report(report, 'plain', 40)
        with self.assertRaises(ValueError):
            runner.validate_report(report, 'plain', 39)
        scripted = {'no_script_us': [1] * 30, 'warmup_count': 10, 'http_requests': 571,
                    'script_first_us': 1, 'script_warm_us': [1] * 500,
                    'native_before': {'controls': 0, 'runtimes': 0},
                    'native_after': {'controls': 0, 'runtimes': 1}}
        with self.assertRaises(ValueError):
            runner.validate_report(scripted, 'script', 571)
    def test_unprobed_first_script_is_distinct_from_500_send_run(self):
        report = {'no_script_us': [1] * 30, 'warmup_count': 10, 'http_requests': 41,
                  'script_first_us': 5, 'native_after': {'controls': 0, 'runtimes': 0}}
        runner.validate_report(report, 'script_cold', 41)
        report['native_before'] = {'controls': 0, 'runtimes': 0}
        with self.assertRaises(ValueError):
            runner.validate_report(report, 'script_cold', 41)

    def test_repeated_native_handle_growth_is_rejected(self):
        report = {'no_script_us': [1] * 30, 'warmup_count': 10, 'http_requests': 571,
                  'script_first_us': 1, 'script_warm_us': [1] * 500,
                  'script_warmup_count': 30,
                  'native_before': {'controls': 0, 'runtimes': 0},
                  'native_after': {'controls': 0, 'runtimes': 0},
                  'ownership_after_each_100': [
                      {'send': i, 'rss': 1000, 'controls': 0, 'runtimes': 0}
                      for i in range(100, 501, 100)]}
        runner.validate_report(report, 'script', 571)
        report['ownership_after_each_100'][2]['controls'] = 1
        with self.assertRaises(ValueError):
            runner.validate_report(report, 'script', 571)


class FixtureTest(unittest.TestCase):
    def test_fixture_counts_only_authenticated_http_and_receives_reports(self):
        import http.server
        import json
        import queue
        import threading
        import urllib.error
        import urllib.request
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), runner.Fixture)
        server.daemon_threads = True
        server.token = 'synthetic-test'
        server.received = 0
        server.mode = 'plain'
        server.reports = queue.Queue()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}'
        try:
            with urllib.request.urlopen(url + '/echo/synthetic-test') as response:
                self.assertEqual(json.load(response), {'ok': True, 'answer': 42})
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(url + '/echo/wrong-token')
            rejected.exception.close()
            self.assertEqual(server.received, 1)
            request = urllib.request.Request(url + '/report/synthetic-test',
                data=b'{"event":"first_frame","elapsed_us":123}', method='POST')
            with urllib.request.urlopen(request) as response:
                self.assertEqual(response.status, 204)
            _, report = server.reports.get(timeout=1)
            self.assertEqual(report, {'event': 'first_frame', 'elapsed_us': 123})
        finally:
            server.shutdown()
            server.server_close()


    def test_dart_chunked_telemetry_is_accepted(self):
        import http.client
        import http.server
        import queue
        import threading
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), runner.Fixture)
        server.daemon_threads = True
        server.token = 'chunked-test'
        server.reports = queue.Queue()
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        client = http.client.HTTPConnection('127.0.0.1', server.server_port, timeout=2)
        try:
            client.request('POST', '/report/chunked-test',
                           body=iter([b'{"event":', b'"first_frame","elapsed_us":123}']),
                           encode_chunked=True)
            response = client.getresponse()
            self.assertEqual(response.status, 204)
            response.read()
            self.assertEqual(server.reports.get(timeout=1)[1]['elapsed_us'], 123)
        finally:
            client.close()
            server.shutdown()
            server.server_close()

    def test_script_fixture_requires_header_after_plain_warmup_and_samples(self):
        import http.server
        import threading
        import urllib.error
        import urllib.request
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), runner.Fixture)
        server.daemon_threads = True
        server.token = 'script-test'
        server.received = 0
        server.mode = 'script'
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}/echo/script-test'
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(urllib.request.Request(url, headers={'X-Answer': '42'}))
            self.assertEqual(rejected.exception.code, 422)
            rejected.exception.close()
            server.received = 39
            with urllib.request.urlopen(url) as response:
                self.assertEqual(response.status, 200)
            for headers in ({}, {'X-Answer': '41'}):
                with self.assertRaises(urllib.error.HTTPError) as rejected:
                    urllib.request.urlopen(urllib.request.Request(url, headers=headers))
                self.assertEqual(rejected.exception.code, 422)
                rejected.exception.close()
            with urllib.request.urlopen(urllib.request.Request(url, headers={'X-Answer': '42'})) as response:
                self.assertEqual(response.status, 200)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    unittest.main()

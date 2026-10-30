"""Real HTTP regressions for the hermetic script/PDF.js fixture host.

Run with: python3 -m unittest discover -s integration_test/support -p 'test_*.py'
The server is copied into a temporary tree so adversarial files never touch
the real fixture directory, and no Flutter/browser process is launched.
"""

import http.client
import json
import pathlib
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest


class ScriptsWebServerTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = pathlib.Path(temporary.name)
        source = pathlib.Path(__file__).resolve().parent
        support = root / 'support'
        support.mkdir()
        server = support / 'scripts_web_server.py'
        shutil.copyfile(source / server.name, server)
        self.fixtures = root / 'fixtures' / 'scripts'
        shutil.copytree(source.parent / 'fixtures' / 'scripts', self.fixtures)
        self.pdfjs = root / 'pdfjs'
        self.pdfjs.mkdir()
        for name in ('pdf.min.mjs', 'pdf.worker.min.mjs'):
            (self.pdfjs / name).write_bytes(b'// local PDF.js test asset\n')
        (self.fixtures / 'unlisted.txt').write_bytes(b'unlisted fixture')
        (self.pdfjs / 'index.html').write_bytes(b'unlisted harness file')
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0))
            self.port = listener.getsockname()[1]
        self.process = subprocess.Popen(
            [sys.executable, str(server), str(self.port), str(self.pdfjs)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(self.stop_server)
        deadline = time.monotonic() + 5
        while True:
            try:
                self.request('/')
                break
            except (ConnectionError, OSError):
                if self.process.poll() is not None or time.monotonic() >= deadline:
                    self.fail('Fixture server failed to start within five seconds')
                time.sleep(0.02)

    def stop_server(self):
        self.process.terminate()
        try:
            self.process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.process.kill()
            self.process.wait(timeout=3)

    def request(self, path, method='GET', body=None, headers=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        try:
            connection.request(method, path, body=body, headers=headers or {})
            response = connection.getresponse()
            return response.status, response.getheaders(), response.read()
        finally:
            connection.close()

    def test_manifest_and_every_script_remain_available(self):
        manifest = json.loads((self.fixtures / 'manifest.json').read_text())
        names = ['manifest.json'] + [entry['file'] for entry in manifest['fixtures']]
        for name in names:
            with self.subTest(name=name):
                status, headers, payload = self.request('/fixtures/' + name)
                self.assertEqual(status, 200)
                self.assertEqual(payload, (self.fixtures / name).read_bytes())
                self.assertIn(('Access-Control-Allow-Origin', '*'), headers)

    def test_pdfjs_modules_remain_available_as_javascript(self):
        for name in ('pdf.min.mjs', 'pdf.worker.min.mjs'):
            with self.subTest(name=name):
                status, headers, payload = self.request('/pdfjs/' + name)
                self.assertEqual(status, 200)
                self.assertIn(('Content-Type', 'application/javascript'), headers)
                self.assertEqual(payload, b'// local PDF.js test asset\n')

    def test_rejects_fixture_route_aliases(self):
        # These URLs must never become valid through basename extraction or decoding.
        for suffix in (
            '../manifest.json', 'nested/manifest.json', '%2e%2e/manifest.json',
            '%2e%2e%2fmanifest.json', '%6danifest.json',
            'manifest.json/extra', 'manifest.json?extra=1',
        ):
            with self.subTest(suffix=suffix):
                self.assertEqual(self.request('/fixtures/' + suffix)[0], 404)

    def test_rejects_pdfjs_route_aliases(self):
        for suffix in (
            '../pdf.min.mjs', 'nested/pdf.min.mjs', '%2e%2e/pdf.min.mjs',
            '%2e%2e%2fpdf.min.mjs', '%70df.min.mjs',
            'pdf.min.mjs/extra', 'pdf.min.mjs?extra=1',
        ):
            with self.subTest(suffix=suffix):
                self.assertEqual(self.request('/pdfjs/' + suffix)[0], 404)

    def test_unlisted_files_are_not_served(self):
        for path in ('/fixtures/unlisted.txt', '/pdfjs/index.html'):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)

    def test_unknown_files_return_404(self):
        for path in ('/fixtures/missing.js', '/pdfjs/missing.mjs'):
            with self.subTest(path=path):
                self.assertEqual(self.request(path)[0], 404)

    def test_missing_allowed_pdfjs_asset_returns_404(self):
        (self.pdfjs / 'pdf.worker.min.mjs').unlink()
        self.assertEqual(self.request('/pdfjs/pdf.worker.min.mjs')[0], 404)

    def test_api_login_echo_and_cors_remain_available(self):
        status, _, payload = self.request('/login')
        self.assertEqual(status, 200)
        self.assertIn('token', json.loads(payload))
        status, _, payload = self.request(
            '/echo', method='POST', body='{"description":"fixture"}',
            headers={'X-Session': 'sessao-web-42'},
        )
        self.assertEqual(status, 200)
        self.assertEqual(json.loads(payload), {
            'body': {'description': 'fixture'}, 'session': 'sessao-web-42',
        })
        status, headers, _ = self.request('/echo', method='OPTIONS')
        self.assertEqual(status, 204)
        self.assertIn(('Access-Control-Allow-Origin', '*'), headers)


if __name__ == '__main__':
    unittest.main()

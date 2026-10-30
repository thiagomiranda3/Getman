"""Hermetic CORS fixture host; no credentials or external dependencies."""
import base64
import json
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'fixtures' / 'scripts'
claims = base64.urlsafe_b64encode(json.dumps({'session': {'id': 'sessao-web-42'}}).encode()).decode().rstrip('=')
TOKEN = 'eyJhbGciOiJub25lIn0.' + claims + '.c2ln'

# Keep filesystem paths independent of request input. Exact routes deliberately
# reject nested, traversal, encoded and query-string aliases; only the harness's
# known fixture files and PDF.js modules may be exposed.
JSON_CONTENT_TYPE = 'application/json; charset=utf-8'
FILE_ROUTES = {
    '/fixtures/' + name: (ROOT / name, JSON_CONTENT_TYPE)
    for name in (
        'manifest.json',
        'jwt_session_pre.js',
        'login_post.js',
        'response_tests_post.js',
        'extract_regex_post.js',
        'pre_failure.js',
        'post_failure.js',
        'infinite_loop.js',
        'pending_promise.js',
        'memory_limit.js',
        'console_limit.js',
    )
}
if len(sys.argv) > 2:
    FILE_ROUTES.update({
        '/pdfjs/' + name: (pathlib.Path(sys.argv[2]) / name, 'application/javascript')
        for name in ('pdf.min.mjs', 'pdf.worker.min.mjs')
    })

class Handler(BaseHTTPRequestHandler):
    def headers_cors(self, content_type=JSON_CONTENT_TYPE):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', '*')
        self.send_header('Content-Type', content_type)
    def do_OPTIONS(self):
        self.send_response(204)
        self.headers_cors()
        self.end_headers()
    def do_GET(self):
        content_type = JSON_CONTENT_TYPE
        if self.path.startswith(('/fixtures/', '/pdfjs/')):
            asset = FILE_ROUTES.get(self.path)
            if asset is None:
                self.send_error(404)
                return
            file, content_type = asset
            try:
                payload = file.read_bytes()
            except (FileNotFoundError, IsADirectoryError):
                self.send_error(404)
                return
        elif self.path == '/login':
            payload = json.dumps({'token': TOKEN}).encode()
        else:
            payload = b'{"ok":true}'
        self.send_response(200)
        self.headers_cors(content_type)
        self.end_headers()
        self.wfile.write(payload)
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        payload = json.dumps({'body': json.loads(body), 'session': self.headers.get('X-Session')}).encode()
        self.send_response(200)
        self.headers_cors()
        self.end_headers()
        self.wfile.write(payload)
    def log_message(self, *_):
        pass

HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()

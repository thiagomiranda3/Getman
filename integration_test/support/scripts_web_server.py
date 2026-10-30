"""Hermetic CORS fixture host; no credentials or external dependencies."""
import base64
import json
import pathlib
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'fixtures' / 'scripts'
claims = base64.urlsafe_b64encode(json.dumps({'session': {'id': 'sessao-web-42'}}).encode()).decode().rstrip('=')
TOKEN = 'eyJhbGciOiJub25lIn0.' + claims + '.c2ln'

class Handler(BaseHTTPRequestHandler):
    def headers_cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.send_header('Access-Control-Allow-Methods', '*')
        self.send_header('Content-Type', 'application/json; charset=utf-8')
    def do_OPTIONS(self):
        self.send_response(204)
        self.headers_cors()
        self.end_headers()
    def do_GET(self):
        if self.path.startswith('/pdfjs/') and len(sys.argv) > 2:
            file = pathlib.Path(sys.argv[2]) / pathlib.Path(self.path).name
            self.send_response(200)
            self.headers_cors()
            self.send_header('Content-Type', 'application/javascript')
            self.end_headers()
            self.wfile.write(file.read_bytes())
            return
        if self.path.startswith('/fixtures/'):
            file = ROOT / pathlib.Path(self.path).name
            if not file.is_file():
                self.send_error(404)
                return
            payload = file.read_bytes()
        elif self.path == '/login':
            payload = json.dumps({'token': TOKEN}).encode()
        else:
            payload = b'{"ok":true}'
        self.send_response(200)
        self.headers_cors()
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

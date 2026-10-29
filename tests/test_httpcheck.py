"""Loopback-only HTTP diagnostics regressions; no external targets."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import subprocess
import threading
import unittest

TOOL = Path(__file__).resolve().parents[1] / 'bash/bin/recon/httpcheck.sh'


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_HEAD(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/ok')
            self.send_header('Content-Security-Policy', 'default-src none')
        elif self.path == '/missing':
            self.send_response(404)
        else:
            self.send_response(200)
        self.end_headers()


class HttpCheck(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(('127.0.0.1', 0), Handler)
        cls.worker = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.worker.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.worker.join(timeout=5)

    def check_url(self, url):
        return subprocess.run(['bash', str(TOOL), url], text=True,
                              capture_output=True, timeout=20)

    def test_redirect_headers_do_not_leak_to_final_response(self):
        result = self.check_url(f'http://127.0.0.1:{self.server.server_port}/redirect')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('200', result.stdout)
        self.assertNotIn('default-src none', result.stdout)

    def test_http_error_status_is_failure(self):
        result = self.check_url(f'http://127.0.0.1:{self.server.server_port}/missing')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn('404', result.stdout)

    def test_connection_error_is_failure(self):
        # Reserve a bound but non-listening port, avoiding an external network dependency.
        import socket
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            result = self.check_url(f'http://127.0.0.1:{sock.getsockname()[1]}/')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('connection failed', result.stderr)


if __name__ == '__main__':
    unittest.main()

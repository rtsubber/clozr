#!/usr/bin/env python3
"""Server for Clozr PWA + API proxy to backend on 8540"""
import http.server
import json
import os
import sys
import urllib.request
import urllib.error

PORT = 8795
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
API_PORT = 8540  # Clozr backend

class ClozrHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, PATCH, DELETE')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        super().end_headers()

    def _proxy_to_api(self):
        """Proxy /api/ requests to Clozr backend on 8540"""
        api_url = f'http://localhost:{API_PORT}{self.path}'
        try:
            headers = {'Content-Type': 'application/json'}
            # Forward auth header if present
            auth = self.headers.get('Authorization')
            if auth:
                headers['Authorization'] = auth

            if self.command == 'POST':
                length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(length) if length else None
                req = urllib.request.Request(api_url, data=body, method='POST', headers=headers)
            elif self.command == 'PUT':
                length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(length) if length else None
                req = urllib.request.Request(api_url, data=body, method='PUT', headers=headers)
            elif self.command == 'PATCH':
                length = int(self.headers.get('Content-Length', 0))
                body = self.rfile.read(length) if length else None
                req = urllib.request.Request(api_url, data=body, method='PATCH', headers=headers)
            elif self.command == 'DELETE':
                req = urllib.request.Request(api_url, method='DELETE', headers=headers)
            else:
                req = urllib.request.Request(api_url, headers=headers)

            with urllib.request.urlopen(req, timeout=30) as resp:
                content_type = resp.headers.get('Content-Type', 'application/json')
                self.send_response(resp.status)
                self.send_header('Content-Type', content_type)
                self.end_headers()
                self.wfile.write(resp.read())
        except urllib.error.HTTPError as e:
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())
        except Exception as e:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"Proxy error: {e}"}).encode())

    def do_GET(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        elif self.path.startswith('/health'):
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"status": "ok", "service": "clozr-web"}).encode())
        else:
            super().do_GET()

    def do_POST(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        else:
            self.send_response(404)
            self.end_headers()

    def do_PUT(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        else:
            self.send_response(404)
            self.end_headers()

    def do_PATCH(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        else:
            self.send_response(404)
            self.end_headers()

    def do_DELETE(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        else:
            self.send_response(404)
            self.end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    print(f'Clozr web + API proxy running on http://localhost:{port}')
    print(f'  Static files: {DIRECTORY}')
    print(f'  API proxy: http://localhost:{API_PORT}/api/*')
    server = http.server.HTTPServer(('0.0.0.0', port), ClozrHandler)
    server.serve_forever()
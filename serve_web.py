#!/usr/bin/env python3
"""Server for Jarvis Meeting App PWA + Proposal API proxy"""
import http.server
import json
import os
import sys
import urllib.request
import urllib.error

PORT = 8795
DIRECTORY = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'build', 'web')
API_PORT = 8510  # Proposal tracker API

class JarvisHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)
    
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, X-Playground-Token, X-API-Key, Authorization')
        self.send_header('X-Content-Type-Options', 'nosniff')
        if self.path.endswith('.js'):
            self.send_header('Content-Type', 'application/javascript')
        if self.path.endswith('.wasm'):
            self.send_header('Content-Type', 'application/wasm')
        super().end_headers()
    
    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()
    
    def _proxy_to_api(self):
        """Proxy /api/ requests to the Proposal Tracker API"""
        api_url = f'http://localhost:{API_PORT}{self.path}'
        
        if self.command == 'POST':
            length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(length) if length else b''
            req = urllib.request.Request(api_url, data=body, method='POST')
            req.add_header('Content-Type', 'application/json')
        else:
            req = urllib.request.Request(api_url)
        
        try:
            with urllib.request.urlopen(req) as resp:
                data = resp.read()
                self.send_response(resp.status)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(data)
        except urllib.error.HTTPError as e:
            data = e.read()
            self.send_response(e.code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_response(502)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())
    
    def do_GET(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        elif self.path.startswith('/proposal/'):
            # Serve the proposal viewer page
            self.path = '/proposal/index.html'
            super().do_GET()
        else:
            # SPA: serve index.html for unknown paths
            path = self.path.split('?')[0]
            if path != '/' and not os.path.exists(os.path.join(DIRECTORY, path.lstrip('/'))):
                self.path = '/index.html'
            super().do_GET()
    
    def do_POST(self):
        if self.path.startswith('/api/'):
            self._proxy_to_api()
        else:
            self.send_response(404)
            self.end_headers()
    
    def log_message(self, format, *args):
        pass  # Suppress logs

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else PORT
    with http.server.HTTPServer(('', port), JarvisHandler) as server:
        print(f'Jarvis Meeting App + API proxy running on http://localhost:{port}')
        server.serve_forever()
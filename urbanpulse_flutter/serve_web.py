import http.server
import os
import socketserver
import sys
from pathlib import Path

PORT = 8080
DIRECTORY = Path(__file__).resolve().parent / "build" / "web"

if not DIRECTORY.exists():
    print(f"Error: {DIRECTORY} does not exist. Please run flutter build web first.")
    sys.exit(1)

class FlutterSpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DIRECTORY), **kwargs)

    def translate_path(self, path):
        # Strip query strings
        path = path.split('?', 1)[0]
        path = path.split('#', 1)[0]
        
        # Handle GitHub Pages base-href '/Urban-Pulse/'
        if path.startswith('/Urban-Pulse/'):
            path = path[len('/Urban-Pulse'):]
        elif path == '/Urban-Pulse':
            path = '/'
        
        # Translate to local filesystem path
        local_path = super().translate_path(path)
        
        # If the requested path does not exist, fall back to index.html (SPA routing)
        if not os.path.exists(local_path):
            index_path = os.path.join(str(DIRECTORY), "index.html")
            if os.path.exists(index_path):
                return index_path
                
        return local_path

    def end_headers(self):
        # Ensure Cross-Origin-Opener-Policy and Cross-Origin-Embedder-Policy if needed
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        super().end_headers()

    def guess_type(self, path):
        if path.endswith('.wasm'):
            return 'application/wasm'
        if path.endswith('.js'):
            return 'application/javascript'
        return super().guess_type(path)

class ThreadingHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True

if __name__ == '__main__':
    os.chdir(str(DIRECTORY))
    with ThreadingHTTPServer(("0.0.0.0", PORT), FlutterSpaHandler) as httpd:
        print(f"UrbanPulse Flutter Web Server running at:")
        print(f"  -> Local URL: http://localhost:{PORT}/Urban-Pulse/")
        print(f"  -> Root URL:  http://localhost:{PORT}/")
        sys.stdout.flush()
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nShutting down server.")

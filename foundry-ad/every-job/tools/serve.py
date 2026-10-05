#!/usr/bin/env python3
"""Dev server with caching off, so preview stills never mix old and new scripts. usage: tools/serve.py [port]"""
import http.server, sys

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, *a): pass

http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 8767), H).serve_forever()

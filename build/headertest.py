"""Serve dist/ with the exact response headers the NixOS nginx module sets.

Not a production server - it exists so the CSP and caching policy in
nix/module.nix can be exercised against the real application in a real
browser instead of being reasoned about and hoped for.
"""
import http.server, os, sys, functools

CSP = ("default-src 'none'; "
       "script-src 'self' 'unsafe-inline' 'unsafe-eval' blob:; "
       "worker-src blob:; "
       "style-src 'self' 'unsafe-inline'; "
       "img-src 'self' data: blob:; "
       "media-src 'self' blob:; "
       "connect-src 'self' blob: data:; "
       "font-src 'self'; "
       "base-uri 'none'; "
       "form-action 'none'; "
       "frame-ancestors 'none'; "
       "object-src 'none'")

class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Content-Security-Policy', CSP)
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Permissions-Policy',
                         'geolocation=(), microphone=(), camera=(), payment=(), usb=()')
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        p = self.path.split('?')[0]
        if p.endswith('.html') or p.endswith('/'):
            self.send_header('Cache-Control', 'no-cache')
        elif p.endswith(('.jpg', '.png', '.webp', '.svg', '.woff2')):
            self.send_header('Cache-Control', 'public, max-age=604800')
        super().end_headers()
    def log_message(self, *a):
        pass

if __name__ == '__main__':
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8778
    root = sys.argv[2] if len(sys.argv) > 2 else 'dist'
    os.chdir(root)
    http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()

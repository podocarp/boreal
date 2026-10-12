#!/usr/bin/env python3
"""Measure web build frame times headlessly: serve dist/web, boot, sample rAF deltas."""
import http.server, socketserver, threading, os, sys, subprocess, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8137
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a): pass
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        tempfile.mkdtemp(), executable_path=CHROMIUM or None, headless=True,
        args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox"])
    page = ctx.new_page()
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    # wait for engine boot: canvas + splash gone
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(4000)  # let it settle into menu
    # sample rAF deltas for 4s
    res = page.evaluate("""() => new Promise(resolve => {
        const deltas = []; let last = performance.now(); let n = 0;
        function tick(t) { deltas.push(t - last); last = t; if (++n < 240) requestAnimationFrame(tick); else resolve(deltas); }
        requestAnimationFrame(tick);
        setTimeout(() => resolve(deltas), 12000);
    })""")
    deltas = sorted(res)
    if deltas:
        import statistics
        print(f"frames sampled: {len(deltas)}")
        print(f"median frame: {deltas[len(deltas)//2]:.1f} ms  (~{1000/max(deltas[len(deltas)//2],0.01):.1f} fps)")
        print(f"p90 frame: {deltas[int(len(deltas)*0.9)]:.1f} ms")
        print(f"worst: {deltas[-1]:.0f} ms")
    # also check console errors
    ctx.close()
httpd.shutdown()

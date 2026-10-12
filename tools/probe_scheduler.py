#!/usr/bin/env python3
"""Is the engine main loop alive via setTimeout scheduler (not rAF)?"""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8148
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a): pass

socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        tempfile.mkdtemp(), executable_path=CHROMIUM or None, headless=True,
        args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox"])
    page = ctx.new_page()
    page.add_init_script("""
        window.__st = 0;
        const origST = window.setTimeout.bind(window);
        window.setTimeout = function(cb, ms) {
            if (typeof cb === 'function' && ms !== undefined && ms < 50) window.__st++;
            return origST(cb, ms);
        };
    """)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_timeout(12000)
    s1 = page.evaluate("window.__st")
    page.wait_for_timeout(2000)
    s2 = page.evaluate("window.__st")
    print(f"short-setTimeout ticks/sec: {(s2-s1)/2:.0f}")
    # engine internals if exposed
    info = page.evaluate("""() => {
        const out = {};
        try { out.godotKeys = Object.getOwnPropertyNames(window.Godot).slice(0,15); } catch(e) {}
        try {
            const el = document.querySelector('canvas');
            out.canvasSize = [el.width, el.height];
        } catch(e) {}
        return out;
    }""")
    print("info:", info)
    ctx.close()
httpd.shutdown()

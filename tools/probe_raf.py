#!/usr/bin/env python3
"""Is the ENGINE's rAF loop alive? Count total rAF calls/s (engine re-arms every frame)."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8145
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
        args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox", "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding", "--disable-background-timer-throttling"])
    page = ctx.new_page()
    page.add_init_script("""
        window.__rafCount = 0;
        const orig = window.requestAnimationFrame.bind(window);
        window.requestAnimationFrame = function(cb) { window.__rafCount++; return orig(cb); };
    """)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(3000)
    c1 = page.evaluate("window.__rafCount")
    page.wait_for_timeout(2000)
    c2 = page.evaluate("window.__rafCount")
    rate = (c2 - c1) / 2
    print(f"rAF calls/sec: {rate:.0f}  -> engine main loop {'ALIVE' if rate > 30 else 'DEAD (stalled)'}")
    # click and see if rafCount changes behavior / canvas changes
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(2000)
    print("canvas changed after click:", page.locator("canvas").screenshot() != page.locator("canvas").screenshot())
    ctx.close()
httpd.shutdown()

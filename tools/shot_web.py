#!/usr/bin/env python3
"""Screenshot the web build at boot, menu, after click — for vision inspection."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8143
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None
OUT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/webshots"
os.makedirs(OUT, exist_ok=True)

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
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(2000)
    page.screenshot(path=f"{OUT}/menu.png")
    page.wait_for_timeout(3000)
    page.screenshot(path=f"{OUT}/menu_3s_later.png")
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(3000)
    page.screenshot(path=f"{OUT}/after_click.png")
    page.keyboard.press("Enter")
    page.wait_for_timeout(3000)
    page.screenshot(path=f"{OUT}/after_enter.png")
    print("shots saved to", OUT)
    ctx.close()
httpd.shutdown()

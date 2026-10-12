#!/usr/bin/env python3
"""Which input actually starts the game on web: click? Enter? click-then-Enter?"""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8140
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
    errs = []
    page.on("console", lambda m: errs.append(m.text) if m.type == "error" else None)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(4000)
    base = page.locator("canvas").screenshot()
    box = page.locator("canvas").bounding_box()
    cx, cy = box["x"] + box["width"]/2, box["y"] + box["height"]/2

    page.mouse.click(cx, cy); page.wait_for_timeout(2500)
    print("after click:      changed =", page.locator("canvas").screenshot() != base)
    page.keyboard.press("Enter"); page.wait_for_timeout(2500)
    print("after Enter:      changed =", page.locator("canvas").screenshot() != base)
    # double click
    page.mouse.dblclick(cx, cy); page.wait_for_timeout(2500)
    print("after dblclick:   changed =", page.locator("canvas").screenshot() != base)
    # move mouse (look) then click again
    page.mouse.move(cx+50, cy+20); page.wait_for_timeout(300)
    page.mouse.click(cx, cy); page.wait_for_timeout(2500)
    print("after move+click: changed =", page.locator("canvas").screenshot() != base)
    print("console errors:", errs[:5] if errs else "none")
    ctx.close()
httpd.shutdown()

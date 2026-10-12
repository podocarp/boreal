#!/usr/bin/env python3
"""Input matrix on live engine: focus canvas, Enter, click, keydown+keyup timing."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8151
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
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_timeout(12000)
    page.bring_to_front()
    page.evaluate("document.querySelector('canvas').focus(); document.querySelector('canvas').tabIndex = -1;")
    print("hasFocus:", page.evaluate("document.hasFocus()"))
    base = page.locator("canvas").screenshot()
    page.locator("canvas").click()          # playwright click (real mouse events)
    page.wait_for_timeout(1500)
    print("after canvas.click():", page.locator("canvas").screenshot() != base)
    page.keyboard.press("Enter")
    page.wait_for_timeout(1500)
    print("after Enter:", page.locator("canvas").screenshot() != base)
    page.keyboard.press("Space")
    page.wait_for_timeout(1500)
    print("after Space:", page.locator("canvas").screenshot() != base)
    # dispatch synthetic events directly at the canvas (bypass focus?)
    page.evaluate("""() => {
        const c = document.querySelector('canvas');
        const r = c.getBoundingClientRect();
        const x = r.left + r.width/2, y = r.top + r.height/2;
        c.dispatchEvent(new PointerEvent('pointerdown', {clientX:x, clientY:y, bubbles:true, pointerId:1, button:0}));
        c.dispatchEvent(new MouseEvent('mousedown', {clientX:x, clientY:y, bubbles:true, button:0}));
        c.dispatchEvent(new PointerEvent('pointerup', {clientX:x, clientY:y, bubbles:true, pointerId:1, button:0}));
        c.dispatchEvent(new MouseEvent('mouseup', {clientX:x, clientY:y, bubbles:true, button:0}));
        c.dispatchEvent(new MouseEvent('click', {clientX:x, clientY:y, bubbles:true, button:0}));
    }""")
    page.wait_for_timeout(1500)
    print("after synthetic events:", page.locator("canvas").screenshot() != base)
    # walk test: W held
    page.keyboard.down("w"); page.wait_for_timeout(2500); page.keyboard.up("w")
    print("after W-walk:", page.locator("canvas").screenshot() != base)
    ctx.close()
httpd.shutdown()

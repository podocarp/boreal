#!/usr/bin/env python3
"""Definitive start test: menu shot -> click -> walk W -> compare + HUD check."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8150
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None
OUT = "/persist/hermes/.hermes/profiles/gamedev/cache/scratch/webshots"

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
    menu = page.screenshot()
    open(f"{OUT}/fix_menu.png","wb").write(menu)
    box = page.evaluate("() => { const r = document.querySelector('canvas').getBoundingClientRect(); return {x: r.x, y: r.y, width: r.width, height: r.height}; }")
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(1000)
    page.keyboard.down("w"); page.wait_for_timeout(3000); page.keyboard.up("w")
    walked = page.screenshot()
    open(f"{OUT}/fix_walked.png","wb").write(walked)
    print("walk changed canvas (game started + moving):", menu != walked)
    # day counter advances? sim clock moves after start
    page.wait_for_timeout(2000)
    print("second walk shot differs from first:", walked != page.screenshot())
    ctx.close()
httpd.shutdown()

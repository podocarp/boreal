#!/usr/bin/env python3
"""Control: does headless chromium input reach a plain Godot web build at all?"""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8153
ROOT = sys.argv[1]
CHROMIUM = sys.argv[2]

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
    logs = []
    page.on("console", lambda m: logs.append(m.text[:120]))
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_timeout(8000)
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.keyboard.press("Enter")
    page.keyboard.press("W")
    page.wait_for_timeout(2000)
    hits = [l for l in logs if "MINI INPUT" in l]
    print(f"MINI INPUT events seen: {len(hits)}")
    for h in hits[:4]: print(" ", h)
    ctx.close()
httpd.shutdown()

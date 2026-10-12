#!/usr/bin/env python3
"""Verify click actually starts gameplay (pixels change) and sample fps after start."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8139
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
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(3000)
    shot1 = page.locator("canvas").screenshot()
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(4000)
    shot2 = page.locator("canvas").screenshot()
    print("canvas pixels changed after click:", shot1 != shot2, f"({len(shot1)} vs {len(shot2)} bytes png)")
    # walk a bit to force terrain/streaming work
    page.keyboard.down("w"); page.wait_for_timeout(3000); page.keyboard.up("w")
    deltas = page.evaluate("""() => new Promise(resolve => {
        const d=[]; let last=performance.now(), n=0;
        function t(x){d.push(x-last); last=x; if(++n<180) requestAnimationFrame(t); else resolve(d);}
        requestAnimationFrame(t); setTimeout(()=>resolve(d), 15000);
    })""")
    d = sorted(deltas)
    if d:
        med = d[len(d)//2]
        print(f"after-walk fps: median={med:.1f}ms (~{1000/max(med,.01):.0f}fps) p90={d[int(len(d)*.9)]:.0f}ms worst={d[-1]:.0f}ms")
    ctx.close()
httpd.shutdown()

#!/usr/bin/env python3
"""Boot web build, click through title into gameplay, sample frame times."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8138
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a): pass

socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

from playwright.sync_api import sync_playwright

SAMPLE = """() => new Promise(resolve => {
    const deltas = []; let last = performance.now(); let n = 0;
    function tick(t) { deltas.push(t - last); last = t; if (++n < 300) requestAnimationFrame(tick); else resolve(deltas); }
    requestAnimationFrame(tick);
    setTimeout(() => resolve(deltas), 20000);
})"""

def report(tag, deltas):
    if not deltas: print(tag, "no frames"); return
    d = sorted(deltas)
    med = d[len(d)//2]
    print(f"{tag}: n={len(d)} median={med:.1f}ms (~{1000/max(med,.01):.0f}fps) p90={d[int(len(d)*.9)]:.0f}ms worst={d[-1]:.0f}ms")

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        tempfile.mkdtemp(), executable_path=CHROMIUM or None, headless=True,
        args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox"])
    page = ctx.new_page()
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(3000)
    report("menu", page.evaluate(SAMPLE))
    # click canvas center to start (game_ui accepts left click)
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(1000)
    report("first 5s of gameplay", page.evaluate(SAMPLE))
    page.wait_for_timeout(5000)
    report("settled gameplay", page.evaluate(SAMPLE))
    ctx.close()
httpd.shutdown()

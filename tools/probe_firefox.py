#!/usr/bin/env python3
"""Firefox-specific repro: boot, click start, walk, verify engine alive + input works."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8144
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
FIREFOX = sys.argv[2] if len(sys.argv) > 2 else None

class H(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw): super().__init__(*a, directory=ROOT, **kw)
    def log_message(self, *a): pass

socketserver.TCPServer.allow_reuse_address = True
httpd = socketserver.TCPServer(("127.0.0.1", PORT), H)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    launch = dict(headless=True)
    if FIREFOX: launch["executable_path"] = FIREFOX
    browser = p.firefox.launch(**launch)
    page = browser.new_page()
    errs = []
    page.on("console", lambda m: errs.append(f"{m.type}: {m.text[:140]}") if m.type in ("error","warning") else None)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=90000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=180000)
    page.wait_for_timeout(4000)
    menu = page.locator("canvas").screenshot()
    box = page.locator("canvas").bounding_box()
    page.mouse.click(box["x"] + box["width"]/2, box["y"] + box["height"]/2)
    page.wait_for_timeout(2500)
    started = page.locator("canvas").screenshot()
    print("click changed canvas (menu dismissed):", menu != started)
    page.keyboard.down("w"); page.wait_for_timeout(2500); page.keyboard.up("w")
    walked = page.locator("canvas").screenshot()
    print("W-walk changed canvas (input+engine alive):", started != walked)
    # fps sample
    deltas = page.evaluate("""() => new Promise(res => {
        const d=[]; let last=performance.now(), n=0;
        function t(x){d.push(x-last); last=x; if(++n<120) requestAnimationFrame(t); else res(d);}
        requestAnimationFrame(t); setTimeout(()=>res(d), 10000);
    })""")
    if deltas:
        d = sorted(deltas); med = d[len(d)//2]
        print(f"firefox fps: median={med:.1f}ms (~{1000/max(med,.01):.0f}fps)")
    print("console:", *errs[:6], sep="\n  ")
    browser.close()
httpd.shutdown()

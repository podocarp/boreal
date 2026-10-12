#!/usr/bin/env python3
"""Detect main-thread long tasks during boot+menu: what blocks the engine?"""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8141
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
    # install long-task observer BEFORE navigation
    page.add_init_script("""
        window.__longtasks = [];
        new PerformanceObserver(l => {
            for (const e of l.getEntries()) window.__longtasks.push({dur: Math.round(e.duration), at: Math.round(e.startTime)});
        }).observe({entryTypes: ['longtask']});
    """)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(6000)
    lt = page.evaluate("window.__longtasks")
    print(f"long tasks during boot+6s menu: {len(lt)}")
    for t in sorted(lt, key=lambda x: -x['dur'])[:8]:
        print(f"  {t['dur']}ms at t={t['at']}ms")
    # rAF gap check: is the engine's own frame loop alive?
    gaps = page.evaluate("""() => new Promise(res => {
        const g=[]; let last=performance.now(), n=0;
        function t(x){g.push(Math.round(x-last)); last=x; if(++n<120) requestAnimationFrame(t); else res(g);}
        requestAnimationFrame(t); setTimeout(()=>res(g), 8000);
    })""")
    big = [g for g in gaps if g > 100]
    print(f"rAF frames: {len(gaps)}, gaps>100ms: {len(big)} {big[:5]}")
    ctx.close()
httpd.shutdown()

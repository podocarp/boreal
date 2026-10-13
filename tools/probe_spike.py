#!/usr/bin/env python3
"""Measure main-thread long tasks around the START click (lag-spike gate)."""
import os, sys, threading, http.server, socketserver, functools, time
os.environ.setdefault("TMPDIR", "/tmp")
from playwright.sync_api import sync_playwright

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "dist/web")
CHROMIUM = sys.argv[2] if len(sys.argv) > 2 else None
PORT = 8137

Handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
class Quiet(socketserver.TCPServer):
    allow_reuse_address = True
    def handle_error(self, *a): pass
httpd = Quiet(("127.0.0.1", PORT), Handler)
threading.Thread(target=httpd.serve_forever, daemon=True).start()

with sync_playwright() as pw:
    b = pw.chromium.launch(executable_path=CHROMIUM, args=[
        "--use-gl=swiftshader", "--enable-unsafe-swiftshader",
        "--no-sandbox", "--disable-dev-shm-usage"])
    page = b.new_page(viewport={"width": 1280, "height": 720})
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.evaluate("""() => {
        window.__longtasks = [];
        new PerformanceObserver((l) => {
            for (const e of l.getEntries())
                window.__longtasks.push({dur: Math.round(e.duration),
                                         at: Math.round(e.startTime)});
        }).observe({entryTypes: ['longtask']});
    }""")
    # wait for the title screen to be up (canvas animating)
    page.wait_for_timeout(12000)
    before = page.evaluate("window.__longtasks.length")
    t0 = page.evaluate("performance.now()")
    page.mouse.click(640, 360)          # dismiss title -> PLAYING
    page.wait_for_timeout(6000)         # let the spike (if any) land
    lts = page.evaluate("window.__longtasks")
    after = [t for t in lts[before:] if t["at"] >= t0 - 500]
    worst = max((t["dur"] for t in after), default=0)
    print(f"long tasks after START click (6s window): {len(after)}")
    for t in sorted(after, key=lambda x: -x["dur"])[:5]:
        print(f"  {t['dur']}ms at t={t['at']}ms")
    print(f"worst: {worst}ms -> {'SPIKE' if worst > 1500 else 'OK'}")
    b.close()
httpd.shutdown()

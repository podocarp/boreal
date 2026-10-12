#!/usr/bin/env python3
"""Pinpoint the stall: rAF timeline + uncaught errors + what the engine object says."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8147
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
    page.add_init_script("""
        window.__raf = [];
        const t0 = performance.now();
        const orig = window.requestAnimationFrame.bind(window);
        window.requestAnimationFrame = function(cb) {
            window.__raf.push(Math.round(performance.now() - t0));
            return orig(function(ts) { try { cb(ts); } catch(e) { window.__rafErr = String(e.stack || e).slice(0,500); throw e; } });
        };
        window.addEventListener('unhandledrejection', e => { window.__rej = String(e.reason && (e.reason.stack || e.reason)).slice(0,500); });
        window.addEventListener('error', e => { window.__err = String(e.message).slice(0,300); });
    """)
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_timeout(15000)
    info = page.evaluate("""() => {
        const r = window.__raf;
        return {
            rafTotal: r.length,
            first10: r.slice(0,10),
            last10: r.slice(-10),
            rafErr: window.__rafErr || null,
            rej: window.__rej || null,
            err: window.__err || null,
            now: Math.round(performance.now())
        };
    }""")
    print("rafTotal:", info["rafTotal"], "now:", info["now"])
    print("first rAFs:", info["first10"])
    print("last rAFs: ", info["last10"])
    print("rAF callback error:", info["rafErr"])
    print("unhandled rejection:", info["rej"])
    print("window error:", info["err"])
    ctx.close()
httpd.shutdown()

#!/usr/bin/env python3
"""Is the ENGINE main loop alive? canvas redraws + audio ctx state."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8142
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
    page.on("console", lambda m: errs.append(f"{m.type}: {m.text[:160]}"))
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=120000)
    page.wait_for_timeout(5000)
    # engine frame counter: Godot 4 shell exposes window.Godot / engine
    info = page.evaluate("""() => {
        const out = {};
        out.godotKeys = Object.keys(window).filter(k => /godot/i.test(k)).slice(0,10);
        try { out.hasGodot = typeof window.Godot; } catch(e) {}
        try {
            const g = window.Godot;
            if (g && g.__wd) out.wd = Object.keys(g.__wd).slice(0,10);
        } catch(e) {}
        // audio ctx sanity
        try {
            const ac = new (window.AudioContext || window.webkitAudioContext)();
            out.acOk = ac instanceof BaseAudioContext;
            out.acState = ac.state;
            out.hasWorklet = !!ac.audioWorklet;
        } catch(e) { out.acErr = String(e); }
        return out;
    }""")
    print("page info:", info)
    # does the canvas redraw? water shader animates with TIME if engine draws frames
    s1 = page.locator("canvas").screenshot()
    page.wait_for_timeout(3000)
    s2 = page.locator("canvas").screenshot()
    print("canvas animating (engine drawing frames):", s1 != s2)
    print("console:", *errs[:8], sep="\n  ")
    ctx.close()
httpd.shutdown()

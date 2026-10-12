#!/usr/bin/env python3
"""Inspect Godot engine JS internals: audio driver state, main loop method."""
import http.server, socketserver, threading, os, sys, tempfile
os.environ.setdefault("TMPDIR", "/tmp")
PORT = 8154
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
    page.goto(f"http://127.0.0.1:{PORT}/index.html")
    page.wait_for_selector("canvas", timeout=60000)
    page.wait_for_timeout(12000)
    info = page.evaluate("""() => {
        const out = {};
        try { out.audioCtx = GodotAudio.ctx ? GodotAudio.ctx.state : 'null'; } catch(e) { out.audioCtx = 'ERR ' + e; }
        try { out.driver = GodotAudio.driver ? (GodotAudio.driver === GodotAudioWorklet ? 'worklet' : GodotAudio.driver === GodotAudioScript ? 'script' : 'other') : 'null'; } catch(e) { out.driver = 'ERR ' + e; }
        try { out.workletPromise = GodotAudioWorklet.promise ? 'set' : 'null'; out.workletNode = GodotAudioWorklet.worklet ? 'yes' : 'null'; } catch(e) { out.workletPromise = 'ERR ' + e; }
        try { out.mainLoop = MainLoop.method; } catch(e) { out.mainLoop = 'ERR ' + e; }
        try { out.rafPending = MainLoop.runner ? 'runner set' : 'no runner'; } catch(e) {}
        try { out.callStack = (typeof _emscripten_get_now === 'function') ? 'emsc ok' : '?'; } catch(e) {}
        return out;
    }""")
    print("engine internals:", info)
    ctx.close()
httpd.shutdown()

# Smoke-test the exported Godot web build in headless Chromium (nixpkgs
# chromium via python playwright). Success signals, all observed live:
#   - index.wasm / index.pck fetched with HTTP 200
#   - the #status splash overlay is REMOVED (the stock HTML shell only does
#     that in the startGame().then() success path)
#   - canvas exists with non-zero size and a live WebGL context
#   - canvas pixels are non-uniform after boot (real frames rendered)
#   - no page errors
# Exit 0 = pass.
import sys, threading, http.server, socketserver, functools, json

PORT = 8765
ROOT = sys.argv[1] if len(sys.argv) > 1 else "dist/web"
CHROME = sys.argv[2] if len(sys.argv) > 2 else None

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
srv = Server(("127.0.0.1", PORT), handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()

from playwright.sync_api import sync_playwright

args = ["--no-sandbox", "--use-gl=angle", "--use-angle=vulkan",
        "--enable-unsafe-swiftshader", "--autoplay-policy=no-user-gesture-required"]
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        "/tmp/pwprof", headless=True, executable_path=CHROME, args=args)
    page = ctx.new_page()
    errors, reqs = [], []
    page.on("pageerror", lambda e: errors.append("pageerror: " + str(e)))
    page.on("console", lambda m: errors.append("console.error: " + m.text)
            if m.type == "error" else None)
    def on_resp(r):
        if any(r.url.endswith(s) for s in (".wasm", ".pck", ".js", ".html")):
            reqs.append((r.status, r.url.split("/")[-1]))
    page.on("response", on_resp)

    page.goto(f"http://127.0.0.1:{PORT}/index.html", wait_until="load")
    # wait for the splash overlay to be removed (= startGame resolved)
    booted = True
    try:
        page.wait_for_function(
            "() => !document.getElementById('status')", timeout=180000)
    except Exception:
        booted = False
    page.wait_for_timeout(4000)  # let a few frames render

    info = page.evaluate("""() => {
        const c = document.querySelector('canvas');
        const out = {canvas: !!c, w: c ? c.width : 0, h: c ? c.height : 0,
                     title: document.title, gl: 'none', distinct: 0,
                     notice: (document.getElementById('status-notice') || {}).textContent || ''};
        if (c) {
            try {
                const g = c.getContext('webgl2') || c.getContext('webgl');
                if (g) {
                    out.gl = g.getParameter(g.VERSION);
                    const w = g.drawingBufferWidth, h = g.drawingBufferHeight;
                    const buf = new Uint8Array(4 * 64 * 64);
                    const seen = new Set();
                    for (let by = 0; by < h; by += Math.max(1, (h/8)|0)) {
                        g.readPixels((w/2 - 32)|0, (by)|0, 64, 64, g.RGBA, g.UNSIGNED_BYTE, buf);
                        for (let i = 0; i < buf.length; i += 4)
                            seen.add((buf[i] >> 3) * 4096 + (buf[i+1] >> 3) * 64 + (buf[i+2] >> 3));
                    }
                    out.distinct = seen.size;
                }
            } catch (e) { out.gl = 'err: ' + e.message; }
        }
        return out;
    }""")
    page.screenshot(path="/tmp/boreal_web_smoke.png")
    # Alive check (web 0.1.0 regression): click through the title (sim paused
    # on menu = static canvas), then the water shader animates with sim time,
    # so a LIVE engine's canvas changes between frames. A dead engine (tree
    # quit, frozen menu) renders an identical frame forever.
    # Staged build (2026-10-12): the loading overlay swallows early clicks,
    # so retry until the canvas animates (title dismissed).
    for attempt in range(6):
        page.mouse.click(640, 360)
        page.wait_for_timeout(1500)
        s1 = page.screenshot(timeout=120000)
        page.wait_for_timeout(1500)
        info["animating"] = page.screenshot(timeout=120000) != s1
        if info["animating"]:
            info["click_attempts"] = attempt + 1
            break
    ctx.close()
    srv.shutdown()

print("requests:", json.dumps(reqs))
print("booted (splash removed):", booted)
print("canvas:", json.dumps(info))
print("page errors:", json.dumps(errors[:10]) if errors else "none")
ok = (booted and info["canvas"] and info["w"] > 0 and info["gl"] != "none"
      and info["distinct"] > 3 and info.get("animating")
      and all(s == 200 for s, _ in reqs))
print("SMOKE:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)

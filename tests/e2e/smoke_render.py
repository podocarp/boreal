"""BOREAL — headless render smoke test (Sprint 0).

Run inside the flake dev shell with a static server on :4173:
  nix develop --extra-experimental-features 'nix-command flakes' . -c bash -lc \
    'python3 tests/e2e/smoke_render.py'
"""
import os
import sys
from playwright.sync_api import sync_playwright

URL = os.environ.get("BOREAL_URL", "http://localhost:4173/")
CHROMIUM = os.environ.get("CHROMIUM", "chromium")

ARGS = ["--no-sandbox", "--disable-gpu", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"]


def main() -> int:
    errors: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM, headless=True, args=ARGS)
        page = browser.new_page(viewport={"width": 800, "height": 600})
        page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
        page.goto(URL, wait_until="load")
        page.wait_for_function("() => !!window.__boreal", timeout=30000)

        # Step the sim deterministically and read state back via the debug API.
        state = page.evaluate(
            """() => { const b = window.__boreal; b.reset(7); b.step(400);
                       return { day: b.world.day, hour: b.world.hourOfDay, t: b.world.t }; }"""
        )
        assert state["t"] > 90, f"sim did not advance: {state}"

        # Read pixels straight from the preserved WebGL framebuffer
        # (main.ts renders every rAF frame, so the buffer is live).
        # Feature checks are color-signature scans, not fixed screen points —
        # robust to camera/layout changes.
        sample = page.evaluate(
            """() => {
              const canvas = document.querySelector('canvas');
              const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
              const w = canvas.width, h = canvas.height;
              const buf = new Uint8Array(w * h * 4);
              gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, buf);
              const pts = {};
              const at = (fx, fy, name) => { const x=(w*fx)|0, y=(h*fy)|0, i=(y*w+x)*4;
                 pts[name] = [buf[i], buf[i+1], buf[i+2]]; };
              at(0.5, 0.12, 'sky');
              let bottomCool = 0, bottomTotal = 0, orange = 0;
              const uniq = new Set();
              for (let y = 0; y < h; y++) {
                const inBottom = y > h * 0.75; // ground region (camera looks slightly down)
                for (let x = 0; x < w; x++) {
                  const i = (y * w + x) * 4;
                  const r = buf[i], g = buf[i+1], b = buf[i+2];
                  if (inBottom) {
                    bottomTotal++;
                    if (b >= r && b > 120) bottomCool++; // snow/fog-blended cool cast
                  }
                  if (r > 90 && r > g + 40 && g > b + 10) orange++;
                  if ((i & 1023) === 0)
                    uniq.add((r >> 3) + ',' + (g >> 3) + ',' + (b >> 3));
                }
              }
              pts.bottomCoolFrac = bottomCool / Math.max(1, bottomTotal);
              pts.orangePixels = orange;
              pts.distinct = uniq.size; pts.total = w * h;
              return pts;
            }"""
        )
        browser.close()

    print("sim state:", state)
    print("pixels:", sample)
    if errors:
        print("PAGE ERRORS:", errors)
        return 1
    sky = sample["sky"]
    assert sky[0] > 100 and sky[2] > 120, f"sky not pale blue: {sky}"
    assert sample["bottomCoolFrac"] > 0.8, \
        f"bottom of frame not cool ground fill: {sample['bottomCoolFrac']:.2f}"
    assert sample["orangePixels"] > 200, \
        f"crash-site marker missing: {sample['orangePixels']} px"
    assert sample["distinct"] > 8, f"framebuffer looks flat: {sample['distinct']} colors"
    print("SMOKE_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Capture a pretty noon screenshot of the world (manual inspection aid)."""
import os
import sys
from playwright.sync_api import sync_playwright

URL = os.environ.get("BOREAL_URL", "http://localhost:4173/")
CHROMIUM = os.environ.get("CHROMIUM", "chromium")
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/boreal_shot.png"
ARGS = ["--no-sandbox", "--disable-gpu", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"]

with sync_playwright() as p:
    b = p.chromium.launch(executable_path=CHROMIUM, headless=True, args=ARGS)
    page = b.new_page(viewport={"width": 1280, "height": 720})
    page.goto(URL, wait_until="load")
    page.wait_for_function("() => !!window.__boreal", timeout=30000)
    # stand on the lake ice south of the wreck, late-afternoon light, looking
    # north at the wreck with the player figure in the lower frame
    page.evaluate(
        """() => { const b = window.__boreal;
                   b.setPaused(true); b.reset(1);
                   b.world.player.x = 0; b.world.player.z = -108;
                   b.step(1);
                   b.world.hourOfDay = 15.4;
                   b.orbitCam(Math.PI, -0.12);
                   b.renderOnce(); }"""
    )
    page.wait_for_timeout(600)
    page.screenshot(path=OUT, timeout=90000)
    print("saved", OUT)
    b.close()

"""Capture styled screenshots of the current build (manual inspection aid).

Usage: python3 screenshot.py <out.png> [day|night]
"""
import os
import sys
from playwright.sync_api import sync_playwright

URL = os.environ.get("BOREAL_URL", "http://localhost:4173/")
CHROMIUM = os.environ.get("CHROMIUM", "chromium")
ARGS = ["--no-sandbox", "--disable-gpu", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"]

POSES = {
    # day: on the bank beside the wreck, late-afternoon light, looking north
    # across the frozen lake (wreck + grove in frame)
    "day": """
        b.world.player.x = -20; b.world.player.z = -56; b.step(1);
        b.world.hourOfDay = 15.4; b.orbitCam(Math.PI, 0.05);""",
    # day2: from the lake looking at the camp — grove + wreck shoreline
    "camp": """
        b.world.player.x = -25; b.world.player.z = -85; b.step(1);
        b.world.hourOfDay = 14.0; b.orbitCam(0, -0.18);""",
    # night: camped with a big fire, warm glow against the dark
    "night": """
        b.world.player.x = -20; b.world.player.z = -62; b.step(1);
        b.world.hourOfDay = 21.5;
        b.world.fires.push({ id: 1, x: -18, z: -60, fuel: 90, lit: true });
        b.step(2);
        b.orbitCam(Math.PI * 1.18, -0.16);""",
}

OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/boreal_shot.png"
NAME = sys.argv[2] if len(sys.argv) > 2 else "day"

with sync_playwright() as p:
    b = p.chromium.launch(executable_path=CHROMIUM, headless=True, args=ARGS)
    page = b.new_page(viewport={"width": 1280, "height": 720})
    page.goto(URL, wait_until="load")
    page.wait_for_function("() => !!window.__boreal", timeout=30000)
    page.evaluate(
        f"""() => {{ const b = window.__boreal;
                     b.setPaused(true); b.reset(1);
                     {POSES[NAME]}
                     b.renderOnce(); }}"""
    )
    page.wait_for_timeout(700)
    page.screenshot(path=OUT, timeout=90000)
    print("saved", OUT, NAME)
    b.close()

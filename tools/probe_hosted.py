#!/usr/bin/env python3
"""End-to-end check of the LIVE hosted build: boot -> click -> walk -> title gone."""
import sys, tempfile
from playwright.sync_api import sync_playwright

URL = "https://podocarp.github.io/boreal/"
with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        tempfile.mkdtemp(), executable_path=sys.argv[1] if len(sys.argv)>1 else None, headless=True,
        args=["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--no-sandbox"])
    page = ctx.new_page()
    errs = []
    page.on("pageerror", lambda e: errs.append(str(e)[:120]))
    page.goto(URL, wait_until="load", timeout=120000)
    page.wait_for_selector("canvas", timeout=120000)
    page.wait_for_function("() => { const s = document.getElementById('status'); return !s || s.style.display === 'none'; }", timeout=240000)
    page.wait_for_timeout(5000)
    menu = page.screenshot()
    page.mouse.click(640, 360)
    page.wait_for_timeout(1500)
    started = page.screenshot()
    print("title dismissed on click:", menu != started)
    page.keyboard.down("w"); page.wait_for_timeout(3000); page.keyboard.up("w")
    walked = page.screenshot()
    print("walking moves view:", started != walked)
    open("/persist/hermes/.hermes/profiles/gamedev/cache/scratch/webshots/hosted_walked.png","wb").write(walked)
    print("page errors:", errs[:3] if errs else "none")
    ctx.close()

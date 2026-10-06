"""BOREAL — headless render + behavior smoke test.

Sprint 1 checks: sim clock, scripted movement, camera orbit, scene-graph
feature presence (terrain/lake/stream/trees/player/crash), day/night lighting,
and framebuffer pixel signatures from two deterministic poses.

Run inside the flake dev shell with a static server on :4173:
  nix develop --extra-experimental-features 'nix-command flakes' . -c bash -lc \
    'BOREAL_URL=http://localhost:4173/ CHROMIUM=$(which chromium) python3 tests/e2e/smoke_render.py'
"""
import os
import sys
from playwright.sync_api import sync_playwright

URL = os.environ.get("BOREAL_URL", "http://localhost:4173/")
CHROMIUM = os.environ.get("CHROMIUM", "chromium")

ARGS = ["--no-sandbox", "--disable-gpu", "--use-gl=swiftshader", "--enable-unsafe-swiftshader"]

# Full-framebuffer scan for feature color signatures (fog-lit aware).
PIXEL_SCAN_JS = """() => {
  const canvas = document.querySelector('canvas');
  const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
  const w = canvas.width, h = canvas.height;
  const buf = new Uint8Array(w * h * 4);
  gl.readPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, buf);
  let bottomCool = 0, bottomTotal = 0, orange = 0, darkGreen = 0;
  const uniq = new Set();
  for (let y = 0; y < h; y++) {
    // NOTE: readPixels origin is BOTTOM-left, so framebuffer y<h*0.25 is the
    // bottom of the visible frame (ground when looking slightly down).
    const inBottom = y < h * 0.25;
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      const r = buf[i], g = buf[i+1], b = buf[i+2];
      if (inBottom) { bottomTotal++; if (b >= r && b > 100) bottomCool++; }
      if (r > 90 && r > g + 40 && g > b + 10) orange++;
      if (g > r + 8 && g > b + 4 && g < 120) darkGreen++;
      if ((i & 1023) === 0) uniq.add((r >> 3) + ',' + (g >> 3) + ',' + (b >> 3));
    }
  }
  return { bottomCoolFrac: bottomCool / Math.max(1, bottomTotal),
           orangePixels: orange, sprucePixels: darkGreen,
           distinct: uniq.size, total: w * h };
}"""


def main() -> int:
    errors: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch(executable_path=CHROMIUM, headless=True, args=ARGS)
        page = browser.new_page(viewport={"width": 800, "height": 600})
        page.on("pageerror", lambda e: errors.append(f"pageerror: {e}"))
        page.goto(URL, wait_until="load")
        page.wait_for_function("() => !!window.__boreal", timeout=30000)

        # 1) sim clock advances deterministically
        state = page.evaluate(
            """() => { const b = window.__boreal; b.reset(7); b.step(400);
                       return { day: b.world.day, hour: b.world.hourOfDay, t: b.world.t }; }"""
        )
        assert state["t"] > 90, f"sim did not advance: {state}"

        # 2) scripted movement moves the player and tracks terrain height
        moved = page.evaluate(
            """() => { const b = window.__boreal; b.reset(1);
                       const p0 = {x: b.world.player.x, z: b.world.player.z};
                       for (let i = 0; i < 80; i++) b.move(1, 0, true);
                       return { p0, p1: {x: b.world.player.x, z: b.world.player.z},
                                y: b.world.player.y, moving: b.world.player.moving }; }"""
        )
        d = ((moved["p1"]["x"] - moved["p0"]["x"]) ** 2
             + (moved["p1"]["z"] - moved["p0"]["z"]) ** 2) ** 0.5
        assert d > 5, f"player did not move: {d:.2f} m"
        assert moved["moving"], "moving flag not set"

        # 3) camera orbit changes the eye position and stays above terrain
        cam = page.evaluate(
            """() => { const b = window.__boreal;
                       const e0 = b.camera.position.clone();
                       b.orbitCam(2.0, 0.3); b.renderOnce();
                       const e1 = b.camera.position.clone();
                       return { moved: e0.distanceTo(e1), eyeY: e1.y,
                                playerY: b.world.player.y }; }"""
        )
        assert cam["moved"] > 0.1, f"camera did not orbit: {cam}"
        assert cam["eyeY"] > cam["playerY"] - 0.5, f"camera below player: {cam}"

        # 4) scene graph contains the sprint-1 features
        graph = page.evaluate(
            """() => { const names = {};
                       window.__boreal.scene.traverse(o => {
                         if (o.name) names[o.name] = (names[o.name] || 0) + 1; });
                       return names; }"""
        )
        for feat in ["terrain", "lake", "stream", "props_spruce", "props_birch",
                     "props_rock", "player", "crash"]:
            assert graph.get(feat, 0) >= 1, f"scene missing '{feat}': {sorted(graph)}"

        # 5) needs sim: idle night on the lake chills the core; debuff fires
        needs = page.evaluate(
            """() => { const b = window.__boreal; b.reset(1);
                       const t0 = b.world.needs.coreTemp;
                       // 6 game hours idle at night
                       for (let i = 0; i < 6 * 120; i++) b.step(1);
                       return { t0, t1: b.world.needs.coreTemp,
                                log: b.world.log.map(l => l.msg),
                                dead: b.world.dead || null }; }"""
        )
        assert needs["t1"] < needs["t0"] - 1.5, f"core temp did not drop overnight: {needs}"
        assert any('shivering' in m for m in needs["log"]), f"no shiver event: {needs['log']}"

        # 6) interaction: scavenge the wreck via the debug API
        loot = page.evaluate(
            """() => { const b = window.__boreal; b.reset(1);
                       b.world.player.x = 0; b.world.player.z = -140;
                       const ok = b.beginWork();
                       for (let i = 0; i < 20 * 60; i++) b.step(1); // plenty of time
                       return { ok, inv: b.world.inventory,
                                log: b.world.log.slice(-1)[0].msg }; }"""
        )
        assert loot["ok"], f"beginWork at wreck failed: {loot}"
        assert loot["inv"].get("knife") == 1, f"wreck loot missing knife: {loot}"

        # 7) day/night: sun intensity at noon >> midnight (rAF frames update sky)
        def sun_intensity(hour: float) -> float:
            page.evaluate(f"() => {{ window.__boreal.world.hourOfDay = {hour}; }}")
            page.wait_for_timeout(400)
            return page.evaluate(
                """() => { let s = 0;
                           window.__boreal.scene.traverse(o => { if (o.isDirectionalLight) s = o.intensity; });
                           return s; }"""
            )

        noon = sun_intensity(13)
        night = sun_intensity(1)
        assert noon > night * 3, f"day/night not working: noon={noon} night={night}"

        # 8) framebuffer pixel signatures at noon, from two deterministic poses.
        # Freeze the loop first so scripted poses survive to readPixels.
        page.evaluate(
            "() => { const b = window.__boreal; b.setPaused(true); b.reset(1); b.world.hourOfDay = 13; }"
        )

        def pixels_after_pose(px: float, pz: float, d_yaw: str, d_pitch: float) -> dict:
            page.evaluate(
                f"""() => {{ const b = window.__boreal;
                            b.world.player.x = {px}; b.world.player.z = {pz};
                            b.step(1); b.orbitCam({d_yaw}, {d_pitch});
                            // hide the player's red parka — it matches the orange
                            // signature and would mask the wreck check
                            b.scene.traverse(o => {{ if (o.name === 'player') o.visible = false; }});
                            b.renderOnce(); }}"""
            )
            page.wait_for_timeout(250)
            return page.evaluate(PIXEL_SCAN_JS)

        # pose A: on the lake south of the wreck, looking north (-z) at it
        # (camera forward = (-sin yaw, -cos yaw); yaw 0 → -z; dYaw = π from start yaw π)
        a = pixels_after_pose(0, -110, "Math.PI", -0.25)
        # pose B: forest edge east of the lake, looking east (+x) into trees
        # (yaw -π/2 → forward (+1, 0); dYaw = π - (-π/2) = 3π/2)
        b = pixels_after_pose(170, -100, "(3 * Math.PI / 2)", -0.1)

        browser.close()

    print("sim state:", state)
    print(f"moved: {d:.1f} m; cam: {cam}")
    print("lights: noon", noon, "night", night)
    print("pixels A (wreck):", a)
    print("pixels B (forest):", b)
    if errors:
        print("PAGE ERRORS:", errors)
        return 1
    assert a["bottomCoolFrac"] > 0.7, f"bottom not cool ground: {a['bottomCoolFrac']:.2f}"
    assert a["orangePixels"] > 100, f"crash site not visible: {a['orangePixels']} px"
    assert b["sprucePixels"] > 500, f"spruce silhouettes missing: {b['sprucePixels']} px"
    assert a["distinct"] > 8, f"flat framebuffer: {a['distinct']} colors"
    print("SMOKE_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())

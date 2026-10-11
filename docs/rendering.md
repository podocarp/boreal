# Headless rendering on this factory host (NixOS VM, no GPU)

**TL;DR — the only working path is weston (headless Wayland) + lavapipe (software Vulkan) + Godot's wayland/vulkan drivers. Use `scripts/render_shot.sh`; do not hand-roll it.**

```
weston --backend=headless --socket=wl-X --width=640 --height=360 &   # XDG_RUNTIME_DIR must be exported first
VK_DRIVER_FILES=<mesa>/share/vulkan/icd.d/lvp_icd.x86_64.json \
WAYLAND_DISPLAY=wl-X godot --path <proj> --display-driver wayland --rendering-driver vulkan
```

Verified: `Vulkan 1.4.354 - Forward+ - llvmpipe (LLVM 21.1.8)` renders real pixels; a 640x360
screenshot round-trip takes ~6s including compositor startup.

## Screenshot convention

`render_shot.sh` exports `SHOT_OUT=<absolute output png>`. A capture harness scene does:

```gdscript
func _process(_d):
    queue_redraw()
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(OS.get_environment("SHOT_OUT"))
    get_tree().quit.call_deferred()
```

`--quit-after 3600` is passed as a backstop so a forgotten `quit()` cannot hang CI.

## Two Godot modes — pick deliberately

| Mode | Command | Pixels? | Use for |
| --- | --- | --- | --- |
| headless | `godot --headless --script ...` | NO (dummy renderer) | sim tests, scene (de)serialization, CLI authoring, import passes — fast |
| weston windowed | `scripts/render_shot.sh` | YES (llvmpipe) | visual checkpoints only — CPU rasterization is slow, keep scenes small |

## Dead ends already burned on this host (do not retry)

- **Xvfb + GLX**: nixpkgs `xvfb` package ships no `libglx` module; `xorg-server`'s own Xvfb has
  `libglx.so` on disk but never loads it (no `-modulepath`/`-config` honored; `+extension GLX`
  ignored). `glxgears` → "couldn't get an RGB GLX visual".
- **EGL-on-X11**: Godot logs `EGL_EXT_platform_base not found` then SIGSEGVs in its crash handler
  (misleading "Illegal instruction" exit).
- **Vulkan + X11**: lavapipe exposes no `VK_KHR_surface` for X11 — impossible by construction.
- **bwrap bind of Mesa to `/run/opengl-driver`**: GLX failure is server-side; no client env var fixes it.
- Forgetting `VK_DRIVER_FILES` in the Godot process env → no Vulkan device → X11 fallback → crash.
  Looks like a Godot bug; it is an env bug.

## Performance budget

llvmpipe is CPU rasterization: expect seconds per frame for 3D Forward+ scenes at 640x360.
Visual checkpoints must be: fixed seed, fixed tick, ≤ a handful of objects, ≤ 640x360, and run
only at milestones or on failure. Semantic tests never need pixels.

## Audio

No sound card: ALSA errors at startup are benign (Godot falls back to the dummy driver).

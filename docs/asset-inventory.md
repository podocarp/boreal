# Shared Asset Inventory — `/srv/shared/game assets/`

Audited 2026-10-08 by direct directory listing and glTF/GLB JSON parsing (triangle counts
are actual index-buffer counts from sampled models, not estimates; audio durations by
ffprobe).
Updated 2026-10-08 (deep-audit pass): library naming standard adopted (see below); three
itch.io packs added and audited in depth (KayKit Adventurers, Modern Interiors, Music Loop
Bundle); all directories renamed to the standard; global format counts recounted across the
whole library.

## Library standard (applies to every pack here)

- **Directory name:** `<Pack>_<Author>` — CamelCase, no spaces, no brackets, no version
  numbers (versions change; the pack identity doesn't). Examples:
  `StylizedNatureMegaKit_Quaternius`, `MusicLoopBundle_Tallbeard`.
- **`SOURCE.txt` in every pack root** (provenance manifest): source URL, fetch date,
  itch rating, tags, license pointer, and the full upstream file list with what was
  fetched vs skipped. Written automatically by the `itch-asset-fetch` skill's
  `itch.py get`; hand-written for manually-added packs.
- **Keep the upstream license file** (`License.txt` / `_LICENSE.txt`) where it is; never
  delete it. If a pack ships no license file, add one to `SOURCE.txt` quoting the page.
- **Extracted archives:** keep the original `.zip` next to the extracted tree only if
  under ~50 MB; otherwise extract and drop the zip (the SOURCE.txt file list preserves
  what the zip contained).
- **Adding a pack:** prefer the `itch-asset-fetch` skill (search → info → vision-check
  the cover → `get --name <Pack>_<Author> --extract`), then add a section to this doc.

**Global facts (verified 2026-10-08, full-library recount):**
- **No pack is a Godot project** — zero `project.godot`, zero `.tscn` anywhere. All packs are
  raw DCC exports (FBX / glTF / OBJ). Nothing needs "open in editor once"; everything is
  copy-into-`res://` and let Godot import.
- **No `.blend` files anywhere** — no Blender dependency.
- **Audio: music AND SFX covered as of 2026-10-11** — `MusicLoopBundle_Tallbeard` adds 334 OGG
  music loops (CC0; ffprobe-measured 4 h 35 min total). SFX gap closed 2026-10-11 with the
  two Kenney packs below (§13, §14 — CC0, direct from kenney.nl) plus single-file CC0 SFX
  from OpenGameArt (fireplace loop, wind whoosh loop, propeller loop, game-over sting,
  menu tick — provenance recorded per-file in `assets/audio/LICENSE.txt`).
- **Rigged + animated characters: covered as of 2026-10-08** — `KayKitAdventurers_KayLousberg`
  ships 6 skinned characters + 26 shared animation clips on one common 23-bone rig
  (idle/walk/run/jump/hit/death/interact/pickup/throw/use — full list in §8). Universal
  Base Characters still has `animations: 0` (rig only); its skeleton differs from
  Rig_Medium, so animating it means hand-authoring or a retarget pass — prefer KayKit for
  anything that moves.
- Formats present (whole library, recounted): `.glb` (473), `.gltf+.bin` (170), `.fbx` (894,
  binary Kaydara format), `.obj+.mtl` (152), `.ogg` (334), `.png` (208), `.jpg` (6),
  `.tga` (1). Godot 4.7 imports glTF/GLB and OGG natively, binary FBX via the built-in
  (theufu) importer, OBJ via tinyobjloader, TGA natively.
  **Use the glTF/GLB variants wherever a pack offers them** — fewer import surprises, materials
  come through correctly.
- **License: every pack is CC0 1.0 except ModernInteriors_LimeZu** (verified by reading each
  license file). CC0 packs are safe for GitHub-published, commercial, and redistributed use;
  attribution optional everywhere. **ModernInteriors_LimeZu free tier is NON-COMMERCIAL
  ONLY** — see §6 and the redistribution section.

---

## 1. CookingAssets_MilkAndBanana (MilkAndBanana)

- **Contents:** 231 unique cooking props (appliances, pans, knives, boards, bowls, plates,
  cups, utensils, gadgets, chopsticks…) in two parallel trees: `GLB/<Category>/*.glb`
  (+ `GLB/All/` with all 231) and `FBX/<Category>/*.fbx`.
- **Formats:** `.glb` (textures embedded — verified: 1–3 textures per file, no sidecar files)
  and `.fbx`. Use GLB.
- **Style / budget:** stylized low-poly, flat/vertex-ish shading. Measured: dutch oven 372 tris,
  oven 2.5k, rice cooker 7.3k tris. Typical prop ≈ 0.3–3k tris. Files 15–150 KB each.
- **Godot 4.7:** drop `.glb` into `res://assets/…`, imports directly, materials embedded.
- **License:** CC0 (MilkAndBanana, itch.io). Credit optional.
- **Size on disk:** 25 MB.

## 2. PondKit_AssetQuest (Asset Quest)

- **Contents:** 89 FBX meshes — pond basins (Pond_1–4), rocks/pebbles (many moss variants),
  cattails, grass patches, mini plants, branches, plus small creatures (frog, bird, dragonfly
  ×3 variants each), clay pot, tubs.
- **Formats:** FBX only (binary). Textures: `Pond_Plants_Atlas_2K.tga` (plant atlas; **alpha
  channel = plant cutout opacity** — Godot imports TGA fine, but set transparency hint to
  "Alpha" on the plant material) + `Pond_Props_BaseColor.png` (6.5 KB color-swatch atlas).
- **Style / budget:** low-poly stylized nature; readme says metalness 0, one shared atlas.
  No glTF variant → FBX import required (works in 4.7; verify materials re-assign after import
  since FBX material embedding is weaker than glTF).
- **Godot note from readme:** disable backface culling (cull-disabled material) for plants —
  required, not optional.
- **License:** CC0 (Asset Quest). Credit optional.
- **Size:** 8.7 MB (mostly the 9 MB TGA).

## 3. KayKitFurnitureBits_KayLousberg (Kay Lousberg)

- **Contents:** 53 furniture props (beds, chairs, couches, cabinets, lamps, rugs, picture
  frames, pillows, plants, books…) in `Assets/`:
  - `kaykit furniture free/` — **glTF+bin, one shared texture** ← use this
  - `fbx/`, `fbx (unity)/`, `obj/` — duplicates in other formats
  - `texture/furniturebits_texture.png` — single atlas for everything
- **Style / budget:** low-poly stylized, one 1024-ish atlas, no PBR maps. Couch = 636 tris;
  typical prop < 1k tris.
- **Godot 4.7:** copy `Assets/kaykit furniture free/*.gltf+bin` + the texture png (keep the
  relative path the gltf expects, or re-point the material after import).
- **License:** CC0. Credit optional.
- **Size:** 6.7 MB.

## 4. StylizedNatureMegaKit_Quaternius (Quaternius)

- **The boreal workhorse.** 68 models (of 116 in PRO — free tier is partial, stated in license
  file). In `glTF/` (68 × `.gltf+.bin`, textures as sidecar PNGs in the same dir), plus `FBX/`,
  `FBX (Unity)/`, `OBJ/` duplicates and a `Textures/` mirror.
- **Model list (verified):** CommonTree_1–5, Pine_1–5, DeadTree_1–5, TwistedTree_1–5,
  Bush(_Flowers), Clover_1–2, Fern_1, Flower_3/4 (single+group), Grass_Common/Wispy
  (short+tall), Mushroom_Common, Mushroom_Laetiporus, Pebble_Round_1–5, Pebble_Square_1–6,
  Petal_1–5, Plant_1/7 (+big), Rock_Medium_1–3, RockPath_Round/Square pieces (5 each).
- **Textures:** 20 PNGs incl. bark diffuse+normal ×3, leaves/grass/flowers/mushrooms/rocks
  atlases, some `_C` (color-tint) variants. Diffuse+normal only — stylized, not PBR.
- **Budget (measured):** Pine 3.9k, CommonTree 6.3k, Rock 342, Grass 326 tris. Trees 3–7k,
  ground clutter < 500. Good for a survival game at moderate tree counts.
- **Godot 4.7:** copy `glTF/*.gltf + *.bin + *.png` **together, flat** (gltfs reference the
  PNGs by relative filename in the same folder). Alpha-cutout leaves need the transparency
  hint set post-import (glTF import usually gets `KHR_materials` alpha right for these).
- **License:** CC0, free "Standard" tier = 68/116 models; PRO/SOURCE paid (SOURCE has a Godot
  project with the stylized shader — we don't have it; the free glTFs import fine without it).
- **Size:** 111 MB (FBX/OBJ duplicates are most of it; the glTF subset is small).

## 5. UniversalBaseCharacters_Quaternius (Quaternius)

- **Contents:** 2 rigged base characters — **Superhero_Male_FullBody, Superhero_Female_FullBody**
  — in `Base Characters/Godot - UE/` (glTF+bin, **for Godot/UE scale**) and `Unity/` (FBX).
  8 hairstyles in `Hairstyles/Origin at 0/glTF (Godot)/` and 8 in `Rigged to Head Bone/glTF
  (Godot -Unreal)/` (Eyebrows, Beard, Buns, Buzzed, BuzzedFemale, Long, SimpleParted…).
  ~48 PNG textures (basecolor/normal/roughness per character, hair, eyes) — this pack is the
  only PBR-ish one (has roughness maps).
- **Budget (measured):** male FullBody = 14.3k tris, skinned (`skins: 1`), **`animations: 0`**
  — rigged skeleton, no animation clips included. **For boreal this is now the fallback, not
  the pick**: KayKit Adventurers (§8) ships its own clips; keep UBC only if you want the
  realistic-PBR base and bring your own (e.g. mixamo-retargeted) animations.
- **Gotcha (from pack README):** glTF variants exist because Blender→FBX rigged export has a
  scale bug; **use the `Godot - UE` glTFs, not the Unity FBXs**. Use the normals under
  `Textures/Normals Unity - Godot/` (OpenGL +Y convention) if re-wiring materials.
- **License:** CC0, Standard = partial (SOURCE paid adds .blend rigs + Godot project).
- **Size:** 126 MB.

## 6. ModernInteriors_LimeZu (LimeZu)

- **Contents (verified by listing):** free tier of the Modern Interiors RPG tileset —
  top-down interior tiles: furniture + floors/walls (`Interiors_free_16x16/32x32/48x48.png`
  and `Room_Builder_free_16x16/32x32/48x48.png` — **three pixel-grid sizes shipped, not
  just 16×16**), 4 characters (Adam, Alex, Amelia, Bob) with idle/run/sit/phone sprite
  sheets, `free_overview.png` preview, plus an `Old/` legacy tileset folder.
  `Modern tiles_Free/` tree, PNG only.
- **Formats:** 2D PNG only (not a 3D pack). Godot: import as-is; spritesheets need manual
  region setup or AnimatedSprite2D frames.
- **Style:** cozy Stardew-like pixel interiors, warm muted palette. Vision-checked cover
  suggests effective detail closer to 32×32 than strict 16×16 — verify grid before use.
- **Rating:** 4.9★ (609) on itch. **License: NON-COMMERCIAL ONLY** — `LICENSE.txt` allows
  use/edit in non-commercial projects, forbids commercial use and reselling. Fine for
  jams/prototypes; buy the paid tier before shipping any commercial game with it.
- **Relevance to boreal: none** — boreal is 3D third-person; this is a 2D pixel tileset.
  Kept in the library for other (2D) projects only.
- **Size:** 2.9 MB. `SOURCE.txt` present.

## 7. MusicLoopBundle_Tallbeard (Abstraction Music / Tallbeard Studios)

- **Contents (verified):** **334 OGG music loops, ffprobe-measured total 4 h 35 min**
  (16 503 s), flat in pack root, 1.4 GB. Music only — **no SFX in this pack**.
  `_LICENSE.txt` + `_README.txt` + `_TROUBADECK_INFO.txt` in root.
- **Formats:** `.ogg` (Vorbis, stereo) — use OGG, not MP3 (readme: MP3 framing breaks
  seamless loops; Godot's loop points on OGG work correctly).
- **Seamless-loop status:** the whole bundle is authored as seamless loops (the pack's
  premise; itch tag "seamless"). No `LOOPSTART`/`LOOPEND` vorbis tags found in sampled
  files — the loop point is baked into the encode, so Godot's default loop on
  AudioStreamOggVorbis is the right usage. Naming conventions signal structure:
  `_IN`/`_LOOP` pairs (intro + seamless body, e.g. `Interior Birdecorator Menu_IN/_LOOP`),
  `BASE`/`MELODY`/`CHORDS` stems for layering (Week series), `_EXTENDED`, `_TRANS`
  interludes. Metadata reference sheets in root: `FreeLoopsMetadata.png`,
  `Free Chiptune Metadata.png`.
- **Collections by name prefix (counts):** Week 1–39 series (~120 tracks, themed two-mood
  pairs — the richest vein for game-specific scoring), Sketchbook 2023–2025 (~85 dated
  drops), Troubadeck 01–54 (54, cute/cartoony), VGMA Challenge 01–31 (31), Three Red
  Hearts (21, chiptune), Ludum Dare 28/30/32/38 (32), Patreon Challenge 01–14 (16),
  Interior Birdecorator (7), Dani Maccari (2), misc (3).
- **Style:** broad — ambient, chiptune, upbeat, orchestral-ish; covers most genres.
- **Rating:** 4.9★ (325) on itch. **License:** CC0 public domain (`_LICENSE.txt` read: full
  copyright waiver; "any commercial or non-commercial project, may be modified in any way").
  Non-endorsement ask (not a license restriction): against NFT / AI-ML-training /
  unmodified-resale use. Credit optional; author asks to be listed as "Abstraction".
- **Size:** 1.4 GB extracted (zips dropped per library standard; full file list in
  `SOURCE.txt`). Song-browser/troubadeck player apps were skipped — music only.

## 8. KayKitAdventurers_KayLousberg (Kay Lousberg)

- **Contents (verified by listing):** 6 rigged stylized humanoid characters —
  **Barbarian, Knight, Mage, Ranger, Rogue, Rogue_Hooded** — in
  `KayKit_Adventurers_2.0_FREE/Characters/gltf/*.glb` (texture embedded in each GLB;
  sidecar PNGs in the same folder serve the FBX/OBJ trees). Plus:
  - **26 shared animation clips** in `Animations/gltf/Rig_Medium/` (full list below)
  - **31 weapon/prop glTF+bin** in `Assets/gltf/` (swords ×3, axes ×2, bow, crossbows,
    daggers, shields ×8, staff, wand, spellbooks, quiver, arrows, mug, smokebomb) — each
    references a sibling `*_texture.png` (verified `image.uri = "knight_texture.png"`),
    so keep that folder flat
  - `Animations/fbx/Rig_Medium/`, `Characters/fbx/`, `Assets/fbx|fbx(unity)|obj/` — format
    duplicates; don't copy into a Godot project
- **Animation clips (parsed from the GLB JSON — this is the library's character-animation
  answer):**
  - `Rig_Medium_General.glb` — 15 clips: `Idle_A`, `Idle_B`, `Hit_A`, `Hit_B`, `Death_A`,
    `Death_A_Pose`, `Death_B`, `Death_B_Pose`, `Interact`, `PickUp`, `Spawn_Air`,
    `Spawn_Ground`, `Throw`, `Use_Item`, `T-Pose`
  - `Rig_Medium_MovementBasic.glb` — 11 clips: `Walking_A`, `Walking_B`, `Walking_C`,
    `Running_A`, `Running_B`, `Jump_Start`, `Jump_Full_Long`, `Jump_Full_Short`,
    `Jump_Idle`, `Jump_Land`, `T-Pose`
  - Packaging: **characters carry NO embedded animations** (`animations: 0` in every
    character GLB); clips live only in the two shared animation GLBs. Import both kinds
    and retarget in Godot.
- **Rig (verified):** 23-joint `Rig_Medium` skeleton (root, hips, spine, chest,
  upperarm/lowerarm/hand, upperleg/lowerleg/foot/toes…) — **identical skeleton in every
  character and in both animation GLBs** → any clip drives any character; Godot 4 retargets
  by bone name with no extra work.
- **Budget (measured, index-buffer tris):** Knight 5.8k, Mage 6.7k, Barbarian 7.1k,
  Rogue_Hooded 7.2k, Rogue 7.6k, Ranger 8.9k. 7–9 meshes per character (body + gear parts,
  all skinned to the one rig).
- **Third-person controller:** the library's answer for humanoid 3rd-person — drop a
  `Characters/gltf/*.glb` + the two animation GLBs into `res://`, Godot 4 imports
  skeleton + clips; wire an AnimationTree (Idle/Walk/Run/Jump states) on the shared rig.
  No movement logic included (none needed).
- **Style:** chunky toy-like cartoon (vision-verified), cohesive party, reads well from
  behind. Matches KayKit furniture (pack 3) — same author/look.
- **Rating:** 4.9★ (277). **License:** CC0 (`License.txt` read: "Creative Commons Zero,
  CC0… free to use in personal, educational and commercial projects"; credit optional).
  Free tier 2.0 — paid tiers add more characters/anim sets (Samples/ previews Druid,
  Engineer).
- **Size:** 12 MB zip / 30 MB extracted. `SOURCE.txt` present.

## 9. GobkitAnimalPackA_Gobkit (Gobkit)

- **Contents (measured):** 10 animals, one self-contained `.glb` each (textures embedded):
  Anglerfish, Bat, Corgi, Duck, Hippo, Jellyfish, Platypus, Red (red panda), Rhino, Shark.
- **Rig/anims (parsed from GLB JSON):** every model skinned to a **16-bone rig** with
  **1 embedded animation clip** (idle/locomotion loop). Tri budget 266–508 per animal —
  extremely cheap.
- **Style (vision-verified):** smooth-shaded rounded low-poly, flat saturated color-block
  materials, big glossy eyes, chibi proportions ("plush toy" read). Vision verdict: shares
  the low-poly flat-color toy DNA of KayKit; slightly softer/rounder and cuter-eyed than
  KayKit's more faceted humans — fine together in a casual cartoon game, unify lighting.
- **Caveat:** one clip per animal (no walk/run/attack variety); fine for ambient/fauna use,
  combat animals would need authored or retargeted clips.
- **License:** CC0 (stated on itch page; no license file shipped upstream). No itch rating
  yet (new pack). **Size:** 680 KB. `SOURCE.txt` present.

## 10. GobkitAnimalPackB_Gobkit (Gobkit)

- **Contents (measured):** 10 more animals, same series/format: Bee, Blue (blue whale?
  bird), Boar, Fugu, Goat, Marmot, Owl, Rat, Seal, Whale — one `.glb` each, 16-bone rig,
  1 clip ("Take 001") per model, 256–398 tris.
- **Style:** identical to pack 9 (same author/series) → A+B are mutually uniform; Boar,
  Goat, Owl, Rat, Seal are the land/air game-relevant ones for boreal-adjacent settings.
- **License:** CC0 (page-stated). **Size:** 1.2 MB. `SOURCE.txt` present.

## 11. FarmAnimalsAnimated_Quaternius (Quaternius)

- **Contents:** 7 farm animals — Cow, Horse, Llama, Pig, Pug, Sheep, Zebra — in
  `FBX/` (with embedded textures, ~1 MB each), `OBJ/` (+MTL), `Blend/`, `Preview.gif`.
  **No glTF** — Godot imports FBX natively (Blender not required).
- **Rig/anims:** skinned + walk-cycle animated (preview gif shows mid-stride lineup;
  FBX binary — clip names not parsed here; verify on import).
- **Style (vision-verified on Preview.gif frame):** low-poly **flat-shaded faceted**
  cartoon, color-blocked materials, chunky toy proportions — vision verdict: *closer to
  KayKit's faceted look than Gobkit's smooth roundness*; "standard, visually coherent
  combination" with KayKit Adventurers. Same author as StylizedNatureMegaKit (pack 4),
  so nature + animals share one author's hand.
- **Content gap for boreal:** farm set (cow/pig/llama…) — no wolf/reindeer/arctic fauna;
  Gobkit B's Boar/Owl/Rat/Seal are closer to that niche.
- **Rating:** 4.9★ (11). **License:** CC0 (page-stated). **Size:** 16 MB. `SOURCE.txt` present.

## 12. LowPolyPlane_DeJunes (DeJunes)

- **Contents (verified 2026-10-11):** one low-poly high-wing light plane
  ("cessna_152") — `cessna_152.fbx` (binary Kaydara; 14 MeshInstance3D parts,
  ~2.5k tris, flat-color red/white livery materials, no textures), plus the
  source `.blend` and zip. Godot 4.7 imports the FBX cleanly (materials come
  through; part transforms are messy Blender export scales — normalize at
  runtime, see `src/render/wreck_visuals.gd`).
- **Style (vision-verified on cover + in-engine render):** very-low-poly
  faceted flat-shaded, flat-color materials — same family as Quaternius/
  KayKit; reads well next to the Stylized Nature kit.
- **License:** Royalty Free per page text "free to use in any kind of
  project" (verified 2026-10-11; no license file ships inside the zip —
  recorded in `SOURCE.txt`). No attribution required.
- **Size:** ~1 MB. `SOURCE.txt` present. **Used by boreal** as the crash-site
  plane wreck (`assets/wreck/`).

## 13. KenneyRPGAudio_Kenney (Kenney)

- **Contents (verified 2026-10-11):** 50 OGG SFX (`Audio/*.ogg`) — foley
  footsteps (footstep00–09), cloth, books, doors, drops, clicks,
  confirmations, errors. Extracted from the direct kenney.nl zip.
- **License:** Creative Commons CC0 1.0 (page "License" field, verified
  2026-10-11 via browser; `License.txt` ships in the pack).
- **Size:** ~1 MB. `SOURCE.txt` present. **Used by boreal**: footstep00–04
  copied to `assets/audio/footstep_00..04.ogg` (walking cadence
  variants; see `src/audio/audio_director.gd`).

## 14. KenneyInterfaceSounds_Kenney (Kenney)

- **Contents (verified 2026-10-11):** 100 OGG UI SFX (`Audio/*.ogg`) —
  clicks, switches, ticks, pops, confirmations, errors. Extracted from the
  direct kenney.nl zip.
- **License:** Creative Commons CC0 1.0 (page "License" field, verified
  2026-10-11 via browser; `License.txt` ships in the pack).
- **Size:** ~0.8 MB. `SOURCE.txt` present. Spare UI-sound pool for boreal
  (the shipped `ui_confirm.ogg` came from OGA menu-select-tick; swap freely).

### OGA CC0 singles (not a pack — fetched per-file 2026-10-11)

Fireplace Sound loop (PagDev), wind whoosh loop (SketchMan3), Propeller
Cartoon Loop (Mish7913), Game Over! (zuvizu), Menu select tick (mikeask) —
all CC0 per page badge, re-encoded mono OGG, live in
`assets/audio/` with per-file provenance in `LICENSE.txt`.
Note: the CC0-only search facet on OpenGameArt is `field_art_licenses_tid[]=4`;
snow-footstep candidates there ship as .7z (no extractor on this host) —
Kenney RPG Audio's footstep set is the working route.

---

## Suitability for porting **boreal** (stylized arctic survival)

| boreal need | coverage | source |
|---|---|---|
| Trees (pines, dead, twisted) | ✅ strong | Stylized Nature: Pine_1–5, DeadTree_1–5, TwistedTree, CommonTree |
| Rocks / boulders / pebble scatter | ✅ | Stylized Nature Rock_Medium + Pebbles; Pond kit rocks (mossy — less arctic) |
| Ground clutter (grass, ferns, mushrooms) | ✅ (green — tint or skip under snow) | Stylized Nature grass/fern/mushroom set |
| Character + animation | ✅ **(was the biggest gap — now closed)** | KayKitAdventurers: 6 rigged characters + 26 clips (Idle/Walk/Run/Jump/Interact/PickUp/Death…) on shared Rig_Medium; weapons/props included. Matches KayKit look. UBC only if you want the PBR base (then bring/retarget your own anims) |
| Campfire | ⚠️ partial | No fire logs/stones pack; KayKit has no campfire. Improvise: Pond `Branch_1–3` as logs + Stylized rocks as fire ring. Flames = own shader/particles |
| Snow terrain | ❌ missing | No snow material/terrain kit in any pack. Procedural: white-blue vertex-tinted terrain + Stylized Nature rocks/trees with a snow-cap shader or vertex-color snow mask |
| Snow-covered trees | ❌ missing | Recolor: trees use `_C` tint atlases (Leaves_GiantPine_C etc.) — shift hue toward desaturated blue-white |
| Aurora sky | ❌ missing | Own procedural sky / skybox shader (Godot `ProceduralSkyMaterial` + custom shader bands) |
| Wolf | ⚠️ **partial — quadrupeds now in library, but no wolf** | Gobkit A+B (20 rigged+animated quadrupeds/creatures, CC0, GLB) + Quaternius farm set (7, FBX, walk anims). Closest to boreal fauna: Boar, Owl, Rat, Seal (Gobkit B), Horse/Sheep (Quat). **No wolf/reindeer/fox** — KayKit has no animal pack; either model a wolf on the Gobkit 16-bone style or check Kenney/Quaternius paid "Animals" later |
| Crashed plane wreck | ✅ **(was the critical gap — closed 2026-10-11)** | LowPolyPlane_DeJunes (§12): royalty-free low-poly Cessna FBX, flat-color livery, imports clean in Godot 4.7; posed as a crash by `src/render/wreck_visuals.gd` |
| Camp/shelter furniture | ✅ | KayKit Furniture Bits (beds, crates→cabinets, lamps, rugs — cabin interior) |
| Cooking/crafting props | ✅ strong | Cooking Assets, 231 props (pots, knives, boards, stove…) — fits survival crafting UI/props perfectly |
| Water (thaw ponds) | ✅ | Pond kit basins + water material |
| Audio (music) | ✅ (as of 2026-10-08) | MusicLoopBundle_Tallbeard — 334 CC0 OGG loops, 4.6 h; top boreal picks below |
| Audio (SFX) | ✅ **(closed 2026-10-11)** | KenneyRPGAudio_Kenney (§13: footstep set) + KenneyInterfaceSounds_Kenney (§14: UI pool) + OGA CC0 singles (fire crackle, wind loop, plane flyby, death sting, UI confirm) — wired in `src/audio/` |
| 2D interiors | n/a | ModernInteriors_LimeZu is a 2D pixel tileset — irrelevant to 3D boreal, and non-commercial-licensed anyway |

**Top boreal music picks** (from the Week series — themed mood pairs, seamless loops, CC0;
durations ffprobe-measured):
1. `Week 2 - Ruined Lands WASTELAND.ogg` (36 s) — desolate post-crash main/exploration theme
2. `Week 19 - Dark Portents SHROUDED FUTURE.ogg` (33 s) — tense night / wolf-threat layer
3. `Week 35 - Reverence ENDLESS.ogg` (49 s) — solemn ambient calm (aurora / campfire beats)
4. `Week 31 - Forget About Us AMNESIA.ogg` (22 s) — melancholy calm (story/memory scenes)
5. `Week 9 - Graceful Descent FLOATING.ogg` (25 s) — weightless calm (idle / northern lights)
   Backups: `Week 2 - Ruined Lands HOPE` (hope motif, same key as #1), `Week 27 - Dusty
   Memories`, `Week 11 - Lost in Space`, `Week 24 - Pull Me Down DEEP WELL`,
   `Troubadeck 20 Long Lonely Road`.

**Verdict:** Stylized Nature + Cooking + KayKit (furniture + adventurers) + the music
bundle give a coherent Quaternius/KayKit-adjacent stylized look and cover ~75% of boreal's
needs (flora, rocks, props, animated character, music). Plane wreck closed 2026-10-11
(LowPolyPlane_DeJunes); SFX closed 2026-10-11 (Kenney §13/§14 + OGA CC0 singles, wired in
`src/audio/`). **Must source externally before port:** wolf (or substitute
another animal), snow material approach, aurora sky.

## License / redistribution (GitHub publication)

- **Packs 1–5, 7 (Music Loop Bundle) and 8 (KayKit Adventurers): CC0 1.0 Universal** —
  public-domain dedication, verified by reading `License.txt` / `License_Standard.txt` /
  `_LICENSE.txt` in each. Commercial use, modification, redistribution on GitHub:
  **allowed, no attribution required** (all authors ask for optional credit; the music
  author additionally asks — outside license terms — against NFT/ML/unmodified-resale use).
- **Pack 6 (ModernInteriors_LimeZu) is NOT CC0 and NOT commercial-safe** — free tier is
  **non-commercial use only** per its `LICENSE.txt`. Do not ship it in a commercial game
  or a public repo that implies commercial intent without checking the paid tier.
- Recommended repo hygiene: keep each pack's original `License.txt` next to the copied subset
  in `game/assets/<pack>/`, and add a one-paragraph credits section to the game README
  (MilkAndBanana, Asset Quest, Kay Lousberg / KayKit, @Quaternius, Abstraction/Tallbeard).
  Costs nothing, avoids any bad-faith dispute.
- The two Quaternius "[Standard]" packs are the **free partial tiers** — redistributing them is
  still CC0; just don't imply you have the PRO/SOURCE content. Same caveat for KayKit free
  tiers (Adventurers 2.0 FREE = 6 of the paid roster).
- No EULAs, no asset-store restrictions, no non-redistributable terms found anywhere except
  the ModernInteriors non-commercial clause.

## Import guidance for porting agents (res://)

1. **Prefer glTF/GLB from every pack.** Never copy FBX/OBJ duplicates into a Godot project —
   they're format duplicates that only bloat the repo (Nature pack: copy only `glTF/`, ~small,
   not the 111 MB).
2. **Cooking Assets:** copy `GLB/All/*.glb` (or per-category subsets) → `res://assets/cooking/`.
   Self-contained, zero sidecars.
3. **KayKit:** copy `Assets/kaykit furniture free/*.gltf|*.bin` **plus**
   `furniturebits_texture.png` (a copy already sits inside that folder; gltfs reference it as
   a sibling — verified `image.uri = "furniturebits_texture.png"`). One flat folder works.
4. **Stylized Nature:** copy `glTF/` contents (gltf + bin + png together, flat) →
   `res://assets/nature/`. Do not split textures into another folder.
5. **Pond Kit:** FBX-only. Copy `Meshes/*.fbx` + `Textures/*` → `res://assets/pond/`; after
   import, re-assign the TGA atlas (alpha = cutout) and set plant materials cull-disabled
   (readme requirement). Or pre-convert to glb once with `godot --headless --import` and commit
   the .glb if FBX materials misbehave.
6. **KayKit Adventurers:** copy `Characters/gltf/*.glb` (textures embedded — the GLBs alone
   are self-contained), `Animations/gltf/Rig_Medium/*.glb`, and `Assets/gltf/*` **flat with
   their sibling `*_texture.png` files** (prop gltfs reference e.g. `knight_texture.png` by
   relative name). In Godot: each character imports with the Rig_Medium skeleton; the two
   animation GLBs import as clips — retarget via AnimationTree (bone names match exactly).
7. **Universal Base Characters:** only if you want the realistic base instead of KayKit —
   copy `Base Characters/Godot - UE/*.gltf|*.bin|*.png` and `Hairstyles/…/glTF (Godot)/*` →
   `res://assets/chars/`. Use these glTFs, **not** the Unity FBX (known rigged-FBX scale bug,
   per pack README). Normals for re-wiring: the `Normals Unity - Godot` folders. No
   animations included — expect to add your own.
8. **Music:** copy only the tracks you use → `res://assets/audio/music/` (never the whole
   1.4 GB into the repo). Import as AudioStreamOggVorbis with loop enabled; for `_IN`/`_LOOP`
   pairs play IN then hand off to LOOP at the track boundary.
9. **Headless CI:** all of the above import with `godot --headless --import` on first run;
   no editor session is ever required (no project.godot in any pack, no .blend).

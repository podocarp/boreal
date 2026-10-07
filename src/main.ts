/**
 * BOREAL — boot: wires sim + render + input + HUD. Sprint 1: terrain, movement,
 * Skyrim-style third-person camera, day/night cycle, stylized scatter world.
 */
import * as THREE from 'three';
import { CONFIG } from './sim/config';
import { beginWork, boilWater, buildShelter, checkSnares, createWorld, currentTarget, drink, eat, feedFire, feelsLike, fireFlare, fish, lightFire, setSnareAction, signalSmoke, step, tickWork, toggleSleep, treatWound, cook, type WorldState } from './sim/world';
import { updatePlayer } from './sim/player';
import { computeDebuffs } from './sim/needs';
import { RECIPES, craft, canCraft } from './sim/craft';
import { INTERACT_LABEL } from './sim/interact';
import { heightAt } from './sim/terrain';
import { buildScene } from './render/scene';
import { createCamState, orbit, updateCam, CAM, type CamState } from './render/camera';
import { createInput, readIntent, consumeKey, isHeld, consumeMouseButton, isMouseButtonHeld } from './input/input';
import { updateSky } from './render/daynight';
import { updateHud, hideEndScreen } from './ui/hud';
import { contextActions, primaryAction, type ActionCtx } from './sim/actions';
import { openMenu, closeMenu, menuIsOpen, menuSteer } from './ui/menu';

let world: WorldState = createWorld(1);
let cam: CamState = createCamState();

const app = document.getElementById('app')!;
const bundle = buildScene(app);
const { scene, camera, renderer, sun, hemi, fog } = bundle;
const input = createInput(renderer.domElement);

/** Fire visuals: one group per sim fire (log pile + flame + point light). */
const fireGroups = new Map<number, { group: THREE.Group; light: THREE.PointLight; flame: THREE.Mesh }>();
function syncFireMeshes(): void {
  const seen = new Set<number>();
  for (const f of world.fires) {
    seen.add(f.id);
    let g = fireGroups.get(f.id);
    if (!g) {
      const group = new THREE.Group();
      const logs = new THREE.Mesh(
        new THREE.BoxGeometry(1.2, 0.25, 0.5),
        new THREE.MeshLambertMaterial({ color: 0x4a3524, flatShading: true }),
      );
      logs.rotation.y = 0.6;
      logs.position.y = 0.12;
      group.add(logs);
      const flame = new THREE.Mesh(
        new THREE.ConeGeometry(0.45, 1.1, 5),
        new THREE.MeshBasicMaterial({ color: 0xff8c3a }),
      );
      flame.position.y = 0.75;
      group.add(flame);
      const light = new THREE.PointLight(0xff9a45, 0, 12, 1.6);
      light.position.y = 1;
      group.add(light);
      group.position.set(f.x, heightAt(f.x, f.z), f.z);
      scene.add(group);
      g = { group, light, flame };
      fireGroups.set(f.id, g);
    }
    const stage = f.lit ? Math.max(1, Math.min(4, Math.ceil(f.fuel / 25))) : 0;
    g.flame.visible = stage > 0;
    g.flame.scale.setScalar(0.4 + stage * 0.25);
    g.light.intensity = stage * 2.2;
    g.light.distance = 4 + stage * 4;
  }
  for (const [id, g] of fireGroups) {
    if (!seen.has(id)) {
      scene.remove(g.group);
      fireGroups.delete(id);
    }
  }
}

/** Shelter visuals: lean-to mesh grows with build step. */
const shelterGroups = new Map<number, THREE.Group>();
const wolfGroups = new Map<number, THREE.Group>();
function makeWolfMesh(): THREE.Group {
  const g = new THREE.Group();
  const grey = new THREE.MeshLambertMaterial({ color: 0x6b6f75, flatShading: true });
  const dark = new THREE.MeshLambertMaterial({ color: 0x3a3d42, flatShading: true });
  const body = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.5, 1.1), grey);
  body.position.y = 0.55;
  const head = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.34, 0.45), grey);
  head.position.set(0, 0.78, 0.72);
  const snout = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.16, 0.22), dark);
  snout.position.set(0, 0.7, 0.98);
  g.add(body, head, snout);
  for (const [dx, dz] of [[-0.18, 0.35], [0.18, 0.35], [-0.18, -0.35], [0.18, -0.35]] as const) {
    const leg = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.4, 0.13), dark);
    leg.position.set(dx, 0.2, dz);
    g.add(leg);
  }
  return g;
}
function syncWolfMeshes(): void {
  const seen = new Set<number>();
  for (const w of world.wolves) {
    seen.add(w.id);
    let g = wolfGroups.get(w.id);
    if (!g) {
      g = makeWolfMesh();
      wolfGroups.set(w.id, g);
      scene.add(g);
    }
    g.position.set(w.x, heightAt(w.x, w.z), w.z);
    const d = Math.hypot(world.player.x - w.x, world.player.z - w.z) || 1;
    g.rotation.y = Math.atan2((world.player.x - w.x) / d, (world.player.z - w.z) / d);
    g.visible = w.state !== 'fleeing';
  }
  for (const [id, g] of wolfGroups) {
    if (!seen.has(id)) {
      scene.remove(g);
      wolfGroups.delete(id);
    }
  }
}

function syncShelterMeshes(): void {
  const seen = new Set<number>();
  for (const s of world.shelters) {
    seen.add(s.id);
    let g = shelterGroups.get(s.id);
    if (!g) {
      g = new THREE.Group();
      scene.add(g);
      shelterGroups.set(s.id, g);
    }
    // rebuild children when step changes (cheap: few meshes)
    const want = s.step;
    if (g.children.length !== want) {
      g.clear();
      const y = heightAt(s.x, s.z);
      const mat = new THREE.MeshLambertMaterial({ color: 0x3a5c4b, flatShading: true });
      const wood = new THREE.MeshLambertMaterial({ color: 0x5a4632, flatShading: true });
      if (want >= 1) {
        const ridge = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 2.6, 5), wood);
        ridge.rotation.z = Math.PI / 2.6;
        ridge.position.set(0, 1.1, 0);
        g.add(ridge);
      }
      if (want >= 2) {
        for (let i = -1; i <= 1; i++) {
          const rib = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 1.8, 4), wood);
          rib.rotation.z = Math.PI / 3;
          rib.position.set(i * 0.7, 0.8, 0);
          g.add(rib);
        }
      }
      if (want >= 3) {
        const wall = new THREE.Mesh(new THREE.BoxGeometry(2.2, 1.4, 0.15), mat);
        wall.rotation.x = -0.5;
        wall.position.set(0, 0.8, -0.35);
        g.add(wall);
      }
      if (want >= 4) {
        const mulch = new THREE.Mesh(new THREE.BoxGeometry(2.3, 1.5, 0.25),
          new THREE.MeshLambertMaterial({ color: 0x6b5a3a, flatShading: true }));
        mulch.rotation.x = -0.5;
        mulch.position.set(0, 0.85, -0.45);
        g.add(mulch);
      }
      if (want >= 5) {
        const bed = new THREE.Mesh(new THREE.BoxGeometry(1.8, 0.25, 0.9), mat);
        bed.position.set(0, 0.12, 0.55);
        g.add(bed);
      }
      g.position.set(s.x, y, s.z);
    }
  }
  for (const [id, g] of shelterGroups) {
    if (!seen.has(id)) {
      scene.remove(g);
      shelterGroups.delete(id);
    }
  }
}

const ray = new THREE.Raycaster();
/** free distance along pivot→eye for camera collision (props only; terrain
 * handled by an eye-height clamp below). */
function rayDist(
  from: [number, number, number],
  to: [number, number, number],
): number {
  const a = new THREE.Vector3(...from);
  const b = new THREE.Vector3(...to);
  const dir = b.clone().sub(a);
  const len = dir.length();
  ray.set(a, dir.normalize());
  const hits = ray.intersectObjects(bundle.obstacles, false);
  return hits.length > 0 && hits[0].distance < len ? hits[0].distance : Infinity;
}

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

let acc = 0;
let last = performance.now();
let paused = false; // E2E: freeze sim/camera so scripted poses survive to readPixels

/** Compute + apply camera pose from cam state (shared by frame loop + debug API). */
function applyCamera(dtReal: number): void {
  const p = world.player;
  const pose = updateCam(
    cam,
    {
      px: p.x, py: p.y, pz: p.z, pyaw: p.yaw,
      moving: p.moving, sprinting: input.intent.run && p.moving,
    },
    dtReal,
    rayDist,
  );
  camera.position.set(pose.eye[0], pose.eye[1], pose.eye[2]);
  // never let the eye sink under terrain
  const minY = heightAt(pose.eye[0], pose.eye[2]) + 0.4;
  if (camera.position.y < minY) camera.position.y = minY;
  camera.lookAt(pose.pivot[0], pose.pivot[1], pose.pivot[2]);
}

function frame(now: number) {
  const dtReal = Math.min((now - last) / 1000, 0.25);
  last = now;
  if (paused) {
    // keep framebuffer + sky + player pose live (state may be scripted),
    // but don't advance the sim
    updateSky(world, scene, sun, hemi, fog);
    bundle.playerMesh.position.set(world.player.x, world.player.y, world.player.z);
    bundle.playerMesh.rotation.y = world.player.yaw;
    syncFireMeshes();
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
    return;
  }

  // --- sim (fixed timestep) ---
  readIntent(input, cam.yaw);
  if (menuIsOpen()) {
    input.intent.fwd = 0;
    input.intent.strafe = 0;
    input.intent.run = false;
  }
  if (world.needs.sleeping) {
    // asleep: no movement, no work
    input.intent.fwd = 0;
    input.intent.strafe = 0;
    input.intent.run = false;
    world.task = null;
  }
  acc += dtReal;
  while (acc >= CONFIG.SIM_DT) {
    updatePlayer(world, input.intent, CONFIG.SIM_DT);
    step(world, CONFIG.SIM_DT, input.intent.run && world.player.moving);
    tickWork(world, CONFIG.SIM_DT, computeDebuffs(world.needs).dexterity);
    acc -= CONFIG.SIM_DT;
  }

  // --- contextual actions (playtest: one verb + one wheel, no key sprawl) ---
  // LMB / E  = primary verb on the nearest thing (gather/loot/wake)
  // hold RMB = radial menu of everything possible HERE, release to do it
  const actx: ActionCtx = { dexterity: computeDebuffs(world.needs).dexterity };
  if (consumeKey('Enter') && (world.dead || world.rescued)) {
    hideEndScreen();
    world = createWorld(world.seed);
    cam = createCamState();
  } else if (!world.dead && !world.rescued) {
    if (menuIsOpen() && !input.locked) closeMenu(); // Esc dropped pointer lock
    if (consumeMouseButton(input, 2) && !menuIsOpen()) {
      openMenu(contextActions(world, actx));
    }
    if (menuIsOpen()) {
      if (consumeKey('Escape')) closeMenu();
      else if (!isMouseButtonHeld(input, 2)) {
        const a = closeMenu();
        if (a) a.run(world);
      }
    } else if (input.locked && (consumeKey('KeyE') || consumeMouseButton(input, 0))) {
      const a = primaryAction(world, actx);
      if (a?.enabled) a.run(world);
    }
  }
  world.shouting = isHeld(input, 'Space'); // hoo-hoo! repels wolves
  syncFireMeshes();
  syncShelterMeshes();
  syncWolfMeshes();

  // --- camera (per-frame, smooth); mouse steers the wheel while it's open ---
  if (menuIsOpen()) menuSteer(input.dYaw, input.dPitch);
  else orbit(cam, input.dYaw, input.dPitch, 0.0022);
  input.dYaw = 0;
  input.dPitch = 0;
  applyCamera(dtReal);
  const p = world.player;

  // --- player mesh follows sim (no animation, user-locked) ---
  bundle.playerMesh.position.set(p.x, p.y, p.z);
  bundle.playerMesh.rotation.y = p.yaw;

  // --- day/night ---
  updateSky(world, scene, sun, hemi, fog);

  // --- HUD ---
  const tgt = currentTarget(world);
  updateHud(
    world,
    input.locked,
    feelsLike(world),
    computeDebuffs(world.needs),
    world.task
      ? 'Working…'
      : tgt
        ? `[LMB/E] ${INTERACT_LABEL[tgt.kind]} · hold [RMB] for everything else`
        : 'hold [RMB] for actions',
  );

  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

/** Debug/E2E API — getters for reassigned bindings (stale-ref bug class). */
(window as unknown as Record<string, unknown>).__boreal = {
  get world() { return world; },
  get scene() { return scene; },
  get camera() { return camera; },
  get renderer() { return renderer; },
  get cam() { return cam; },
  reset(seed = 1) {
    world = createWorld(seed);
    cam = createCamState();
    hideEndScreen();
  },
  fireFlare() { return fireFlare(world); },
  signalSmoke() { return signalSmoke(world); },
  step(n = 1, dt = CONFIG.SIM_DT) {
    for (let i = 0; i < n; i++) {
      updatePlayer(world, { fwd: 0, strafe: 0, run: false, camYaw: cam.yaw }, dt);
      step(world, dt);
      tickWork(world, dt, computeDebuffs(world.needs).dexterity);
    }
  },
  /** scripted movement for E2E (bypasses keyboard) */
  move(fwd: number, strafe: number, run = false) {
    updatePlayer(world, { fwd, strafe, run, camYaw: cam.yaw }, CONFIG.SIM_DT);
  },
  orbitCam(dYaw: number, dPitch: number) {
    orbit(cam, dYaw, dPitch, 1);
    applyCamera(0.1); // sync immediately for synchronous E2E assertions
  },
  beginWork() { return beginWork(world); },
  setSnare() { return setSnareAction(world); },
  checkSnares() { return checkSnares(world); },
  fish() { return fish(world); },
  cook() { return cook(world); },
  treatWound() { return treatWound(world); },
  buildShelter() { return buildShelter(world); },
  toggleSleep() { return toggleSleep(world); },
  lightFire() { return lightFire(world, computeDebuffs(world.needs).dexterity); },
  feedFire() { return feedFire(world); },
  boilWater() { return boilWater(world); },
  drink() { return drink(world); },
  eat() { return eat(world); },
  craftFirst() {
    const r = RECIPES.find((x) => canCraft(world.inventory, x));
    if (r && craft(world.inventory, r)) return r.id;
    return null;
  },
  /** contextual action layer (E2E): labels + enabled flags right now */
  contextActions() {
    const ctx: ActionCtx = { dexterity: computeDebuffs(world.needs).dexterity };
    return contextActions(world, ctx).map((a) => ({ id: a.id, enabled: a.enabled }));
  },
  /** run the primary verb (what LMB/E would do) */
  runPrimary() {
    const ctx: ActionCtx = { dexterity: computeDebuffs(world.needs).dexterity };
    const a = primaryAction(world, ctx);
    if (a?.enabled) a.run(world);
    return a?.id ?? null;
  },
  renderOnce() { renderer.render(scene, camera); },
  setPaused(v: boolean) { paused = v; },
  CAM,
};

/**
 * BOREAL — boot: wires sim + render + input + HUD. Sprint 1: terrain, movement,
 * Skyrim-style third-person camera, day/night cycle, stylized scatter world.
 */
import * as THREE from 'three';
import { CONFIG } from './sim/config';
import { beginWork, boilWater, createWorld, currentTarget, drink, eat, feedFire, feelsLike, lightFire, step, tickWork, type WorldState } from './sim/world';
import { updatePlayer } from './sim/player';
import { computeDebuffs } from './sim/needs';
import { RECIPES, craft, canCraft } from './sim/craft';
import { INTERACT_LABEL } from './sim/interact';
import { heightAt } from './sim/terrain';
import { buildScene } from './render/scene';
import { createCamState, orbit, updateCam, CAM, type CamState } from './render/camera';
import { createInput, readIntent, consumeKey } from './input/input';
import { updateSky } from './render/daynight';
import { updateHud } from './ui/hud';

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
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
    return;
  }

  // --- sim (fixed timestep) ---
  readIntent(input, cam.yaw);
  acc += dtReal;
  while (acc >= CONFIG.SIM_DT) {
    updatePlayer(world, input.intent, CONFIG.SIM_DT);
    step(world, CONFIG.SIM_DT, input.intent.run && world.player.moving);
    tickWork(world, CONFIG.SIM_DT, computeDebuffs(world.needs).dexterity);
    acc -= CONFIG.SIM_DT;
  }

  // --- one-shot keys: E work · Tab craft · F light · R feed · Q boil · 1 drink · 2 eat ---
  if (consumeKey('KeyE')) beginWork(world);
  if (consumeKey('Tab')) {
    const r = RECIPES.find((x) => canCraft(world.inventory, x));
    if (r && craft(world.inventory, r)) {
      world.log.push({ t: world.t, day: world.day, msg: `Crafted: ${r.label}` });
    }
  }
  if (consumeKey('KeyF')) lightFire(world, computeDebuffs(world.needs).dexterity);
  if (consumeKey('KeyR')) feedFire(world);
  if (consumeKey('KeyQ')) boilWater(world);
  if (consumeKey('Digit1')) drink(world);
  if (consumeKey('Digit2')) eat(world);
  syncFireMeshes();

  // --- camera (per-frame, smooth) ---
  orbit(cam, input.dYaw, input.dPitch, 0.0022);
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
    world.task ? 'Working…' : tgt ? `[E] ${INTERACT_LABEL[tgt.kind]}` : '',
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
  },
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
  renderOnce() { renderer.render(scene, camera); },
  setPaused(v: boolean) { paused = v; },
  CAM,
};

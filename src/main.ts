/**
 * BOREAL — boot: wires sim + render + input + HUD. Sprint 1: terrain, movement,
 * Skyrim-style third-person camera, day/night cycle, stylized scatter world.
 */
import * as THREE from 'three';
import { CONFIG } from './sim/config';
import { createWorld, step, type WorldState } from './sim/world';
import { updatePlayer } from './sim/player';
import { heightAt } from './sim/terrain';
import { buildScene } from './render/scene';
import { createCamState, orbit, updateCam, CAM, type CamState } from './render/camera';
import { createInput, readIntent } from './input/input';
import { updateSky } from './render/daynight';
import { updateHud } from './ui/hud';

let world: WorldState = createWorld(1);
let cam: CamState = createCamState();

const app = document.getElementById('app')!;
const bundle = buildScene(app);
const { scene, camera, renderer, sun, hemi, fog } = bundle;
const input = createInput(renderer.domElement);

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
    // keep framebuffer + sky live (hour may be scripted), but don't touch state
    updateSky(world, scene, sun, hemi, fog);
    renderer.render(scene, camera);
    requestAnimationFrame(frame);
    return;
  }

  // --- sim (fixed timestep) ---
  readIntent(input, cam.yaw);
  acc += dtReal;
  while (acc >= CONFIG.SIM_DT) {
    updatePlayer(world, input.intent, CONFIG.SIM_DT);
    step(world, CONFIG.SIM_DT);
    acc -= CONFIG.SIM_DT;
  }

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
  updateHud(world, input.locked);

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
  renderOnce() { renderer.render(scene, camera); },
  setPaused(v: boolean) { paused = v; },
  CAM,
};

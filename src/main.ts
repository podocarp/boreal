/**
 * BOREAL — boot: wires sim + render + input + HUD.
 * Sprint 0: renders a placeholder ground plane + crash-site marker, steps the sim.
 */
import * as THREE from 'three';
import { CONFIG } from './sim/config';
import { createWorld, step, type WorldState } from './sim/world';

let world: WorldState = createWorld(1);

const app = document.getElementById('app')!;
const hud = document.getElementById('hud')!;

const renderer = new THREE.WebGLRenderer({
  antialias: true,
  // preserveDrawingBuffer lets the headless test harness readPixels() the framebuffer.
  preserveDrawingBuffer: true,
});
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
app.appendChild(renderer.domElement);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x8fa8bd); // pale subarctic sky
scene.fog = new THREE.Fog(0x8fa8bd, 60, CONFIG.WORLD.SIZE_M * 1.2);

const camera = new THREE.PerspectiveCamera(60, window.innerWidth / window.innerHeight, 0.1, 2000);
camera.position.set(0, 8, 14);
camera.lookAt(0, 0, 0);

// Lights: cold key + ambient
scene.add(new THREE.HemisphereLight(0xbfd4e8, 0x3a4a3f, 0.9));
const sun = new THREE.DirectionalLight(0xfff2dd, 1.2);
sun.position.set(60, 40, -80);
scene.add(sun);

// Placeholder ground (snow-tinted) + crash-site marker (orange box)
const ground = new THREE.Mesh(
  new THREE.PlaneGeometry(CONFIG.WORLD.SIZE_M * 2, CONFIG.WORLD.SIZE_M * 2),
  new THREE.MeshLambertMaterial({ color: 0xdfe7ec }),
);
ground.rotation.x = -Math.PI / 2;
scene.add(ground);

const marker = new THREE.Mesh(
  new THREE.BoxGeometry(3, 1.5, 8),
  new THREE.MeshLambertMaterial({ color: 0xd4622a }),
);
marker.position.set(0, 0.75, -12);
scene.add(marker);

window.addEventListener('resize', () => {
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
  renderer.setSize(window.innerWidth, window.innerHeight);
});

// Fixed-timestep accumulator loop (sim is dt-independent of frame rate).
let acc = 0;
let last = performance.now();
function frame(now: number) {
  acc += Math.min((now - last) / 1000, 0.25);
  last = now;
  while (acc >= CONFIG.SIM_DT) {
    step(world, CONFIG.SIM_DT);
    acc -= CONFIG.SIM_DT;
  }
  hud.textContent = `BOREAL dev — day ${world.day}, ${world.hourOfDay.toFixed(1)}h`;
  renderer.render(scene, camera);
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);

/**
 * Debug/E2E API. NOTE: getters (not shorthand) for reassigned bindings —
 * shorthand freezes the old reference (classic stale-state bug).
 */
(window as unknown as Record<string, unknown>).__boreal = {
  get world() { return world; },
  get scene() { return scene; },
  get renderer() { return renderer; },
  reset(seed = 1) { world = createWorld(seed); },
  step(n = 1, dt = CONFIG.SIM_DT) { for (let i = 0; i < n; i++) step(world, dt); },
};

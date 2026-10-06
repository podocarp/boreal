/**
 * Scene construction: stylized low-poly world from the SAME analytic terrain +
 * scatter the sim uses. Instanced meshes for trees/rocks (cheap draw calls).
 */
import * as THREE from 'three';
import { CONFIG } from '../sim/config';
import { LAKE, heightAt, streamX } from '../sim/terrain';
import { scatter, type Prop } from '../sim/scatter';
import { PALETTE as P } from './palette';

export interface SceneBundle {
  scene: THREE.Scene;
  camera: THREE.PerspectiveCamera;
  renderer: THREE.WebGLRenderer;
  sun: THREE.DirectionalLight;
  hemi: THREE.HemisphereLight;
  playerMesh: THREE.Group;
  obstacles: THREE.Object3D[]; // for camera raycasts
  skyMat: THREE.MeshBasicMaterial;
  fog: THREE.Fog;
}

function terrainMesh(): THREE.Mesh {
  const S = CONFIG.WORLD.SIZE_M;
  const SEG = 128;
  const geo = new THREE.PlaneGeometry(S * 2, S * 2, SEG, SEG);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position as THREE.BufferAttribute;
  const colors: number[] = [];
  const cSnow = new THREE.Color(P.SNOW);
  const cSnowShade = new THREE.Color(P.SNOW_SHADE);
  const cBog = new THREE.Color(P.BOG);
  const cRock = new THREE.Color(P.ROCK_DARK);
  for (let i = 0; i < pos.count; i++) {
    const x = pos.getX(i);
    const z = pos.getZ(i);
    const y = heightAt(x, z);
    pos.setY(i, y);
    // vertex-color blend: snow base, bog green low north, rock on steep west
    const c = cSnow.clone().lerp(cSnowShade, (1 - (y + 8) / 60) * 0.6);
    if (z > 100 && y < 4) c.lerp(cBog, 0.35);
    if (x < -140) c.lerp(cRock, 0.5);
    colors.push(c.r, c.g, c.b);
  }
  geo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
  geo.computeVertexNormals();
  const mat = new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = 'terrain';
  return mesh;
}

function lakeIce(): THREE.Mesh {
  const geo = new THREE.CircleGeometry(1, 48);
  geo.rotateX(-Math.PI / 2);
  geo.scale(LAKE.rx * 1.02, 1, LAKE.rz * 1.02); // after rotateX the disc lies in XZ
  const mat = new THREE.MeshLambertMaterial({
    color: P.ICE,
    flatShading: true,
    transparent: true,
    opacity: 0.95,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.set(LAKE.cx, 0.05, LAKE.cz);
  mesh.name = 'lake';
  return mesh;
}

function streamRibbon(): THREE.Mesh {
  // water ribbon following streamX(z), from ridge to lake
  const pts: THREE.Vector3[] = [];
  for (let z = 240; z > -170; z -= 8) pts.push(new THREE.Vector3(streamX(z), 0.02, z));
  const curve = new THREE.CatmullRomCurve3(pts);
  const geo = new THREE.TubeGeometry(curve, 96, 3.2, 5, false);
  const mat = new THREE.MeshLambertMaterial({ color: P.WATER, flatShading: true });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = 'stream';
  // flatten tube to ribbon-ish: keep as-is for stylized look
  return mesh;
}

function instanced(props: Prop[], kind: Prop['kind'], build: (m: THREE.Group) => void): THREE.InstancedMesh {
  const group = new THREE.Group();
  build(group);
  // merge children into one geometry via matrix composition on a temp object
  const geos: THREE.BufferGeometry[] = [];
  group.updateMatrixWorld(true);
  group.traverse((o) => {
    if ((o as THREE.Mesh).isMesh) {
      const m = o as THREE.Mesh;
      const g = m.geometry.clone();
      g.applyMatrix4(m.matrixWorld);
      geos.push(g);
    }
  });
  const merged = mergeGeos(geos);
  const mat = new THREE.MeshLambertMaterial({ color: 0xffffff, flatShading: true, vertexColors: true });
  const list = props.filter((p) => p.kind === kind);
  const im = new THREE.InstancedMesh(merged, mat, list.length);
  const mtx = new THREE.Matrix4();
  list.forEach((p, i) => {
    mtx.compose(
      new THREE.Vector3(p.x, heightAt(p.x, p.z) - 0.2, p.z),
      new THREE.Quaternion().setFromEuler(new THREE.Euler(0, p.rot, 0)),
      new THREE.Vector3(p.scale, p.scale, p.scale),
    );
    im.setMatrixAt(i, mtx);
  });
  im.instanceMatrix.needsUpdate = true;
  im.name = `props_${kind}`;
  return im;
}

/** Minimal geometry merge (position+normal+color) — avoids extra imports. */
function mergeGeos(geos: THREE.BufferGeometry[]): THREE.BufferGeometry {
  let posCount = 0;
  const nonIndexed = geos.map((g) => (g.index ? g.toNonIndexed() : g));
  for (const g of nonIndexed) posCount += g.attributes.position.count;
  const pos = new Float32Array(posCount * 3);
  const nor = new Float32Array(posCount * 3);
  const col = new Float32Array(posCount * 3);
  let off = 0;
  for (const g of nonIndexed) {
    const n = g.attributes.position.count;
    pos.set(g.attributes.position.array as Float32Array, off * 3);
    if (g.attributes.normal) nor.set(g.attributes.normal.array as Float32Array, off * 3);
    if (g.attributes.color) col.set(g.attributes.color.array as Float32Array, off * 3);
    else col.fill(1, off * 3, (off + n) * 3);
    off += n;
  }
  const out = new THREE.BufferGeometry();
  out.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  out.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  out.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return out;
}

function paint(geo: THREE.BufferGeometry, hex: number): THREE.BufferGeometry {
  const c = new THREE.Color(hex);
  const n = geo.attributes.position.count;
  const col = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    col[i * 3] = c.r;
    col[i * 3 + 1] = c.g;
    col[i * 3 + 2] = c.b;
  }
  geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  return geo;
}

/** Painted geometry + a material that actually reads the vertex colors. */
function pm(geo: THREE.BufferGeometry, hex: number): THREE.Mesh {
  return new THREE.Mesh(paint(geo, hex), new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true }));
}

function buildSpruce(g: THREE.Group): void {
  const trunk = new THREE.Mesh(paint(new THREE.CylinderGeometry(0.12, 0.18, 1.2, 5), 0x5a4632));
  trunk.position.y = 0.6;
  g.add(trunk);
  const tiers = [
    { r: 1.5, h: 2.2, y: 2.0, c: P.SPRUCE_DARK },
    { r: 1.15, h: 1.9, y: 3.3, c: P.SPRUCE_MID },
    { r: 0.75, h: 1.7, y: 4.5, c: P.SPRUCE_MID },
  ];
  for (const t of tiers) {
    const cone = new THREE.Mesh(paint(new THREE.ConeGeometry(t.r, t.h, 6), t.c));
    cone.position.y = t.y;
    g.add(cone);
  }
}

function buildBirch(g: THREE.Group): void {
  const trunk = new THREE.Mesh(paint(new THREE.CylinderGeometry(0.1, 0.14, 3.2, 5), P.BIRCH_TRUNK));
  trunk.position.y = 1.6;
  g.add(trunk);
  const crown = new THREE.Mesh(paint(new THREE.IcosahedronGeometry(1.1, 0), P.BIRCH_LEAF));
  crown.position.y = 3.8;
  g.add(crown);
}

function buildRock(g: THREE.Group): void {
  const rock = new THREE.Mesh(paint(new THREE.DodecahedronGeometry(0.9, 0), P.ROCK));
  rock.scale.set(1, 0.7, 1);
  rock.position.y = 0.4;
  g.add(rock);
}

function playerMesh(): THREE.Group {
  // stylized blocky parka figure — no animation (user-locked)
  const g = new THREE.Group();
  const body = pm(new THREE.BoxGeometry(0.55, 0.75, 0.35), P.PARKA);
  body.position.y = 1.05;
  g.add(body);
  const hood = pm(new THREE.BoxGeometry(0.34, 0.3, 0.32), P.PARKA_DARK);
  hood.position.y = 1.62;
  g.add(hood);
  const face = pm(new THREE.BoxGeometry(0.22, 0.18, 0.06), P.SKIN);
  face.position.set(0, 1.6, 0.18);
  g.add(face);
  const legs = pm(new THREE.BoxGeometry(0.45, 0.7, 0.3), P.PANTS);
  legs.position.y = 0.35;
  g.add(legs);
  g.name = 'player';
  return g;
}

function crashSite(): THREE.Group {
  const g = new THREE.Group();
  const fus = pm(new THREE.BoxGeometry(2.6, 2.0, 7.5), P.WRECK);
  fus.position.y = 1.0;
  g.add(fus);
  const wing = pm(new THREE.BoxGeometry(9, 0.25, 1.6), 0xb3541f);
  wing.position.set(0.5, 1.3, 0.5);
  wing.rotation.z = 0.18;
  g.add(wing);
  const nose = pm(new THREE.ConeGeometry(0.9, 2.2, 6), 0x8f4218);
  nose.rotation.x = Math.PI / 2;
  nose.position.set(0, 1.1, -4.6);
  g.add(nose);
  g.name = 'crash';
  return g;
}

export function buildScene(container: HTMLElement): SceneBundle {
  const renderer = new THREE.WebGLRenderer({ antialias: true, preserveDrawingBuffer: true });
  renderer.setSize(window.innerWidth, window.innerHeight);
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
  container.appendChild(renderer.domElement);

  const scene = new THREE.Scene();
  const fog = new THREE.Fog(P.FOG_DAY, 80, 520);
  scene.fog = fog;
  scene.background = new THREE.Color(P.SKY_DAY);

  const camera = new THREE.PerspectiveCamera(62, window.innerWidth / window.innerHeight, 0.1, 1500);

  const hemi = new THREE.HemisphereLight(0xbfd4e8, 0x4a5a50, 0.85);
  scene.add(hemi);
  const sun = new THREE.DirectionalLight(P.SUN_DAY, 1.4);
  sun.position.set(80, 60, -120);
  scene.add(sun);

  scene.add(terrainMesh());
  scene.add(lakeIce());
  scene.add(streamRibbon());

  const props = scatter(1);
  const spruce = instanced(props, 'spruce', buildSpruce);
  const birch = instanced(props, 'birch', buildBirch);
  const rock = instanced(props, 'rock', buildRock);
  scene.add(spruce, birch, rock);

  const crash = crashSite();
  crash.position.set(0, heightAt(0, -140), -140);
  scene.add(crash);

  const player = playerMesh();
  scene.add(player);

  return {
    scene,
    camera,
    renderer,
    sun,
    hemi,
    playerMesh: player,
    obstacles: [spruce, birch, rock],
    skyMat: null as unknown as THREE.MeshBasicMaterial,
    fog,
  };
}

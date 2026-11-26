// Fishers Cruise: boots the map, runs the game loop, and handles the player.
import * as THREE from 'three';
import { loadMap, lonLatToXZ } from './data.js';
import { World, isDrivable, isTrail, F, VIEW } from './world.js';
import { makeTextures, buildPerson, animatePerson, resetPose, waveAnim, textSprite, CAR_TYPES, lightMats, mountRider, BIKE_COLORS } from './models.js';
import { Car } from './vehicle.js';
import { Nav } from './nav.js';
import { Traffic, PED_LINES } from './traffic.js';
import { Hud } from './hud.js';
import { Missions } from './missions.js';
import { Sound } from './audio.js';
import { clamp, smooth, wrapAngle, mulberry32 } from './util.js';

const $ = (id) => document.getElementById(id);
const SAVE_KEY = 'fishers-cruise-save-v1';
const GFX_KEY = 'fishers-cruise-graphics';
const GKEY = 'fishers-cruise-google-key';
let googleKey = '';
try { googleKey = localStorage.getItem(GKEY) || ''; } catch { /* storage blocked */ }
let city = null; // RealCity when Google 3D tiles are on
let gfx = 'high';
try { gfx = localStorage.getItem(GFX_KEY) || (new URLSearchParams(location.search).has('low') ? 'low' : 'high'); } catch { /* storage blocked */ }

function loadSave() {
  const fresh = { money: 0, done: [], fish: [], hour: 10, sports: false };
  try {
    const s = JSON.parse(localStorage.getItem(SAVE_KEY) || 'null');
    return s ? { ...fresh, ...s } : fresh;
  } catch { return fresh; }
}

function setStatus(text, frac) {
  $('load-status').textContent = text;
  if (frac != null) $('load-bar').style.transform = `scaleX(${clamp(frac, 0, 1)})`;
}

// ---------------------------------------------------------------- renderer & scene
const renderer = new THREE.WebGLRenderer({ antialias: true, logarithmicDepthBuffer: true, powerPreference: 'high-performance' });
function applyGraphics() {
  const low = gfx === 'low';
  renderer.setPixelRatio(low ? 1 : Math.min(window.devicePixelRatio, 1.5));
  renderer.shadowMap.enabled = !low;
  VIEW.load = low ? 800 : 1150; VIEW.unload = low ? 1100 : 1500;
  if (city) { city.tiles.errorTarget = low ? 30 : 16; renderer.shadowMap.enabled = false; }
  if (scene.fog) { scene.fog.near = low ? 250 : 350; scene.fog.far = low ? 950 : 1350; }
  scene.traverse((o) => { if (o.material) o.material.needsUpdate = true; });
  for (const id of ['gfx', 'gfx-title']) {
    const b = document.getElementById(id);
    if (b) b.textContent = low ? 'Graphics: fast' : 'Graphics: detailed';
  }
}
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;
renderer.outputColorSpace = THREE.SRGBColorSpace;
$('game').appendChild(renderer.domElement);

const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(68, window.innerWidth / window.innerHeight, 0.4, 2200);
scene.fog = new THREE.Fog(0xcfe0ea, 350, 1350);
applyGraphics();

const hemi = new THREE.HemisphereLight(0xdfefff, 0x5a6b3c, 0.9);
scene.add(hemi);
const sun = new THREE.DirectionalLight(0xfff1dc, 1.6);
sun.castShadow = true;
sun.shadow.mapSize.set(2048, 2048);
Object.assign(sun.shadow.camera, { left: -90, right: 90, top: 90, bottom: -90, near: 10, far: 600 });
sun.shadow.bias = -0.0006;
sun.shadow.normalBias = 0.4;
scene.add(sun, sun.target);
const headlight = new THREE.SpotLight(0xfff3d6, 0, 90, 0.55, 0.5, 1.2);
scene.add(headlight, headlight.target);

// sky dome with a vertical gradient
const skyMat = new THREE.ShaderMaterial({
  side: THREE.BackSide, depthWrite: false, fog: false,
  uniforms: { top: { value: new THREE.Color(0x5ea8e6) }, bottom: { value: new THREE.Color(0xcfe6f5) }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunCol: { value: new THREE.Color(0xfff2c0) } },
  vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
  fragmentShader: `uniform vec3 top; uniform vec3 bottom; uniform vec3 sunDir; uniform vec3 sunCol; varying vec3 vP;
    void main(){ float h = clamp(vP.y*1.6+0.08,0.0,1.0); vec3 c = mix(bottom, top, pow(h,0.7));
      float s = max(dot(normalize(vP), sunDir), 0.0); c += sunCol * (pow(s, 900.0)*1.5 + pow(s, 12.0)*0.18);
      gl_FragColor = vec4(c,1.0); }`,
});
const sky = new THREE.Mesh(new THREE.SphereGeometry(2000, 32, 16), skyMat);
sky.renderOrder = -1;
scene.add(sky);

// ---------------------------------------------------------------- game state
const G = {
  scene, camera, sound: new Sound(), save: loadSave(), tex: makeTextures(),
  playerCar: null, waypoint: null, events: {},
  get car() { return this.playerCar; },
  get pos() { return this.playerCar ? { x: this.playerCar.x, z: this.playerCar.z, y: this.playerCar.y } : { x: player.x, z: player.z, y: player.ground }; },
  // Street-level height at a point: 0 in preview mode, from the 3D tiles otherwise.
  floorAt(x, z) {
    if (!city) return 0;
    const k = `${Math.round(x / 3)},${Math.round(z / 3)}`;
    const now = performance.now();
    const c = floorCache.get(k);
    if (c && now - c.t < 4000) return c.y;
    const y = city.lowestGroundAt(x, z);
    if (y == null) return c ? c.y : this.pos.y ?? 0;
    floorCache.set(k, { y, t: now });
    if (floorCache.size > 4000) floorCache.clear();
    return y;
  },
  addMoney(n) { this.save.money += n; this.hud.setMoney(this.save.money); },
  persist() { try { localStorage.setItem(SAVE_KEY, JSON.stringify(this.save)); } catch { /* storage blocked */ } },
  spawnCar(type, x, z, heading, color) {
    const c = new Car(scene, type, color, x, z, heading);
    c.keep = true;
    this.traffic.extra.push(c);
    return c;
  },
  removeCar(c) { if (c === this.playerCar) return; this.traffic.remove(c); },
  spawnNPC(look, x, z, heading) {
    const mesh = buildPerson(look);
    mesh.position.set(x, this.floorAt(x, z), z); mesh.rotation.y = heading;
    scene.add(mesh);
    return { mesh, x, z };
  },
  spawnHomeCars() {
    if (this.save.sports && !this.sportsCar) {
      const h = this.homeSpot;
      this.sportsCar = this.spawnCar('sports', h.x + h.ux * 6 - h.uz * 3, h.z + h.uz * 6 + h.ux * 3, h.heading, 0xd8262b);
    }
  },
};

window.fishersCruise = { G: null, player: null, enterCar: null };
const floorCache = new Map();
const PLAYER_LOOK = { shirt: 0x1f6fb2, pants: 0x2b3a55, hair: 0x3a2a1c, skin: 0xe0ac87, cap: 0xff8a3d };
// y is the height above the ground under the player (for jumping); ground is the ground height itself
const player = { x: 0, z: 0, y: 0, vy: 0, ground: 0, heading: 0, speed: 0, mesh: buildPerson(PLAYER_LOOK) };
scene.add(player.mesh);

const cam = { yaw: 0, pitch: 0.32, dist: 6, lastMouse: -10, shake: 0 };
const keys = new Set(), pressed = new Set();
let mouseDX = 0, mouseDY = 0, playing = false, locked = false;

// ---------------------------------------------------------------- input
window.addEventListener('keydown', (e) => {
  if (['Space', 'Tab', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight'].includes(e.code)) e.preventDefault();
  if (!keys.has(e.code)) pressed.add(e.code);
  keys.add(e.code);
});
window.addEventListener('keyup', (e) => keys.delete(e.code));
window.addEventListener('blur', () => keys.clear());
document.addEventListener('mousemove', (e) => {
  if (!locked) return;
  mouseDX += e.movementX; mouseDY += e.movementY;
});
document.addEventListener('pointerlockchange', () => {
  locked = document.pointerLockElement === renderer.domElement;
  if (playing) $('pause').hidden = locked || G.hud.mapOpen;
});
function lock() {
  try {
    const r = renderer.domElement.requestPointerLock();
    if (r && r.catch) r.catch(() => { locked = false; });
  } catch { /* pointer lock unavailable */ }
}
renderer.domElement.addEventListener('click', () => { if (playing && !locked) lock(); });
$('resume').addEventListener('click', () => { $('pause').hidden = true; lock(); });
$('mute').addEventListener('click', () => {
  G.sound.setMuted(!G.sound.muted);
  $('mute').textContent = G.sound.muted ? 'Sound: off' : 'Sound: on';
});
for (const id of ['gfx', 'gfx-title']) {
  $(id).addEventListener('click', () => {
    gfx = gfx === 'low' ? 'high' : 'low';
    try { localStorage.setItem(GFX_KEY, gfx); } catch { /* storage blocked */ }
    applyGraphics();
  });
}
$('reset').addEventListener('click', () => {
  $('reset-confirm').hidden = false;
});
$('reset-yes').addEventListener('click', () => {
  try { localStorage.removeItem(SAVE_KEY); } catch { /* ignore */ }
  location.reload();
});
$('reset-no').addEventListener('click', () => { $('reset-confirm').hidden = true; });
window.addEventListener('resize', () => {
  renderer.setSize(window.innerWidth, window.innerHeight);
  camera.aspect = window.innerWidth / window.innerHeight;
  camera.updateProjectionMatrix();
});

function gamepad() {
  const pads = navigator.getGamepads ? navigator.getGamepads() : [];
  const p = pads && [...pads].find((x) => x && x.connected);
  if (!p) return null;
  const dz = (v) => (Math.abs(v) < 0.15 ? 0 : v);
  const b = (i) => !!(p.buttons[i] && p.buttons[i].pressed);
  const prev = G._padPrev || {};
  const edge = (i) => b(i) && !prev[i];
  const out = {
    lx: dz(p.axes[0] || 0), ly: dz(p.axes[1] || 0), rx: dz(p.axes[2] || 0), ry: dz(p.axes[3] || 0),
    rt: p.buttons[7] ? p.buttons[7].value : 0, lt: p.buttons[6] ? p.buttons[6].value : 0,
    a: b(0), interact: edge(3) || edge(2), jump: edge(0), map: edge(8), horn: b(10) || b(1), handbrake: b(1) || b(5),
  };
  G._padPrev = Object.fromEntries(p.buttons.map((x, i) => [i, x.pressed]));
  return out;
}

// ---------------------------------------------------------------- boot
async function boot() {
  setStatus('Downloading the map of Fishers', 0);
  let map;
  try {
    map = await loadMap('data/', (f) => setStatus('Downloading the map of Fishers', f * 0.5));
  } catch (e) {
    setStatus('The map files could not be loaded. Reload the page to try again.');
    console.error(e);
    return;
  }
  let world = new World(scene, map, G.tex, { real: !!googleKey });
  G.world = world;
  if (googleKey) {
    const ok = await startRealCity(map);
    if (!ok) { world = new World(scene, map, G.tex); G.world = world; }
  }
  G.real = !!city;
  $('mode-note').textContent = city
    ? 'Real 3D city: buildings, trees and ground are Google\'s 3D model of the real place.'
    : 'Map preview: real street and building outlines; building heights are estimates. Add a Google key for the real 3D city.';
  await world.buildStatic((label, f) => setStatus(label, 0.5 + f * 0.4));
  G.nav = new Nav(world);
  G.traffic = new Traffic(scene, world, G.nav);
  if (city) {
    G.traffic.ground = Car.ground;
    G.traffic.floor = Car.floor;
  }
  G.hud = new Hud(world);
  G.hud.setMoney(G.save.money);
  G.hud.onWaypoint = (p) => { G.waypoint = p; routeState.key = ''; };
  setStatus('Finding your new house', 0.92);
  chooseHome();
  placeBikeRacks();
  G.missions = new Missions(G);
  G.hud.setFish(G.save.fish.length, G.missions.fish.length);
  makeLabels();
  if (city) await settleStart();
  world.updateTiles(player.x, player.z);
  while (world.pending) { world.pump(30); setStatus('Building the neighborhood', 0.92 + 0.08 * (1 - world.pending / 40)); await new Promise((r) => setTimeout(r, 0)); }
  G.traffic.updateParked(player.x, player.z);
  hour = G.save.hour ?? 10;
  $('loading').hidden = true;
  $('title').hidden = false;
  $('start').focus();
  $('start').addEventListener('click', startGame);
  last = performance.now();
  requestAnimationFrame(loop);
}

function startGame() {
  $('title').hidden = true;
  $('hud').hidden = false;
  $('credits').hidden = !city;
  playing = true;
  G.sound.start();
  lock();
  if (!G.save.done.includes('welcome')) G.hud.toast('Mom wants to talk to you. Walk over and press E.');
  else G.hud.toast('Welcome back! Press M for the map.');
}

// Loads Google's 3D tiles for the map area. Returns false (and explains why) if they can't be used.
async function startRealCity(map) {
  setStatus('Connecting to Google 3D tiles', 0.5);
  let RealCity;
  try {
    ({ RealCity } = await import('./realcity.js'));
  } catch (e) {
    console.error(e);
    realFailed('The 3D tiles code could not be downloaded.');
    return false;
  }
  const o = map.meta.origin;
  const params = new URLSearchParams(location.search);
  city = new RealCity(scene, camera, renderer, { apiKey: googleKey, origin: { lat: o.lat, lon: o.lon, h: o.h || 0 }, rootURL: params.get('tiles') || null });
  Car.ground = (x, z, fromY) => city.groundAt(x, z, fromY);
  Car.floor = (x, z) => city.lowestGroundAt(x, z);
  renderer.shadowMap.enabled = false;
  applyGraphics();
  // wait for the first tiles over the map centre to prove the key works
  camera.position.set(0, 400, 300);
  camera.lookAt(0, 0, 0);
  const t0 = performance.now();
  while (performance.now() - t0 < 45000) {
    city.update();
    if (city.loaded > 0) return true;
    if (city.errors.length >= 3) break;
    setStatus(`Connecting to Google 3D tiles (${Math.round((performance.now() - t0) / 1000)} s)`, 0.5);
    await new Promise((r) => setTimeout(r, 200));
  }
  realFailed(city.errors[0] || 'No tiles arrived within 45 seconds.');
  city.dispose();
  city = null;
  Car.ground = null; Car.floor = null;
  return false;
}

function realFailed(reason) {
  console.warn('Real city unavailable:', reason);
  const inArtifact = /claude\.ai|claudeusercontent/.test(location.host);
  $('real-status').textContent = inArtifact
    ? 'Google 3D tiles cannot load inside the Claude link. Run the game with play.bat on your PC to use the real city.'
    : `Google 3D tiles did not load (${reason.slice(0, 140)}). Check that the Map Tiles API is enabled for this key. Showing the map preview instead.`;
  $('real-status').hidden = false;
}

// After the real tiles load near home, put the player and parked cars on the real ground.
async function settleStart() {
  const h = G.homeSpot;
  const t0 = performance.now();
  while (performance.now() - t0 < 30000) {
    camera.position.set(h.x, 150, h.z + 120);
    camera.lookAt(h.x, 0, h.z);
    city.update();
    const y = city.lowestGroundAt(player.x, player.z);
    if (y != null && city.bvhQueue.length === 0 && performance.now() - t0 > 3000) { player.ground = y; break; }
    setStatus('Loading the real neighborhood in 3D', 0.92);
    await new Promise((r) => setTimeout(r, 150));
  }
  cam.yaw = player.heading;
}

// Picks a house with a driveway near the middle of Fishers.
function chooseHome() {
  const w = G.world, R = w.R;
  const center = lonLatToXZ(w.meta, 39.9505, -86.0045);
  const rnd = mulberry32(2024);
  let best = null;
  const cands = [];
  w.roadGrid.query(center.x - 2500, center.z - 2500, center.x + 2500, center.z + 2500, (e) => {
    if (R.type[e] === 14 && R.flags[e] & F.DRIVEWAY) cands.push(e);
  });
  const uniq = [...new Set(cands)];
  uniq.sort((a, b) => {
    const [ax, az] = w.edgePoint(a, 0), [bx, bz] = w.edgePoint(b, 0);
    return Math.hypot(ax - center.x, az - center.z) - Math.hypot(bx - center.x, bz - center.z);
  });
  const pick = (needHouse) => {
    for (const e of uniq.slice(0, 1500)) {
      if (rnd() < 0.3) continue;
      const n = R.count[e];
      const deg = (node) => w.adjStart[node + 1] - w.adjStart[node];
      const houseEnd = deg(R.a[e]) <= deg(R.b[e]) ? 0 : n - 1;
      const [hx, hz] = w.edgePoint(e, houseEnd), [ox, oz] = w.edgePoint(e, houseEnd === 0 ? n - 1 : 0);
      const L = Math.hypot(ox - hx, oz - hz);
      if (L < 9 || L > 40) continue;
      // the driveway must meet a residential street
      const street = w.nearestRoad(ox, oz, (t) => t === 11, 6);
      if (!street) continue;
      const ux = (ox - hx) / L, uz = (oz - hz) / L;
      if (needHouse && w.buildingAt(hx - ux * 3, hz - uz * 3, 4) < 0) continue;
      const cx = hx + ux * 3.8, cz = hz + uz * 3.8;
      if (w.buildingAt(cx, cz, 1.4) >= 0) continue;
      return { x: cx, z: cz, ux, uz, heading: Math.atan2(-ux, -uz), hx, hz };
    }
    return null;
  };
  best = pick(true) || pick(false);
  if (!best) {
    const hit = w.nearestRoad(center.x, center.z, isDrivable, 2000);
    best = { x: hit.x, z: hit.z, ux: 1, uz: 0, heading: 0, hx: hit.x, hz: hit.z };
  }
  G.homeSpot = best;
  G.home = { x: best.x + best.ux * 4.5 + best.uz * 2.5, z: best.z + best.uz * 4.5 - best.ux * 2.5, name: 'Home' };
  G.traffic.reserved.push({ x: best.x, z: best.z, r: 16 });
  G.familyCar = G.spawnCar('minivan', best.x, best.z, best.heading, 0x8b9096);
  // the family bike leans next to the minivan
  for (const side of [2.4, -2.4]) {
    const bx = best.x + best.uz * side, bz = best.z - best.ux * side;
    if (w.buildingAt(bx, bz, 0.8) >= 0) continue;
    G.homeBike = G.spawnCar('bike', bx, bz, best.heading, 0x2bb3b1);
    break;
  }
  G.spawnHomeCars();
  player.x = G.home.x + best.uz * 1.5; player.z = G.home.z - best.ux * 1.5;
  player.heading = Math.atan2(best.ux, best.uz);
  cam.yaw = player.heading;
}

// ---------------------------------------------------------------- trails and bike racks
const TRAILS = [{ re: /monon/i, label: 'Monon Trail' }, { re: /nickel plate/i, label: 'Nickel Plate Trail' }];
// Bikes wait at real bike-parking spots (from the map) within 80 m of each trail.
// No racks or signs are drawn: the real ones are part of the 3D city.
function placeBikeRacks() {
  const w = G.world, R = w.R;
  G.trails = [];
  let colorIdx = 0;
  const parking = w.meta.bikeParking || [];
  for (const tr of TRAILS) {
    const pts = [];
    for (let e = 0; e < R.nEdges; e++) {
      if (!isTrail(R.type[e], R.flags[e]) || !tr.re.test(w.roadName(e))) continue;
      for (let k = 0; k < R.count[e]; k++) {
        const [x, z] = w.edgePoint(e, k);
        const [x2, z2] = w.edgePoint(e, Math.min(k + 1, R.count[e] - 1));
        const [x0, z0] = w.edgePoint(e, Math.max(k - 1, 0));
        const L = Math.hypot(x2 - x0, z2 - z0) || 1;
        pts.push({ x, z, dx: (x2 - x0) / L, dz: (z2 - z0) / L });
      }
    }
    if (pts.length < 2) continue;
    const xs = pts.map((p) => p.x), zs = pts.map((p) => p.z);
    const alongZ = Math.max(...zs) - Math.min(...zs) > Math.max(...xs) - Math.min(...xs);
    pts.sort((a, b) => (alongZ ? a.z - b.z : a.x - b.x));
    const mid = pts[Math.floor(pts.length / 2)];
    const racks = [];
    for (const [bx, bz] of parking) {
      let near = null, nd = 80;
      for (const p of pts) { const d = Math.hypot(p.x - bx, p.z - bz); if (d < nd) { nd = d; near = p; } }
      if (!near || racks.some((r) => Math.hypot(r.x - bx, r.z - bz) < 30)) continue;
      const h = Math.atan2(near.dx, near.dz) + Math.PI / 2;
      racks.push({ x: bx, z: bz, h });
      for (const off of [-0.5, 0.5]) {
        const bike = G.spawnCar('bike', bx + Math.sin(h + Math.PI / 2) * off, bz + Math.cos(h + Math.PI / 2) * off, h, BIKE_COLORS[colorIdx++ % BIKE_COLORS.length]);
        bike.rack = true;
      }
    }
    G.trails.push({ label: tr.label, re: tr.re, pts, mid, racks });
  }
}

const labels = [];
function makeLabels() {
  const L = G.missions.L;
  for (const lm of Object.values(L)) {
    const s = textSprite(lm.label, { scale: 1, depthTest: false });
    s.position.set(lm.x, 18 + G.floorAt(lm.x, lm.z), lm.z);
    s.visible = false;
    scene.add(s);
    labels.push({ s, x: lm.x, z: lm.z, base: s.scale.clone() });
  }
}

// ---------------------------------------------------------------- beacons
const beaconGeo = new THREE.CylinderGeometry(2.2, 2.2, 70, 20, 1, true).translate(0, 35, 0);
const beaconMats = {
  yellow: new THREE.MeshBasicMaterial({ color: 0xffd23f, transparent: true, opacity: 0.32, depthWrite: false, side: THREE.DoubleSide, fog: false }),
  pink: new THREE.MeshBasicMaterial({ color: 0xff4fa3, transparent: true, opacity: 0.3, depthWrite: false, side: THREE.DoubleSide, fog: false }),
};
const ringGeo = new THREE.RingGeometry(0.85, 1, 40).rotateX(-Math.PI / 2);
const beacons = [];
function setBeacons(list) {
  while (beacons.length < list.length) {
    const g = new THREE.Group();
    const cyl = new THREE.Mesh(beaconGeo, beaconMats.yellow);
    const ring = new THREE.Mesh(ringGeo, beaconMats.yellow);
    ring.position.y = 0.25;
    g.add(cyl, ring);
    scene.add(g);
    beacons.push({ g, cyl, ring });
  }
  beacons.forEach((b, i) => {
    const m = list[i];
    b.g.visible = !!m;
    if (!m) return;
    b.g.position.set(m.x, G.floorAt(m.x, m.z), m.z);
    const mat = m.pink ? beaconMats.pink : beaconMats.yellow;
    b.cyl.material = mat; b.ring.material = mat;
    const r = m.radius || 6;
    b.ring.scale.set(r, 1, r);
    b.cyl.scale.set(i === 0 ? 1 : 0.6, i === 0 ? 1 : 0.5, i === 0 ? 1 : 0.6);
  });
}

// ---------------------------------------------------------------- GPS
const routeState = { key: '', t: 0, route: null, from: null };
function updateRoute(dt) {
  routeState.t -= dt;
  const mk = G.missions.markers;
  let target = null;
  if (G.missions.active && mk.length && G.missions.active.route !== false) target = mk[0];
  else if (G.waypoint) target = G.waypoint;
  if (!target) { routeState.route = null; return; }
  const p = G.pos;
  const bike = !!G.car?.spec.bike;
  const key = `${Math.round(target.x)},${Math.round(target.z)},${bike}`;
  const moved = routeState.from ? Math.hypot(p.x - routeState.from.x, p.z - routeState.from.z) : 1e9;
  if (key !== routeState.key || (routeState.t <= 0 && moved > 12)) {
    routeState.key = key; routeState.t = 1.2; routeState.from = { ...p };
    routeState.route = G.nav.route(p.x, p.z, target.x, target.z, bike);
  }
  if (G.waypoint && !G.missions.active && Math.hypot(p.x - G.waypoint.x, p.z - G.waypoint.z) < 20) {
    G.waypoint = null; G.hud.waypoint = null; G.hud.toast('You have arrived.');
  }
}

// ---------------------------------------------------------------- car enter / exit
function enterCar(c) {
  const t = G.traffic;
  if (c.driver === 'ai') {
    // the driver hops out and lends you the car
    const side = { x: c.x + Math.cos(c.heading) * 2.2, z: c.z - Math.sin(c.heading) * 2.2 };
    const npc = G.spawnNPC({}, side.x, side.z, c.heading);
    t.peds.push({ mesh: npc.mesh, x: side.x, z: side.z, edge: c.ai.edge, dir: 1, seg: 0, off: 4, foot: false, speed: 1.2, heading: c.heading, dodge: 0, dodgeX: 0, dodgeZ: 0, talk: 4, line: '' });
    say(t.peds[t.peds.length - 1], ['Sure, take it for a spin!', 'Borrowing my car? Okay, bring it back with gas!', 'Ha, fine, I needed a walk anyway.'][Math.floor(Math.random() * 3)]);
  }
  t.detach(c);
  c.driver = 'player';
  c.ai = null;
  c.keep = true;
  G.playerCar = c;
  player.mesh.visible = false;
  if (c.spec.bike) mountRider(c.mesh, buildPerson(PLAYER_LOOK));
  else G.sound.door();
  if (G.lastCar && G.lastCar !== c && G.lastCar !== G.familyCar && G.lastCar !== G.sportsCar && G.lastCar !== G.homeBike && !G.lastCar.rack) G.lastCar.keep = false;
  G.lastCar = c;
}

function exitCar() {
  const c = G.playerCar;
  if (!c) return;
  if (c.absSpeed > 6) { G.hud.toast('Slow down before you get out.'); return; }
  const lx = Math.cos(c.heading), lz = -Math.sin(c.heading);
  let px = c.x + lx * (c.spec.w / 2 + 0.8), pz = c.z + lz * (c.spec.w / 2 + 0.8);
  const out = { x: 0, z: 0, nx: 0, nz: 0, hit: false };
  G.world.collide(px, pz, 0.35, out);
  if (out.hit) { px = c.x - lx * (c.spec.w / 2 + 0.8); pz = c.z - lz * (c.spec.w / 2 + 0.8); }
  player.x = px; player.z = pz; player.y = 0; player.vy = 0;
  player.ground = c.y;
  player.heading = c.heading;
  player.mesh.visible = true;
  c.driver = null;
  c.input = { throttle: 0, brake: 0, steer: 0, handbrake: 1 };
  const rider = c.mesh.userData.rider;
  if (rider) { c.mesh.userData.body.remove(rider); c.mesh.userData.rider = null; c.sync(); }
  G.traffic.extra.push(c);
  G.playerCar = null;
  if (!c.spec.bike) G.sound.door();
  G.sound.engine(false, 0, 0, false);
  // only keep a few personal cars around
  const ex = G.traffic.extra;
  for (let i = ex.length - 1; i >= 0; i--) {
    const k = ex[i];
    if (k.keep || k === c) continue;
    if (Math.hypot(k.x - player.x, k.z - player.z) > 300) { G.traffic.remove(k); }
  }
}

// Bumps the player's car off walls of the real 3D buildings. The ray runs at
// 2.3 m so cars that are part of the 3D photo (about 1.5 m tall) don't block it.
function realWalls(car) {
  const sp = car.absSpeed;
  if (sp < 0.3) return;
  const dx = car.vx / sp, dz = car.vz / sp;
  const reach = car.halfLen + 0.4 + sp * 0.03;
  const hit = city.wall(car.x, car.y + (car.spec.bike ? 1.2 : 2.3), car.z, dx, dz, reach);
  if (!hit) return;
  const push = reach - hit.dist;
  car.x += hit.nx * push; car.z += hit.nz * push;
  const vn = car.vx * hit.nx + car.vz * hit.nz;
  if (vn < 0) {
    car.vx -= vn * hit.nx * 1.35; car.vz -= vn * hit.nz * 1.35;
    car.vx *= 0.8; car.vz *= 0.8;
    car.hitStrength = Math.max(car.hitStrength, -vn);
  }
  car.sync();
}

const bubbles = [];
function say(ped, text) { bubbles.length = 0; bubbles.push({ ped, text, t: 3 }); }

// ---------------------------------------------------------------- player on foot
const tmp = { x: 0, z: 0, nx: 0, nz: 0, hit: false };
function updatePlayer(dt, inp) {
  const fwd = { x: Math.sin(cam.yaw), z: Math.cos(cam.yaw) };
  const right = { x: -fwd.z, z: fwd.x };
  let mx = fwd.x * inp.y + right.x * inp.x, mz = fwd.z * inp.y + right.z * inp.x;
  const ml = Math.hypot(mx, mz);
  const run = inp.sprint ? 7.2 : 4.2;
  let target = 0;
  if (ml > 0.05) {
    mx /= ml; mz /= ml;
    target = run * Math.min(1, ml);
    const h = Math.atan2(mx, mz);
    player.heading += wrapAngle(h - player.heading) * (1 - Math.exp(-14 * dt));
  }
  player.speed = smooth(player.speed, target, 10, dt);
  player.x += Math.sin(player.heading) * player.speed * dt;
  player.z += Math.cos(player.heading) * player.speed * dt;
  if (inp.jump && player.y <= 0.001) player.vy = 6.2;
  player.vy -= 20 * dt;
  player.y = Math.max(0, player.y + player.vy * dt);
  if (player.y === 0) player.vy = Math.max(0, player.vy);
  G.world.collide(player.x, player.z, 0.35, tmp);
  player.x = tmp.x; player.z = tmp.z;
  if (city) {
    // walls of the real buildings (also blocks fences and hedges)
    if (player.speed > 0.1) {
      const fx = Math.sin(player.heading), fz = Math.cos(player.heading);
      const hit = city.wall(player.x, player.ground + player.y + 1.0, player.z, fx, fz, 0.6);
      if (hit) { const push = 0.6 - hit.dist; player.x += hit.nx * push; player.z += hit.nz * push; }
    }
    const gy = city.groundAt(player.x, player.z, player.ground + player.y + 1.2);
    if (gy != null) {
      // step up kerbs and stairs; fall off ledges
      if (gy > player.ground + player.y) { player.ground = gy; player.y = 0; } else { player.y += player.ground - gy; player.ground = gy; }
    }
  }
  // push out of cars
  for (const list of [G.traffic.cars, G.traffic.parked, G.traffic.extra]) {
    for (const c of list) {
      if (Math.abs(c.x - player.x) > 8 || Math.abs(c.z - player.z) > 8) continue;
      for (const [cx, cz] of c.circles()) {
        const dx = player.x - cx, dz = player.z - cz, d = Math.hypot(dx, dz), rr = c.radius + 0.35;
        if (d < rr && d > 1e-4) { player.x += (dx / d) * (rr - d); player.z += (dz / d) * (rr - d); }
      }
    }
  }
  player.mesh.position.set(player.x, player.ground + player.y, player.z);
  player.mesh.rotation.y = player.heading;
  animatePerson(player.mesh, player.speed, dt, player.y > 0.05);
}

// ---------------------------------------------------------------- time of day
let hour = 10;
const C = (h) => new THREE.Color(h);
const SKY = {
  dayTop: C(0x4d9be0), dayBot: C(0xcfe4f2), nightTop: C(0x060b1c), nightBot: C(0x1a2340), duskTop: C(0x34508f), duskBot: C(0xf0a05a),
};
const tmpC = new THREE.Color(), tmpC2 = new THREE.Color();
function updateSky(dt) {
  hour = (hour + dt / 120) % 24; // one game hour every two minutes
  const a = ((hour - 6) / 12) * Math.PI;
  const el = Math.sin(a);
  const day = clamp(el * 2.5 + 0.25, 0, 1);
  const dusk = clamp(1 - Math.abs(el) * 4, 0, 1);
  const sunDir = new THREE.Vector3(-Math.cos(a) * 0.8, Math.max(el, -0.3), -0.45).normalize();
  tmpC.copy(SKY.nightTop).lerp(SKY.dayTop, day).lerp(SKY.duskTop, dusk * 0.5);
  tmpC2.copy(SKY.nightBot).lerp(SKY.dayBot, day).lerp(SKY.duskBot, dusk * 0.6);
  skyMat.uniforms.top.value.copy(tmpC);
  skyMat.uniforms.bottom.value.copy(tmpC2);
  skyMat.uniforms.sunDir.value.copy(sunDir);
  scene.fog.color.copy(tmpC2);
  hemi.intensity = 0.32 + 0.6 * day;
  hemi.color.setHex(day > 0.3 ? 0xdfefff : 0x8090c0);
  sun.intensity = 1.7 * day + 0.12;
  sun.color.copy(C(0xfff1dc)).lerp(C(0xffa060), dusk * 0.6);
  if (day < 0.05) sun.color.setHex(0x8898cc);
  const night = 1 - day;
  G.world.mats.houseWall.emissiveIntensity = night * 0.8;
  G.world.mats.bigWall.emissiveIntensity = night * 0.9;
  G.world.mats.leaves.color.setScalar(1);
  G.night = night > 0.55;
  if (city) city.setDim(0.38 + 0.62 * day);
  const p = G.pos;
  sun.position.set(p.x + (el > -0.05 ? sunDir.x : -sunDir.x) * 250, Math.abs(sunDir.y) * 250 + 40, p.z + sunDir.z * 250);
  sun.target.position.set(p.x, p.y ?? 0, p.z);
  G.hud.setClock(hour);
}

// ---------------------------------------------------------------- main loop
let last = 0, locTimer = 0, waterTimer = 0, saveTimer = 0, tileTimer = 0;
function loop(now) {
  requestAnimationFrame(loop);
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (!G.world) return;
  if (playing) step(dt);
  renderFrame(dt);
  pressed.clear();
}

function readInput() {
  const pad = gamepad();
  const k = (c) => keys.has(c);
  const inp = {
    x: (k('KeyD') || k('ArrowRight') ? 1 : 0) - (k('KeyA') || k('ArrowLeft') ? 1 : 0),
    y: (k('KeyW') || k('ArrowUp') ? 1 : 0) - (k('KeyS') || k('ArrowDown') ? 1 : 0),
    sprint: k('ShiftLeft') || k('ShiftRight'),
    jump: pressed.has('Space'),
    interact: pressed.has('KeyE') || pressed.has('KeyF') || pressed.has('Enter'),
    map: pressed.has('KeyM'),
    horn: pressed.has('KeyH'),
    handbrake: k('Space'),
    throttle: k('KeyW') || k('ArrowUp') ? 1 : 0,
    brake: k('KeyS') || k('ArrowDown') ? 1 : 0,
    cancel: pressed.has('KeyX'),
    camX: 0, camY: 0,
  };
  if (pad) {
    if (Math.abs(pad.lx) > Math.abs(inp.x)) inp.x = pad.lx;
    if (Math.abs(pad.ly) > Math.abs(inp.y)) inp.y = -pad.ly;
    inp.throttle = Math.max(inp.throttle, pad.rt);
    inp.brake = Math.max(inp.brake, pad.lt);
    inp.jump ||= pad.jump; inp.interact ||= pad.interact; inp.map ||= pad.map;
    inp.handbrake ||= pad.handbrake; inp.horn ||= pad.horn && !G._hornHeld;
    G._hornHeld = pad.horn;
    inp.sprint ||= pad.a;
    inp.camX = pad.rx * 14; inp.camY = pad.ry * 10;
  }
  return inp;
}

function step(dt) {
  const inp = readInput();
  const hud = G.hud;
  // map toggle
  if (inp.map) {
    if (hud.mapOpen) { hud.closeMap(); lock(); } else { hud.openMap(G.pos.x, G.pos.z); document.exitPointerLock?.(); $('pause').hidden = true; }
  }
  if (hud.mapOpen) { hud.update(dt); return; }
  if (!locked && !inp.camX && $('pause').hidden === false) { hud.update(dt); return; }
  // camera mouse
  const mdx = mouseDX + inp.camX, mdy = mouseDY + inp.camY;
  mouseDX = mouseDY = 0;
  if (Math.abs(mdx) + Math.abs(mdy) > 0.5) cam.lastMouse = performance.now();
  cam.yaw -= mdx * 0.0026;
  cam.pitch = clamp(cam.pitch + mdy * 0.0022, -0.15, 1.2);
  let prompt = '';
  const car = G.playerCar;
  // interact
  if (inp.interact && hud.dialog) { hud.advanceDialog(); inp.interact = false; }
  if (inp.cancel && G.missions.active) G.missions.cancel();
  if (car) {
    const ci = car.input;
    // on a bike, W pedals at a steady pace and Shift pedals hard
    ci.throttle = car.spec.bike ? inp.throttle * (inp.sprint ? 1 : 0.55) : inp.throttle;
    ci.brake = inp.brake;
    ci.steer = inp.x; ci.handbrake = inp.handbrake ? 1 : 0;
    // two physics substeps for stability at speed
    car.followSlope = !!city;
    car.update(dt / 2, G.world); car.update(dt / 2, G.world);
    if (city) realWalls(car);
    if (car.hitStrength > 4) { G.sound.bump(car.hitStrength); cam.shake = Math.min(0.6, car.hitStrength * 0.04); G.missions.active?.onBump?.(car.hitStrength); }
    car.hitStrength = 0;
    if (inp.interact) exitCar();
    if (inp.horn) { if (car.spec.bike) G.sound.bell(); else G.sound.horn(); hornNearby(); }
    if (car.spec.bike) G.sound.engine(false, 0, 0, false);
    else G.sound.engine(true, car.speed, ci.throttle, ci.handbrake && car.absSpeed > 6);
    car.setHeadlights(G.night);
  } else {
    updatePlayer(dt, inp);
    const gv = G.missions.nearGiver(player);
    const nearCar = G.traffic.nearestEnterable(player.x, player.z);
    const ped = G.traffic.nearestPed(player.x, player.z);
    if (gv && !hud.dialog) {
      prompt = `<kbd>E</kbd> Talk to ${gv.def.giver.name}: <b>${gv.def.title}</b>${gv.done ? ' (replay for half pay)' : ''}`;
      if (inp.interact) G.missions.start(gv);
    } else if (nearCar && !hud.dialog) {
      const label = CAR_TYPES[nearCar.type].label;
      prompt = nearCar.driver === 'ai' ? `<kbd>E</kbd> Ask to borrow the ${label.toLowerCase()}` : nearCar.spec.bike ? '<kbd>E</kbd> Hop on the bike' : `<kbd>E</kbd> Get in the ${label.toLowerCase()}`;
      if (inp.interact) enterCar(nearCar);
    } else if (ped && !hud.dialog) {
      prompt = '<kbd>E</kbd> Say hi';
      if (inp.interact) { ped.talk = 3; ped.heading = Math.atan2(player.x - ped.x, player.z - ped.z); say(ped, ped.line || PED_LINES[0]); G.sound.blip(); }
    }
  }
  if (G.missions.active && !hud.dialog) prompt = prompt || '';
  hud.setPrompt(prompt);
  // world streaming
  const p = G.pos;
  tileTimer -= dt;
  if (tileTimer <= 0) { tileTimer = 0.4; G.world.updateTiles(p.x, p.z); }
  G.world.pump(5);
  const camDir = { x: Math.sin(cam.yaw), z: Math.cos(cam.yaw) };
  G.traffic.update(dt, { px: p.x, pz: p.z, playerCar: G.playerCar, player: G.playerCar ? null : player, camDir, nightLights: G.night });
  G.missions.update(dt);
  animateGivers(dt);
  updateRoute(dt);
  // water check
  waterTimer -= dt;
  if (waterTimer <= 0) { waterTimer = 0.3; checkWater(); }
  // location sign
  locTimer -= dt;
  if (locTimer <= 0) {
    locTimer = 0.5;
    const nr = G.world.nearestRoad(p.x, p.z, null, 40);
    const pl = G.world.placeName(p.x, p.z);
    hud.setLocation(nr ? G.world.roadName(nr.edge) : '', pl.hood ? `${pl.hood} · ${pl.city}` : pl.city);
  }
  saveTimer -= dt;
  if (saveTimer <= 0) { saveTimer = 20; G.save.hour = hour; G.persist(); }
  hud.setSpeed(car ? Math.abs(car.speed) * 2.237 : 0, !!car, car ? CAR_TYPES[car.type].label : '');
  hud.update(dt);
  updateSky(dt);
  for (const b of bubbles) b.t -= dt;
  if (bubbles.length && bubbles[0].t <= 0) bubbles.length = 0;
  if (G.traffic.onShout == null) G.traffic.onShout = (ped, text) => { if (Math.hypot(ped.x - G.pos.x, ped.z - G.pos.z) < 40) say(ped, text); };
  if (G.traffic.onHonk == null) G.traffic.onHonk = (c) => { if (Math.hypot(c.x - G.pos.x, c.z - G.pos.z) < 60) G.sound.smallHorn(); };
  if (G.traffic.onBump == null) G.traffic.onBump = (other, imp) => { G.sound.bump(imp); cam.shake = Math.min(0.6, imp * 0.04); G.missions.active?.onBump?.(imp); };
}

function hornNearby() {
  for (const p of G.traffic.peds) {
    if (Math.hypot(p.x - G.pos.x, p.z - G.pos.z) < 25 && Math.random() < 0.5) { say(p, ['Beep beep to you too!', 'Hi!', 'Oh! Hello!'][Math.floor(Math.random() * 3)]); break; }
  }
}

function animateGivers(dt) {
  const t = performance.now() / 1000;
  for (const gv of G.missions.givers) {
    const d = Math.hypot(gv.x - G.pos.x, gv.z - G.pos.z);
    const m = gv.npc.mesh;
    if (d < 18 && !G.missions.active) {
      m.rotation.y += wrapAngle(Math.atan2(G.pos.x - gv.x, G.pos.z - gv.z) - m.rotation.y) * Math.min(1, dt * 4);
      waveAnim(m, t);
    } else resetPose(m);
  }
}

function checkWater() {
  const c = G.playerCar;
  const x = c ? c.x : player.x, z = c ? c.z : player.z;
  if (!G.world.inWater(x, z)) return;
  const hit = G.world.nearestRoad(x, z, isDrivable, 600);
  if (!hit) return;
  G.sound.splash();
  const off = c ? 0 : 3;
  if (c) {
    c.x = hit.x; c.z = hit.z; c.vx = c.vz = 0; c.heading = Math.atan2(hit.dx, hit.dz); c.settled = !city; c.followGround(); c.sync();
    G.hud.toast('Splash! A friendly tow truck pulled you out of the water.', 'warn');
  } else {
    player.x = hit.x - hit.dz * off; player.z = hit.z + hit.dx * off;
    player.ground = G.floorAt(player.x, player.z); player.y = 0;
    G.hud.toast('Brrr, too cold for a swim. Back to dry land!', 'warn');
  }
}

// ---------------------------------------------------------------- render
const camPos = new THREE.Vector3(), camTarget = new THREE.Vector3();
const projV = new THREE.Vector3();
function renderFrame(dt) {
  const car = G.playerCar;
  if (car) {
    const sinceMouse = performance.now() - cam.lastMouse;
    if (sinceMouse > 1400 && car.absSpeed > 2) {
      const behind = car.speed < -1 ? car.heading + Math.PI : car.heading;
      cam.yaw += wrapAngle(behind - cam.yaw) * (1 - Math.exp(-3 * dt));
      cam.pitch = smooth(cam.pitch, 0.22, 2, dt);
    }
    const big = car.spec.l > 6 ? 1.6 : 1;
    if (car.spec.bike) {
      cam.dist = smooth(cam.dist, 4.6 + car.absSpeed * 0.08, 3, dt);
      camTarget.set(car.x, car.y + 1.7, car.z);
    } else {
      cam.dist = smooth(cam.dist, (8.5 + car.absSpeed * 0.06) * big, 3, dt);
      camTarget.set(car.x, car.y + 1.6 * big, car.z);
    }
  } else {
    cam.dist = smooth(cam.dist, 5.5, 4, dt);
    camTarget.set(player.x, player.ground + player.y + 1.6, player.z);
  }
  // pull the camera in front of buildings that would block the view
  let d = cam.dist;
  const cp = Math.cos(cam.pitch), sp = Math.sin(cam.pitch);
  if (city) {
    // keep the camera in front of real walls and above the ground
    const hit = city.cast(camTarget.x, camTarget.y, camTarget.z, -Math.sin(cam.yaw) * cp, sp, -Math.cos(cam.yaw) * cp, cam.dist);
    if (hit) d = Math.max(1.2, hit.distance - 0.4);
  } else {
    for (let i = 1; i <= 8; i++) {
      const t = (i / 8) * cam.dist;
      const x = camTarget.x - Math.sin(cam.yaw) * cp * t, z = camTarget.z - Math.cos(cam.yaw) * cp * t, y = camTarget.y + sp * t;
      if (G.world.heightAt(x, z) > y - 0.5) { d = Math.max(1.5, t - 0.6); break; }
    }
  }
  const baseY = car ? car.y : player.ground;
  camPos.set(camTarget.x - Math.sin(cam.yaw) * cp * d, Math.max(baseY + 0.6, camTarget.y + sp * d), camTarget.z - Math.cos(cam.yaw) * cp * d);
  if (cam.shake > 0) {
    cam.shake = Math.max(0, cam.shake - dt * 1.8);
    camPos.x += (Math.random() - 0.5) * cam.shake; camPos.y += (Math.random() - 0.5) * cam.shake;
  }
  camera.position.copy(camPos);
  camera.lookAt(camTarget.x, camTarget.y + 0.3, camTarget.z);
  sky.position.copy(camera.position);
  // headlight follows the player's car at night
  if (car && G.night) {
    headlight.intensity = 60;
    headlight.position.set(car.x + car.fx * 2, car.y + 1.2, car.z + car.fz * 2);
    headlight.target.position.set(car.x + car.fx * 25, car.y, car.z + car.fz * 25);
  } else headlight.intensity = 0;
  // markers
  const mk = G.missions ? G.missions.markers : [];
  const list = mk.slice(0, 6).map((m) => ({ ...m }));
  if (G.waypoint && !G.missions?.active) list.push({ ...G.waypoint, pink: true, radius: 10 });
  setBeacons(list);
  for (const b of beacons) b.cyl.material.opacity = 0.22 + Math.sin(performance.now() / 300) * 0.08;
  // labels scale with distance so they stay readable
  for (const l of labels) {
    const dd = Math.hypot(l.x - camera.position.x, l.z - camera.position.z);
    l.s.visible = dd < 900 && dd > 40;
    if (l.s.visible) { const k = clamp(dd / 90, 1, 8); l.s.scale.set(l.base.x * k, l.base.y * k, 1); l.s.position.y = G.floorAt(l.x, l.z) + 14 + k * 2; }
  }
  // speech bubble
  if (G.hud) {
    const b = bubbles[0];
    if (b) {
      projV.set(b.ped.x, (b.ped.y ?? 0) + (b.ped.mesh.userData.height || 1.8) + 0.5, b.ped.z).project(camera);
      if (projV.z < 1) G.hud.bubble(b.text, { x: (projV.x * 0.5 + 0.5) * window.innerWidth, y: (-projV.y * 0.5 + 0.5) * window.innerHeight });
      else G.hud.bubble(null);
    } else G.hud.bubble(null);
    // photo flash
    $('flash').style.opacity = G.missions ? G.missions.flash : 0;
    const route = routeState.route;
    const blips = [{ x: G.home.x, z: G.home.z, icon: 'home', color: '#7fd1ff' }, ...(G.missions ? G.missions.blips() : [])];
    if (G.waypoint) blips.push({ x: G.waypoint.x, z: G.waypoint.z, color: '#ff4fa3' });
    const heading = car ? car.heading : player.heading;
    if (playing) G.hud.drawMinimap(G.pos.x, G.pos.z, cam.yaw, heading, route, blips);
    if (G.hud.mapOpen) G.hud.drawBigMap(G.pos.x, G.pos.z, heading, route, blips, mapLabels());
  }
  if (city) {
    city.update();
    creditTimer -= dt;
    if (creditTimer <= 0) { creditTimer = 2; $('credit-text').textContent = city.attributions(); }
  }
  renderer.render(scene, camera);
}
let creditTimer = 0;

let _mapLabels = null;
function mapLabels() {
  if (_mapLabels) return _mapLabels;
  const out = [];
  for (const p of G.world.cities) out.push({ text: p[0], x: p[2], z: p[3], big: true });
  for (const p of G.world.hoods) out.push({ text: p[0], x: p[2], z: p[3], minScale: 0.22 });
  for (const l of Object.values(G.missions.L)) out.push({ text: l.label, x: l.x, z: l.z, minScale: 0.07 });
  out.push({ text: 'Home', x: G.home.x, z: G.home.z + 30, minScale: 0.05 });
  for (const t of G.trails) out.push({ text: t.label, x: t.mid.x, z: t.mid.z, minScale: 0.05, trail: true });
  _mapLabels = out;
  return out;
}

// Google key box on the title screen. The key is kept only in this browser.
$('gkey-clear').hidden = !googleKey;
$('gkey-state').textContent = googleKey ? 'A key is saved in this browser.' : 'No key saved.';
$('gkey-save').addEventListener('click', () => {
  const v = $('gkey').value.trim();
  if (!v) { $('gkey-state').textContent = 'Paste a key first.'; return; }
  try { localStorage.setItem(GKEY, v); } catch { $('gkey-state').textContent = 'This browser blocked saving the key.'; return; }
  location.reload();
});
$('gkey-clear').addEventListener('click', () => {
  try { localStorage.removeItem(GKEY); } catch { /* ignore */ }
  location.reload();
});

window.fishersCruise = { G, player, enterCar: (c) => enterCar(c), cam, renderer, applyGraphics, setGfx: (v) => { gfx = v; applyGraphics(); }, get city() { return city; }, realWalls: (c) => realWalls(c) };
boot();

// Procedural textures, shared materials, and low-poly cars and people.
import * as THREE from 'three';

// ------------------------------------------------------------ textures
function canvasTex(w, h, draw, repeat = true) {
  const c = document.createElement('canvas');
  c.width = w; c.height = h;
  draw(c.getContext('2d'), w, h);
  const t = new THREE.CanvasTexture(c);
  if (repeat) { t.wrapS = t.wrapT = THREE.RepeatWrapping; }
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 8;
  return t;
}

function noise(ctx, w, h, base, spread, n, size) {
  ctx.fillStyle = base; ctx.fillRect(0, 0, w, h);
  for (let i = 0; i < n; i++) {
    const v = (Math.random() - 0.5) * spread;
    ctx.fillStyle = v > 0 ? `rgba(255,255,255,${v})` : `rgba(0,0,0,${-v})`;
    const s = Math.random() * size + 1;
    ctx.fillRect(Math.random() * w, Math.random() * h, s, s);
  }
}

export function makeTextures() {
  const grass = canvasTex(256, 256, (ctx, w, h) => {
    noise(ctx, w, h, '#ffffff', 0.18, 9000, 2.5);
    for (let i = 0; i < 40; i++) {
      ctx.fillStyle = `rgba(0,0,0,${Math.random() * 0.05})`;
      ctx.beginPath(); ctx.arc(Math.random() * w, Math.random() * h, 10 + Math.random() * 30, 0, 7); ctx.fill();
    }
  });
  const asphalt = canvasTex(256, 256, (ctx, w, h) => noise(ctx, w, h, '#ffffff', 0.22, 14000, 1.6));
  // House siding with two windows per bay. One bay is 4 m wide and one storey 3 m tall.
  const facade = (lit) => canvasTex(128, 128, (ctx, w, h) => {
    if (lit) { ctx.fillStyle = '#000'; ctx.fillRect(0, 0, w, h); } else {
      ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h);
      for (let y = 0; y < h; y += 6) { ctx.fillStyle = 'rgba(0,0,0,0.06)'; ctx.fillRect(0, y, w, 1); }
    }
    for (const x of [18, 76]) {
      if (lit) {
        ctx.fillStyle = Math.random() < 0.55 ? '#ffd890' : '#000';
        ctx.fillRect(x, 34, 34, 50);
      } else {
        ctx.fillStyle = '#f4f4f0'; ctx.fillRect(x - 4, 30, 42, 58);
        ctx.fillStyle = '#2d3a46'; ctx.fillRect(x, 34, 34, 50);
        ctx.fillStyle = '#f4f4f0'; ctx.fillRect(x + 15, 34, 4, 50); ctx.fillRect(x, 57, 34, 4);
      }
    }
  });
  const office = (lit) => canvasTex(128, 128, (ctx, w, h) => {
    ctx.fillStyle = lit ? '#000' : '#fff'; ctx.fillRect(0, 0, w, h);
    for (let x = 0; x < 4; x++) {
      if (lit) {
        ctx.fillStyle = Math.random() < 0.4 ? '#fff2c8' : '#000';
      } else {
        ctx.fillStyle = '#4c6276';
      }
      ctx.fillRect(x * 32 + 3, 22, 26, 70);
      if (!lit) { ctx.fillStyle = 'rgba(255,255,255,0.18)'; ctx.fillRect(x * 32 + 3, 22, 8, 70); }
    }
  });
  const panel = canvasTex(64, 64, (ctx, w, h) => {
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, w, h);
    for (let x = 0; x < w; x += 8) { ctx.fillStyle = 'rgba(0,0,0,0.08)'; ctx.fillRect(x, 0, 2, h); }
  });
  const shingles = canvasTex(64, 64, (ctx, w, h) => {
    noise(ctx, w, h, '#ffffff', 0.15, 600, 2);
    for (let y = 0; y < h; y += 8) { ctx.fillStyle = 'rgba(0,0,0,0.18)'; ctx.fillRect(0, y, w, 1.5); }
  });
  const fish = canvasTex(128, 128, (ctx) => {
    ctx.fillStyle = '#ffc93c';
    ctx.beginPath(); ctx.ellipse(56, 64, 40, 24, 0, 0, 7); ctx.fill();
    ctx.beginPath(); ctx.moveTo(90, 64); ctx.lineTo(122, 38); ctx.lineTo(122, 90); ctx.fill();
    ctx.fillStyle = '#20242a'; ctx.beginPath(); ctx.arc(36, 58, 5, 0, 7); ctx.fill();
  }, false);
  return {
    grass, asphalt, facade: facade(false), facadeLit: facade(true),
    office: office(false), officeLit: office(true), panel, shingles, fish,
  };
}

// Text drawn onto a sprite, used for place labels and markers.
export function textSprite(text, opts = {}) {
  const font = opts.font || '600 44px "Barlow Condensed", "Arial Narrow", sans-serif';
  const c = document.createElement('canvas');
  const ctx = c.getContext('2d');
  ctx.font = font;
  const w = Math.ceil(ctx.measureText(text).width) + 40;
  c.width = w; c.height = 72;
  ctx.font = font;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  if (opts.bg) {
    ctx.fillStyle = opts.bg;
    const r = 18;
    ctx.beginPath(); ctx.roundRect(2, 6, w - 4, 60, r); ctx.fill();
  }
  ctx.lineWidth = 8; ctx.strokeStyle = opts.stroke || 'rgba(10,16,24,0.85)';
  if (!opts.bg) ctx.strokeText(text, w / 2, 38);
  ctx.fillStyle = opts.color || '#fff';
  ctx.fillText(text, w / 2, 38);
  const tex = new THREE.CanvasTexture(c);
  tex.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.SpriteMaterial({ map: tex, depthTest: opts.depthTest ?? true, transparent: true, fog: false });
  const s = new THREE.Sprite(mat);
  const scale = opts.scale || 1;
  s.scale.set((w / 72) * 2 * scale, 2 * scale, 1);
  s.renderOrder = 10;
  return s;
}

// ------------------------------------------------------------ baking
// Parts are collected per "bone" and merged into one vertex-coloured mesh,
// which keeps each car or person to a handful of draw calls.
const unitBox = new THREE.BoxGeometry(1, 1, 1);
const _m = new THREE.Matrix4(), _q = new THREE.Quaternion(), _s = new THREE.Vector3(), _p = new THREE.Vector3(), _e = new THREE.Euler();

class Baker {
  constructor() { this.pos = []; this.nrm = []; this.col = []; }
  add(geo, color, w, h, l, x, y, z, rx = 0, ry = 0, rz = 0) {
    const g = geo.index ? geo.toNonIndexed() : geo;
    _m.compose(_p.set(x, y, z), _q.setFromEuler(_e.set(rx, ry, rz)), _s.set(w, h, l));
    const nm = new THREE.Matrix3().getNormalMatrix(_m);
    const P = g.attributes.position, N = g.attributes.normal;
    const c = new THREE.Color(color);
    const v = new THREE.Vector3();
    for (let i = 0; i < P.count; i++) {
      v.fromBufferAttribute(P, i).applyMatrix4(_m);
      this.pos.push(v.x, v.y, v.z);
      v.fromBufferAttribute(N, i).applyMatrix3(nm).normalize();
      this.nrm.push(v.x, v.y, v.z);
      this.col.push(c.r, c.g, c.b);
    }
    return this;
  }
  box(color, w, h, l, x, y, z) { return this.add(unitBox, color, w, h, l, x, y, z); }
  geometry() {
    const geo = new THREE.BufferGeometry();
    geo.setAttribute('position', new THREE.Float32BufferAttribute(this.pos, 3));
    geo.setAttribute('normal', new THREE.Float32BufferAttribute(this.nrm, 3));
    geo.setAttribute('color', new THREE.Float32BufferAttribute(this.col, 3));
    geo.computeBoundingSphere();
    return geo;
  }
}

export const carMat = new THREE.MeshPhongMaterial({ vertexColors: true, shininess: 70, specular: 0x555555 });
export const personMat = new THREE.MeshLambertMaterial({ vertexColors: true });
export const lightMats = {
  off: new THREE.MeshLambertMaterial({ color: 0xf2efe2 }),
  on: new THREE.MeshBasicMaterial({ color: 0xfff6d0 }),
};

// ------------------------------------------------------------ cars
const GLASS = 0x1e2a36, TRIM = 0x24272c, TAIL = 0xa31515;

// Car specs: size, handling and look. Lengths in metres, speeds in m/s.
export const CAR_TYPES = {
  sedan:    { w: 1.82, l: 4.7, h: 1.45, clear: 0.32, cabin: [0.55, 2.4, -0.15], maxSpeed: 46, accel: 9.5, grip: 7.5, steer: 0.62, label: 'Sedan' },
  suv:      { w: 1.95, l: 4.85, h: 1.75, clear: 0.42, cabin: [0.7, 2.9, -0.35], maxSpeed: 42, accel: 8.5, grip: 7.0, steer: 0.58, label: 'SUV' },
  minivan:  { w: 1.95, l: 5.1, h: 1.78, clear: 0.36, cabin: [0.8, 3.6, -0.3], maxSpeed: 40, accel: 8.0, grip: 7.0, steer: 0.56, label: 'Minivan' },
  pickup:   { w: 2.0, l: 5.6, h: 1.85, clear: 0.5, cabin: [0.75, 1.9, 0.55], bed: true, maxSpeed: 42, accel: 8.8, grip: 6.6, steer: 0.55, label: 'Pickup' },
  hatch:    { w: 1.76, l: 4.1, h: 1.45, clear: 0.3, cabin: [0.6, 2.3, -0.35], maxSpeed: 43, accel: 9.2, grip: 8.0, steer: 0.66, label: 'Hatchback' },
  sports:   { w: 1.9, l: 4.5, h: 1.22, clear: 0.22, cabin: [0.42, 1.9, -0.25], maxSpeed: 60, accel: 14, grip: 9.5, steer: 0.62, label: 'Sports car' },
  van:      { w: 2.0, l: 5.4, h: 2.4, clear: 0.4, cabin: [1.3, 4.6, -0.3], boxy: true, maxSpeed: 36, accel: 6.5, grip: 6.2, steer: 0.52, label: 'Delivery van' },
  icecream: { w: 2.1, l: 5.8, h: 2.8, clear: 0.42, cabin: [1.6, 4.8, -0.35], boxy: true, maxSpeed: 34, accel: 6.5, grip: 6.2, steer: 0.5, label: 'Ice cream truck' },
  bus:      { w: 2.45, l: 10.5, h: 3.0, clear: 0.45, cabin: [1.7, 9.6, -0.2], boxy: true, maxSpeed: 30, accel: 5, grip: 6.0, steer: 0.45, label: 'School bus' },
  bike:     { w: 0.62, l: 1.8, h: 1.1, clear: 0.36, cabin: [0, 0, 0], bike: true, maxSpeed: 14, accel: 5, grip: 10, steer: 0.75, label: 'Bike' },
  golf:     { w: 1.25, l: 2.4, h: 1.8, clear: 0.2, cabin: [0.9, 1.4, -0.1], open: true, maxSpeed: 12, accel: 6, grip: 8.5, steer: 0.7, label: 'Golf cart' },
};

export const CAR_COLORS = [0xe8e8e8, 0x1d1f22, 0x8b9096, 0x5d6268, 0x1f3f6b, 0x8c1c1c, 0xbfc3c6, 0x26472f,
  0x6d4c33, 0xd9d4c5, 0x2f6fb5, 0xb33b2e, 0x3c3f45, 0xf2f2f2, 0x7a1f3d, 0xe5b22b];

const wheelCache = new Map();
function wheelGeometry() {
  if (wheelCache.has('w')) return wheelCache.get('w');
  const b = new Baker();
  const cyl = new THREE.CylinderGeometry(1, 1, 1, 14);
  b.add(cyl, 0x1a1a1a, 1, 0.26, 1, 0, 0, 0, 0, 0, Math.PI / 2);
  b.add(cyl, 0xbfc4c9, 0.62, 0.27, 0.62, 0, 0, 0, 0, 0, Math.PI / 2);
  b.box(0x8d9298, 0.28, 1.1, 0.25, 0, 0, 0);
  const g = b.geometry();
  wheelCache.set('w', g);
  return g;
}

const carGeoCache = new Map();
function carBodyGeometry(typeName, color) {
  const key = typeName + ':' + color;
  if (carGeoCache.has(key)) return carGeoCache.get(key);
  const t = CAR_TYPES[typeName];
  const b = new Baker(), lights = new Baker();
  const bodyH = t.boxy ? t.h - t.clear - 0.1 : (t.h - t.clear) * 0.48;
  const by = t.clear + bodyH / 2;
  if (typeName === 'bus') {
    const Y = 0xf2b705;
    b.box(Y, t.w, bodyH, t.l, 0, by, 0);
    b.box(GLASS, t.w + 0.02, 0.8, t.l * 0.86, 0, t.clear + bodyH * 0.72, -0.4);
    b.box(TRIM, t.w + 0.04, 0.12, t.l, 0, t.clear + bodyH * 0.42, 0);
    b.box(Y, t.w * 0.9, 0.9, 1.0, 0, t.clear + 0.45, t.l / 2 + 0.4);
    b.box(TRIM, 0.9, 0.5, 0.06, -0.6, by + bodyH * 0.2, t.l / 2 + 0.01);
  } else if (t.boxy) {
    b.box(color, t.w, bodyH, t.l, 0, by, 0);
    b.box(GLASS, t.w - 0.1, bodyH * 0.38, 0.06, 0, by + bodyH * 0.22, t.l / 2 + 0.01);
    b.box(GLASS, t.w + 0.02, bodyH * 0.3, 1.2, 0, by + bodyH * 0.22, t.l / 2 - 0.9);
    if (typeName === 'icecream') {
      b.box(0xff7eb6, t.w + 0.03, 0.35, t.l * 0.98, 0, by - bodyH * 0.12, 0);
      b.add(new THREE.ConeGeometry(0.35, 0.9, 10), 0xd9a05b, 1, 1, 1, 0, t.h + 0.4, 0.4, Math.PI, 0, 0);
      b.add(new THREE.SphereGeometry(0.42, 12, 8), 0xff9fcf, 1, 1, 1, 0, t.h + 1.0, 0.4);
      b.box(GLASS, 0.06, 0.9, 1.8, t.w / 2 + 0.01, by + 0.2, -0.8);
    } else {
      b.box(0xd9d9d9, t.w + 0.02, 0.25, t.l * 0.6, 0, by + bodyH * 0.05, -0.8);
    }
  } else if (t.open) {
    b.box(color, t.w, 0.5, t.l, 0, t.clear + 0.35, 0);
    b.box(0x2a2a2a, t.w * 0.9, 0.5, 0.6, 0, t.clear + 0.85, -0.2);
    b.box(color, t.w, 0.06, t.l * 0.8, 0, t.h, -0.1);
    for (const sx of [-1, 1]) for (const sz of [-1, 1]) b.box(TRIM, 0.05, t.h - 0.6, 0.05, sx * (t.w / 2 - 0.05), t.clear + (t.h - t.clear) / 2 + 0.2, sz * 0.75 - 0.1);
  } else {
    b.box(color, t.w, bodyH, t.l, 0, by, 0);
    b.box(color, t.w * 0.98, 0.06, t.l * 0.28, 0, t.clear + bodyH + 0.02, t.l * 0.33);
    const [ch, cl, cz] = t.cabin;
    const cy = t.clear + bodyH + ch / 2;
    b.box(GLASS, t.w * 0.86, ch, cl, 0, cy, cz);
    b.box(color, t.w * 0.84, 0.07, cl * 0.82, 0, cy + ch / 2 + 0.03, cz);
    b.box(color, t.w * 0.87, ch * 0.95, 0.12, 0, cy, cz + cl / 2 - 0.05);
    b.box(color, t.w * 0.87, ch * 0.95, 0.16, 0, cy, cz - cl / 2 + 0.08);
    b.box(color, t.w * 0.875, ch * 0.9, 0.1, 0, cy, cz);
    if (t.bed) {
      b.box(color, 0.1, 0.45, t.l * 0.38, t.w / 2 - 0.05, t.clear + bodyH + 0.22, -t.l * 0.28);
      b.box(color, 0.1, 0.45, t.l * 0.38, -t.w / 2 + 0.05, t.clear + bodyH + 0.22, -t.l * 0.28);
      b.box(color, t.w, 0.45, 0.1, 0, t.clear + bodyH + 0.22, -t.l / 2 + 0.05);
    }
    if (typeName === 'sports') b.box(TRIM, t.w * 0.9, 0.06, 0.3, 0, t.clear + bodyH + 0.25, -t.l / 2 + 0.2);
  }
  b.box(TRIM, t.w + 0.04, 0.22, 0.14, 0, t.clear + 0.12, t.l / 2 + 0.02);
  b.box(TRIM, t.w + 0.04, 0.22, 0.14, 0, t.clear + 0.12, -t.l / 2 - 0.02);
  for (const s of [-1, 1]) {
    lights.box(0xffffff, 0.36, 0.14, 0.06, s * (t.w / 2 - 0.3), t.clear + bodyH * 0.72, t.l / 2 + 0.01);
    b.box(TAIL, 0.32, 0.14, 0.06, s * (t.w / 2 - 0.28), t.clear + bodyH * 0.72, -t.l / 2 - 0.01);
  }
  const out = { body: b.geometry(), lights: lights.geometry() };
  carGeoCache.set(key, out);
  return out;
}

const BIKE_COLORS = [0x2f6fb5, 0xd94848, 0x3b9c5a, 0xf2c037, 0x2b2f36, 0xff8a3d, 0x2bb3b1, 0xe46aa7];
export { BIKE_COLORS };

// A bicycle with the same userData shape as a car, so the car physics drive it.
function buildBike(color) {
  const g = new THREE.Group();
  const body = new THREE.Group();
  g.add(body);
  const b = new Baker();
  const tube = (x0, y0, z0, x1, y1, z1, r, col) => {
    const dx = x1 - x0, dy = y1 - y0, dz = z1 - z0;
    const len = Math.hypot(dx, dy, dz);
    // a unit box stretched along y, then tilted in the y/z plane
    b.add(unitBox, col, r, len, r, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, Math.atan2(dz, dy), 0, 0);
  };
  const R = 0.34;
  // frame (front of the bike is +z)
  tube(0, R, -0.52, 0, 0.82, -0.12, 0.05, color);   // seat tube
  tube(0, R, -0.52, 0, R + 0.02, 0.05, 0.045, color); // chain stay
  tube(0, R + 0.02, 0.05, 0, 0.82, -0.12, 0.05, color); // down tube
  tube(0, 0.82, -0.12, 0, 0.86, 0.42, 0.05, color);  // top tube
  tube(0, 0.86, 0.42, 0, R, 0.55, 0.045, color);     // fork
  tube(0, 0.86, 0.42, 0, 1.02, 0.45, 0.04, 0x2a2a2a); // stem
  b.box(0x2a2a2a, 0.56, 0.04, 0.04, 0, 1.02, 0.45);    // handlebar
  b.box(0x1c1c1c, 0.16, 0.05, 0.26, 0, 0.88, -0.16);   // seat
  b.box(0x3a3a3a, 0.08, 0.08, 0.08, 0, R + 0.02, 0.05); // crank
  g.add(new THREE.Mesh(b.geometry(), carMat));
  body.add(g.children[1]);
  body.children[0].castShadow = true;
  const lights = new Baker().box(0xffffff, 0.09, 0.07, 0.05, 0, 0.92, 0.5).geometry();
  const lm = new THREE.Mesh(lights, lightMats.off);
  body.add(lm);
  const wheelGeo = cached('bikewheel', () => {
    const w = new Baker();
    w.add(new THREE.TorusGeometry(1, 0.09, 6, 22), 0x1a1a1a, 1, 1, 1, 0, 0, 0, 0, Math.PI / 2, 0);
    w.box(0xbfc4c9, 0.03, 1.9, 0.05, 0, 0, 0);
    w.box(0xbfc4c9, 0.03, 0.05, 1.9, 0, 0, 0);
    return w.geometry();
  });
  const wheels = [];
  for (const sz of [1, -1]) {
    const pivot = new THREE.Group();
    pivot.position.set(0, R, sz > 0 ? 0.55 : -0.52);
    const tire = new THREE.Mesh(wheelGeo, carMat);
    tire.scale.setScalar(R);
    tire.castShadow = true;
    pivot.add(tire);
    g.add(pivot);
    wheels.push({ pivot, tire, front: sz > 0 });
  }
  g.userData = { body, wheels, wheelR: R, spec: CAR_TYPES.bike, lights: lm, rider: null };
  return g;
}

// Seats a person on a bike and returns it. Call pedal() each frame to animate.
export function mountRider(bike, person) {
  const u = person.userData;
  person.position.set(0, 0.02, -0.2);
  person.rotation.set(0, 0, 0);
  u.hips.rotation.x = 0.35;
  u.armL.rotation.x = -1.15; u.armR.rotation.x = -1.15;
  bike.userData.body.add(person);
  bike.userData.rider = person;
  return person;
}

export function pedal(bike, crank) {
  const r = bike.userData.rider;
  if (!r) return;
  const u = r.userData;
  u.hips.position.y = 0.9;
  u.legL.rotation.x = -0.75 + Math.sin(crank) * 0.45;
  u.legR.rotation.x = -0.75 - Math.sin(crank) * 0.45;
}

export function buildCar(typeName, color) {
  if (typeName === 'bike') return buildBike(color);
  const t = CAR_TYPES[typeName];
  const g = new THREE.Group();
  const body = new THREE.Group();
  g.add(body);
  const geo = carBodyGeometry(typeName, color);
  const bm = new THREE.Mesh(geo.body, carMat);
  bm.castShadow = true;
  body.add(bm);
  const lm = new THREE.Mesh(geo.lights, lightMats.off);
  body.add(lm);
  const r = Math.max(0.28, t.clear + 0.05);
  const wheels = [];
  const wz = t.l / 2 - Math.max(0.75, r * 2.2);
  const wg = wheelGeometry();
  for (const sz of [1, -1]) {
    for (const sx of [-1, 1]) {
      const pivot = new THREE.Group();
      pivot.position.set(sx * (t.w / 2 - 0.12), r, sz * wz);
      const tire = new THREE.Mesh(wg, carMat);
      tire.scale.set(1, r, r);
      pivot.add(tire);
      g.add(pivot);
      wheels.push({ pivot, tire, front: sz > 0 });
    }
  }
  g.userData = { body, wheels, wheelR: r, spec: t, lights: lm };
  return g;
}

// ------------------------------------------------------------ people
export const SKIN = [0xf1c8a5, 0xe0ac87, 0xc68a62, 0x9b6744, 0x6e4a32, 0xf6d6bd];
export const HAIR = [0x2a1c12, 0x5a3a22, 0xa36b35, 0xd9b26b, 0x1a1a1a, 0x8a8a8a, 0xb5532b];
export const SHIRT = [0x2f6fb5, 0xd94848, 0x3b9c5a, 0xf2c037, 0x8d5bc2, 0xf2f2f2, 0x2b2f36, 0xff8a3d, 0x2bb3b1, 0xe46aa7];
export const PANTS = [0x2b3a55, 0x3a3a3a, 0x6b5b45, 0x1f2b3d, 0x7a7f86, 0x4b5d3a];

const limbCache = new Map();
function cached(key, fn) {
  if (!limbCache.has(key)) limbCache.set(key, fn());
  return limbCache.get(key);
}

export function buildPerson(look = {}) {
  const pick = (a) => a[Math.floor(Math.random() * a.length)];
  const skin = look.skin ?? pick(SKIN), hair = look.hair ?? pick(HAIR);
  const shirt = look.shirt ?? pick(SHIRT), pants = look.pants ?? pick(PANTS);
  const g = new THREE.Group();
  const hips = new THREE.Group(); hips.position.y = 0.92; g.add(hips);
  const torsoGeo = cached(`t${shirt}${skin}${hair}${look.longHair ? 1 : 0}${look.cap ?? ''}${look.backpack ?? ''}`, () => {
    const b = new Baker();
    b.box(shirt, 0.46, 0.6, 0.26, 0, 0.32, 0);
    b.box(skin, 0.28, 0.3, 0.27, 0, 0.9, 0);
    b.box(hair, 0.3, 0.1, 0.29, 0, 1.07, -0.01);
    b.box(hair, 0.3, 0.2, 0.08, 0, 0.96, -0.12);
    if (look.longHair) b.box(hair, 0.3, 0.34, 0.08, 0, 0.8, -0.14);
    if (look.cap) { b.box(look.cap, 0.31, 0.08, 0.3, 0, 1.08, 0); b.box(look.cap, 0.28, 0.03, 0.16, 0, 1.05, 0.2); }
    b.box(0x1c1c1c, 0.05, 0.04, 0.02, -0.07, 0.93, 0.14);
    b.box(0x1c1c1c, 0.05, 0.04, 0.02, 0.07, 0.93, 0.14);
    if (look.backpack) b.box(look.backpack, 0.36, 0.42, 0.14, 0, 0.32, -0.2);
    return b.geometry();
  });
  const torso = new THREE.Mesh(torsoGeo, personMat);
  torso.castShadow = true;
  hips.add(torso);
  const legGeo = cached('l' + pants, () => new Baker().box(pants, 0.18, 0.84, 0.2, 0, -0.42, 0).box(0x24262a, 0.19, 0.1, 0.28, 0, -0.87, 0.04).geometry());
  const armGeo = cached('a' + shirt + skin, () => new Baker().box(shirt, 0.14, 0.3, 0.16, 0, -0.12, 0).box(skin, 0.12, 0.34, 0.13, 0, -0.42, 0).geometry());
  const limbs = {};
  for (const s of [-1, 1]) {
    const leg = new THREE.Group(); leg.position.set(s * 0.12, 0, 0); hips.add(leg);
    const lm = new THREE.Mesh(legGeo, personMat); lm.castShadow = true; leg.add(lm);
    const arm = new THREE.Group(); arm.position.set(s * 0.3, 0.58, 0); hips.add(arm);
    const am = new THREE.Mesh(armGeo, personMat); am.castShadow = true; arm.add(am);
    limbs[s < 0 ? 'legL' : 'legR'] = leg;
    limbs[s < 0 ? 'armL' : 'armR'] = arm;
  }
  const sc = look.scale ?? 1;
  g.scale.setScalar(sc);
  g.userData = { hips, torso, ...limbs, phase: Math.random() * 6, height: 1.8 * sc };
  return g;
}

// Swings limbs for walking/running. speed in m/s.
export function animatePerson(p, speed, dt, airborne = false) {
  const u = p.userData;
  const k = Math.min(1, speed / 2.2);
  u.phase += dt * (3 + speed * 2.2);
  const sw = Math.sin(u.phase) * 0.75 * k;
  u.armR.rotation.z = 0;
  if (airborne) {
    u.legL.rotation.x = -0.5; u.legR.rotation.x = 0.3;
    u.armL.rotation.x = -2.6; u.armR.rotation.x = -2.6;
  } else {
    u.legL.rotation.x = sw; u.legR.rotation.x = -sw;
    u.armL.rotation.x = -sw * 0.9; u.armR.rotation.x = sw * 0.9;
  }
  u.hips.position.y = 0.92 + Math.abs(Math.cos(u.phase)) * 0.05 * k;
  u.torso.rotation.x = speed > 5 ? 0.15 : 0;
}

export function waveAnim(p, t) {
  const u = p.userData;
  u.armR.rotation.x = -2.8; u.armR.rotation.z = Math.sin(t * 8) * 0.3 - 0.2;
}

export function resetPose(p) {
  const u = p.userData;
  u.legL.rotation.x = u.legR.rotation.x = 0;
  u.armL.rotation.x = u.armR.rotation.x = 0;
  u.armR.rotation.z = 0;
  u.hips.position.y = 0.92;
}

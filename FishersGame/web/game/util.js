// Small shared helpers: seeded random numbers, spatial hashing and 2D geometry.

export function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function hash2(x, z) {
  let h = Math.imul(x | 0, 374761393) + Math.imul(z | 0, 668265263);
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smooth = (cur, target, rate, dt) => cur + (target - cur) * (1 - Math.exp(-rate * dt));

export function wrapAngle(a) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

// Grid of cells, each holding a list of integer ids.
export class Grid {
  constructor(cell) {
    this.cell = cell;
    this.map = new Map();
  }
  key(cx, cz) { return (cx + 32768) * 65536 + (cz + 32768); }
  insertBox(id, minx, minz, maxx, maxz) {
    const c = this.cell;
    const x0 = Math.floor(minx / c), x1 = Math.floor(maxx / c);
    const z0 = Math.floor(minz / c), z1 = Math.floor(maxz / c);
    for (let x = x0; x <= x1; x++) {
      for (let z = z0; z <= z1; z++) {
        const k = this.key(x, z);
        let l = this.map.get(k);
        if (!l) { l = []; this.map.set(k, l); }
        l.push(id);
      }
    }
  }
  cellAt(x, z) { return this.map.get(this.key(Math.floor(x / this.cell), Math.floor(z / this.cell))); }
  // Calls fn(id) for ids in cells overlapping the box. Ids may repeat.
  query(minx, minz, maxx, maxz, fn) {
    const c = this.cell;
    const x0 = Math.floor(minx / c), x1 = Math.floor(maxx / c);
    const z0 = Math.floor(minz / c), z1 = Math.floor(maxz / c);
    for (let x = x0; x <= x1; x++) {
      for (let z = z0; z <= z1; z++) {
        const l = this.map.get(this.key(x, z));
        if (l) for (let i = 0; i < l.length; i++) fn(l[i]);
      }
    }
  }
}

export function pointInRing(x, z, pts, start, count) {
  let inside = false;
  for (let i = 0, j = count - 1; i < count; j = i++) {
    const xi = pts[start + i * 2], zi = pts[start + i * 2 + 1];
    const xj = pts[start + j * 2], zj = pts[start + j * 2 + 1];
    if ((zi > z) !== (zj > z) && x < ((xj - xi) * (z - zi)) / (zj - zi) + xi) inside = !inside;
  }
  return inside;
}

// Closest point on segment ab to p. Returns t in [0,1].
export function segT(px, pz, ax, az, bx, bz) {
  const dx = bx - ax, dz = bz - az;
  const ll = dx * dx + dz * dz;
  if (ll < 1e-9) return 0;
  return clamp(((px - ax) * dx + (pz - az) * dz) / ll, 0, 1);
}

export function formatMoney(n) {
  return '$' + Math.round(n).toLocaleString('en-US');
}

export function formatTime(s) {
  s = Math.max(0, Math.ceil(s));
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
}

// Binary heap keyed by f for A*.
export class Heap {
  constructor() { this.ids = []; this.keys = []; }
  get size() { return this.ids.length; }
  push(id, key) {
    const ids = this.ids, keys = this.keys;
    let i = ids.length;
    ids.push(id); keys.push(key);
    while (i > 0) {
      const p = (i - 1) >> 1;
      if (keys[p] <= key) break;
      ids[i] = ids[p]; keys[i] = keys[p];
      i = p;
    }
    ids[i] = id; keys[i] = key;
  }
  pop() {
    const ids = this.ids, keys = this.keys;
    const top = ids[0];
    const lastId = ids.pop(), lastKey = keys.pop();
    if (ids.length) {
      let i = 0;
      const n = ids.length;
      for (;;) {
        let l = i * 2 + 1;
        if (l >= n) break;
        if (l + 1 < n && keys[l + 1] < keys[l]) l++;
        if (keys[l] >= lastKey) break;
        ids[i] = ids[l]; keys[i] = keys[l];
        i = l;
      }
      ids[i] = lastId; keys[i] = lastKey;
    }
    return top;
  }
}

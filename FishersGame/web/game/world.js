// Builds the 3D city from map data and answers spatial questions about it
// (collisions, nearest road, what is under a point, place names).
import * as THREE from 'three';
import { Grid, pointInRing, segT, hash2, mulberry32 } from './util.js';

export const TILE = 400;
export const VIEW = { load: 1150, unload: 1500 };

// --------------------------------------------------------------- road classes
export const RT = { MOTORWAY: 1, TRUNK: 3, PRIMARY: 5, SECONDARY: 7, TERTIARY: 9, RESIDENTIAL: 11, UNCLASSIFIED: 12, LIVING: 13, SERVICE: 14, TRACK: 15, FOOT: 16 };
export const F = { ONEWAY: 1, BRIDGE: 2, TUNNEL: 4, ROUNDABOUT: 8, SIDEWALK: 16, DRIVEWAY: 32, PARKING: 64 };

export function roadWidth(t, flags) {
  if (t === 16) return 2.0;
  if (t === 15) return 3.2;
  if (t === 14) return flags & F.DRIVEWAY ? 3.2 : flags & F.PARKING ? 5.5 : 5;
  if (t % 2 === 0 && t <= 10) return 6.5; // links
  const oneway = flags & F.ONEWAY;
  switch (t) {
    case 1: return 11.5;
    case 3: return oneway ? 10 : 15;
    case 5: return oneway ? 9 : 14;
    case 7: return oneway ? 8 : 11;
    case 9: return oneway ? 7 : 9.5;
    case 11: return 7.5;
    case 12: return 7;
    case 13: return 6;
  }
  return 6;
}
export function speedLimit(t) {
  return [0, 29, 18, 24, 16, 20, 13, 18, 12, 15.6, 11, 11.2, 12, 7, 6, 5, 2][t] || 10;
}
export const isDrivable = (t, flags) => t <= 15 && !(flags & F.DRIVEWAY);
export const isTrafficRoad = (t, flags) => t <= 13 && !(flags & (F.DRIVEWAY | F.PARKING));

const ROAD_COLOR = (t) => (t === 16 ? 0xc9c4b8 : t === 15 ? 0x9a8a68 : t === 14 ? 0x5b5e63 : t <= 10 ? 0x46494e : 0x515459);
const ROAD_Y = (t) => (t === 16 ? 0.1 : t >= 14 ? 0.115 : t >= 11 ? 0.13 : 0.145);

// --------------------------------------------------------------- area classes
const AREA = {
  1: { c: 0x3d7ea6, y: 0.06, water: true },
  2: { c: 0x557d3c, y: 0.04, trees: 85 },
  3: { c: 0x7fb85a, y: 0.035, trees: 650 },
  4: { c: 0x8cc860, y: 0.035, trees: 1400 },
  5: { c: 0x72b24f, y: 0.05 },
  6: { c: 0xa99a68, y: 0.02, field: true },
  7: { c: 0x60636a, y: 0.08, paved: true },
  8: { c: 0x86a764, y: 0.025 },
  9: { c: 0x9c9c8e, y: 0.025 },
  10: { c: 0x7aa85a, y: 0.03, trees: 500 },
  11: { c: 0x84b25e, y: 0.028, trees: 900 },
  12: { c: 0xb98f5c, y: 0.055 },
  13: { c: 0x63804c, y: 0.04, trees: 260 },
  14: { c: 0xe0d09c, y: 0.04 },
  15: { c: 0x52c6ea, y: 0.085, water: true },
  16: { c: 0x9b8462, y: 0.03 },
  17: { c: 0x9d9877, y: 0.025 },
  18: { c: 0xb4563f, y: 0.055 },
  19: { c: 0x8dbb5d, y: 0.025 },
};

const HOUSE_WALLS = [0xe9e2d0, 0xd8cdb4, 0xc9c2b4, 0xb7b9b4, 0x9ea7ad, 0xa7b3a0, 0xe2d6bf, 0xf1eee6, 0x8e9aa3, 0xc7b39a, 0xa66a4f, 0x9b5a43, 0xd5c7a4];
const ROOFS = [0x4a4b4f, 0x3d3a38, 0x5a4f46, 0x6a6b6e, 0x33373d, 0x5e5249, 0x46413c];
const BIG_WALLS = [0xd6cdb8, 0xbfb6a3, 0xa9a7a1, 0x9c6b54, 0xc9c6bf, 0x8f8b85, 0xd8d2c4, 0xb38b6d];
const TREE_COLORS = [0x4f7f33, 0x5f8f3a, 0x6b9a3f, 0x3f6e2f, 0xc9a12a, 0xd98a2b, 0xb8452a, 0x8f6b2a, 0x7a8f35, 0xe0b440, 0x5a8a3c];

export class World {
  constructor(scene, map, tex) {
    this.scene = scene;
    this.map = map;
    this.meta = map.meta;
    this.R = map.roads;
    this.B = map.buildings;
    this.tex = tex;
    this.tiles = new Map();
    this.tileQueue = [];
    this.bounds = this.meta.bounds; // [minx, minz, maxx, maxz]
    this.materials();
    this.index();
  }

  materials() {
    const t = this.tex;
    this.mats = {
      ground: new THREE.MeshLambertMaterial({ color: 0x7fae55, map: t.grass }),
      area: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.grass }),
      water: new THREE.MeshPhongMaterial({ color: 0x3f86b0, shininess: 90, specular: 0x88aacc }),
      road: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.asphalt }),
      mark: new THREE.MeshLambertMaterial({ vertexColors: true }),
      houseWall: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.facade, emissiveMap: t.facadeLit, emissive: 0xffffff, emissiveIntensity: 0 }),
      bigWall: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.office, emissiveMap: t.officeLit, emissive: 0xffffff, emissiveIntensity: 0 }),
      plainWall: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.panel }),
      roof: new THREE.MeshLambertMaterial({ vertexColors: true, map: t.shingles }),
      flatRoof: new THREE.MeshLambertMaterial({ vertexColors: true }),
      trunk: new THREE.MeshLambertMaterial({ color: 0x5b4330 }),
      leaves: new THREE.MeshLambertMaterial({ color: 0xffffff, flatShading: true }),
      pine: new THREE.MeshLambertMaterial({ color: 0x2f5a35, flatShading: true }),
    };
    this.treeGeo = {
      trunk: new THREE.CylinderGeometry(0.16, 0.26, 1, 6).translate(0, 0.5, 0),
      leaf: new THREE.IcosahedronGeometry(1, 1).translate(0, 0, 0),
      pine: new THREE.ConeGeometry(1, 1, 7).translate(0, 0.5, 0),
    };
  }

  // ------------------------------------------------------------ spatial indexes
  index() {
    const R = this.R, B = this.B;
    // node -> edges adjacency (CSR)
    const deg = new Uint32Array(R.nNodes + 1);
    for (let e = 0; e < R.nEdges; e++) { deg[R.a[e]]++; deg[R.b[e]]++; }
    const adjStart = new Uint32Array(R.nNodes + 1);
    for (let i = 0; i < R.nNodes; i++) adjStart[i + 1] = adjStart[i] + deg[i];
    const fill = adjStart.slice();
    const adj = new Uint32Array(adjStart[R.nNodes]);
    for (let e = 0; e < R.nEdges; e++) { adj[fill[R.a[e]]++] = e; adj[fill[R.b[e]]++] = e; }
    this.adjStart = adjStart; this.adj = adj;

    this.roadGrid = new Grid(64);
    for (let e = 0; e < R.nEdges; e++) {
      const s = R.start[e], n = R.count[e];
      for (let k = 0; k < n - 1; k++) {
        const i = (s + k) * 2;
        const ax = R.pts[i], az = R.pts[i + 1], bx = R.pts[i + 2], bz = R.pts[i + 3];
        this.roadGrid.insertBox(e, Math.min(ax, bx), Math.min(az, bz), Math.max(ax, bx), Math.max(az, bz));
      }
    }
    // dedupe repeated ids per cell
    for (const [k, l] of this.roadGrid.map) this.roadGrid.map.set(k, [...new Set(l)]);
    this.edgeStamp = new Uint32Array(R.nEdges);
    this.stamp = 1;

    this.bGrid = new Grid(32);
    this.bTile = new Map();
    for (let i = 0; i < B.n; i++) {
      const o = i * 4;
      this.bGrid.insertBox(i, B.bbox[o], B.bbox[o + 1], B.bbox[o + 2], B.bbox[o + 3]);
      const k = this.tileKey(Math.floor(B.center[i * 2] / TILE), Math.floor(B.center[i * 2 + 1] / TILE));
      let l = this.bTile.get(k);
      if (!l) { l = []; this.bTile.set(k, l); }
      l.push(i);
    }
    this.bStamp = new Uint32Array(B.n);
    this.bHeight = new Float32Array(B.n);
    for (let i = 0; i < B.n; i++) this.bHeight[i] = this.buildingSpec(i).wall;

    this.aGrid = new Grid(200);
    this.map.areas.forEach((a, i) => this.aGrid.insertBox(i, ...a.bbox));

    const places = this.meta.places || [];
    this.cities = places.filter((p) => ['city', 'town', 'village'].includes(p[1]));
    this.hoods = places.filter((p) => ['suburb', 'neighbourhood', 'quarter', 'hamlet', 'locality'].includes(p[1]));
  }

  tileKey(tx, tz) { return (tx + 1000) * 4096 + (tz + 1000); }

  edgePoint(e, k) {
    const i = (this.R.start[e] + k) * 2;
    return [this.R.pts[i], this.R.pts[i + 1]];
  }

  // ------------------------------------------------------------ static meshes
  async buildStatic(progress) {
    const scene = this.scene;
    const [minx, minz, maxx, maxz] = this.bounds;
    const W = maxx - minx + 3000, H = maxz - minz + 3000;
    const g = new THREE.PlaneGeometry(W, H);
    g.rotateX(-Math.PI / 2);
    g.translate((minx + maxx) / 2, 0, (minz + maxz) / 2);
    const uv = g.attributes.uv;
    for (let i = 0; i < uv.count; i++) uv.setXY(i, uv.getX(i) * W / 24, uv.getY(i) * H / 24);
    const ground = new THREE.Mesh(g, this.mats.ground);
    ground.receiveShadow = true;
    scene.add(ground);
    await this.buildAreas(progress);
    await this.buildLines();
    await this.buildRoads(progress);
  }

  async buildAreas(progress) {
    const CH = 1500;
    const chunks = new Map();
    const water = new Map();
    const areas = this.map.areas;
    const col = new THREE.Color();
    let n = 0;
    for (const a of areas) {
      const spec = AREA[a.kind];
      if (!spec) continue;
      const cx = Math.floor((a.bbox[0] + a.bbox[2]) / 2 / CH), cz = Math.floor((a.bbox[1] + a.bbox[3]) / 2 / CH);
      const key = cx * 1000 + cz;
      const target = spec.water ? water : chunks;
      let b = target.get(key);
      if (!b) { b = { pos: [], col: [], uv: [], idx: [] }; target.set(key, b); }
      const contour = [], holes = [];
      const toV = (ring) => { const v = []; for (let i = 0; i < ring.length; i += 2) v.push(new THREE.Vector2(ring[i], ring[i + 1])); return v; };
      a.rings.forEach((r, i) => (i === 0 ? contour.push(...toV(r)) : holes.push(toV(r))));
      if (contour.length < 3) continue;
      let tris;
      try { tris = THREE.ShapeUtils.triangulateShape(contour, holes); } catch { continue; }
      const verts = contour.concat(...holes);
      const base = b.pos.length / 3;
      let c = spec.c;
      if (spec.field) {
        const h = hash2(Math.round(a.bbox[0]), Math.round(a.bbox[1]));
        c = h < 0.45 ? 0xa48e5e : h < 0.75 ? 0xb9a774 : 0x93a35a;
      }
      col.setHex(c);
      const y = spec.y + (a.kind === 1 ? 0 : (n % 7) * 0.001);
      for (const v of verts) {
        b.pos.push(v.x, y, v.y);
        b.col.push(col.r, col.g, col.b);
        b.uv.push(v.x / 24, v.y / 24);
      }
      for (const t of tris) b.idx.push(base + t[0], base + t[2], base + t[1]);
      n++;
      if (n % 400 === 0) { progress?.('Laying out parks, fields and lakes', n / areas.length); await frame(); }
    }
    const make = (b, mat) => {
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.Float32BufferAttribute(b.pos, 3));
      geo.setAttribute('color', new THREE.Float32BufferAttribute(b.col, 3));
      geo.setAttribute('uv', new THREE.Float32BufferAttribute(b.uv, 2));
      geo.setIndex(b.idx);
      geo.computeVertexNormals();
      fixUp(geo);
      const m = new THREE.Mesh(geo, mat);
      m.receiveShadow = true;
      this.scene.add(m);
    };
    for (const b of chunks.values()) make(b, this.mats.area);
    for (const b of water.values()) make(b, this.mats.water);
  }

  async buildLines() {
    const water = { pos: [], col: [], uv: [], idx: [] };
    const rail = { pos: [], col: [], uv: [], idx: [] };
    for (const l of this.map.lines) {
      if (l.kind === 6) continue;
      const w = l.kind === 1 ? 18 : l.kind === 3 ? 8 : l.kind === 5 ? 3.2 : l.kind === 2 ? 3.5 : 2;
      const target = l.kind === 5 ? rail : water;
      ribbon(target, l.pts, 0, l.pts.length / 2, w / 2, l.kind === 5 ? 0.09 : 0.055, l.kind === 5 ? 0x6f6458 : 0x3d7ea6);
    }
    for (const [b, mat] of [[water, this.mats.water], [rail, this.mats.road]]) {
      if (!b.pos.length) continue;
      const m = new THREE.Mesh(toGeo(b), mat);
      m.receiveShadow = true;
      this.scene.add(m);
    }
  }

  async buildRoads(progress) {
    const R = this.R;
    const CH = 1000;
    const chunks = new Map();
    const getChunk = (x, z) => {
      const key = Math.floor(x / CH) * 1000 + Math.floor(z / CH);
      let b = chunks.get(key);
      if (!b) { b = { road: { pos: [], col: [], uv: [], idx: [] }, mark: { pos: [], col: [], uv: [], idx: [] } }; chunks.set(key, b); }
      return b;
    };
    for (let e = 0; e < R.nEdges; e++) {
      const t = R.type[e], fl = R.flags[e];
      if (fl & F.TUNNEL) continue;
      const [x0, z0] = this.edgePoint(e, 0);
      const b = getChunk(x0, z0);
      const hw = roadWidth(t, fl) / 2;
      ribbon(b.road, R.pts, R.start[e], R.count[e], hw, ROAD_Y(t), ROAD_COLOR(t));
      // markings on bigger roads
      if (t <= 9 && t % 2 === 1) {
        if (fl & F.ONEWAY) {
          if (hw > 4.5) dashes(b.mark, R.pts, R.start[e], R.count[e], 0, 0.07, 0.17, 0xf2f2ee, 3, 9);
        } else {
          offsetLine(b.mark, R.pts, R.start[e], R.count[e], 0.13, 0.065, 0.17, 0xe8c547);
          offsetLine(b.mark, R.pts, R.start[e], R.count[e], -0.13, 0.065, 0.17, 0xe8c547);
          if (hw > 6) {
            dashes(b.mark, R.pts, R.start[e], R.count[e], hw / 2, 0.07, 0.17, 0xf2f2ee, 3, 9);
            dashes(b.mark, R.pts, R.start[e], R.count[e], -hw / 2, 0.07, 0.17, 0xf2f2ee, 3, 9);
          }
        }
      }
      if (e % 3000 === 0) { progress?.('Paving the roads', e / R.nEdges); await frame(); }
    }
    // round joints at intersections and dead ends
    for (let nIdx = 0; nIdx < R.nNodes; nIdx++) {
      let maxHw = 0, maxT = 99, cnt = 0, types = 0;
      for (let k = this.adjStart[nIdx]; k < this.adjStart[nIdx + 1]; k++) {
        const e = this.adj[k];
        if (R.flags[e] & F.TUNNEL) continue;
        const t = R.type[e];
        const hw = roadWidth(t, R.flags[e]) / 2;
        cnt++; types |= 1 << (t % 31);
        if (hw > maxHw) { maxHw = hw; }
        if (t < maxT) maxT = t;
      }
      if (!cnt) continue;
      if (cnt === 2 && (types & (types - 1)) === 0) continue;
      const x = R.nodes[nIdx * 2], z = R.nodes[nIdx * 2 + 1];
      disc(getChunk(x, z).road, x, z, maxHw, ROAD_Y(maxT) + 0.004, ROAD_COLOR(maxT));
    }
    for (const b of chunks.values()) {
      const m = new THREE.Mesh(toGeo(b.road), this.mats.road);
      m.receiveShadow = true;
      this.scene.add(m);
      if (b.mark.pos.length) this.scene.add(new THREE.Mesh(toGeo(b.mark), this.mats.mark));
    }
  }

  // ------------------------------------------------------------ buildings
  buildingSpec(i) {
    const B = this.B;
    const kind = B.kind[i], area = B.area[i];
    const r = hash2(i, 7);
    let wall, roof = 'flat', style = 'big';
    let tagged = B.h[i];
    const houseLike = kind === 1 || (kind === 0 && area >= 45 && area < 480) || kind === 9;
    if (houseLike) {
      style = 'house'; roof = 'pitched';
      wall = kind === 9 ? 5 : r < 0.42 ? 3.1 : 5.6;
      if (tagged) wall = Math.max(2.8, tagged * 0.72);
    } else if (kind === 7 || (kind === 0 && area < 45)) {
      style = 'plain'; wall = 2.7; roof = area < 80 ? 'pitched' : 'flat';
    } else {
      switch (kind) {
        case 2: wall = 10.5; break;
        case 3: wall = area > 5000 ? 9.5 : area > 1500 ? 7.5 : 5.8; break;
        case 4: wall = 9; style = 'plain'; break;
        case 5: wall = 8.5; break;
        case 6: wall = 9.5; break;
        case 8: wall = 18; break;
        case 10: wall = 13; break;
        default: wall = area > 5000 ? 9 : area > 1500 ? 7.5 : 6.2;
      }
      if (tagged) wall = tagged;
    }
    return { wall, roof, style };
  }

  updateTiles(px, pz) {
    const t0 = Math.floor((px - VIEW.load) / TILE), t1 = Math.floor((px + VIEW.load) / TILE);
    const s0 = Math.floor((pz - VIEW.load) / TILE), s1 = Math.floor((pz + VIEW.load) / TILE);
    const want = [];
    for (let tx = t0; tx <= t1; tx++) {
      for (let tz = s0; tz <= s1; tz++) {
        const cx = (tx + 0.5) * TILE, cz = (tz + 0.5) * TILE;
        const d = Math.hypot(cx - px, cz - pz);
        if (d > VIEW.load + TILE * 0.7) continue;
        const k = this.tileKey(tx, tz);
        if (!this.tiles.has(k)) want.push({ k, tx, tz, d });
      }
    }
    want.sort((a, b) => a.d - b.d);
    this.tileQueue = want;
    for (const [k, tile] of this.tiles) {
      const d = Math.hypot((tile.tx + 0.5) * TILE - px, (tile.tz + 0.5) * TILE - pz);
      if (d > VIEW.unload + TILE) this.unloadTile(k, tile);
    }
  }

  // Builds queued tiles for up to `budget` ms. A tile is built a few dozen
  // buildings at a time so that no single frame stalls.
  pump(budget = 6) {
    const start = performance.now();
    while (performance.now() - start < budget) {
      if (!this.building) {
        const w = this.tileQueue.shift();
        if (!w) return;
        if (this.tiles.has(w.k)) continue;
        this.building = this.buildTile(w.k, w.tx, w.tz);
      }
      if (this.building.next().done) this.building = null;
    }
  }

  get pending() { return this.tileQueue.length + (this.building ? 1 : 0); }

  loadTile(k, tx, tz) {
    const gen = this.buildTile(k, tx, tz);
    while (!gen.next().done);
  }

  unloadTile(k, tile) {
    this.scene.remove(tile.group);
    tile.group.traverse((o) => { if (o.geometry && !o.userData.shared) o.geometry.dispose(); });
    this.tiles.delete(k);
    this.onTileUnload?.(tile);
  }

  *buildTile(k, tx, tz) {
    const ids = this.bTile.get(k) || [];
    const B = this.B;
    const group = new THREE.Group();
    const bufs = {
      house: newBuf(), big: newBuf(), plain: newBuf(), roof: newBuf(), flat: newBuf(),
    };
    const col = new THREE.Color();
    const houses = [];
    let count = 0;
    for (const i of ids) {
      if (++count % 40 === 0) yield;
      const spec = this.buildingSpec(i);
      const s = B.start[i], n = B.count[i];
      const pts = [];
      for (let j = 0; j < n; j++) pts.push(B.pts[(s + j) * 2], B.pts[(s + j) * 2 + 1]);
      const r = hash2(i, 3);
      let wallColor;
      if (spec.style === 'house') wallColor = HOUSE_WALLS[Math.floor(r * HOUSE_WALLS.length)];
      else if (spec.style === 'plain') wallColor = [0xc8c6c0, 0xb0aea6, 0x9aa0a6, 0xd4cfc4][Math.floor(r * 4)];
      else wallColor = BIG_WALLS[Math.floor(r * BIG_WALLS.length)];
      col.setHex(wallColor);
      const storey = spec.style === 'house' ? (spec.wall > 4 ? spec.wall / 2 : spec.wall) : 3.6;
      walls(bufs[spec.style], pts, 0, spec.wall, col, spec.style === 'house' ? 4.2 : 4, storey);
      if (spec.roof === 'pitched') {
        const ok = hipRoof(bufs.roof, bufs[spec.style], pts, spec.wall, col.clone().setHex(ROOFS[Math.floor(hash2(i, 5) * ROOFS.length)]), col, hash2(i, 9) < 0.5, B.area[i]);
        if (!ok) flatRoof(bufs.flat, pts, spec.wall, col.clone().setHex(0x55585c));
        if (spec.style === 'house' && B.area[i] > 60) houses.push(i);
      } else {
        const rc = B.area[i] > 1500 ? (hash2(i, 11) < 0.6 ? 0xc4c7c9 : 0x8c8f92) : 0x6e7174;
        flatRoof(bufs.flat, pts, spec.wall, col.clone().setHex(rc));
        if (B.area[i] > 900 && spec.wall > 5) parapet(bufs.plain, pts, spec.wall, col.clone().setHex(wallColor));
      }
    }
    const add = (b, mat) => {
      if (!b.pos.length) return;
      const m = new THREE.Mesh(toGeo(b, true), mat);
      m.castShadow = true; m.receiveShadow = true;
      group.add(m);
    };
    add(bufs.house, this.mats.houseWall);
    add(bufs.big, this.mats.bigWall);
    add(bufs.plain, this.mats.plainWall);
    add(bufs.roof, this.mats.roof);
    add(bufs.flat, this.mats.flatRoof);
    yield;
    const trees = this.makeTrees(tx, tz, houses, group);
    this.scene.add(group);
    const tile = { tx, tz, group, trees };
    this.tiles.set(k, tile);
    this.onTileLoad?.(tile);
  }

  makeTrees(tx, tz, houses, group) {
    const rnd = mulberry32(tx * 9781 + tz * 6271 + 13);
    const x0 = tx * TILE, z0 = tz * TILE, x1 = x0 + TILE, z1 = z0 + TILE;
    const spots = [];
    const tryPlace = (x, z, kind) => {
      if (this.buildingAt(x, z, 1.6) >= 0) return;
      const nr = this.nearestRoad(x, z, null, 12);
      if (nr && nr.dist < roadWidth(this.R.type[nr.edge], this.R.flags[nr.edge]) / 2 + 2.2) return;
      spots.push(x, z, kind);
    };
    const seen = new Set();
    this.aGrid.query(x0, z0, x1, z1, (ai) => {
      if (seen.has(ai)) return;
      seen.add(ai);
      const a = this.map.areas[ai];
      const spec = AREA[a.kind];
      if (!spec || !spec.trees) return;
      const bx0 = Math.max(x0, a.bbox[0]), bz0 = Math.max(z0, a.bbox[1]);
      const bx1 = Math.min(x1, a.bbox[2]), bz1 = Math.min(z1, a.bbox[3]);
      if (bx1 <= bx0 || bz1 <= bz0) return;
      const count = Math.min(1100, ((bx1 - bx0) * (bz1 - bz0)) / spec.trees);
      const outer = a.rings[0];
      for (let i = 0; i < count; i++) {
        const x = bx0 + rnd() * (bx1 - bx0), z = bz0 + rnd() * (bz1 - bz0);
        if (!pointInRing(x, z, outer, 0, outer.length / 2)) continue;
        let hole = false;
        for (let h = 1; h < a.rings.length && !hole; h++) hole = pointInRing(x, z, a.rings[h], 0, a.rings[h].length / 2);
        if (hole) continue;
        if (a.kind !== 2 && this.areaKindAt(x, z, 1)) continue;
        tryPlace(x, z, a.kind === 2 && rnd() < 0.3 ? 1 : 0);
      }
    });
    // yard trees
    for (const i of houses) {
      if (rnd() > 0.55) continue;
      const cx = this.B.center[i * 2], cz = this.B.center[i * 2 + 1];
      const ang = rnd() * Math.PI * 2, d = Math.sqrt(this.B.area[i]) * 0.6 + 4 + rnd() * 6;
      tryPlace(cx + Math.cos(ang) * d, cz + Math.sin(ang) * d, rnd() < 0.2 ? 1 : 0);
    }
    const n = spots.length / 3;
    const trees = { x: new Float32Array(n), z: new Float32Array(n), grid: new Grid(16) };
    if (!n) return trees;
    const trunk = new THREE.InstancedMesh(this.treeGeo.trunk, this.mats.trunk, n);
    const nLeaf = spots.filter((v, i) => i % 3 === 2 && v === 0).length;
    const leaf = new THREE.InstancedMesh(this.treeGeo.leaf, this.mats.leaves, Math.max(1, nLeaf));
    const pine = new THREE.InstancedMesh(this.treeGeo.pine, this.mats.pine, Math.max(1, n - nLeaf));
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
    const c = new THREE.Color();
    let li = 0, pi = 0;
    for (let i = 0; i < n; i++) {
      const x = spots[i * 3], z = spots[i * 3 + 1], kind = spots[i * 3 + 2];
      trees.x[i] = x; trees.z[i] = z;
      trees.grid.insertBox(i, x - 0.5, z - 0.5, x + 0.5, z + 0.5);
      const size = 0.75 + rnd() * 0.7;
      q.setFromAxisAngle(UP, rnd() * 6.28);
      const th = kind ? 2 * size : 3.2 * size;
      m.compose(p.set(x, 0, z), q, s.set(size, th, size));
      trunk.setMatrixAt(i, m);
      if (kind) {
        m.compose(p.set(x, 1.2 * size, z), q, s.set(2.2 * size, 7 * size, 2.2 * size));
        pine.setMatrixAt(pi++, m);
      } else {
        const r = 2.6 * size;
        m.compose(p.set(x, th + r * 0.6, z), q, s.set(r, r * 0.85, r));
        leaf.setMatrixAt(li, m);
        leaf.setColorAt(li++, c.setHex(TREE_COLORS[Math.floor(rnd() * TREE_COLORS.length)]));
      }
    }
    leaf.count = li; pine.count = pi;
    for (const im of [trunk, leaf, pine]) {
      im.castShadow = true;
      im.computeBoundingSphere();
      group.add(im);
    }
    // instanced meshes share the tree geometry: don't dispose it on unload
    for (const im of [trunk, leaf, pine]) im.userData.shared = true;
    return trees;
  }

  // ------------------------------------------------------------ queries
  // Index of a building whose footprint contains (x,z) (grown by pad), or -1.
  buildingAt(x, z, pad = 0) {
    const B = this.B;
    const l = this.bGrid.cellAt(x, z);
    if (!l) return -1;
    for (const i of l) {
      const o = i * 4;
      if (x < B.bbox[o] - pad || x > B.bbox[o + 2] + pad || z < B.bbox[o + 1] - pad || z > B.bbox[o + 3] + pad) continue;
      if (pointInRing(x, z, B.pts, B.start[i] * 2, B.count[i])) return i;
      if (pad > 0 && distToRing(x, z, B.pts, B.start[i] * 2, B.count[i]) < pad) return i;
    }
    return -1;
  }

  heightAt(x, z) {
    const i = this.buildingAt(x, z);
    return i < 0 ? 0 : this.bHeight[i];
  }

  // Returns the kind of the topmost area under the point (0 if none).
  areaKindAt(x, z, onlyWater = 0) {
    let best = 0, bestY = -1;
    const l = this.aGrid.cellAt(x, z);
    if (!l) return 0;
    for (const ai of l) {
      const a = this.map.areas[ai];
      if (x < a.bbox[0] || x > a.bbox[2] || z < a.bbox[1] || z > a.bbox[3]) continue;
      const spec = AREA[a.kind];
      if (!spec || (onlyWater && !spec.water)) continue;
      const r = a.rings[0];
      if (!pointInRing(x, z, r, 0, r.length / 2)) continue;
      let hole = false;
      for (let h = 1; h < a.rings.length && !hole; h++) hole = pointInRing(x, z, a.rings[h], 0, a.rings[h].length / 2);
      if (hole) continue;
      if (spec.y > bestY) { bestY = spec.y; best = a.kind; }
    }
    return best;
  }

  inWater(x, z) {
    const k = this.areaKindAt(x, z, 1);
    if (k === 1 || k === 15) {
      // roads and bridges over water are dry
      const nr = this.nearestRoad(x, z, (t, f) => t !== 16, 12);
      if (nr && nr.dist < roadWidth(this.R.type[nr.edge], this.R.flags[nr.edge]) / 2 + 0.5) return false;
      return true;
    }
    return false;
  }

  // Nearest point on a road. filter(type, flags) chooses which roads count.
  nearestRoad(x, z, filter, maxDist = 80) {
    const R = this.R;
    const st = ++this.stamp;
    let best = null, bd = maxDist;
    this.roadGrid.query(x - maxDist, z - maxDist, x + maxDist, z + maxDist, (e) => {
      if (this.edgeStamp[e] === st) return;
      this.edgeStamp[e] = st;
      if (filter && !filter(R.type[e], R.flags[e])) return;
      const s = R.start[e], n = R.count[e];
      for (let k = 0; k < n - 1; k++) {
        const i = (s + k) * 2;
        const ax = R.pts[i], az = R.pts[i + 1], bx = R.pts[i + 2], bz = R.pts[i + 3];
        const t = segT(x, z, ax, az, bx, bz);
        const px = ax + (bx - ax) * t, pz = az + (bz - az) * t;
        const d = Math.hypot(px - x, pz - z);
        if (d < bd) {
          bd = d;
          const L = Math.hypot(bx - ax, bz - az) || 1;
          best = { edge: e, seg: k, t, x: px, z: pz, dist: d, dx: (bx - ax) / L, dz: (bz - az) / L };
        }
      }
    });
    return best;
  }

  // Pushes a circle out of buildings and trees. Returns {x,z,nx,nz,hit}.
  collide(x, z, r, out) {
    const B = this.B;
    out.hit = false; out.nx = 0; out.nz = 0;
    for (let iter = 0; iter < 2; iter++) {
      const st = ++this.stamp;
      let moved = false;
      this.bGrid.query(x - r, z - r, x + r, z + r, (i) => {
        if (this.bStamp[i] === st) return;
        this.bStamp[i] = st;
        const o = i * 4;
        if (x + r < B.bbox[o] || x - r > B.bbox[o + 2] || z + r < B.bbox[o + 1] || z - r > B.bbox[o + 3]) return;
        const s = B.start[i] * 2, n = B.count[i];
        const inside = pointInRing(x, z, B.pts, s, n);
        let bd = 1e9, bx = 0, bz = 0;
        for (let k = 0; k < n; k++) {
          const k2 = (k + 1) % n;
          const ax = B.pts[s + k * 2], az = B.pts[s + k * 2 + 1], cx = B.pts[s + k2 * 2], cz = B.pts[s + k2 * 2 + 1];
          const t = segT(x, z, ax, az, cx, cz);
          const px = ax + (cx - ax) * t, pz = az + (cz - az) * t;
          const d = Math.hypot(px - x, pz - z);
          if (d < bd) { bd = d; bx = px; bz = pz; }
        }
        if (!inside && bd >= r) return;
        let nx = x - bx, nz = z - bz;
        const L = Math.hypot(nx, nz) || 1;
        nx /= L; nz /= L;
        if (inside) { nx = -nx; nz = -nz; }
        const push = inside ? bd + r : r - bd;
        x += nx * push; z += nz * push;
        out.nx += nx; out.nz += nz; out.hit = true; moved = true;
      });
      // trees
      const tk = this.tiles.get(this.tileKey(Math.floor(x / TILE), Math.floor(z / TILE)));
      if (tk && tk.trees.x.length) {
        tk.trees.grid.query(x - r, z - r, x + r, z + r, (i) => {
          const dx = x - tk.trees.x[i], dz = z - tk.trees.z[i];
          const d = Math.hypot(dx, dz), rr = r + 0.35;
          if (d < rr && d > 1e-4) {
            x += (dx / d) * (rr - d); z += (dz / d) * (rr - d);
            out.nx += dx / d; out.nz += dz / d; out.hit = true; moved = true;
          }
        });
      }
      if (!moved) break;
    }
    const [minx, minz, maxx, maxz] = this.bounds;
    if (x < minx) { x = minx; out.hit = true; out.nx += 1; }
    if (x > maxx) { x = maxx; out.hit = true; out.nx -= 1; }
    if (z < minz) { z = minz; out.hit = true; out.nz += 1; }
    if (z > maxz) { z = maxz; out.hit = true; out.nz -= 1; }
    const L = Math.hypot(out.nx, out.nz);
    if (L > 0) { out.nx /= L; out.nz /= L; }
    out.x = x; out.z = z;
    return out;
  }

  placeName(x, z) {
    let city = 'Hamilton County', cd = 1e12;
    for (const p of this.cities) {
      const d = (p[2] - x) ** 2 + (p[3] - z) ** 2;
      if (d < cd) { cd = d; city = p[0]; }
    }
    let hood = '', hd = 900 * 900;
    for (const p of this.hoods) {
      const d = (p[2] - x) ** 2 + (p[3] - z) ** 2;
      if (d < hd) { hd = d; hood = p[0]; }
    }
    return { city, hood };
  }

  roadName(e) { return this.meta.names[this.R.name[e]] || ''; }
}

// ------------------------------------------------------------------ helpers
const UP = new THREE.Vector3(0, 1, 0);
const frame = () => new Promise((r) => setTimeout(r, 0));
const newBuf = () => ({ pos: [], col: [], uv: [], idx: [], nrm: [] });

function fixUp(geo) {
  const n = geo.attributes.normal;
  for (let i = 0; i < n.count; i++) n.setXYZ(i, 0, 1, 0);
  faceUp(geo);
}

// Flips any triangle of a flat, indexed mesh so that it faces up (+y).
function faceUp(geo) {
  const idx = geo.index;
  if (!idx) return;
  const p = geo.attributes.position.array, a = idx.array;
  for (let i = 0; i < a.length; i += 3) {
    const i0 = a[i] * 3, i1 = a[i + 1] * 3, i2 = a[i + 2] * 3;
    const ux = p[i1] - p[i0], uz = p[i1 + 2] - p[i0 + 2];
    const vx = p[i2] - p[i0], vz = p[i2 + 2] - p[i0 + 2];
    if (uz * vx - ux * vz < 0) { const t = a[i + 1]; a[i + 1] = a[i + 2]; a[i + 2] = t; }
  }
}

function toGeo(b, withNormals = false) {
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.Float32BufferAttribute(b.pos, 3));
  geo.setAttribute('color', new THREE.Float32BufferAttribute(b.col, 3));
  geo.setAttribute('uv', new THREE.Float32BufferAttribute(b.uv, 2));
  if (b.idx.length) geo.setIndex(b.idx);
  if (withNormals && b.nrm && b.nrm.length) geo.setAttribute('normal', new THREE.Float32BufferAttribute(b.nrm, 3));
  else {
    const n = new Float32Array(b.pos.length);
    for (let i = 1; i < n.length; i += 3) n[i] = 1;
    geo.setAttribute('normal', new THREE.BufferAttribute(n, 3));
    faceUp(geo);
  }
  geo.computeBoundingSphere();
  return geo;
}

function distToRing(x, z, pts, s, n) {
  let bd = 1e9;
  for (let k = 0; k < n; k++) {
    const k2 = (k + 1) % n;
    const ax = pts[s + k * 2], az = pts[s + k * 2 + 1], cx = pts[s + k2 * 2], cz = pts[s + k2 * 2 + 1];
    const t = segT(x, z, ax, az, cx, cz);
    const d = Math.hypot(ax + (cx - ax) * t - x, az + (cz - az) * t - z);
    if (d < bd) bd = d;
  }
  return bd;
}

// Flat strip along a polyline, facing up.
function ribbon(b, pts, start, count, hw, y, color) {
  if (count < 2) return;
  const c = new THREE.Color(color);
  const base = b.pos.length / 3;
  let len = 0;
  for (let k = 0; k < count; k++) {
    const i = (start + k) * 2;
    const x = pts[i], z = pts[i + 1];
    let dx, dz;
    if (k === 0) { dx = pts[i + 2] - x; dz = pts[i + 3] - z; } else if (k === count - 1) { dx = x - pts[i - 2]; dz = z - pts[i - 1]; } else {
      let ax = x - pts[i - 2], az = z - pts[i - 1], bx = pts[i + 2] - x, bz = pts[i + 3] - z;
      const la = Math.hypot(ax, az) || 1, lb = Math.hypot(bx, bz) || 1;
      ax /= la; az /= la; bx /= lb; bz /= lb;
      dx = ax + bx; dz = az + bz;
      if (Math.hypot(dx, dz) < 1e-3) { dx = bx; dz = bz; }
    }
    const L = Math.hypot(dx, dz) || 1;
    dx /= L; dz /= L;
    let scale = 1;
    if (k > 0 && k < count - 1) {
      const sx = x - pts[i - 2], sz = z - pts[i - 1];
      const sl = Math.hypot(sx, sz) || 1;
      const cos = (dx * sx + dz * sz) / sl;
      scale = 1 / Math.max(0.5, cos);
    }
    if (k > 0) len += Math.hypot(x - pts[i - 2], z - pts[i - 1]);
    const nx = -dz * hw * scale, nz = dx * hw * scale;
    b.pos.push(x + nx, y, z + nz, x - nx, y, z - nz);
    b.col.push(c.r, c.g, c.b, c.r, c.g, c.b);
    b.uv.push((x + nx) / 8, (z + nz) / 8, (x - nx) / 8, (z - nz) / 8);
    if (k > 0) {
      const v = base + k * 2;
      b.idx.push(v - 2, v - 1, v, v - 1, v + 1, v);
    }
  }
}

function offsetLine(b, pts, start, count, off, hw, y, color) {
  const tmp = new Float32Array(count * 2);
  for (let k = 0; k < count; k++) {
    const i = (start + k) * 2;
    const k0 = Math.max(0, k - 1), k1 = Math.min(count - 1, k + 1);
    const dx = pts[(start + k1) * 2] - pts[(start + k0) * 2], dz = pts[(start + k1) * 2 + 1] - pts[(start + k0) * 2 + 1];
    const L = Math.hypot(dx, dz) || 1;
    tmp[k * 2] = pts[i] - (dz / L) * off;
    tmp[k * 2 + 1] = pts[i + 1] + (dx / L) * off;
  }
  ribbon(b, tmp, 0, count, hw, y, color);
}

function dashes(b, pts, start, count, off, hw, y, color, dash, period) {
  let carry = 0;
  for (let k = 0; k < count - 1; k++) {
    const i = (start + k) * 2;
    const ax = pts[i], az = pts[i + 1], bx = pts[i + 2], bz = pts[i + 3];
    const L = Math.hypot(bx - ax, bz - az);
    if (L < 0.01) continue;
    const dx = (bx - ax) / L, dz = (bz - az) / L;
    const ox = -dz * off, oz = dx * off;
    let s = carry;
    while (s < L) {
      const e = Math.min(L, s + dash);
      const seg = new Float32Array([ax + dx * s + ox, az + dz * s + oz, ax + dx * e + ox, az + dz * e + oz]);
      ribbon(b, seg, 0, 2, hw, y, color);
      s += period;
    }
    carry = s - L;
  }
}

function disc(b, x, z, r, y, color) {
  const c = new THREE.Color(color);
  const base = b.pos.length / 3;
  const N = 14;
  b.pos.push(x, y, z); b.col.push(c.r, c.g, c.b); b.uv.push(x / 8, z / 8);
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2;
    const px = x + Math.cos(a) * r, pz = z + Math.sin(a) * r;
    b.pos.push(px, y, pz); b.col.push(c.r, c.g, c.b); b.uv.push(px / 8, pz / 8);
  }
  for (let i = 0; i < N; i++) b.idx.push(base, base + 1 + ((i + 1) % N), base + 1 + i);
}

// Non-indexed triangles with explicit normals for buildings.
function tri(b, a, c, d, n, col, uva, uvc, uvd) {
  // ensure the winding faces along n
  const ux = c[0] - a[0], uy = c[1] - a[1], uz = c[2] - a[2];
  const vx = d[0] - a[0], vy = d[1] - a[1], vz = d[2] - a[2];
  const cx = uy * vz - uz * vy, cy = uz * vx - ux * vz, cz = ux * vy - uy * vx;
  if (cx * n[0] + cy * n[1] + cz * n[2] < 0) { [c, d] = [d, c]; [uvc, uvd] = [uvd, uvc]; }
  b.pos.push(...a, ...c, ...d);
  b.nrm.push(...n, ...n, ...n);
  b.col.push(col.r, col.g, col.b, col.r, col.g, col.b, col.r, col.g, col.b);
  b.uv.push(...uva, ...uvc, ...uvd);
}

function ringSign(pts) {
  let s = 0;
  const n = pts.length / 2;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    s += pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1];
  }
  return s >= 0 ? 1 : -1;
}

function walls(b, pts, y0, y1, col, bay, storey) {
  const n = pts.length / 2;
  const sg = ringSign(pts);
  let u = 0;
  const v0 = y0 / storey, v1 = y1 / storey;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    const ax = pts[i * 2], az = pts[i * 2 + 1], bx = pts[j * 2], bz = pts[j * 2 + 1];
    const L = Math.hypot(bx - ax, bz - az);
    if (L < 0.05) continue;
    const nx = ((bz - az) / L) * sg, nz = (-(bx - ax) / L) * sg;
    const N = [nx, 0, nz];
    // shade walls slightly by facing so corners read well
    const shade = 0.88 + 0.12 * Math.abs(nx);
    const c = col.clone().multiplyScalar(shade);
    const u0 = u / bay, u1 = (u + L) / bay;
    u += L;
    tri(b, [ax, y0, az], [bx, y0, bz], [bx, y1, bz], N, c, [u0, v0], [u1, v0], [u1, v1]);
    tri(b, [ax, y0, az], [bx, y1, bz], [ax, y1, az], N, c, [u0, v0], [u1, v1], [u0, v1]);
  }
}

function parapet(b, pts, h, col) {
  walls(b, pts, h, h + 0.6, col.multiplyScalar(0.9), 4, 100);
}

function flatRoof(b, pts, h, col) {
  const v = [];
  for (let i = 0; i < pts.length; i += 2) v.push(new THREE.Vector2(pts[i], pts[i + 1]));
  let tris;
  try { tris = THREE.ShapeUtils.triangulateShape(v, []); } catch { return; }
  const N = [0, 1, 0];
  for (const t of tris) {
    const a = v[t[0]], c = v[t[1]], d = v[t[2]];
    tri(b, [a.x, h, a.y], [c.x, h, c.y], [d.x, h, d.y], N, col, [0, 0], [0, 0], [0, 0]);
  }
}

// Fits a minimum-area rectangle to the footprint and puts a hip or gable roof on it.
function hipRoof(rb, wb, pts, h, roofCol, wallCol, gable, area) {
  const n = pts.length / 2;
  let best = null;
  for (let i = 0; i < n; i++) {
    const j = (i + 1) % n;
    let ux = pts[j * 2] - pts[i * 2], uz = pts[j * 2 + 1] - pts[i * 2 + 1];
    const L = Math.hypot(ux, uz);
    if (L < 0.5) continue;
    ux /= L; uz /= L;
    let a0 = 1e9, a1 = -1e9, b0 = 1e9, b1 = -1e9;
    for (let k = 0; k < n; k++) {
      const x = pts[k * 2], z = pts[k * 2 + 1];
      const a = x * ux + z * uz, bb = -x * uz + z * ux;
      if (a < a0) a0 = a; if (a > a1) a1 = a; if (bb < b0) b0 = bb; if (bb > b1) b1 = bb;
    }
    const ar = (a1 - a0) * (b1 - b0);
    if (!best || ar < best.ar) best = { ar, ux, uz, a0, a1, b0, b1 };
  }
  if (!best || area / best.ar < 0.62) return false;
  let { ux, uz, a0, a1, b0, b1 } = best;
  let L = (a1 - a0) / 2, W = (b1 - b0) / 2;
  let ca = (a0 + a1) / 2, cb = (b0 + b1) / 2;
  let vx = -uz, vz = ux;
  if (W > L) { [L, W] = [W, L]; [ux, uz, vx, vz] = [vx, vz, -ux, -uz]; [ca, cb] = [cb, -ca]; }
  const cx = ux * ca + vx * cb, cz = uz * ca + vz * cb;
  const ov = 0.35;
  const Lo = L + ov, Wo = W + ov;
  const rh = Math.min(W * 0.62, 3.6);
  const P = (a, bb, y) => [cx + ux * a + vx * bb, y, cz + uz * a + vz * bb];
  const e1 = P(Lo, Wo, h), e2 = P(Lo, -Wo, h), e3 = P(-Lo, -Wo, h), e4 = P(-Lo, Wo, h);
  const ridge = gable ? Lo : Math.max(0.01, Lo - Wo);
  const r1 = P(ridge, 0, h + rh), r2 = P(-ridge, 0, h + rh);
  const norm = (a, c, d, outward) => {
    const ax = c[0] - a[0], ay = c[1] - a[1], az = c[2] - a[2];
    const bx = d[0] - a[0], by = d[1] - a[1], bz = d[2] - a[2];
    let nx = ay * bz - az * by, ny = az * bx - ax * bz, nz = ax * by - ay * bx;
    const l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    if (nx * outward[0] + ny * outward[1] + nz * outward[2] < 0) { nx = -nx; ny = -ny; nz = -nz; }
    return [nx, ny, nz];
  };
  const s = 1 / 3.2;
  const side = (a, c, d, e, out) => {
    const N = norm(a, c, d, out);
    tri(rb, a, c, d, N, roofCol, [0, 0], [Lo * 2 * s, 0], [Lo * 2 * s, Wo * s * 1.2]);
    tri(rb, a, d, e, N, roofCol, [0, 0], [Lo * 2 * s, Wo * s * 1.2], [0, Wo * s * 1.2]);
  };
  side(e4, e1, r1, r2, [vx, 1, vz]);
  side(e2, e3, r2, r1, [-vx, 1, -vz]);
  if (gable) {
    const g1 = P(L, W, h), g2 = P(L, -W, h), g3 = P(-L, -W, h), g4 = P(-L, W, h);
    const t1 = P(L, 0, h + rh * (W / Wo)), t2 = P(-L, 0, h + rh * (W / Wo));
    tri(wb, g1, g2, t1, [ux, 0, uz], wallCol, [0, 0], [0, 0], [0, 0]);
    tri(wb, g3, g4, t2, [-ux, 0, -uz], wallCol, [0, 0], [0, 0], [0, 0]);
    // close the overhang ends with roof colour from below
    tri(rb, e1, e2, r1, norm(e1, e2, r1, [ux, 0, uz]), roofCol.clone().multiplyScalar(0.7), [0, 0], [0, 0], [0, 0]);
    tri(rb, e3, e4, r2, norm(e3, e4, r2, [-ux, 0, -uz]), roofCol.clone().multiplyScalar(0.7), [0, 0], [0, 0], [0, 0]);
  } else {
    tri(rb, e1, e2, r1, norm(e1, e2, r1, [ux, 1, uz]), roofCol, [0, 0], [Wo * 2 * s, 0], [Wo * s, Wo * s]);
    tri(rb, e3, e4, r2, norm(e3, e4, r2, [-ux, 1, -uz]), roofCol, [0, 0], [Wo * 2 * s, 0], [Wo * s, Wo * s]);
  }
  // soffit
  const dn = [0, -1, 0], sc = roofCol.clone().multiplyScalar(0.6);
  tri(rb, e1, e2, e3, dn, sc, [0, 0], [0, 0], [0, 0]);
  tri(rb, e1, e3, e4, dn, sc, [0, 0], [0, 0], [0, 0]);
  return true;
}

// Traffic that drives the real road network, parked cars, and people on the sidewalks.
import * as THREE from 'three';
import { Car, carVsCar } from './vehicle.js';
import { buildPerson, animatePerson, resetPose, CAR_COLORS, buildCar, mountRider, pedal, BIKE_COLORS } from './models.js';
import { isTrafficRoad, isTrail, speedLimit, roadWidth, F, TILE } from './world.js';
import { clamp, wrapAngle, mulberry32, hash2, pointInRing } from './util.js';

const TRAFFIC_TYPES = ['sedan', 'sedan', 'suv', 'suv', 'suv', 'minivan', 'pickup', 'pickup', 'hatch', 'sedan', 'van', 'sports'];
const PARKED_TYPES = ['sedan', 'suv', 'suv', 'minivan', 'pickup', 'hatch', 'sedan', 'minivan'];
const MAX_TRAFFIC = 26, MAX_PEDS = 30, MAX_PARKED = 70;

export const PED_LINES = [
  'Beautiful day in Fishers!', 'Have you tried the food hall at the Nickel Plate?', 'I heard the farmers market is open Saturday.',
  'Watch out for the roundabouts in Carmel, they go on forever.', 'My kids love Conner Prairie.', 'Heading to the library, want to come?',
  'Go Tigers! Or are you a Royals family?', 'The trail by the creek is so pretty this time of year.', 'Is it just me or is 116th Street always busy?',
  'Topgolf later? I need to work on my swing.', 'I walk my dog here every morning.', 'Did you see the geese at the reservoir?',
  'There is a golden fish hidden somewhere around here, I swear.', 'Drive safe, there are kids everywhere!', 'Hi neighbor!',
];

export class Traffic {
  constructor(scene, world, nav) {
    this.scene = scene; this.w = world; this.nav = nav; this.R = world.R;
    this.cars = [];
    this.parked = [];
    this.peds = [];
    this.extra = []; // mission and personal cars that never despawn
    this.reserved = []; // [{x,z,r}] areas kept free of parked cars
    this.parkSpots = new Map(); // tile key -> spots
    this.rnd = mulberry32(12345);
    this.spawnTimer = 0;
    this.time = 0;
    world.onTileLoad = (tile) => this.parkSpots.set(world.tileKey(tile.tx, tile.tz), this.findParkingSpots(tile.tx, tile.tz));
    world.onTileUnload = (tile) => this.parkSpots.delete(world.tileKey(tile.tx, tile.tz));
  }

  // ---------------------------------------------------------------- parked cars
  findParkingSpots(tx, tz) {
    const w = this.w, R = this.R;
    const rnd = mulberry32(tx * 733 + tz * 1999 + 7);
    const spots = [];
    const x0 = tx * TILE, z0 = tz * TILE;
    // driveways: one car near the house end
    const seen = new Set();
    w.roadGrid.query(x0, z0, x0 + TILE, z0 + TILE, (e) => {
      if (seen.has(e)) return;
      seen.add(e);
      if (R.type[e] !== 14 || !(R.flags[e] & F.DRIVEWAY)) return;
      if (rnd() > 0.45) return;
      const n = R.count[e];
      const [ax, az] = w.edgePoint(e, 0), [bx, bz] = w.edgePoint(e, n - 1);
      if (Math.hypot(bx - ax, bz - az) < 7) return;
      // pick the end farther from the street (the one with fewer connections)
      const deg = (node) => w.adjStart[node + 1] - w.adjStart[node];
      const houseEnd = deg(R.a[e]) <= deg(R.b[e]) ? 0 : 1;
      const [hx, hz] = houseEnd === 0 ? [ax, az] : [bx, bz];
      const [ox, oz] = houseEnd === 0 ? [bx, bz] : [ax, az];
      const L = Math.hypot(ox - hx, oz - hz);
      const ux = (ox - hx) / L, uz = (oz - hz) / L;
      const x = hx + ux * 3.5, z = hz + uz * 3.5;
      if (x < x0 || x >= x0 + TILE || z < z0 || z >= z0 + TILE) return;
      if (w.buildingAt(x, z, 1.2) >= 0) return;
      spots.push({ x, z, h: Math.atan2(ux, uz) + (rnd() < 0.5 ? Math.PI : 0), r: rnd() });
    });
    // parking lots
    const aseen = new Set();
    w.aGrid.query(x0, z0, x0 + TILE, z0 + TILE, (ai) => {
      if (aseen.has(ai)) return;
      aseen.add(ai);
      const a = w.map.areas[ai];
      if (a.kind !== 7) return;
      const ring = a.rings[0];
      const cx = (a.bbox[0] + a.bbox[2]) / 2, cz = (a.bbox[1] + a.bbox[3]) / 2;
      if (cx < x0 || cx >= x0 + TILE || cz < z0 || cz >= z0 + TILE) return;
      // orientation from the longest edge
      let best = 0, ang = 0;
      for (let i = 0; i < ring.length / 2; i++) {
        const j = (i + 1) % (ring.length / 2);
        const dx = ring[j * 2] - ring[i * 2], dz = ring[j * 2 + 1] - ring[i * 2 + 1];
        const L = Math.hypot(dx, dz);
        if (L > best) { best = L; ang = Math.atan2(dx, dz); }
      }
      const area = (a.bbox[2] - a.bbox[0]) * (a.bbox[3] - a.bbox[1]);
      const n = Math.min(24, Math.floor(area / 160));
      const fx = Math.sin(ang), fz = Math.cos(ang);
      for (let i = 0; i < n * 3 && spots.length < 120; i++) {
        // snap to a 2.8 m x 12 m stall grid aligned with the lot
        const px = a.bbox[0] + rnd() * (a.bbox[2] - a.bbox[0]), pz = a.bbox[1] + rnd() * (a.bbox[3] - a.bbox[1]);
        const u = Math.round((px * fx + pz * fz) / 2.8) * 2.8, v = Math.round((-px * fz + pz * fx) / 12) * 12;
        const x = u * fx - v * fz, z = u * fz + v * fx;
        if (!pointInRing(x, z, ring, 0, ring.length / 2)) continue;
        if (w.buildingAt(x, z, 1.5) >= 0) continue;
        const nr = w.nearestRoad(x, z, null, 6);
        if (nr && nr.dist < 3.2) continue;
        if (spots.some((s) => Math.hypot(s.x - x, s.z - z) < 2.6)) continue;
        spots.push({ x, z, h: ang + Math.PI / 2 + (rnd() < 0.5 ? Math.PI : 0), r: rnd() });
        if (spots.length > 120) break;
      }
    });
    return spots;
  }

  updateParked(px, pz) {
    // drop far ones
    for (let i = this.parked.length - 1; i >= 0; i--) {
      const c = this.parked[i];
      if (c.keep) continue;
      if (Math.hypot(c.x - px, c.z - pz) > 300) {
        c.remove();
        if (c.spot) c.spot.used = false;
        this.parked.splice(i, 1);
      }
    }
    if (this.parked.length >= MAX_PARKED) return;
    const cands = [];
    for (const spots of this.parkSpots.values()) {
      for (const s of spots) {
        if (s.used) continue;
        if (this.reserved.some((r) => Math.hypot(r.x - s.x, r.z - s.z) < r.r)) continue;
        const d = Math.hypot(s.x - px, s.z - pz);
        if (d < 230) cands.push([d, s]);
      }
    }
    cands.sort((a, b) => a[0] - b[0]);
    for (const [, s] of cands) {
      if (this.parked.length >= MAX_PARKED) break;
      const type = PARKED_TYPES[Math.floor(s.r * PARKED_TYPES.length)];
      const color = CAR_COLORS[Math.floor(hash2(s.x | 0, s.z | 0) * CAR_COLORS.length)];
      const c = new Car(this.scene, type, color, s.x, s.z, s.h);
      c.spot = s; s.used = true;
      this.parked.push(c);
    }
  }

  // ---------------------------------------------------------------- moving traffic
  spawnCar(px, pz, camDir) {
    const hit = this.nav.randomRoadSpot(px, pz, 140, 360, this.rnd);
    if (!hit) return;
    const R = this.R;
    // don't spawn in plain view right in front of the camera
    const vx = hit.x - px, vz = hit.z - pz;
    const d = Math.hypot(vx, vz);
    if (camDir && (vx * camDir.x + vz * camDir.z) / d > 0.6 && d < 220) return;
    for (const c of this.cars) if (Math.hypot(c.x - hit.x, c.z - hit.z) < 25) return;
    let dir = 1;
    if (!(R.flags[hit.edge] & F.ONEWAY) && this.rnd() < 0.5) dir = -1;
    const type = TRAFFIC_TYPES[Math.floor(this.rnd() * TRAFFIC_TYPES.length)];
    const color = CAR_COLORS[Math.floor(this.rnd() * CAR_COLORS.length)];
    const hx = hit.dx * dir, hz = hit.dz * dir;
    const off = this.laneOffset(hit.edge);
    const car = new Car(this.scene, type, color, hit.x - hz * off, hit.z + hx * off, Math.atan2(hx, hz));
    car.driver = 'ai';
    car.ai = { path: [], edge: hit.edge, dir, node: dir > 0 ? R.b[hit.edge] : R.a[hit.edge], stun: 0, honk: 0, blocked: 0 };
    const sp = speedLimit(R.type[hit.edge]);
    car.vx = hx * sp * 0.8; car.vz = hz * sp * 0.8;
    this.appendEdge(car, hit.edge, dir, hit.seg, hit.t);
    this.cars.push(car);
  }

  laneOffset(e) {
    const R = this.R;
    const w = roadWidth(R.type[e], R.flags[e]);
    if (R.flags[e] & F.ONEWAY) return w > 8 ? w / 4 : 0;
    return Math.max(1.6, w / 4);
  }

  // Adds the lane-offset points of edge e (travelled in dir) to the car's path.
  appendEdge(car, e, dir, fromSeg = -1, fromT = 0) {
    const R = this.R;
    const st = R.start[e], c = R.count[e];
    const off = this.laneOffset(e), lim = speedLimit(R.type[e]);
    const pts = [];
    for (let k = 0; k < c; k++) {
      const i = dir > 0 ? k : c - 1 - k;
      pts.push([R.pts[(st + i) * 2], R.pts[(st + i) * 2 + 1]]);
    }
    let first = 0;
    if (fromSeg >= 0) first = dir > 0 ? fromSeg + 1 : c - 1 - fromSeg;
    for (let k = first; k < pts.length; k++) {
      const p = pts[k];
      const a = pts[Math.max(0, k - 1)], b = pts[Math.min(pts.length - 1, k + 1)];
      let dx = b[0] - a[0], dz = b[1] - a[1];
      const L = Math.hypot(dx, dz) || 1;
      dx /= L; dz /= L;
      car.ai.path.push({ x: p[0] - dz * off, z: p[1] + dx * off, lim });
    }
    car.ai.edge = e; car.ai.dir = dir;
    car.ai.node = dir > 0 ? R.b[e] : R.a[e];
  }

  chooseNext(car) {
    const R = this.R, w = this.w, ai = car.ai;
    const n = ai.node;
    const cur = ai.edge;
    // incoming direction
    const p = ai.path;
    let inx = 0, inz = 1;
    if (p.length >= 2) {
      const a = p[p.length - 2], b = p[p.length - 1];
      const L = Math.hypot(b.x - a.x, b.z - a.z) || 1;
      inx = (b.x - a.x) / L; inz = (b.z - a.z) / L;
    }
    const opts = [];
    for (let k = w.adjStart[n]; k < w.adjStart[n + 1]; k++) {
      const e = w.adj[k];
      if (e === cur || !isTrafficRoad(R.type[e], R.flags[e])) continue;
      let dir;
      if (R.a[e] === n) dir = 1; else if (!(R.flags[e] & F.ONEWAY)) dir = -1; else continue;
      const c = R.count[e];
      const k0 = dir > 0 ? 0 : c - 1, k1 = dir > 0 ? Math.min(1, c - 1) : Math.max(0, c - 2);
      const [ax, az] = w.edgePoint(e, k0), [bx, bz] = w.edgePoint(e, k1);
      const L = Math.hypot(bx - ax, bz - az) || 1;
      const cos = ((bx - ax) * inx + (bz - az) * inz) / L;
      if (cos < -0.6) continue;
      let wgt = 1 + (cos > 0.8 ? 2.5 : 0) + (R.type[e] <= 9 ? 1 : 0);
      if (R.type[e] === 14) wgt *= 0.15;
      opts.push([e, dir, wgt]);
    }
    if (!opts.length) {
      // dead end: turn around if two-way
      if (!(R.flags[cur] & F.ONEWAY)) return [cur, -ai.dir];
      return null;
    }
    let sum = opts.reduce((s, o) => s + o[2], 0), r = this.rnd() * sum;
    for (const o of opts) { r -= o[2]; if (r <= 0) return [o[0], o[1]]; }
    return [opts[0][0], opts[0][1]];
  }

  driveAI(car, dt, obstacles) {
    const ai = car.ai;
    const path = ai.path;
    // consume passed points
    while (path.length > 1) {
      const p = path[0], q = path[1];
      const dx = q.x - p.x, dz = q.z - p.z;
      const t = ((car.x - p.x) * dx + (car.z - p.z) * dz) / (dx * dx + dz * dz || 1);
      if (t > 1 || Math.hypot(car.x - p.x, car.z - p.z) < 2.5 && t > 0) path.shift(); else break;
    }
    // keep ~100 m of path ahead
    let ahead = 0;
    for (let i = 1; i < path.length; i++) ahead += Math.hypot(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z);
    let guard = 0;
    while (ahead < 100 && guard++ < 8) {
      const nx = this.chooseNext(car);
      if (!nx) { ai.dead = true; break; }
      const before = path.length;
      this.appendEdge(car, nx[0], nx[1]);
      for (let i = Math.max(1, before); i < path.length; i++) ahead += Math.hypot(path[i].x - path[i - 1].x, path[i].z - path[i - 1].z);
    }
    if (ai.stun > 0) {
      ai.stun -= dt;
      car.input.throttle = 0; car.input.brake = 0.3; car.input.steer = 0;
      return;
    }
    const v = Math.max(0, car.speed);
    // pure pursuit target
    const look = clamp(4 + v * 0.55, 5, 20);
    let tx = path[0]?.x ?? car.x, tz = path[0]?.z ?? car.z, acc = Math.hypot(tx - car.x, tz - car.z);
    let maxTurn = 0, lim = path[0]?.lim ?? 10, distScan = 0;
    let lastDx = car.fx, lastDz = car.fz;
    for (let i = 1; i < path.length; i++) {
      const a = path[i - 1], b = path[i];
      const L = Math.hypot(b.x - a.x, b.z - a.z);
      if (acc < look) { tx = b.x; tz = b.z; acc += L; }
      if (distScan < 15 + v * 2.2 && L > 0.1) {
        const dx = (b.x - a.x) / L, dz = (b.z - a.z) / L;
        const turn = Math.acos(clamp(dx * lastDx + dz * lastDz, -1, 1));
        maxTurn = Math.max(maxTurn, turn);
        lastDx = dx; lastDz = dz;
        lim = Math.min(lim, b.lim);
        distScan += L;
      }
    }
    let target = lim * (1 - clamp(maxTurn / 1.5, 0, 1) * 0.72) * (ai.boost || 1);
    target = Math.max(target, 3.5);
    // obstacles ahead
    for (const o of obstacles) {
      if (o === car) continue;
      const dx = o.x - car.x, dz = o.z - car.z;
      const f = dx * car.fx + dz * car.fz;
      if (f < 0 || f > 8 + v * 1.6) continue;
      const lat = Math.abs(-dx * car.fz + dz * car.fx);
      if (lat > (o.r ?? 2.2)) continue;
      const room = f - (o.r ? 3.5 : 6.5);
      target = Math.min(target, Math.max(0, room * 0.9));
      if (o.isPlayer && room < 4) ai.blocked += dt;
    }
    if (target > 1) ai.blocked = Math.max(0, ai.blocked - dt);
    const desired = Math.atan2(tx - car.x, tz - car.z);
    const dh = wrapAngle(desired - car.heading);
    car.input.steer = clamp(-dh * 2.2, -1, 1);
    const err = target - car.speed;
    car.input.throttle = clamp(err * 0.45, 0, 1);
    car.input.brake = clamp(-err * 0.5, 0, 1);
    if (target < 0.5 && car.speed < 1) { car.input.brake = 1; car.input.throttle = 0; }
  }

  // ---------------------------------------------------------------- pedestrians
  spawnPed(px, pz) {
    const filter = (t, f) => t === 16 || t === 11 || t === 12 || t === 13 || t === 9 || (t === 14 && !(f & F.DRIVEWAY));
    // trails get extra attention so they feel busy with riders and walkers
    const onTrail = this.rnd() < 0.45;
    const hit = onTrail
      ? this.nav.randomRoadSpot(px, pz, 40, 220, this.rnd, isTrail)
      : this.nav.randomRoadSpot(px, pz, 30, 150, this.rnd, filter);
    if (!hit) return;
    if (this.peds.some((p) => Math.hypot(p.x - hit.x, p.z - hit.z) < 20)) return;
    const R = this.R;
    const foot = R.type[hit.edge] === 16;
    const trail = isTrail(R.type[hit.edge], R.flags[hit.edge]);
    const cyclist = trail && this.rnd() < 0.6;
    const side = this.rnd() < 0.5 ? 1 : -1;
    const off = cyclist ? 0.9 : trail ? 1.4 * side : foot ? 0 : (roadWidth(R.type[hit.edge], R.flags[hit.edge]) / 2 + 1.4) * side;
    const x = hit.x - hit.dz * off, z = hit.z + hit.dx * off;
    if (this.w.buildingAt(x, z, 0.5) >= 0 || this.w.inWater(x, z)) return;
    const kid = this.rnd() < 0.25;
    const person = buildPerson({ scale: kid ? 0.68 : 0.95 + this.rnd() * 0.1, longHair: this.rnd() < 0.4, backpack: kid && this.rnd() < 0.6 ? 0x3d6bd1 : undefined, cap: this.rnd() < (cyclist ? 0.7 : 0.15) ? (cyclist ? 0xf2f2f2 : 0xbd2c2c) : undefined });
    let mesh = person;
    if (cyclist) {
      mesh = buildCar('bike', BIKE_COLORS[Math.floor(this.rnd() * BIKE_COLORS.length)]);
      mountRider(mesh, person);
    }
    mesh.position.set(x, 0, z);
    this.scene.add(mesh);
    const dir = this.rnd() < 0.5 ? 1 : -1;
    this.peds.push({
      mesh, x, z, edge: hit.edge, dir, seg: hit.seg, off, foot, cyclist, crank: 0,
      speed: cyclist ? 4.5 + this.rnd() * 2.5 : kid ? 1.5 : 1.1 + this.rnd() * 0.5, heading: Math.atan2(hit.dx * dir, hit.dz * dir),
      dodge: 0, dodgeX: 0, dodgeZ: 0, pause: 0, line: PED_LINES[Math.floor(this.rnd() * PED_LINES.length)],
      talk: 0,
    });
  }

  updatePed(p, dt, threats) {
    const R = this.R, w = this.w;
    const anim = (speed, air) => {
      if (!p.cyclist) { animatePerson(p.mesh, speed, dt, air); return; }
      p.crank += (speed / 0.34) * dt * 0.45;
      pedal(p.mesh, p.crank);
      for (const wh of p.mesh.userData.wheels) wh.tire.rotation.x += (speed / 0.34) * dt;
    };
    if (p.talk > 0) {
      p.talk -= dt;
      anim(0);
      return;
    }
    if (p.dodge > 0) {
      p.dodge -= dt;
      p.x += p.dodgeX * dt; p.z += p.dodgeZ * dt;
      anim(6, p.dodge > 0.25);
      if (!p.cyclist) p.mesh.position.y = Math.max(0, Math.sin(clamp(p.dodge / 0.6, 0, 1) * Math.PI) * 0.6);
    } else {
      p.mesh.position.y = 0;
      // walk along the current edge segment
      const st = R.start[p.edge], c = R.count[p.edge];
      const next = p.dir > 0 ? p.seg + 1 : p.seg;
      if (next < 0 || next >= c) {
        this.pedNextEdge(p);
      } else {
        const tx0 = R.pts[(st + next) * 2], tz0 = R.pts[(st + next) * 2 + 1];
        // offset to the walking side
        const pv = p.dir > 0 ? Math.max(0, next - 1) : Math.min(c - 1, next + 1);
        const fx = tx0 - R.pts[(st + pv) * 2], fz = tz0 - R.pts[(st + pv) * 2 + 1];
        const L = Math.hypot(fx, fz) || 1;
        const tx = tx0 - (fz / L) * p.off, tz = tz0 + (fx / L) * p.off;
        const dx = tx - p.x, dz = tz - p.z, d = Math.hypot(dx, dz);
        if (d < 0.8) {
          p.seg += p.dir;
          if (p.seg < 0 || p.seg >= c - 1) this.pedNextEdge(p);
        } else {
          p.x += (dx / d) * p.speed * dt; p.z += (dz / d) * p.speed * dt;
          const h = Math.atan2(dx, dz);
          p.heading = p.cyclist ? p.heading + wrapAngle(h - p.heading) * Math.min(1, dt * 6) : h;
        }
      }
      anim(p.speed);
    }
    // jump out of the way of fast cars
    for (const t of threats) {
      if (p.dodge > 0) break;
      const dx = p.x - t.x, dz = p.z - t.z;
      const sp = Math.hypot(t.vx, t.vz);
      if (sp < 3) continue;
      const ahead = (dx * t.vx + dz * t.vz) / sp;
      const lat = (-dx * t.vz + dz * t.vx) / sp;
      if (ahead > -1 && ahead < 3 + sp * 0.6 && Math.abs(lat) < 2.6) {
        const s = lat >= 0 ? 1 : -1;
        p.dodgeX = (-t.vz / sp) * s * 6; p.dodgeZ = (t.vx / sp) * s * 6;
        p.dodge = 0.6;
        p.shout = 1.6;
        this.onShout?.(p, ['Whoa!', 'Hey, careful!', 'Yikes!', 'Slow down!'][Math.floor(Math.random() * 4)]);
      }
    }
    const out = { x: 0, z: 0, nx: 0, nz: 0, hit: false };
    w.collide(p.x, p.z, 0.3, out);
    p.x = out.x; p.z = out.z;
    p.mesh.position.x = p.x; p.mesh.position.z = p.z;
    p.mesh.rotation.y = p.heading;
  }

  pedNextEdge(p) {
    const R = this.R, w = this.w;
    const n = p.dir > 0 ? R.b[p.edge] : R.a[p.edge];
    const opts = [];
    for (let k = w.adjStart[n]; k < w.adjStart[n + 1]; k++) {
      const e = w.adj[k];
      const t = R.type[e];
      if (e === p.edge) continue;
      if (!(t === 16 || t === 11 || t === 12 || t === 13 || t === 9 || (t === 14 && !(R.flags[e] & F.DRIVEWAY)))) continue;
      if (p.cyclist && t === 16 && !isTrail(t, R.flags[e])) continue; // riders stay off sidewalks
      opts.push(e);
    }
    if (!opts.length) { p.dir = -p.dir; p.seg = p.dir > 0 ? 0 : R.count[p.edge] - 1; return; }
    // riders and walkers who are on a trail mostly keep following it
    const trailOpts = opts.filter((e) => isTrail(R.type[e], R.flags[e]));
    const pool = trailOpts.length && isTrail(R.type[p.edge], R.flags[p.edge]) && this.rnd() < 0.9 ? trailOpts : opts;
    const e = pool[Math.floor(this.rnd() * pool.length)];
    p.dir = R.a[e] === n ? 1 : -1;
    p.edge = e;
    p.seg = p.dir > 0 ? 0 : R.count[e] - 1;
    const foot = R.type[e] === 16;
    const side = p.off >= 0 ? 1 : -1;
    const trail = isTrail(R.type[e], R.flags[e]);
    if (p.cyclist) p.off = trail ? 0.9 : roadWidth(R.type[e], R.flags[e]) / 2 - 1;
    else p.off = trail ? 1.4 * side : foot ? 0 : (roadWidth(R.type[e], R.flags[e]) / 2 + 1.4) * side;
  }

  // ---------------------------------------------------------------- main update
  update(dt, ctx) {
    const { px, pz, playerCar, player, camDir, nightLights } = ctx;
    this.time += dt;
    this.spawnTimer -= dt;
    if (this.spawnTimer <= 0) {
      this.spawnTimer = 0.25;
      if (this.cars.length < MAX_TRAFFIC) this.spawnCar(px, pz, camDir);
      if (this.peds.length < MAX_PEDS) this.spawnPed(px, pz);
      this.updateParked(px, pz);
    }
    // obstacles for AI braking
    const obstacles = [];
    for (const c of this.cars) obstacles.push(c);
    for (const c of this.parked.concat(this.extra)) if (Math.hypot(c.x - px, c.z - pz) < 200) obstacles.push(c);
    if (playerCar) obstacles.push({ x: playerCar.x, z: playerCar.z, isPlayer: true });
    else if (player) obstacles.push({ x: player.x, z: player.z, r: 1.4, isPlayer: true });
    for (const p of this.peds) obstacles.push({ x: p.x, z: p.z, r: 1.3 });
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i];
      const d = Math.hypot(c.x - px, c.z - pz);
      if (d > 460 || c.ai.dead || c.ai.path.length < 2) {
        if (!c.keep) { c.remove(); this.cars.splice(i, 1); continue; }
      }
      if (c.driver === 'ai') this.driveAI(c, dt, obstacles);
      else { c.input.throttle = 0; c.input.brake = 1; c.input.steer = 0; }
      c.update(dt, d < 260 ? this.w : null);
      if (c.ai.blocked > 3 && c.ai.honk <= 0) { c.ai.honk = 5; this.onHonk?.(c); }
      if (c.ai.honk > 0) c.ai.honk -= dt;
      c.setHeadlights(nightLights);
    }
    // parked cars only move when bumped
    for (const c of this.parked.concat(this.extra)) {
      if (c.driver === 'ai' || c.driver === 'player') continue;
      if (Math.abs(c.vx) + Math.abs(c.vz) > 0.05) {
        c.input.throttle = 0; c.input.brake = 0.6; c.input.handbrake = 1; c.input.steer = 0;
        c.update(dt, this.w);
      }
    }
    // car vs car
    const all = this.cars.concat(this.parked, this.extra);
    if (playerCar && !all.includes(playerCar)) all.push(playerCar);
    for (let i = 0; i < all.length; i++) {
      const a = all[i];
      if (Math.hypot(a.x - px, a.z - pz) > 220) continue;
      for (let j = i + 1; j < all.length; j++) {
        const b = all[j];
        if (Math.abs(a.x - b.x) > 14 || Math.abs(a.z - b.z) > 14) continue;
        const imp = carVsCar(a, b);
        if (imp > 0) {
          if (imp > 3 && (a === playerCar || b === playerCar)) {
            const other = a === playerCar ? b : a;
            if (other.ai) other.ai.stun = 1.5;
            this.onBump?.(other, imp);
          }
          a.sync(); b.sync();
        }
      }
    }
    // pedestrians
    const threats = all.filter((c) => Math.hypot(c.x - px, c.z - pz) < 160 && c.absSpeed > 3);
    for (let i = this.peds.length - 1; i >= 0; i--) {
      const p = this.peds[i];
      if (Math.hypot(p.x - px, p.z - pz) > (p.cyclist ? 320 : 230)) {
        this.scene.remove(p.mesh); this.peds.splice(i, 1); continue;
      }
      this.updatePed(p, dt, threats);
    }
  }

  // A traffic car of a given type that keeps driving until removed (mission use).
  spawnSpecial(type, near, color) {
    const R = this.R;
    for (let i = 0; i < 20; i++) {
      const hit = this.nav.randomRoadSpot(near.x, near.z, 180, 320, this.rnd);
      if (!hit) continue;
      let dir = 1;
      if (!(R.flags[hit.edge] & F.ONEWAY) && this.rnd() < 0.5) dir = -1;
      const hx = hit.dx * dir, hz = hit.dz * dir, off = this.laneOffset(hit.edge);
      const car = new Car(this.scene, type, color, hit.x - hz * off, hit.z + hx * off, Math.atan2(hx, hz));
      car.driver = 'ai'; car.keep = true;
      car.ai = { path: [], edge: hit.edge, dir, node: dir > 0 ? R.b[hit.edge] : R.a[hit.edge], stun: 0, honk: 0, blocked: 0 };
      this.appendEdge(car, hit.edge, dir, hit.seg, hit.t);
      this.cars.push(car);
      return car;
    }
    return null;
  }

  remove(car) {
    for (const l of [this.cars, this.parked, this.extra]) {
      const i = l.indexOf(car);
      if (i >= 0) l.splice(i, 1);
    }
    car.remove();
  }

  detach(car) {
    for (const l of [this.cars, this.parked, this.extra]) {
      const i = l.indexOf(car);
      if (i >= 0) l.splice(i, 1);
    }
    if (car.spot) { car.spot.used = false; car.spot = null; }
  }

  // nearest car the player could get into
  nearestEnterable(x, z, maxD = 3.6) {
    let best = null, bd = maxD;
    for (const list of [this.parked, this.cars, this.extra || []]) {
      for (const c of list) {
        if (c.driver === 'player') continue;
        const d = Math.hypot(c.x - x, c.z - z) - c.spec.w * 0.5;
        if (d < bd) { bd = d; best = c; }
      }
    }
    return best;
  }

  nearestPed(x, z, maxD = 2.6) {
    let best = null, bd = maxD;
    for (const p of this.peds) {
      const d = Math.hypot(p.x - x, p.z - z);
      if (d < bd) { bd = d; best = p; }
    }
    return best;
  }

  clearAround(x, z, r) {
    for (let i = this.cars.length - 1; i >= 0; i--) {
      const c = this.cars[i];
      if (!c.keep && Math.hypot(c.x - x, c.z - z) < r) { c.remove(); this.cars.splice(i, 1); }
    }
  }
}

export { THREE };

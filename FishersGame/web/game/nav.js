// Road graph routing (GPS) and helpers for finding spots on the road network.
import { Heap } from './util.js';
import { isDrivable, isTrafficRoad, speedLimit, roadWidth, F } from './world.js';

export class Nav {
  constructor(world) {
    this.w = world;
    this.R = world.R;
    const n = this.R.nNodes;
    this.g = new Float32Array(n);
    this.prev = new Int32Array(n);
    this.seen = new Uint32Array(n);
    this.closed = new Uint32Array(n);
    this.run = 0;
  }

  // Edges leaving node `n` that may be driven: returns [edge, other node] pairs via callback.
  forEachOut(n, fn, filter = isDrivable) {
    const R = this.R, w = this.w;
    for (let k = w.adjStart[n]; k < w.adjStart[n + 1]; k++) {
      const e = w.adj[k];
      if (!filter(R.type[e], R.flags[e])) continue;
      if (R.a[e] === n) fn(e, R.b[e], 1);
      else if (!(R.flags[e] & F.ONEWAY)) fn(e, R.a[e], -1);
    }
  }

  // Returns {pts:[x,z,...], length} following roads from (sx,sz) to (tx,tz), or null.
  route(sx, sz, tx, tz) {
    const R = this.R;
    const s = this.w.nearestRoad(sx, sz, isDrivable, 250);
    const t = this.w.nearestRoad(tx, tz, isDrivable, 400);
    if (!s || !t) return null;
    if (s.edge === t.edge) return { pts: [sx, sz, s.x, s.z, t.x, t.z, tx, tz], length: Math.hypot(t.x - s.x, t.z - s.z) };
    const run = ++this.run;
    const heap = new Heap();
    const g = this.g, prev = this.prev, seen = this.seen, closed = this.closed;
    const nodes = R.nodes;
    const h = (n) => Math.hypot(nodes[n * 2] - tx, nodes[n * 2 + 1] - tz) / 30;
    const seedNode = (n, cost) => {
      if (seen[n] !== run || cost < g[n]) { seen[n] = run; g[n] = cost; prev[n] = -1; heap.push(n, cost + h(n)); }
    };
    // partial distances along the start edge
    const along = this.alongEdge(s);
    const sp = speedLimit(R.type[s.edge]);
    seedNode(R.b[s.edge], (R.length[s.edge] - along) / sp);
    if (!(R.flags[s.edge] & F.ONEWAY)) seedNode(R.a[s.edge], along / sp);
    const goalA = R.a[t.edge], goalB = R.b[t.edge];
    let found = -1, expansions = 0;
    while (heap.size && expansions < 250000) {
      const n = heap.pop();
      if (closed[n] === run) continue;
      closed[n] = run;
      expansions++;
      if (n === goalA || (n === goalB && !(R.flags[t.edge] & F.ONEWAY))) { found = n; break; }
      this.forEachOut(n, (e, m) => {
        if (closed[m] === run) return;
        const c = g[n] + R.length[e] / speedLimit(R.type[e]) + (R.type[e] >= 14 ? 4 : 0);
        if (seen[m] !== run || c < g[m]) {
          seen[m] = run; g[m] = c; prev[m] = e;
          heap.push(m, c + h(m));
        }
      });
    }
    if (found < 0) return null;
    // walk back through prev edges
    const edges = [];
    let n = found;
    while (prev[n] >= 0) {
      const e = prev[n];
      edges.push([e, n]);
      n = R.a[e] === n ? R.b[e] : R.a[e];
    }
    edges.reverse();
    const pts = [sx, sz, s.x, s.z];
    for (const [e, to] of edges) {
      const fwd = R.b[e] === to;
      const st = R.start[e], c = R.count[e];
      for (let k = 0; k < c; k++) {
        const i = fwd ? k : c - 1 - k;
        pts.push(R.pts[(st + i) * 2], R.pts[(st + i) * 2 + 1]);
      }
    }
    pts.push(t.x, t.z, tx, tz);
    let length = 0;
    for (let i = 2; i < pts.length; i += 2) length += Math.hypot(pts[i] - pts[i - 2], pts[i + 1] - pts[i - 1]);
    return { pts, length };
  }

  alongEdge(hit) {
    const R = this.R;
    let d = 0;
    for (let k = 0; k < hit.seg; k++) {
      const i = (R.start[hit.edge] + k) * 2;
      d += Math.hypot(R.pts[i + 2] - R.pts[i], R.pts[i + 3] - R.pts[i + 1]);
    }
    const i = (R.start[hit.edge] + hit.seg) * 2;
    return d + Math.hypot(R.pts[i + 2] - R.pts[i], R.pts[i + 3] - R.pts[i + 1]) * hit.t;
  }

  // A spot on a road roughly `minD`..`maxD` from (x,z). Returns {x,z,edge,dx,dz} or null.
  randomRoadSpot(x, z, minD, maxD, rnd = Math.random, filter = isTrafficRoad) {
    for (let tries = 0; tries < 40; tries++) {
      const a = rnd() * Math.PI * 2, d = minD + rnd() * (maxD - minD);
      const px = x + Math.cos(a) * d, pz = z + Math.sin(a) * d;
      const hit = this.w.nearestRoad(px, pz, filter, 120);
      if (!hit) continue;
      const dd = Math.hypot(hit.x - x, hit.z - z);
      if (dd < minD * 0.8 || dd > maxD * 1.2) continue;
      return hit;
    }
    return null;
  }

  // Point beside a road at `hit`, on the right-hand side (sidewalk), clear of buildings.
  curbside(hit, extra = 1.5) {
    const R = this.R;
    const hw = roadWidth(R.type[hit.edge], R.flags[hit.edge]) / 2;
    for (const side of [1, -1]) {
      const off = (hw + extra) * side;
      const x = hit.x - hit.dz * off, z = hit.z + hit.dx * off;
      if (this.w.buildingAt(x, z, 0.8) < 0 && !this.w.inWater(x, z)) return { x, z };
    }
    return { x: hit.x, z: hit.z };
  }
}

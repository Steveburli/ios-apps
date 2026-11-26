// Loads and decodes the map files written by tools/build_map.py.
// Coordinates are metres from the map origin: +x east, +z south.

async function fetchWithProgress(url, onBytes) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Could not load ${url} (${res.status})`);
  if (!res.body || !res.body.getReader) {
    const buf = await res.arrayBuffer();
    onBytes(buf.byteLength);
    return buf;
  }
  const reader = res.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value);
    total += value.byteLength;
    onBytes(value.byteLength);
  }
  const out = new Uint8Array(total);
  let o = 0;
  for (const c of chunks) { out.set(c, o); o += c.byteLength; }
  return out.buffer;
}

function decodeRoads(buf, q) {
  const dv = new DataView(buf);
  let o = 0;
  const nNodes = dv.getUint32(o, true); o += 4;
  const nodes = new Float32Array(nNodes * 2);
  for (let i = 0; i < nNodes; i++) {
    nodes[i * 2] = dv.getInt16(o, true) / q;
    nodes[i * 2 + 1] = dv.getInt16(o + 2, true) / q;
    o += 4;
  }
  const nEdges = dv.getUint32(o, true); o += 4;
  const type = new Uint8Array(nEdges), flags = new Uint8Array(nEdges);
  const name = new Uint16Array(nEdges), a = new Uint32Array(nEdges), b = new Uint32Array(nEdges);
  const start = new Uint32Array(nEdges), count = new Uint16Array(nEdges), length = new Float32Array(nEdges);
  const ptsTmp = [];
  let p = 0;
  for (let i = 0; i < nEdges; i++) {
    type[i] = dv.getUint8(o); flags[i] = dv.getUint8(o + 1);
    name[i] = dv.getUint16(o + 2, true);
    a[i] = dv.getUint32(o + 4, true); b[i] = dv.getUint32(o + 8, true);
    const n = dv.getUint16(o + 12, true); o += 14;
    start[i] = p; count[i] = n;
    let len = 0, px = 0, pz = 0;
    for (let k = 0; k < n; k++) {
      const x = dv.getInt16(o, true) / q, z = dv.getInt16(o + 2, true) / q; o += 4;
      ptsTmp.push(x, z);
      if (k) len += Math.hypot(x - px, z - pz);
      px = x; pz = z;
    }
    length[i] = len;
    p += n;
  }
  return { nodes, nNodes, nEdges, type, flags, name, a, b, start, count, length, pts: new Float32Array(ptsTmp) };
}

function decodeBuildings(buf, q) {
  const dv = new DataView(buf);
  let o = 0;
  const n = dv.getUint32(o, true); o += 4;
  const h = new Float32Array(n), kind = new Uint8Array(n), start = new Uint32Array(n), count = new Uint16Array(n);
  const bbox = new Float32Array(n * 4), center = new Float32Array(n * 2), area = new Float32Array(n);
  const ptsTmp = [];
  let p = 0;
  for (let i = 0; i < n; i++) {
    h[i] = dv.getUint8(o) / 2; kind[i] = dv.getUint8(o + 1);
    const c = dv.getUint16(o + 2, true); o += 4;
    start[i] = p; count[i] = c;
    let minx = 1e9, minz = 1e9, maxx = -1e9, maxz = -1e9, sx = 0, sz = 0, ar = 0;
    const first = ptsTmp.length;
    for (let k = 0; k < c; k++) {
      const x = dv.getInt16(o, true) / q, z = dv.getInt16(o + 2, true) / q; o += 4;
      ptsTmp.push(x, z);
      if (x < minx) minx = x; if (x > maxx) maxx = x;
      if (z < minz) minz = z; if (z > maxz) maxz = z;
      sx += x; sz += z;
    }
    for (let k = 0; k < c; k++) {
      const k2 = (k + 1) % c;
      ar += ptsTmp[first + k * 2] * ptsTmp[first + k2 * 2 + 1] - ptsTmp[first + k2 * 2] * ptsTmp[first + k * 2 + 1];
    }
    area[i] = Math.abs(ar) / 2;
    bbox[i * 4] = minx; bbox[i * 4 + 1] = minz; bbox[i * 4 + 2] = maxx; bbox[i * 4 + 3] = maxz;
    center[i * 2] = sx / c; center[i * 2 + 1] = sz / c;
    p += c;
  }
  return { n, h, kind, start, count, bbox, center, area, pts: new Float32Array(ptsTmp) };
}

function decodeAreas(buf, q) {
  const dv = new DataView(buf);
  let o = 0;
  const n = dv.getUint32(o, true); o += 4;
  const areas = [];
  for (let i = 0; i < n; i++) {
    const kind = dv.getUint8(o), nr = dv.getUint8(o + 1); o += 2;
    const rings = [];
    let minx = 1e9, minz = 1e9, maxx = -1e9, maxz = -1e9;
    for (let r = 0; r < nr; r++) {
      const c = dv.getUint16(o, true); o += 2;
      const ring = new Float32Array(c * 2);
      for (let k = 0; k < c; k++) {
        const x = dv.getInt16(o, true) / q, z = dv.getInt16(o + 2, true) / q; o += 4;
        ring[k * 2] = x; ring[k * 2 + 1] = z;
        if (r === 0) {
          if (x < minx) minx = x; if (x > maxx) maxx = x;
          if (z < minz) minz = z; if (z > maxz) maxz = z;
        }
      }
      rings.push(ring);
    }
    areas.push({ kind, rings, bbox: [minx, minz, maxx, maxz] });
  }
  return areas;
}

function decodeLines(buf, q) {
  const dv = new DataView(buf);
  let o = 0;
  const n = dv.getUint32(o, true); o += 4;
  const lines = [];
  for (let i = 0; i < n; i++) {
    const kind = dv.getUint8(o), w = dv.getUint8(o + 1), c = dv.getUint16(o + 2, true); o += 4;
    const pts = new Float32Array(c * 2);
    for (let k = 0; k < c; k++) {
      pts[k * 2] = dv.getInt16(o, true) / q; pts[k * 2 + 1] = dv.getInt16(o + 2, true) / q; o += 4;
    }
    lines.push({ kind, width: w, pts });
  }
  return lines;
}

export async function loadMap(base, onProgress) {
  const files = ['meta.json', 'roads.bin', 'buildings.bin', 'areas.bin', 'lines.bin'];
  // rough sizes so the bar moves sensibly even without Content-Length
  let loaded = 0;
  const expect = 9e6;
  const tick = (n) => { loaded += n; onProgress(Math.min(0.99, loaded / expect)); };
  const bufs = await Promise.all(files.map((f) => fetchWithProgress(base + f, tick)));
  const meta = JSON.parse(new TextDecoder().decode(bufs[0]));
  const q = meta.origin.q;
  return {
    meta,
    roads: decodeRoads(bufs[1], q),
    buildings: decodeBuildings(bufs[2], q),
    areas: decodeAreas(bufs[3], q),
    lines: decodeLines(bufs[4], q),
  };
}

export function lonLatToXZ(meta, lat, lon) {
  const o = meta.origin;
  return { x: (lon - o.lon) * o.kx, z: (o.lat - lat) * o.kz };
}

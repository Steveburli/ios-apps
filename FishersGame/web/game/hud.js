// Heads-up display: minimap with GPS line, the full map, prompts, dialogue and toasts.
import { formatMoney, formatTime } from './util.js';
import { roadWidth } from './world.js';

const $ = (id) => document.getElementById(id);

const MINI_COLORS = {
  major: '#f4f1e6', minor: '#c9cbc4', service: '#8b8f88', foot: '#7f8f75',
};
function roadStyle(t, f = 0) {
  if (t === 16 && f & 128) return '#a6d86a';
  if (t <= 10) return MINI_COLORS.major;
  if (t <= 13) return MINI_COLORS.minor;
  if (t <= 15) return MINI_COLORS.service;
  return MINI_COLORS.foot;
}

export class Hud {
  constructor(world) {
    this.w = world;
    this.mini = $('minimap');
    this.mctx = this.mini.getContext('2d');
    this.big = $('bigmap');
    this.bctx = this.big.getContext('2d');
    this.mapOpen = false;
    this.mapView = { x: 0, z: 0, scale: 0.12 };
    this.waypoint = null;
    this.dialog = null;
    this.toastTimer = 0;
    this.frame = 0;
    this.bindMap();
  }

  // ---------------------------------------------------------------- text bits
  setMoney(m) { $('money').textContent = formatMoney(m); }
  setClock(h) {
    const hh = Math.floor(h) % 24, mm = Math.floor((h % 1) * 60);
    const ampm = hh < 12 ? 'AM' : 'PM';
    $('clock').textContent = `${((hh + 11) % 12) + 1}:${String(mm).padStart(2, '0')} ${ampm}`;
  }
  setFish(n, total) { $('fish').textContent = `${n}/${total}`; }
  setLocation(road, place) {
    $('loc-road').textContent = road || 'Off road';
    $('loc-place').textContent = place;
  }
  setSpeed(mph, show, label) {
    $('speedo').hidden = !show;
    if (show) { $('speed').textContent = Math.round(mph); $('car-name').textContent = label; }
  }
  setPrompt(text) {
    const el = $('prompt');
    el.hidden = !text;
    if (text) el.innerHTML = text;
  }
  setObjective(title, text, timer) {
    const el = $('objective');
    el.hidden = !title;
    if (!title) return;
    $('obj-title').textContent = title;
    $('obj-text').textContent = text;
    const t = $('obj-timer');
    t.hidden = timer == null;
    if (timer != null) { t.textContent = formatTime(timer); t.classList.toggle('urgent', timer < 20); }
  }
  toast(text, kind = '') {
    const el = $('toast');
    el.textContent = text;
    el.className = 'toast show ' + kind;
    this.toastTimer = 3.2;
  }
  banner(title, sub, kind = 'pass') {
    const el = $('banner');
    el.className = 'banner show ' + kind;
    $('banner-title').textContent = title;
    $('banner-sub').textContent = sub;
    clearTimeout(this._bt);
    this._bt = setTimeout(() => { el.className = 'banner'; }, 4200);
  }
  bubble(text, screen) {
    const el = $('bubble');
    if (!text || !screen) { el.hidden = true; return; }
    el.hidden = false;
    el.textContent = text;
    el.style.transform = `translate(${screen.x}px, ${screen.y}px) translate(-50%, -100%)`;
  }

  // ---------------------------------------------------------------- dialogue
  // lines: [{who, text}] ; resolves when the last line is dismissed
  say(lines) {
    if (!Array.isArray(lines)) lines = [lines];
    return new Promise((resolve) => {
      this.dialog = { lines, i: 0, resolve, typed: 0 };
      this.showLine();
    });
  }
  showLine() {
    const d = this.dialog;
    const el = $('dialog');
    if (!d) { el.hidden = true; return; }
    el.hidden = false;
    $('dlg-who').textContent = d.lines[d.i].who || '';
    $('dlg-text').textContent = '';
    d.typed = 0;
  }
  advanceDialog() {
    const d = this.dialog;
    if (!d) return false;
    const full = d.lines[d.i].text;
    if (d.typed < full.length) { d.typed = full.length; $('dlg-text').textContent = full; return true; }
    d.i++;
    if (d.i >= d.lines.length) {
      this.dialog = null;
      $('dialog').hidden = true;
      d.resolve();
    } else this.showLine();
    return true;
  }

  update(dt) {
    if (this.toastTimer > 0) {
      this.toastTimer -= dt;
      if (this.toastTimer <= 0) $('toast').className = 'toast';
    }
    const d = this.dialog;
    if (d) {
      const full = d.lines[d.i].text;
      if (d.typed < full.length) {
        d.typed = Math.min(full.length, d.typed + dt * 70);
        $('dlg-text').textContent = full.slice(0, Math.floor(d.typed));
      }
    }
  }

  // ---------------------------------------------------------------- minimap
  // The static part of the minimap (land, buildings, roads) is drawn north-up into an
  // offscreen canvas around the player and redrawn only after moving ~150 m.
  minimapBase(px, pz) {
    const SPAN = 900, RES = 1024, k = RES / SPAN;
    if (this.mb && Math.hypot(px - this.mb.cx, pz - this.mb.cz) < 150) return this.mb;
    const cv = this.mb?.cv || document.createElement('canvas');
    cv.width = cv.height = RES;
    const c = cv.getContext('2d');
    const cx = Math.round(px), cz = Math.round(pz);
    const x0 = cx - SPAN / 2, z0 = cz - SPAN / 2;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.fillStyle = '#3f5a3a'; c.fillRect(0, 0, RES, RES);
    c.setTransform(k, 0, 0, k, -x0 * k, -z0 * k);
    const R = this.w.R;
    const seen = new Set();
    this.w.aGrid.query(x0, z0, x0 + SPAN, z0 + SPAN, (ai) => {
      if (seen.has(ai)) return;
      seen.add(ai);
      const a = this.w.map.areas[ai];
      const fill = a.kind === 1 || a.kind === 15 ? '#3d7ea6' : a.kind === 3 || a.kind === 4 ? '#5c8a46' : a.kind === 2 ? '#3b5c33' : a.kind === 7 ? '#565a5c' : null;
      if (!fill) return;
      c.fillStyle = fill;
      c.beginPath();
      for (const ring of a.rings) {
        c.moveTo(ring[0], ring[1]);
        for (let i = 2; i < ring.length; i += 2) c.lineTo(ring[i], ring[i + 1]);
        c.closePath();
      }
      c.fill('evenodd');
    });
    c.fillStyle = '#57534d';
    const B = this.w.B, bs = new Set();
    this.w.bGrid.query(x0, z0, x0 + SPAN, z0 + SPAN, (i) => {
      if (bs.has(i)) return;
      bs.add(i);
      const s = B.start[i] * 2, n = B.count[i];
      c.beginPath();
      c.moveTo(B.pts[s], B.pts[s + 1]);
      for (let q = 1; q < n; q++) c.lineTo(B.pts[s + q * 2], B.pts[s + q * 2 + 1]);
      c.closePath(); c.fill();
    });
    const st = ++this.w.stamp;
    const groups = new Map();
    this.w.roadGrid.query(x0, z0, x0 + SPAN, z0 + SPAN, (e) => {
      if (this.w.edgeStamp[e] === st) return;
      this.w.edgeStamp[e] = st;
      const t = R.type[e];
      const key = roadStyle(t, R.flags[e]) + '|' + Math.max(2.5, roadWidth(t, R.flags[e]) * 0.9).toFixed(1);
      let l = groups.get(key);
      if (!l) { l = []; groups.set(key, l); }
      l.push(e);
    });
    c.lineCap = 'round'; c.lineJoin = 'round';
    const sorted = [...groups.entries()].sort((a, b) => parseFloat(a[0].split('|')[1]) - parseFloat(b[0].split('|')[1]));
    for (const [key, edges] of sorted) {
      const [color, w] = key.split('|');
      c.strokeStyle = color; c.lineWidth = parseFloat(w);
      c.beginPath();
      for (const e of edges) {
        const s = R.start[e] * 2, n = R.count[e];
        c.moveTo(R.pts[s], R.pts[s + 1]);
        for (let q = 1; q < n; q++) c.lineTo(R.pts[s + q * 2], R.pts[s + q * 2 + 1]);
      }
      c.stroke();
    }
    this.mb = { cv, cx, cz, x0, z0, k, SPAN };
    return this.mb;
  }

  drawMinimap(px, pz, yaw, heading, route, blips) {
    if (this.frame++ % 2) return;
    const c = this.mctx, W = this.mini.width, H = this.mini.height;
    const scale = (W / 2) / 240; // px per metre: 240 m radius
    const mb = this.minimapBase(px, pz);
    c.save();
    c.clearRect(0, 0, W, H);
    c.beginPath(); c.arc(W / 2, H / 2, W / 2 - 2, 0, Math.PI * 2); c.clip();
    c.fillStyle = '#3f5a3a'; c.fillRect(0, 0, W, H);
    c.translate(W / 2, H / 2);
    c.rotate(Math.PI + yaw);
    c.scale(scale, scale);
    c.translate(-px, -pz);
    c.drawImage(mb.cv, mb.x0, mb.z0, mb.SPAN, mb.SPAN);
    // GPS route
    if (route && route.pts.length > 3) {
      c.strokeStyle = '#ff4fa3'; c.lineWidth = 7;
      c.beginPath(); c.moveTo(route.pts[0], route.pts[1]);
      for (let i = 2; i < route.pts.length; i += 2) c.lineTo(route.pts[i], route.pts[i + 1]);
      c.stroke();
    }
    c.restore();
    // blips (unrotated screen space, clamped to the rim)
    const th = Math.PI + yaw, cos = Math.cos(th), sin = Math.sin(th);
    for (const b of blips) {
      const dx = b.x - px, dz = b.z - pz;
      let sx = (dx * cos - dz * sin) * scale, sy = (dx * sin + dz * cos) * scale;
      const d = Math.hypot(sx, sy), lim = W / 2 - 12;
      const edge = d > lim;
      if (edge) { if (b.hideFar) continue; sx *= lim / d; sy *= lim / d; }
      this.blip(c, W / 2 + sx, H / 2 + sy, b, edge);
    }
    // player arrow
    c.save();
    c.translate(W / 2, H / 2);
    c.rotate(-(heading - yaw));
    c.fillStyle = '#fff'; c.strokeStyle = '#13202b'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(0, -11); c.lineTo(8, 8); c.lineTo(0, 4); c.lineTo(-8, 8); c.closePath();
    c.fill(); c.stroke();
    c.restore();
    // north marker
    const nx = W / 2 + Math.sin(th) * (W / 2 - 12);
    const ny = H / 2 - Math.cos(th) * (W / 2 - 12);
    c.fillStyle = '#13202b'; c.beginPath(); c.arc(nx, ny, 9, 0, 7); c.fill();
    c.fillStyle = '#fff'; c.font = '700 12px Barlow Condensed, sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
    c.fillText('N', nx, ny + 1);
  }

  blip(c, x, y, b, edge) {
    c.save();
    c.translate(x, y);
    const col = b.color || '#ffd23f';
    c.fillStyle = col; c.strokeStyle = '#13202b'; c.lineWidth = 2;
    if (b.icon === 'home') {
      c.beginPath(); c.moveTo(0, -8); c.lineTo(8, 0); c.lineTo(5, 0); c.lineTo(5, 7); c.lineTo(-5, 7); c.lineTo(-5, 0); c.lineTo(-8, 0); c.closePath();
      c.fill(); c.stroke();
    } else if (b.icon === 'giver') {
      c.beginPath(); c.arc(0, 0, 8, 0, 7); c.fill(); c.stroke();
      c.fillStyle = '#13202b'; c.font = '800 13px Barlow Condensed, sans-serif'; c.textAlign = 'center'; c.textBaseline = 'middle';
      c.fillText('!', 0, 1);
    } else {
      c.beginPath(); c.arc(0, 0, edge ? 6 : 7, 0, 7); c.fill(); c.stroke();
    }
    c.restore();
  }

  // ---------------------------------------------------------------- full map
  renderBase() {
    if (this.base) return;
    const [minx, minz, maxx, maxz] = this.w.bounds;
    const S = 0.2; // px per metre
    const cw = Math.ceil((maxx - minx) * S), ch = Math.ceil((maxz - minz) * S);
    const cv = document.createElement('canvas');
    cv.width = cw; cv.height = ch;
    const c = cv.getContext('2d');
    c.fillStyle = '#41593b'; c.fillRect(0, 0, cw, ch);
    c.setTransform(S, 0, 0, S, -minx * S, -minz * S);
    for (const a of this.w.map.areas) {
      const fill = { 1: '#3d7ea6', 15: '#3d7ea6', 2: '#36532f', 3: '#5c8a46', 4: '#66994c', 6: '#7f7651', 7: '#55585a', 10: '#58804a', 5: '#5f9447' }[a.kind];
      if (!fill) continue;
      c.fillStyle = fill;
      c.beginPath();
      for (const ring of a.rings) {
        c.moveTo(ring[0], ring[1]);
        for (let i = 2; i < ring.length; i += 2) c.lineTo(ring[i], ring[i + 1]);
        c.closePath();
      }
      c.fill('evenodd');
    }
    for (const l of this.w.map.lines) {
      if (l.kind > 4) continue;
      c.strokeStyle = '#3d7ea6'; c.lineWidth = l.kind === 1 ? 20 : 6;
      c.beginPath(); c.moveTo(l.pts[0], l.pts[1]);
      for (let i = 2; i < l.pts.length; i += 2) c.lineTo(l.pts[i], l.pts[i + 1]);
      c.stroke();
    }
    const R = this.w.R;
    c.lineCap = 'round'; c.lineJoin = 'round';
    for (const [pred, color, width] of [
      [(t, f) => t === 16 && f & 128, '#9fd36a', 9],
      [(t) => t >= 11 && t <= 14, '#bdbfb7', 9],
      [(t) => t <= 10, '#f2dc8a', 18],
    ]) {
      c.strokeStyle = color; c.lineWidth = width;
      c.beginPath();
      for (let e = 0; e < R.nEdges; e++) {
        if (!pred(R.type[e], R.flags[e])) continue;
        if (R.type[e] === 14 && R.flags[e] & 32) continue;
        const s = R.start[e] * 2, n = R.count[e];
        c.moveTo(R.pts[s], R.pts[s + 1]);
        for (let k = 1; k < n; k++) c.lineTo(R.pts[s + k * 2], R.pts[s + k * 2 + 1]);
      }
      c.stroke();
    }
    this.base = { cv, S, minx, minz };
  }

  openMap(px, pz) {
    this.renderBase();
    this.mapOpen = true;
    $('mapwrap').hidden = false;
    this.mapView.x = px; this.mapView.z = pz;
    this.resizeMap();
  }
  closeMap() { this.mapOpen = false; $('mapwrap').hidden = true; }
  resizeMap() {
    this.big.width = this.big.clientWidth * devicePixelRatio;
    this.big.height = this.big.clientHeight * devicePixelRatio;
  }

  bindMap() {
    let drag = null;
    this.big.addEventListener('mousedown', (e) => { drag = { x: e.clientX, y: e.clientY, moved: false }; });
    window.addEventListener('mousemove', (e) => {
      if (!drag || !this.mapOpen) return;
      const dx = e.clientX - drag.x, dy = e.clientY - drag.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) drag.moved = true;
      const s = this.mapView.scale / devicePixelRatio;
      this.mapView.x -= dx / s; this.mapView.z -= dy / s;
      drag.x = e.clientX; drag.y = e.clientY;
    });
    window.addEventListener('mouseup', (e) => {
      if (drag && !drag.moved && this.mapOpen && e.target === this.big) {
        const p = this.screenToWorld(e.offsetX * devicePixelRatio, e.offsetY * devicePixelRatio);
        if (e.button === 2) this.waypoint = null;
        else this.waypoint = p;
        this.onWaypoint?.(this.waypoint);
      }
      drag = null;
    });
    this.big.addEventListener('contextmenu', (e) => e.preventDefault());
    this.big.addEventListener('wheel', (e) => {
      e.preventDefault();
      const f = Math.exp(-e.deltaY * 0.0015);
      this.mapView.scale = Math.min(1.2, Math.max(0.03, this.mapView.scale * f));
    }, { passive: false });
    window.addEventListener('resize', () => this.mapOpen && this.resizeMap());
  }

  screenToWorld(sx, sy) {
    const v = this.mapView;
    return { x: v.x + (sx - this.big.width / 2) / v.scale, z: v.z + (sy - this.big.height / 2) / v.scale };
  }

  drawBigMap(px, pz, heading, route, blips, labels) {
    if (!this.mapOpen) return;
    const c = this.bctx, W = this.big.width, H = this.big.height, v = this.mapView, b = this.base;
    const k = v.scale / b.S;
    c.setTransform(1, 0, 0, 1, 0, 0);
    c.fillStyle = '#2c3b29'; c.fillRect(0, 0, W, H);
    c.imageSmoothingEnabled = true;
    const ox = W / 2 - (v.x - b.minx) * v.scale, oy = H / 2 - (v.z - b.minz) * v.scale;
    c.drawImage(b.cv, ox, oy, b.cv.width * k, b.cv.height * k);
    const toS = (x, z) => [W / 2 + (x - v.x) * v.scale, H / 2 + (z - v.z) * v.scale];
    if (route && route.pts.length > 3) {
      c.strokeStyle = '#ff4fa3'; c.lineWidth = 5 * devicePixelRatio; c.lineJoin = 'round';
      c.beginPath();
      for (let i = 0; i < route.pts.length; i += 2) {
        const [sx, sy] = toS(route.pts[i], route.pts[i + 1]);
        i ? c.lineTo(sx, sy) : c.moveTo(sx, sy);
      }
      c.stroke();
    }
    const dpr = devicePixelRatio;
    c.textAlign = 'center'; c.textBaseline = 'middle';
    for (const l of labels) {
      if (l.minScale && v.scale < l.minScale) continue;
      const [sx, sy] = toS(l.x, l.z);
      if (sx < -100 || sy < -50 || sx > W + 100 || sy > H + 50) continue;
      c.font = `${l.big ? 700 : 600} ${(l.big ? 22 : 14) * dpr}px Barlow Condensed, sans-serif`;
      c.lineWidth = 4 * dpr; c.strokeStyle = 'rgba(10,18,14,0.85)';
      c.strokeText(l.text, sx, sy); c.fillStyle = l.big ? '#ffffff' : l.trail ? '#c4ef8e' : '#e8e4d6'; c.fillText(l.text, sx, sy);
    }
    for (const bl of blips) {
      const [sx, sy] = toS(bl.x, bl.z);
      c.save(); c.scale(dpr, dpr);
      this.blip(c, sx / dpr, sy / dpr, bl, false);
      c.restore();
    }
    if (this.waypoint) {
      const [sx, sy] = toS(this.waypoint.x, this.waypoint.z);
      c.fillStyle = '#ff4fa3'; c.strokeStyle = '#fff'; c.lineWidth = 2 * dpr;
      c.beginPath(); c.moveTo(sx, sy); c.lineTo(sx - 9 * dpr, sy - 18 * dpr); c.lineTo(sx + 9 * dpr, sy - 18 * dpr); c.closePath(); c.fill(); c.stroke();
    }
    const [sx, sy] = toS(px, pz);
    c.save(); c.translate(sx, sy); c.rotate(Math.PI - heading); c.scale(dpr * 1.3, dpr * 1.3);
    c.fillStyle = '#fff'; c.strokeStyle = '#13202b'; c.lineWidth = 2;
    c.beginPath(); c.moveTo(0, -11); c.lineTo(8, 8); c.lineTo(0, 4); c.lineTo(-8, 8); c.closePath(); c.fill(); c.stroke();
    c.restore();
  }
}

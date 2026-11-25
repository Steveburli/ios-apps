/*
 * Map My Argument: draws an argument map as a building, in SVG.
 *
 *   roof (pediment + beam)  the thesis: the weight everything below must carry
 *   pillars                 top-level reasons; width = strength, the beam sags over weak ones
 *   footings and posts      sources (one post each: I, II, IXI with a cross-brace)
 *   blocks under a footing  sub-claims, colored by how well they stand
 *   clouds under a footing  belief clouds: holding it up with nothing but belief
 *   holes                   termites: very sure, but hasn't looked into it
 *   red arrows              counter-arguments you haven't answered
 *
 * Tower.render() returns markup; Tower.animate*() play the stress tests on it.
 */
(function (root) {
  "use strict";

  const W = 640, H = 560;
  const GROUND = 482, FOOT = 404, BEAM_Y = 176, BEAM_H = 24, SPAN_L = 78, SPAN_R = 562;
  const SAG = 48;

  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  // Deterministic jitter so cracks and holes don't move on every redraw.
  function rand(seed) {
    let h = 2166136261;
    for (let i = 0; i < seed.length; i++) { h ^= seed.charCodeAt(i); h = Math.imul(h, 16777619); }
    return () => { h ^= h << 13; h ^= h >>> 17; h ^= h << 5; return ((h >>> 0) % 10000) / 10000; };
  }

  function layout(map, ev) {
    const roots = map.claims.filter((c) => !c.parent || !map.claims.some((p) => p.id === c.parent) || c.parent === c.id);
    const n = Math.max(1, roots.length);
    const slot = (SPAN_R - SPAN_L) / n;
    return roots.map((c, i) => {
      const r = ev.claims[c.id] || { strength: 0, stability: 0, status: "failing" };
      const cx = SPAN_L + slot * (i + 0.5);
      const pw = Math.max(16, Math.min(96, slot * (0.2 + 0.5 * Math.min(1, r.strength))));
      return { claim: c, r, cx, pw, slot, index: i };
    });
  }

  // A fallen pillar leaves the beam hanging much lower over the gap.
  function beamTop(col, fallen) {
    if (fallen) return BEAM_Y + SAG * 3;
    return BEAM_Y + (1 - Math.min(1, col.r.stability)) * SAG;
  }

  /** The beam's outline: through each pillar's top, out to the ends. */
  function roofPoints(cols, fallenSet) {
    if (!cols.length) return { top: [], peak: BEAM_Y - 74 };
    const pts = cols.map((c) => [c.cx, beamTop(c, fallenSet && fallenSet.has(c.claim.id))]);
    const left = [SPAN_L - 26, pts[0][1]], right = [SPAN_R + 26, pts[pts.length - 1][1]];
    const top = [left, ...pts, right];
    const avg = pts.reduce((a, p) => a + p[1], 0) / pts.length;
    return { top, peak: avg - 74 };
  }

  function roofPaths(roof) {
    const t = roof.top;
    if (!t.length) return { beam: "", pediment: "" };
    const down = t.map(([x, y]) => `${x.toFixed(1)},${(y + BEAM_H).toFixed(1)}`).reverse();
    const beam = "M" + t.map(([x, y]) => `${x.toFixed(1)},${y.toFixed(1)}`).join(" L") + " L" + down.join(" L") + " Z";
    const l = t[0], r = t[t.length - 1];
    const pediment = `M${(l[0] - 8).toFixed(1)},${l[1].toFixed(1)} L320,${roof.peak.toFixed(1)} L${(r[0] + 8).toFixed(1)},${r[1].toFixed(1)} Z`;
    return { beam, pediment };
  }

  function cloudPath(cx, cy, w) {
    const r = w / 4;
    return `M${cx - 2 * r},${cy + r * 0.6} a${r},${r} 0 0,1 ${r * 0.4},${-r * 1.3} a${r * 1.1},${r * 1.1} 0 0,1 ${r * 1.8},${-r * 0.5}` +
      ` a${r},${r} 0 0,1 ${r * 1.6},${r * 0.7} a${r * 0.8},${r * 0.8} 0 0,1 ${r * 0.2},${r * 1.1} Z`;
  }

  function crackPath(rnd, x, y0, y1, w) {
    let d = `M${(x + (rnd() - 0.5) * w * 0.5).toFixed(1)},${y0.toFixed(1)}`;
    const steps = 5;
    for (let i = 1; i <= steps; i++) {
      const y = y0 + (y1 - y0) * (i / steps);
      d += ` L${(x + (rnd() - 0.5) * w * 0.7).toFixed(1)},${y.toFixed(1)}`;
    }
    return d;
  }

  /** Supports under one footing: posts for sources, blocks for sub-claims, a cloud for belief. */
  function supports(map, ev, col) {
    const c = col.claim, r = col.r;
    const kids = map.claims.filter((k) => k.parent === c.id && k.id !== c.id);
    const items = [];
    const counted = new Set();
    // Posts: the sources that count, up to three.
    const srcs = (c.sources || []).filter((s) => !(r.droppedSources || []).includes(s.id));
    srcs.slice(0, 3).forEach((s) => { counted.add(s.id); items.push({ type: "post", source: s }); });
    for (const k of kids) items.push({ type: "block", claim: k, r: ev.claims[k.id] });
    if (c.cloud) items.push({ type: "cloud" });
    const ghost = (c.sources || []).filter((s) => !counted.has(s.id));

    const footW = Math.max(col.pw + 18, Math.min(col.slot - 8, 26 + items.length * 26));
    const x0 = col.cx - footW / 2;
    let out = `<rect class="footing" x="${x0.toFixed(1)}" y="${FOOT}" width="${footW.toFixed(1)}" height="12" rx="2"/>`;
    if (!items.length) {
      out += `<rect class="void" x="${(x0 + 4).toFixed(1)}" y="${FOOT + 14}" width="${(footW - 8).toFixed(1)}" height="${GROUND - FOOT - 16}" rx="3"/>`;
      out += `<text class="void-label" x="${col.cx.toFixed(1)}" y="${(FOOT + 50).toFixed(1)}">no support</text>`;
      return out;
    }
    const gap = footW / items.length;
    items.forEach((it, i) => {
      const x = x0 + gap * (i + 0.5);
      if (it.type === "post") {
        out += `<g class="post" data-source="${esc(it.source.id)}" data-claim="${esc(c.id)}"><rect x="${(x - 3).toFixed(1)}" y="${FOOT + 12}" width="6" height="${GROUND - FOOT - 12}"/></g>`;
      } else if (it.type === "block") {
        const kr = it.r || { status: "failing", strength: 0 };
        const bw = Math.max(10, Math.min(gap - 4, 10 + 20 * Math.min(1, kr.strength)));
        const label = col.index + 1 + String.fromCharCode(97 + kids.indexOf(it.claim));
        out += `<g class="block st-${kr.status}${kr.termites ? " termites" : ""}" data-claim="${esc(it.claim.id)}">` +
          `<rect x="${(x - bw / 2).toFixed(1)}" y="${FOOT + 14}" width="${bw.toFixed(1)}" height="${GROUND - FOOT - 14}" rx="2"/>` +
          `<text x="${x.toFixed(1)}" y="${(FOOT + 50).toFixed(1)}">${label}</text></g>`;
      } else {
        out += `<g class="belief" data-claim="${esc(c.id)}"><path d="${cloudPath(x, GROUND - 26, Math.min(gap + 14, 56))}"/></g>`;
      }
    });
    // Cross-brace when three sources agree: IXI.
    const posts = items.map((it, i) => (it.type === "post" ? x0 + gap * (i + 0.5) : null)).filter((x) => x !== null);
    if (posts.length >= 3) {
      const a = posts[0], b = posts[2];
      out += `<g class="brace" data-claim="${esc(c.id)}"><line x1="${a.toFixed(1)}" y1="${FOOT + 18}" x2="${b.toFixed(1)}" y2="${GROUND - 4}"/><line x1="${b.toFixed(1)}" y1="${FOOT + 18}" x2="${a.toFixed(1)}" y2="${GROUND - 4}"/></g>`;
    }
    // Sources that don't count (distrusted) lie on the ground.
    ghost.slice(0, 3).forEach((s, i) => {
      const gx = x0 + 6 + i * 10;
      out += `<rect class="post-down" x="${gx.toFixed(1)}" y="${GROUND - 5}" width="22" height="4" transform="rotate(${-8 + i * 6} ${gx} ${GROUND})"/>`;
    });
    return out;
  }

  function pillar(map, ev, col) {
    const c = col.claim, r = col.r;
    const top = beamTop(col, false) + BEAM_H;
    const h = FOOT - top;
    const x = col.cx - col.pw / 2;
    const rnd = rand(c.id);
    const status = r.status || "failing";
    let g = `<g class="pillar st-${status}${r.termites ? " termites" : ""}" data-claim="${esc(c.id)}">`;
    g += `<rect class="shaft" x="${x.toFixed(1)}" y="${top.toFixed(1)}" width="${col.pw.toFixed(1)}" height="${h.toFixed(1)}"/>`;
    // Flutes, for a little stone texture.
    const flutes = Math.max(1, Math.floor(col.pw / 14));
    for (let i = 1; i <= flutes; i++) {
      const fx = x + (col.pw * i) / (flutes + 1);
      g += `<line class="flute" x1="${fx.toFixed(1)}" y1="${(top + 6).toFixed(1)}" x2="${fx.toFixed(1)}" y2="${(FOOT - 6).toFixed(1)}"/>`;
    }
    g += `<rect class="capital" x="${(x - 5).toFixed(1)}" y="${(top - 2).toFixed(1)}" width="${(col.pw + 10).toFixed(1)}" height="8" rx="1"/>`;
    g += `<rect class="capital" x="${(x - 5).toFixed(1)}" y="${(FOOT - 8).toFixed(1)}" width="${(col.pw + 10).toFixed(1)}" height="8" rx="1"/>`;
    const cracks = { solid: 0, strained: 1, sagging: 2, failing: 3 }[status] || 0;
    for (let i = 0; i < cracks; i++) {
      const y0 = top + 12 + rnd() * h * 0.4;
      g += `<path class="crack" d="${crackPath(rnd, col.cx, y0, y0 + h * (0.25 + rnd() * 0.3), col.pw)}"/>`;
    }
    if (r.termites) {
      for (let i = 0; i < 7; i++) {
        const hx = x + 4 + rnd() * (col.pw - 8), hy = top + 14 + rnd() * (h - 28);
        g += `<ellipse class="hole" cx="${hx.toFixed(1)}" cy="${hy.toFixed(1)}" rx="${(1.6 + rnd() * 2).toFixed(1)}" ry="${(1.2 + rnd() * 1.6).toFixed(1)}"/>`;
      }
    }
    g += `<circle class="num-bg" cx="${col.cx.toFixed(1)}" cy="${(top + 22).toFixed(1)}" r="10"/>`;
    g += `<text class="num" x="${col.cx.toFixed(1)}" y="${(top + 26).toFixed(1)}">${col.index + 1}</text>`;
    g += `</g>`;

    // Counter-arguments push on the pillar from the side.
    let arrows = "";
    (c.counters || []).forEach((k, i) => {
      const side = i % 2 === 0 ? -1 : 1;
      const ax = col.cx + side * (col.pw / 2 + 4);
      const ay = top + 40 + i * 34;
      if (ay > FOOT - 20) return;
      const len = 14 + k.strength * 5;
      const x1 = ax + side * len;
      arrows += `<g class="counter${k.answered ? " answered" : ""}" data-claim="${esc(c.id)}">` +
        `<line x1="${x1.toFixed(1)}" y1="${ay.toFixed(1)}" x2="${(ax + side * 6).toFixed(1)}" y2="${ay.toFixed(1)}"/>` +
        `<path d="M${(ax + side * 7).toFixed(1)},${(ay - 5).toFixed(1)} L${ax.toFixed(1)},${ay.toFixed(1)} L${(ax + side * 7).toFixed(1)},${(ay + 5).toFixed(1)} Z"/>` +
        (k.answered ? `<line class="block-bar" x1="${(ax + side * 9).toFixed(1)}" y1="${(ay - 7).toFixed(1)}" x2="${(ax + side * 9).toFixed(1)}" y2="${(ay + 7).toFixed(1)}"/>` : "") +
        `</g>`;
    });
    return g + arrows;
  }

  /**
   * The whole scene. opts.id makes gradient ids unique when several towers share a page;
   * opts.compact drops the sky's clouds and labels for thumbnails.
   */
  function render(map, ev, opts) {
    opts = opts || {};
    const id = opts.id || "t";
    const cols = layout(map, ev);
    const roof = roofPoints(cols);
    const paths = roofPaths(roof);
    const leanDeg = ev.lean;

    let s = `<svg class="tower${opts.compact ? " compact" : ""}" viewBox="0 0 ${W} ${H}" role="img" aria-label="${esc(describe(map, ev))}" data-lean="${leanDeg.toFixed(2)}">`;
    s += `<defs><linearGradient id="${id}-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="sky-top"/><stop offset="1" class="sky-bot"/></linearGradient>` +
      `<pattern id="${id}-soil" width="14" height="14" patternUnits="userSpaceOnUse" patternTransform="rotate(30)"><rect width="14" height="14" class="soil-a"/><line x1="0" y1="0" x2="0" y2="14" class="soil-b"/></pattern></defs>`;
    s += `<rect class="sky" width="${W}" height="${GROUND}" fill="url(#${id}-sky)"/>`;
    if (!opts.compact) {
      s += `<g class="sky-clouds"><path d="${cloudPath(90, 74, 70)}"/><path d="${cloudPath(540, 52, 54)}"/></g>`;
    }
    s += `<g class="scene" data-scene>`;
    s += `<g class="structure" style="transform-origin:320px ${GROUND}px; transform: rotate(${leanDeg.toFixed(2)}deg)">`;
    if (!cols.length) {
      s += `<text class="empty-label" x="320" y="320">Add a reason to raise the first pillar</text>`;
    } else {
      for (const col of cols) s += `<g class="column" data-col="${esc(col.claim.id)}">${supports(map, ev, col)}${pillar(map, ev, col)}</g>`;
      s += `<g class="roof"><path class="pediment" d="${paths.pediment}"/><path class="beam" d="${paths.beam}"/>`;
      s += `<text class="load" x="320" y="${(roof.peak + 52).toFixed(1)}">LOAD ${ev.weight}</text>`;
      if (ev.flags && ev.flags.headInClouds) {
        s += `<g class="head-clouds"><path d="${cloudPath(250, roof.peak + 20, 70)}"/><path d="${cloudPath(390, roof.peak + 8, 80)}"/></g>`;
      }
      s += `</g>`;
    }
    s += `</g>`;
    s += `<rect class="ground" x="0" y="${GROUND}" width="${W}" height="${H - GROUND}" fill="url(#${id}-soil)"/>`;
    s += `<line class="grade-line" x1="0" y1="${GROUND}" x2="${W}" y2="${GROUND}"/>`;
    if (!opts.compact) {
      for (const col of cols) {
        const tier = col.r.tier || "–";
        s += `<text class="tier" x="${col.cx.toFixed(1)}" y="${GROUND + 26}">${col.index + 1} · ${tier}</text>`;
      }
    }
    s += `</g></svg>`;
    return s;
  }

  function describe(map, ev) {
    if (!map.claims.length) return "An empty lot: no reasons yet.";
    return `A tower for “${map.thesis || map.topic}”: ${ev.gradeLabel}, ${Math.round(ev.score * 100)} percent stable, leaning ${Math.abs(ev.lean).toFixed(0)} degrees.`;
  }

  // ---------------------------------------------------------------- animation

  const reduceMotion = () => typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  const wait = (ms) => new Promise((res) => setTimeout(res, reduceMotion() ? Math.min(ms, 60) : ms));

  /** Tweens the roof to where it rests once some pillars have fallen. */
  function settleRoof(svg, map, ev, fallenSet, ms) {
    const cols = layout(map, ev);
    const from = roofPoints(cols);
    const to = roofPoints(cols, fallenSet);
    const beam = svg.querySelector(".beam"), ped = svg.querySelector(".pediment"), load = svg.querySelector(".load");
    if (!beam) return Promise.resolve();
    const dur = reduceMotion() ? 1 : ms || 700;
    return new Promise((res) => {
      const t0 = performance.now();
      const step = (now) => {
        const k = Math.min(1, (now - t0) / dur);
        const e = 1 - Math.pow(1 - k, 3);
        const mix = {
          top: from.top.map(([x, y], i) => [x, y + (to.top[i][1] - y) * e]),
          peak: from.peak + (to.peak - from.peak) * e,
        };
        const p = roofPaths(mix);
        beam.setAttribute("d", p.beam);
        ped.setAttribute("d", p.pediment);
        if (load) load.setAttribute("y", (mix.peak + 52).toFixed(1));
        if (k < 1) requestAnimationFrame(step); else res();
      };
      requestAnimationFrame(step);
    });
  }

  function fall(svg, ids) {
    ids.forEach((id, i) => {
      const side = i % 2 === 0 ? "fall-l" : "fall-r";
      svg.querySelectorAll(`.pillar[data-claim="${CSS.escape(id)}"], .block[data-claim="${CSS.escape(id)}"]`).forEach((el) => el.classList.add("fallen", side));
      svg.querySelectorAll(`.counter[data-claim="${CSS.escape(id)}"]`).forEach((el) => el.classList.add("gone"));
    });
  }

  function lean(svg, deg) {
    const s = svg.querySelector(".structure");
    if (s) s.style.transform = `rotate(${deg.toFixed(2)}deg)`;
  }

  async function animateWind(svg, map, outcome) {
    svg.classList.add("windy");
    svg.querySelectorAll(".belief, .head-clouds").forEach((el) => el.classList.add("blown"));
    await wait(900);
    fall(svg, outcome.fallen);
    await settleRoof(svg, map, outcome.result, new Set(outcome.fallen), 800);
    if (outcome.toppled) topple(svg, outcome.result.lean);
    else lean(svg, outcome.result.lean);
    await wait(500);
    svg.classList.remove("windy");
  }

  async function animateQuake(svg, map, outcome) {
    svg.classList.add("quaking");
    await wait(1100);
    svg.classList.remove("quaking");
    fall(svg, outcome.fallen);
    await settleRoof(svg, map, outcome.result, new Set(outcome.fallen), 800);
    if (outcome.toppled) topple(svg, outcome.result.lean);
    else lean(svg, outcome.result.lean);
  }

  /** Plays one combat step. Step 0 pulls sources and clouds; 1 knocks out premises; 2 is the final push. */
  async function animateCombatStep(svg, map, outcome, stepIndex) {
    const step = outcome.steps[stepIndex];
    if (stepIndex === 0) {
      for (const it of step.items) {
        if (it.source) svg.querySelectorAll(`.post[data-source="${CSS.escape(it.source)}"]`).forEach((el) => el.classList.add("pulled"));
      }
      for (const id of step.clouds) svg.querySelectorAll(`.belief[data-claim="${CSS.escape(id)}"]`).forEach((el) => el.classList.add("blown"));
      if (step.items.some((it) => it.source)) {
        const ids = new Set(step.items.map((it) => it.claim));
        ids.forEach((id) => svg.querySelectorAll(`.brace[data-claim="${CSS.escape(id)}"]`).forEach((el) => el.classList.add("pulled")));
      }
      await wait(700);
    } else if (stepIndex === 1) {
      fall(svg, step.items);
      await wait(700);
    } else {
      svg.classList.add("pressed");
      await wait(600);
      svg.classList.remove("pressed");
      fall(svg, step.fallen);
      await settleRoof(svg, map, outcome.result, new Set(outcome.fallen), 800);
      if (outcome.toppled) topple(svg, outcome.result.lean);
      else lean(svg, outcome.result.lean);
    }
  }

  function topple(svg, leanDeg) {
    const s = svg.querySelector(".structure");
    if (!s) return;
    const dir = leanDeg < 0 ? -1 : 1;
    s.classList.add("toppled");
    s.style.transform = `rotate(${dir * 9}deg) translateY(10px)`;
    svg.querySelector(".roof")?.classList.add("collapsed", dir < 0 ? "to-l" : "to-r");
  }

  // ---------------------------------------------------------------- knowledge vs. conviction chart

  /** Familiarity (x, 1–5) against confidence (y, 0–100), with the termite zone shaded. */
  function knowledgeChart(map, report, labelFor) {
    const w = 320, h = 220, l = 44, r = 14, t = 14, b = 40;
    const x = (f) => l + ((f - 1) / 4) * (w - l - r);
    const y = (c) => t + (1 - c / 100) * (h - t - b);
    let s = `<svg class="kchart" viewBox="0 0 ${w} ${h}" role="img" aria-label="How much you know against how sure you are, for each claim">`;
    s += `<rect class="zone" x="${l}" y="${y(100)}" width="${(x(2.5) - l).toFixed(1)}" height="${(y(70) - y(100)).toFixed(1)}"/>`;
    s += `<text class="zone-label" x="${l + 6}" y="${y(100) + 14}">termites</text>`;
    s += `<rect class="zone humble" x="${x(3.5).toFixed(1)}" y="${y(35).toFixed(1)}" width="${(w - r - x(3.5)).toFixed(1)}" height="${(y(0) - y(35)).toFixed(1)}"/>`;
    s += `<text class="zone-label" x="${(w - r - 6)}" y="${(y(0) - 8).toFixed(1)}" text-anchor="end">humble</text>`;
    for (const c of [0, 50, 100]) {
      s += `<line class="grid" x1="${l}" x2="${w - r}" y1="${y(c)}" y2="${y(c)}"/><text class="tick" x="${l - 8}" y="${y(c) + 4}" text-anchor="end">${c}%</text>`;
    }
    for (let f = 1; f <= 5; f++) s += `<text class="tick" x="${x(f)}" y="${h - b + 16}" text-anchor="middle">${f}</text>`;
    s += `<text class="axis" x="${(l + w - r) / 2}" y="${h - 6}" text-anchor="middle">how much you know →</text>`;
    s += `<text class="axis" transform="translate(12 ${(t + h - b) / 2}) rotate(-90)" text-anchor="middle">how sure you are →</text>`;
    const seen = {};
    for (const k of report) {
      const key = k.familiarity + ":" + Math.round(k.confidence / 5);
      const nudge = (seen[key] = (seen[key] || 0) + 1) - 1;
      const cx = x(k.familiarity) + nudge * 9, cy = y(k.confidence);
      s += `<g class="dot v-${k.verdict}" data-claim="${esc(k.id)}"><circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="7"/>` +
        `<text x="${cx.toFixed(1)}" y="${(cy + 3.5).toFixed(1)}" text-anchor="middle">${esc(labelFor(k.id))}</text></g>`;
    }
    return s + `</svg>`;
  }

  root.Tower = { render, animateWind, animateQuake, animateCombatStep, knowledgeChart, describe };
})(typeof globalThis !== "undefined" ? globalThis : this);

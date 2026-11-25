/*
 * Map My Argument: the website.
 *
 * One page, several views picked by the address's #hash: home, build, map,
 * rate, compare and how. Everything is kept in this browser (localStorage);
 * maps travel between people as share codes (MMA1.…), the same codes the iOS
 * app reads and writes.
 */
(function () {
  "use strict";

  const M = window.MMA, C = window.MMA_CATALOG, T = window.Tower;
  const KEY = "mma.v1";
  const STEPS = ["Topic", "Sources", "Position", "Reasons", "Support", "Familiarity", "Confidence"];
  const IMPORTANCE = ["", "A little", "Somewhat", "A fair bit", "A lot", "Everything"];

  // ---------------------------------------------------------------- storage

  function load() {
    try {
      const raw = JSON.parse(localStorage.getItem(KEY) || "null");
      if (raw && Array.isArray(raw.maps)) {
        return {
          maps: raw.maps.map(M.normalize), trust: raw.trust || {}, name: raw.name || "",
          draft: raw.draft ? M.normalize(raw.draft) : null, draftStep: raw.draftStep || 0, last: raw.last || "",
        };
      }
    } catch (e) { /* private window or blocked storage: start fresh */ }
    return { maps: [], trust: {}, name: "", draft: null, draftStep: 0, last: "" };
  }

  function save() {
    try {
      localStorage.setItem(KEY, JSON.stringify({
        maps: store.maps, trust: store.trust, name: store.name, draft: ui.draft, draftStep: ui.step, last: ui.current || "",
      }));
    } catch (e) { /* storage full or blocked: keep working in memory */ }
  }

  const store = load();
  const ui = {
    view: "home", step: store.draftStep || 0, draft: store.draft, current: store.last,
    editing: null, confirmDelete: false, testing: false, testNote: null, dialogue: [],
    compare: null, queueIndex: 0, rate: null, rateStep: 0, codeError: "", homeTest: false,
  };

  const example = M.normalize(C.EXAMPLE);
  const exampleFriend = M.normalize(C.EXAMPLE_FRIEND);

  // ---------------------------------------------------------------- helpers

  const $ = (sel, el) => (el || document).querySelector(sel);
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const pct = (x) => Math.round(x * 100) + "%";
  const now = () => new Date().toISOString();

  function mapById(id) {
    if (id === example.id) return example;
    return store.maps.find((m) => m.id === id) || null;
  }

  function currentMap() {
    return mapById(ui.current) || null;
  }

  function isExample(map) { return map && map.id === example.id; }

  function upsert(map) {
    map.updated = now();
    const i = store.maps.findIndex((m) => m.id === map.id);
    if (i >= 0) store.maps[i] = map; else store.maps.unshift(map);
    save();
  }

  /** Claims in reading order: each top-level claim, then its sub-claims. */
  function ordered(map) {
    const ids = new Set(map.claims.map((c) => c.id));
    const isRoot = (c) => !c.parent || !ids.has(c.parent) || c.parent === c.id;
    const out = [];
    const walk = (c, depth, label) => {
      if (out.some((o) => o.claim.id === c.id)) return;
      out.push({ claim: c, depth, label });
      map.claims.filter((k) => k.parent === c.id && k.id !== c.id)
        .forEach((k, i) => walk(k, depth + 1, label + String.fromCharCode(97 + i)));
    };
    map.claims.filter(isRoot).forEach((c, i) => walk(c, 0, String(i + 1)));
    return out;
  }

  function labels(map) {
    return Object.fromEntries(ordered(map).map((o) => [o.claim.id, o.label]));
  }

  function newClaim(parent, extra) {
    return {
      id: M.newId("c"), parent: parent || null, text: "", importance: 3, confidence: 60, familiarity: 3,
      cloud: false, votes: 0, sources: [], counters: [], disputedBy: [], ...extra,
    };
  }

  function newMap(topic) {
    return M.normalize({
      id: M.newId("map"), topic, thesis: topic, stance: "for", author: store.name,
      trust: { ...store.trust }, created: now(), updated: now(), claims: [],
    });
  }

  function toast(text) {
    const old = $(".toast");
    if (old) old.remove();
    const el = document.createElement("div");
    el.className = "toast";
    el.setAttribute("role", "status");
    el.textContent = text;
    document.body.appendChild(el);
    setTimeout(() => el.remove(), 2600);
  }

  async function copy(text, okText) {
    try {
      await navigator.clipboard.writeText(text);
      toast(okText || "Copied");
    } catch (e) {
      const box = $(".share-code");
      if (box) {
        const range = document.createRange();
        range.selectNodeContents(box);
        const sel = getSelection();
        sel.removeAllRanges();
        sel.addRange(range);
      }
      toast("Selected. Press Copy on your keyboard or menu.");
    }
  }

  function go(view) {
    if (location.hash !== "#" + view) location.hash = view;
    else route();
  }

  // ---------------------------------------------------------------- shared pieces

  const brandMark = `<svg viewBox="0 0 32 32" aria-hidden="true"><path d="M3 11 L16 3 L29 11 Z" fill="var(--accent)"/><rect x="3" y="11" width="26" height="4" fill="var(--ink)"/><rect x="6" y="15" width="4" height="11" fill="var(--ink)"/><rect x="14" y="15" width="4" height="11" fill="var(--ink)"/><rect x="22" y="15" width="4" height="11" fill="var(--ink)"/><rect x="2" y="26" width="28" height="3" fill="var(--ink)"/></svg>`;

  function statusPill(r) {
    if (!r) return "";
    const names = { solid: "Solid", strained: "Strained", sagging: "Sagging", failing: "Failing", fallen: "Fell" };
    return `<span class="pill ${r.status}">${names[r.status] || r.status}</span>`;
  }

  function seg(action, id, options, value, cls) {
    return `<div class="seg ${cls || ""}" role="group">` + options.map(([v, label]) =>
      `<button type="button" data-action="${action}" data-id="${esc(id)}" data-value="${esc(v)}" aria-pressed="${String(v) === String(value)}">${esc(label)}</button>`).join("") + `</div>`;
  }

  function kindOptions(selected) {
    return M.SOURCE_KINDS.map((k) => `<option value="${k.id}"${k.id === selected ? " selected" : ""}>${esc(k.label)}</option>`).join("");
  }

  function leanOptions(selected) {
    return M.LEANS.map((k) => `<option value="${k.id}"${k.id === selected ? " selected" : ""}>${esc(k.label)}</option>`).join("");
  }

  function importancePicker(claim) {
    let s = `<div class="importance" role="group" aria-label="How much does this matter">`;
    for (let i = 1; i <= 5; i++) {
      s += `<button type="button" data-action="importance" data-id="${esc(claim.id)}" data-value="${i}" aria-pressed="${claim.importance === i}" title="${IMPORTANCE[i]}">${i}</button>`;
    }
    return s + `<span class="hint">${IMPORTANCE[claim.importance]}</span></div>`;
  }

  function spectrum(claim) {
    let s = `<div class="spectrum" role="group" aria-label="How familiar are you with this">`;
    for (const f of M.FAMILIARITY) {
      s += `<button type="button" data-action="familiarity" data-id="${esc(claim.id)}" data-value="${f.value}" aria-pressed="${claim.familiarity === f.value}"><span class="mono">${f.value}</span>${esc(f.label)}</button>`;
    }
    const chosen = M.FAMILIARITY.find((f) => f.value === claim.familiarity);
    return s + `</div><span class="hint">${esc(chosen ? chosen.label : "")}</span>`;
  }

  function confidenceSlider(claim) {
    return `<div class="conf-row"><input type="range" min="0" max="100" step="5" value="${claim.confidence}" data-input="confidence" data-id="${esc(claim.id)}" id="conf-${esc(claim.id)}" aria-label="How sure you are"><output for="conf-${esc(claim.id)}">${claim.confidence}%</output></div>`;
  }

  /** The editor for one claim: its words, weight, sources, sub-points, belief cloud, counter-argument and critics. */
  function claimEditor(map, claim, label, opts) {
    opts = opts || {};
    const sub = !!claim.parent;
    const kids = map.claims.filter((k) => k.parent === claim.id && k.id !== claim.id);
    let s = `<section class="claim-edit${sub ? " sub" : ""}" data-claim="${esc(claim.id)}">`;
    s += `<header><span class="badge">${esc(label)}</span><div class="field"><label for="text-${esc(claim.id)}">${sub ? "Supporting point" : "Reason"}</label>` +
      `<input type="text" id="text-${esc(claim.id)}" data-input="text" data-id="${esc(claim.id)}" value="${esc(claim.text)}" placeholder="${sub ? "Something that backs this up" : "Because…"}"></div></header>`;
    if (!opts.textOnly) {
      s += `<div class="field"><label>${sub ? "How much does the point above depend on this?" : "How much does your position depend on this?"}</label>${importancePicker(claim)}</div>`;
    }
    if (opts.full) {
      s += `<div class="field"><label>Sources</label><div class="hint">Three independent sources you trust make the strongest support (IXI).</div>`;
      for (const src of claim.sources) {
        s += `<div class="source-row" data-source="${esc(src.id)}">` +
          `<div class="field"><label for="st-${esc(src.id)}">Title</label><input type="text" id="st-${esc(src.id)}" data-input="src-title" data-id="${esc(claim.id)}" data-src="${esc(src.id)}" value="${esc(src.title)}" placeholder="Where it comes from"></div>` +
          `<div class="field"><label for="sk-${esc(src.id)}">Kind</label><select id="sk-${esc(src.id)}" data-input="src-kind" data-id="${esc(claim.id)}" data-src="${esc(src.id)}">${kindOptions(src.kind)}</select></div>` +
          `<div class="field"><label for="sl-${esc(src.id)}">How others see it</label><select id="sl-${esc(src.id)}" data-input="src-lean" data-id="${esc(claim.id)}" data-src="${esc(src.id)}">${leanOptions(src.lean)}</select></div>` +
          `<button type="button" class="quiet danger" data-action="remove-source" data-id="${esc(claim.id)}" data-value="${esc(src.id)}" aria-label="Remove this source">Remove</button>` +
          `</div>`;
      }
      s += `<div class="row"><button type="button" data-action="add-source" data-id="${esc(claim.id)}">Add a source</button>` +
        (depthOf(map, claim) < 2 ? `<button type="button" data-action="add-sub" data-id="${esc(claim.id)}">Add a supporting point</button>` : "") +
        `</div></div>`;
      s += `<label class="row"><input type="checkbox" data-input="cloud" data-id="${esc(claim.id)}" ${claim.cloud ? "checked" : ""}> I don't have evidence for this. I just believe it.</label>`;
      const counter = claim.counters[0];
      s += `<div class="field"><label for="ct-${esc(claim.id)}">The strongest point against it</label>` +
        `<input type="text" id="ct-${esc(claim.id)}" data-input="counter-text" data-id="${esc(claim.id)}" value="${esc(counter ? counter.text : "")}" placeholder="What would someone who disagrees say? (optional)">`;
      if (counter && counter.text.trim()) {
        s += `<div class="row"><span class="hint">How strong is it?</span>${seg("counter-strength", claim.id, [[1, "1"], [2, "2"], [3, "3"], [4, "4"], [5, "5"]], counter.strength)}` +
          `<label class="row"><input type="checkbox" data-input="counter-answered" data-id="${esc(claim.id)}" ${counter.answered ? "checked" : ""}> I have an answer to it</label></div>`;
      }
      s += `</div>`;
      s += `<div class="field"><label>Who would reject this outright?</label><div class="chips">` +
        M.PERSPECTIVES.map((p) => `<button type="button" class="chip" data-action="disputed" data-id="${esc(claim.id)}" data-value="${p.id}" aria-pressed="${claim.disputedBy.includes(p.id)}">${esc(p.label)}</button>`).join("") +
        `</div><span class="hint">An opponent knocks these out before it attacks anything else.</span></div>`;
    }
    if (opts.removable !== false) {
      s += `<div class="row end"><button type="button" class="quiet danger" data-action="remove-claim" data-id="${esc(claim.id)}">Remove ${sub ? "this point" : "this reason"}</button></div>`;
    }
    s += `</section>`;
    if (opts.full) {
      kids.forEach((k, i) => { s += claimEditor(map, k, label + String.fromCharCode(97 + i), opts); });
    }
    return s;
  }

  function depthOf(map, claim) {
    let d = 0, c = claim;
    const seen = new Set();
    while (c && c.parent && !seen.has(c.id)) { seen.add(c.id); c = map.claims.find((x) => x.id === c.parent); d++; }
    return d;
  }

  // ---------------------------------------------------------------- views: home

  function viewHome() {
    const ev = M.evaluate(example);
    let s = `<section class="hero">
      <div class="copy">
        <span class="eyebrow">Argument mapping</span>
        <h1>See if your argument can stand.</h1>
        <p class="lede">Build your position like a building. Every reason is a pillar, every source is a support, and anything you only believe floats on a cloud. Then send in a gust of wind, an earthquake or someone who disagrees, and watch what stays standing.</p>
        <div class="row">
          <button class="primary" data-action="start">Build my argument</button>
          <button data-action="open-map" data-id="${example.id}">Explore the example</button>
        </div>
        ${ui.draft ? `<p class="hint">You have an unfinished map about “${esc(M.short(ui.draft.topic || ui.draft.thesis || "a new topic", 50))}”. <button class="quiet" data-action="resume">Pick up where you left off</button></p>` : ""}
      </div>
      <figure>
        <div class="tower-frame" id="home-tower">${T.render(example, ev, { id: "home" })}</div>
        <figcaption><strong>Example:</strong> “${esc(example.thesis)}”. <span class="mono">${pct(ev.score)}</span> stable, ${esc(ev.gradeLabel.toLowerCase())}. Pillar 3 rests on one social media post its owner doesn't trust, and pillar 4 floats on a belief cloud.</figcaption>
        <div class="row">
          <button data-action="home-wind" ${ui.homeTest ? "disabled" : ""}>Send a gust of wind</button>
          <button data-action="home-quake" ${ui.homeTest ? "disabled" : ""}>Start an earthquake</button>
          <button class="quiet" data-action="home-reset">Rebuild</button>
        </div>
      </figure>
    </section>`;

    s += `<section class="card"><h2>How to read a tower</h2><div class="legend">
      ${legendItem(`<rect x="10" y="4" width="14" height="26" fill="var(--stone)" stroke="var(--stone-edge)" stroke-width="1.5"/>`, "<strong>Pillars</strong> are your reasons. Wider means better supported; the beam sags over weak ones.")}
      ${legendItem(`<rect x="6" y="6" width="22" height="4" fill="var(--stone-dark)"/><rect x="8" y="10" width="3" height="20" fill="var(--stone)" stroke="var(--stone-edge)"/><rect x="16" y="10" width="3" height="20" fill="var(--stone)" stroke="var(--stone-edge)"/><rect x="24" y="10" width="3" height="20" fill="var(--stone)" stroke="var(--stone-edge)"/><line x1="9" y1="12" x2="25" y2="30" stroke="var(--stone-edge)" stroke-width="2"/><line x1="25" y1="12" x2="9" y2="30" stroke="var(--stone-edge)" stroke-width="2"/>`, "<strong>Posts</strong> are sources. One is weak (I), two moderate (II), three independent ones are braced (IXI).")}
      ${legendItem(`<path d="${"M4,24 a7,7 0 0,1 3,-9 a8,8 0 0,1 13,-4 a7,7 0 0,1 11,5 a6,6 0 0,1 1,8 Z"}" fill="var(--cloud)" stroke="var(--cloud-edge)" stroke-width="1.5"/>`, "<strong>Belief clouds</strong> hold up what you believe without evidence. Too many and your head is in the clouds.")}
      ${legendItem(`<rect x="10" y="4" width="14" height="26" fill="var(--stone-dark)" stroke="var(--stone-edge)" stroke-dasharray="3 2"/><ellipse cx="14" cy="12" rx="2" ry="1.5" fill="var(--ink)"/><ellipse cx="19" cy="20" rx="2.4" ry="1.6" fill="var(--ink)"/><ellipse cx="15" cy="25" rx="1.6" ry="1.2" fill="var(--ink)"/>`, "<strong>Termites</strong> eat claims you're very sure of but haven't looked into.")}
      ${legendItem(`<line x1="30" y1="17" x2="12" y2="17" stroke="var(--failing)" stroke-width="3"/><path d="M13,11 L5,17 L13,23 Z" fill="var(--failing)"/>`, "<strong>Red arrows</strong> are counter-arguments you haven't answered yet.")}
      ${legendItem(`<path d="M3,12 L17,4 L31,12 Z" fill="var(--stone-dark)" stroke="var(--stone-edge)"/><path d="M3,12 L31,12 L31,17 L17,21 L3,17 Z" fill="var(--stone)" stroke="var(--stone-edge)"/>`, "<strong>The roof</strong> is your conclusion. Its load is how much weight your reasons carry.")}
    </div></section>`;

    s += `<section class="how-steps"><h2>How it works</h2><div class="steps">
      ${step(1, "Pick a topic", "Choose one of the ready-made questions or write your own.")}
      ${step(2, "Say who you trust", "Rate kinds of sources: studies, government data, news, social posts and more.")}
      ${step(3, "Lay out your case", "Give your reasons, how much each matters, and the evidence under each one.")}
      ${step(4, "Check yourself", "Say how well you know each point and how sure you are. Mismatches show up as termites.")}
      ${step(5, "Stress-test it", "Wind blows away belief clouds. Earthquakes find the cracks. Opponents throw out the sources they don't trust.")}
      ${step(6, "Compare with a friend", "Send a code. They rate your claims, and you see exactly where you agree and where to start talking.")}
    </div></section>`;

    if (store.maps.length) {
      s += `<section class="card"><h2>Your maps</h2><div class="maps-list">` + store.maps.map((m) => {
        const e = M.evaluate(m);
        return `<button class="map-tile" data-action="open-map" data-id="${esc(m.id)}">${T.render(m, e, { id: "tile-" + m.id, compact: true })}<span><strong>${esc(M.short(m.thesis || m.topic || "Untitled", 70))}</strong><span class="muted mono">${m.claims.length ? pct(e.score) + " · " + esc(e.gradeLabel) : "No reasons yet"}${m.basedOn ? " · reply" : ""}${m.author && m.author !== store.name ? " · " + esc(m.author) : ""}</span></span></button>`;
      }).join("") + `</div></section>`;
    }

    s += `<section class="card" id="code-card"><h2>Got a code from a friend?</h2>
      <p class="muted">Paste the code they sent. If it's their map, you'll rate it. If it's their answer to yours, you'll see where you agree.</p>
      <div class="field"><label for="code-in">Share code</label><textarea id="code-in" placeholder="MMA1.…"></textarea></div>
      ${ui.codeError ? `<div class="notice bad" role="alert">${esc(ui.codeError)}</div>` : ""}
      <div class="row"><button class="primary" data-action="open-code">Open</button><button class="quiet" data-action="demo-compare">See an example comparison</button></div>
    </section>`;
    return s;
  }

  function legendItem(svgInner, html) {
    return `<div><svg viewBox="0 0 34 34" aria-hidden="true">${svgInner}</svg><p>${html}</p></div>`;
  }

  function step(n, title, body) {
    return `<div class="card"><h3><span class="mono">${n}</span>${esc(title)}</h3><p class="muted">${esc(body)}</p></div>`;
  }

  // ---------------------------------------------------------------- views: build

  function viewBuild() {
    if (!ui.draft) ui.draft = newMap("");
    const d = ui.draft;
    const stepIdx = Math.min(ui.step, STEPS.length - 1);
    let s = `<div class="wizard"><ol class="progress" aria-label="Steps">` + STEPS.map((name, i) =>
      `<li><button type="button" data-action="goto-step" data-value="${i}" ${i === stepIdx ? 'aria-current="step"' : ""} ${i > maxStep() ? "disabled" : ""}><span class="mono">${i + 1}</span>${name}</button></li>`).join("") + `</ol>`;
    s += `<div class="sheet">` + [stepTopic, stepTrust, stepPosition, stepReasons, stepSupport, stepFamiliarity, stepConfidence][stepIdx](d) + `</div></div>`;
    return s;
  }

  function maxStep() {
    const d = ui.draft;
    if (!d || !(d.topic || "").trim()) return 0;
    if (!d.thesis.trim()) return 2;
    if (!d.claims.some((c) => !c.parent && c.text.trim())) return 3;
    return STEPS.length - 1;
  }

  function nav(back, nextLabel, nextAction, disabled) {
    return `<div class="row">${back ? `<button type="button" data-action="prev-step">Back</button>` : ""}<span class="spacer"></span>` +
      `<button type="button" class="primary" data-action="${nextAction || "next-step"}" ${disabled ? "disabled" : ""}>${esc(nextLabel || "Next")}</button></div>`;
  }

  function stepTopic(d) {
    let s = `<div><span class="eyebrow">Step 1 of 7</span><h2>What do you want to argue about?</h2></div>`;
    for (const group of C.TOPICS) {
      s += `<div class="topic-group"><h3>${esc(group.category)}</h3><div class="chips">` + group.items.map((t) =>
        `<button type="button" class="chip" data-action="topic" data-value="${esc(t)}" aria-pressed="${d.topic === t}">${esc(t)}</button>`).join("") + `</div></div>`;
    }
    const custom = C.TOPICS.some((g) => g.items.includes(d.topic)) ? "" : d.topic;
    s += `<div class="field"><label for="topic-own">Or write your own</label><input type="text" id="topic-own" data-input="topic" value="${esc(custom)}" placeholder="A statement someone could agree or disagree with"></div>`;
    return s + nav(false, "Next", "next-step", !d.topic.trim());
  }

  function stepTrust(d) {
    let s = `<div><span class="eyebrow">Step 2 of 7</span><h2>Which sources do you trust?</h2><p class="muted">Your answers decide how much each source holds up. A source you don't trust holds up nothing, even if it agrees with you.</p></div>`;
    s += `<div class="trust-grid">` + M.SOURCE_KINDS.map((k) =>
      `<div class="trust-row"><span>${esc(k.label)}</span>${seg("trust", k.id, [["trust", "Trust"], ["unfamiliar", "Not sure"], ["distrust", "Don't trust"]], d.trust[k.id] || "unfamiliar", "trust")}</div>`).join("") + `</div>`;
    return s + nav(true);
  }

  function stepPosition(d) {
    let s = `<div><span class="eyebrow">Step 3 of 7</span><h2>Where do you stand?</h2><p class="muted">Topic: “${esc(d.topic)}”</p></div>`;
    s += `<div class="field"><label>Are you for or against it?</label>${seg("stance", "draft", [["for", "For"], ["against", "Against"], ["unsure", "Not sure yet"]], d.stance)}</div>`;
    s += `<div class="field"><label for="thesis">Your position, in one sentence</label><textarea id="thesis" data-input="thesis" placeholder="Say it the way you'd say it to a friend">${esc(d.thesis)}</textarea><span class="hint">This is the roof of your tower. Everything else has to hold it up.</span></div>`;
    return s + nav(true, "Next", "next-step", !d.thesis.trim());
  }

  function stepReasons(d) {
    const roots = d.claims.filter((c) => !c.parent);
    let s = `<div><span class="eyebrow">Step 4 of 7</span><h2>Why do you think so?</h2><p class="muted">List the reasons your position rests on, and how much it depends on each. Facts first: there's no point arguing whether something is good until you agree it exists.</p></div>`;
    roots.forEach((c, i) => { s += claimEditor(d, c, String(i + 1)); });
    s += `<div class="row"><button type="button" data-action="add-reason">Add a reason</button><span class="hint">${roots.length ? roots.length + " so far. Most strong arguments have three to five." : "Start with your strongest one."}</span></div>`;
    return s + nav(true, "Next", "next-step", !roots.some((c) => c.text.trim()));
  }

  function stepSupport(d) {
    const roots = d.claims.filter((c) => !c.parent);
    let s = `<div><span class="eyebrow">Step 5 of 7</span><h2>What holds each reason up?</h2><p class="muted">Add your sources, the points underneath, and the best argument against each one. Be honest: a belief cloud is allowed, it just doesn't hold much.</p></div>`;
    roots.forEach((c, i) => { s += claimEditor(d, c, String(i + 1), { full: true, removable: false }); });
    return s + nav(true);
  }

  function stepFamiliarity(d) {
    let s = `<div><span class="eyebrow">Step 6 of 7</span><h2>How familiar are you with each of these?</h2><p class="muted">Not whether it's true, just how much you've looked into it.</p></div>`;
    for (const o of ordered(d)) {
      if (!o.claim.text.trim()) continue;
      s += `<div class="survey-item"><p class="q"><span class="mono">${esc(o.label)}</span> ${esc(o.claim.text)}</p>${spectrum(o.claim)}</div>`;
    }
    return s + nav(true);
  }

  function stepConfidence(d) {
    let s = `<div><span class="eyebrow">Step 7 of 7</span><h2>How sure are you that each is true?</h2><p class="muted">0% is “probably not”, 100% is “certain”. Your conviction is part of the structure: opponents push hardest on what you're unsure of.</p></div>`;
    for (const o of ordered(d)) {
      if (!o.claim.text.trim()) continue;
      s += `<div class="survey-item"><p class="q"><span class="mono">${esc(o.label)}</span> ${esc(o.claim.text)}</p>${confidenceSlider(o.claim)}</div>`;
    }
    return s + nav(true, "Construct my argument", "construct");
  }

  // ---------------------------------------------------------------- views: map

  function viewMap() {
    const map = currentMap();
    if (!map) return `<div class="sheet"><h2>No map open</h2><p class="muted">Build one, or open the example.</p><div class="row"><button class="primary" data-action="start">Build my argument</button><button data-action="open-map" data-id="${example.id}">Open the example</button></div></div>`;
    const ev = M.evaluate(map);
    const lab = labels(map);
    const readOnly = isExample(map);
    const stance = { for: "For", against: "Against", unsure: "Not sure yet" }[map.stance];

    let s = `<section class="map-head">
      <span class="eyebrow">${esc(map.topic && map.topic !== map.thesis ? "Topic: " + map.topic : "Your argument")}${map.author && map.author !== store.name ? " · by " + esc(map.author) : ""}</span>
      <div class="row"><h1>${esc(map.thesis || map.topic)}</h1><span class="pill accent">${stance}</span></div>
      <div class="scorebar"><span class="big mono">${map.claims.length ? pct(ev.score) : "–"}</span><span><strong>${esc(ev.gradeLabel)}.</strong> <span class="muted">${esc(ev.gradeLine)}</span></span>
        <span class="mono muted">LEAN ${ev.lean >= 0 ? "" : "−"}${Math.abs(ev.lean).toFixed(1)}° · LOAD ${ev.weight}</span></div>
      ${readOnly ? `<div class="notice"><strong>This is the example map.</strong><span>Try the stress tests, then <button class="quiet" data-action="copy-example">make an editable copy</button> or <button class="quiet" data-action="start">build your own</button>.</span></div>` : ""}
    </section>`;

    s += `<div class="map-grid"><div class="tower-panel">
      <div class="tower-frame" id="map-tower">${T.render(map, ev, { id: "map" })}</div>
      <div class="card tests"><h3>Test it</h3>
        <div class="row"><button data-action="test-wind" ${ui.testing ? "disabled" : ""}>Gust of wind</button><button data-action="test-quake" ${ui.testing ? "disabled" : ""}>Earthquake</button></div>
        <div class="field"><label>Send in an opponent</label><div class="chips">${M.PERSPECTIVES.map((p) =>
          `<button class="chip" data-action="test-combat" data-value="${p.id}" title="${esc(p.blurb)}" ${ui.testing ? "disabled" : ""}>${esc(p.label)}</button>`).join("")}</div></div>
        ${ui.testNote ? `<div class="notice ${ui.testNote.toppled ? "bad" : ui.testNote.fallen ? "warn" : "good"}" role="status"><strong>${esc(ui.testNote.title)}</strong><span>${esc(ui.testNote.body)}</span><div class="row"><button class="quiet" data-action="test-reset">Rebuild the tower</button></div></div>` : ""}
        ${ui.dialogue.length ? `<div class="dialogue" aria-live="polite">${ui.dialogue.map(bubble).join("")}</div>` : ""}
      </div>
    </div><div class="outline">`;

    s += diagnostics(map, ev, lab);
    s += `<div class="row"><h2>The structure</h2><span class="spacer"></span>${readOnly ? "" : `<button data-action="add-reason-map">Add a reason</button>`}</div>`;
    for (const o of ordered(map)) s += claimCard(map, ev, o, readOnly);

    s += `<section class="card"><h3>What you know against how sure you are</h3>
      <p class="muted">Top left is the termite zone: very sure, little research. Bottom right is humble: you know more than you're claiming.</p>
      ${T.knowledgeChart(map, M.knowledgeReport(map), (id) => lab[id] || "")}</section>`;

    if (!readOnly) s += shareCard(map);
    else s += `<section class="card"><h3>See a comparison</h3><p class="muted">Sam rated this example map. See where they agree and where the conversation should start.</p><div class="row"><button data-action="demo-compare">Compare with Sam</button></div></section>`;

    if (!readOnly) {
      s += `<section class="card"><h3>This map</h3><div class="row">
        <button data-action="edit-position">Change the position or sources</button>
        ${ui.confirmDelete ? `<span>Delete this map for good?</span><button class="danger" data-action="delete-map">Delete</button><button data-action="cancel-delete">Keep it</button>` : `<button class="quiet danger" data-action="ask-delete">Delete this map</button>`}
      </div></section>`;
    }
    s += `</div></div>`;
    return s;
  }

  function bubble(line) {
    if (line.who === "them") return `<div class="bubble them"><strong>${esc(line.label)}</strong>${esc(line.text)}</div>`;
    return `<div class="bubble narrator">${esc(line.text)}</div>`;
  }

  function diagnostics(map, ev, lab) {
    const f = ev.flags;
    const byId = Object.fromEntries(map.claims.map((c) => [c.id, c]));
    const list = (ids) => ids.map((id) => `<span class="mono">${esc(lab[id] || "?")}</span> ${esc(M.short(byId[id].text, 70))}`).join("<br>");
    const notes = [];
    if (!map.claims.length) notes.push(`<div class="notice">Add your first reason to raise a pillar.</div>`);
    if (f.termites.length) notes.push(`<div class="notice bad"><strong>Termites</strong><span>You're very sure of these but said you haven't looked into them much. They're hollow until you do.</span><span>${list(f.termites)}</span></div>`);
    if (f.unsupported.length) notes.push(`<div class="notice warn"><strong>Nothing underneath</strong><span>No sources you trust, no supporting points, no belief cloud. These are floating.</span><span>${list(f.unsupported)}</span></div>`);
    if (f.headInClouds) notes.push(`<div class="notice warn"><strong>Head in the clouds</strong><span>${f.clouds} of your claims rest on belief alone. That's a lot of sky for one building.</span></div>`);
    if (f.cherryPicking) notes.push(`<div class="notice warn"><strong>Only good news?</strong><span>You haven't written down a single point against your own argument. If you only collect facts that agree with you, the tower looks sturdier than it is.</span></div>`);
    if (f.unansweredCounters) notes.push(`<div class="notice"><strong>${f.unansweredCounters} unanswered counter-argument${f.unansweredCounters === 1 ? "" : "s"}</strong><span>Each one leans on its pillar until you have an answer.</span></div>`);
    if (f.humble.length) notes.push(`<div class="notice good"><strong>You know more than you're claiming</strong><span>${list(f.humble)}</span></div>`);
    if (!notes.length) notes.push(`<div class="notice good"><strong>No obvious weak spots.</strong><span>Try an opponent to see it from the other side.</span></div>`);
    return `<section class="diag"><h2>What to shore up</h2>${notes.join("")}</section>`;
  }

  function claimCard(map, ev, o, readOnly) {
    const c = o.claim, r = ev.claims[c.id];
    if (ui.editing === c.id && !readOnly) {
      return claimEditor(map, c, o.label, { full: true }) .replace(/<\/section>/, `<div class="row"><span class="hint">How sure are you?</span></div>${confidenceSlider(c)}<div class="field"><label>How familiar are you with it?</label>${spectrum(c)}</div><div class="row end"><button class="primary" data-action="done-edit">Done</button></div></section>`);
    }
    const fam = M.FAMILIARITY.find((f) => f.value === c.familiarity);
    const width = r ? Math.min(100, Math.round(r.stability * 100)) : 0;
    let s = `<article class="claim-card${o.depth ? " sub" : ""}" data-claim="${esc(c.id)}">
      <div class="head"><span class="num">${esc(o.label)}</span><span class="text">${esc(c.text || "(no words yet)")}</span>${statusPill(r)}</div>
      <div class="meter" title="Stability ${r ? pct(r.stability) : ""}"><i class="${r ? r.status : "failing"}" style="width:${width}%"></i></div>
      <div class="meta"><span class="mono">${r && r.tier ? r.tier : "no sources"}</span><span>weight ${c.importance}/5</span><span>${c.confidence}% sure</span><span>${esc(fam ? fam.label : "")}</span>
      ${r && r.termites ? `<span class="pill failing">termites</span>` : ""}${c.cloud ? `<span class="pill neutral">belief cloud</span>` : ""}${c.votes ? `<span>${c.votes} agree</span>` : ""}</div>`;
    if (c.sources.length) {
      s += `<ul class="sources">` + c.sources.map((src) => {
        const t = map.trust[src.kind] || "unfamiliar";
        const label = src.url ? `<a href="${esc(src.url)}" target="_blank" rel="noopener">${esc(src.title || "Untitled source")}</a>` : esc(src.title || "Untitled source");
        return `<li class="${t === "distrust" ? "gone" : ""}">${label} <span class="muted">· ${esc(M.kindLabel(src.kind).toLowerCase())}${src.lean !== "neutral" ? ", " + src.lean + "-leaning" : ""}${t === "distrust" ? " · you don't trust these" : ""}</span></li>`;
      }).join("") + `</ul>`;
    }
    if (c.counters.some((k) => k.text.trim())) {
      s += `<ul class="counters">` + c.counters.filter((k) => k.text.trim()).map((k) =>
        `<li><strong>${k.answered ? "Answered:" : "Against:"}</strong> ${esc(k.text)} <span class="muted mono">(${k.strength}/5)</span></li>`).join("") + `</ul>`;
    }
    if (!readOnly) {
      s += `<div class="row"><button class="quiet" data-action="edit-claim" data-id="${esc(c.id)}">Edit</button>` +
        (o.depth < 2 ? `<button class="quiet" data-action="add-sub-map" data-id="${esc(c.id)}">Add a supporting point</button>` : "") +
        `<span class="spacer"></span><button class="quiet danger" data-action="remove-claim-map" data-id="${esc(c.id)}">Remove</button></div>`;
    }
    return s + `</article>`;
  }

  function shareCard(map) {
    let code = "";
    try { code = M.encodeMap({ ...map, author: store.name || map.author }); } catch (e) { code = ""; }
    return `<section class="card" id="share"><h3>Send it to a friend</h3>
      <p class="muted">They paste the code into Map My Argument (on the web or the iPhone app), rate each of your claims, and send theirs back. Then you'll see exactly where you agree.</p>
      <div class="field"><label for="your-name">Your name, so they know who it's from</label><input type="text" id="your-name" data-input="name" value="${esc(store.name)}" placeholder="First name is fine"></div>
      <div class="share-code" tabindex="0" aria-label="Share code">${esc(code)}</div>
      <div class="row"><button class="primary" data-action="copy-code">Copy the code</button><span class="hint mono">${code.length.toLocaleString()} characters</span></div>
      <div class="field"><label for="reply-in">Paste their answer</label><textarea id="reply-in" placeholder="MMA1.…"></textarea></div>
      ${ui.codeError ? `<div class="notice bad" role="alert">${esc(ui.codeError)}</div>` : ""}
      <div class="row"><button data-action="open-reply">Compare</button></div>
    </section>`;
  }

  // ---------------------------------------------------------------- views: rate a friend's map

  function viewRate() {
    const r = ui.rate;
    if (!r) return `<div class="sheet"><h2>Nothing to rate</h2><p class="muted">Paste a friend's code on the home page.</p><button data-action="home">Go home</button></div>`;
    const theirs = r.theirs, mine = r.mine;
    const who = theirs.author || "Your friend";
    let s = `<div class="sheet"><div><span class="eyebrow">Rating ${esc(who)}'s argument</span><h2>“${esc(theirs.thesis || theirs.topic)}”</h2></div>`;
    if (ui.rateStep === 0) {
      s += `<p class="muted">First, which sources do you trust? ${esc(who)} will see where your trust differs.</p><div class="trust-grid">` +
        M.SOURCE_KINDS.map((k) => `<div class="trust-row"><span>${esc(k.label)}</span>${seg("rate-trust", k.id, [["trust", "Trust"], ["unfamiliar", "Not sure"], ["distrust", "Don't trust"]], mine.trust[k.id] || "unfamiliar", "trust")}</div>`).join("") + `</div>`;
      s += `<div class="field"><label>Where do you stand on the topic?</label>${seg("rate-stance", "mine", [["for", "For"], ["against", "Against"], ["unsure", "Not sure yet"]], mine.stance)}</div>`;
      s += `<div class="row"><span class="spacer"></span><button class="primary" data-action="rate-next">Rate their claims</button></div>`;
    } else if (ui.rateStep === 1) {
      s += `<p class="muted">For each claim: how sure are you it's true, and how much do you know about it?</p>`;
      const lab = labels(theirs);
      for (const o of ordered(theirs)) {
        const c = mine.claims.find((x) => x.id === o.claim.id);
        s += `<div class="survey-item"><p class="q"><span class="mono">${esc(o.label)}</span> ${esc(o.claim.text)}</p>`;
        if (o.claim.sources.length) s += `<p class="hint">Their sources: ${o.claim.sources.map((x) => esc(x.title || M.kindLabel(x.kind))).join(" · ")}</p>`;
        s += confidenceSlider(c) + spectrum(c) + `</div>`;
        void lab;
      }
      s += `<div class="row"><button data-action="rate-back">Back</button><span class="spacer"></span><button class="primary" data-action="rate-next">Next</button></div>`;
    } else {
      const own = mine.claims.filter((c) => !theirs.claims.some((t) => t.id === c.id));
      s += `<p class="muted">Anything they left out? Add your own reasons (optional).</p>`;
      own.forEach((c, i) => { s += claimEditor(mine, c, "+" + (i + 1), { textOnly: false }) + confidenceSlider(c); });
      s += `<div class="row"><button data-action="rate-add">Add a reason of my own</button></div>`;
      s += `<div class="row"><button data-action="rate-back">Back</button><span class="spacer"></span><button class="primary" data-action="rate-finish">See where we agree</button></div>`;
    }
    return s + `</div>`;
  }

  // ---------------------------------------------------------------- views: compare

  function viewCompare() {
    const cmp = ui.compare;
    if (!cmp) return `<div class="sheet"><h2>Nothing to compare</h2><p class="muted">Paste a friend's answer under your map's “Send it to a friend”.</p><button data-action="home">Go home</button></div>`;
    const mine = cmp.mine, theirs = cmp.theirs;
    const res = M.compare(mine, theirs);
    const them = theirs.author || "your friend";
    const Them = them.charAt(0).toUpperCase() + them.slice(1);
    const me = cmp.meLabel || "You";
    const byMine = Object.fromEntries(mine.claims.map((c) => [c.id, c]));
    const byTheirs = Object.fromEntries(theirs.claims.map((c) => [c.id, c]));
    const lab = labels(mine);
    const stance = { for: "for", against: "against", unsure: "not sure" };

    let s = `<section class="map-head"><span class="eyebrow">Comparison</span><h1>${esc(me)} and ${esc(them)}</h1>
      <p class="muted">“${esc(mine.thesis || mine.topic)}”. ${esc(me)} ${me === "You" ? "are" : "is"} ${stance[mine.stance]}; ${esc(Them)} is ${stance[theirs.stance]}.</p></section>`;
    s += `<div class="versus">
      <div class="stat"><b class="mono">${res.agreeCount}</b><span>claims you agree on</span></div>
      <div class="stat"><b class="mono">${res.disagreeCount}</b><span>one of you thinks is false</span></div>
      <div class="stat"><b class="mono">${res.degreeCount}</b><span>agree, but not how sure</span></div>
      <div class="stat"><b class="mono">${res.onlyTheirs.length}</b><span>reasons only ${esc(them)} gave</span></div>
    </div>`;

    if (res.queue.length) {
      const i = Math.min(ui.queueIndex, res.queue.length - 1);
      const item = res.queue[i];
      const prompt = {
        disagree: "One of you thinks this is true and the other doesn't. Put your sources side by side and settle the facts before arguing about what follows from them.",
        degree: "You agree it's true, but not how sure to be. What would it take to move either of you?",
        bothDoubt: "Neither of you is convinced. Is it worth keeping in the argument at all?",
        agree: "You agree on this. Can you agree on a source for it, too?",
      }[item.kind];
      s += `<section class="sheet"><span class="eyebrow">Talk it through · ${i + 1} of ${res.queue.length}${item.depth ? " · a foundation" : ""}</span>
        <h2><span class="mono">${esc(lab[item.mine] || "")}</span> ${esc(item.text)}</h2>
        <div class="duel"><div class="side"><span class="muted">${esc(me)}</span><span class="mono">${item.myConfidence}% sure</span>${sourcesLine(byMine[item.mine])}</div>
        <div class="side"><span class="muted">${esc(Them)}</span><span class="mono">${item.theirConfidence}% sure</span>${sourcesLine(byTheirs[item.theirs])}</div></div>
        <p>${esc(prompt)}</p>
        ${item.conflicts.map((cf) => `<div class="notice warn">${cf.side === "mine" ? esc(Them) + " doesn't trust " : esc(me) + (me === "You" ? " don't" : " doesn't") + " trust "}${esc(M.kindLabel(cf.kind).toLowerCase())}s, and this rests on one. Is there a source you both trust?</div>`).join("")}
        ${res.queue.length > 1 ? `<div class="row"><button data-action="queue-prev" ${i === 0 ? "disabled" : ""}>Previous</button><button class="primary" data-action="queue-next" ${i >= res.queue.length - 1 ? "disabled" : ""}>Next disagreement</button></div>` : ""}
      </section>`;
    } else {
      s += `<div class="notice good"><strong>Nothing to argue about here.</strong><span>You agree on every claim you share.</span></div>`;
    }

    s += `<section class="card"><h3>Claim by claim</h3><div class="table-wrap"><table class="split-table"><thead><tr><th></th><th>Claim</th><th class="mono">${esc(me)}</th><th class="mono">${esc(them)}</th><th></th></tr></thead><tbody>` +
      res.items.map((it) => `<tr><td class="mono">${esc(lab[it.mine] || "")}</td><td>${esc(M.short(it.text, 90))}</td><td class="mono">${it.myConfidence}%</td><td class="mono">${it.theirConfidence}%</td><td>${kindPill(it.kind)}</td></tr>`).join("") +
      `</tbody></table></div></section>`;

    if (res.onlyTheirs.length) {
      s += `<section class="card"><h3>Reasons only ${esc(them)} gave</h3><ul class="sources">` + res.onlyTheirs.map((id) => {
        const c = byTheirs[id];
        return `<li>${esc(c.text)} <span class="muted mono">${c.confidence}% sure</span>${cmp.canAdopt ? ` <button class="quiet" data-action="adopt" data-id="${esc(id)}">Add to my map</button>` : ""}</li>`;
      }).join("") + `</ul></section>`;
    }
    if (res.onlyMine.length) {
      s += `<section class="card"><h3>Reasons only ${esc(me === "You" ? "you" : me)} gave</h3><ul class="sources">` +
        res.onlyMine.map((id) => `<li>${esc(byMine[id].text)}</li>`).join("") + `</ul></section>`;
    }
    if (res.trustSplit.length) {
      s += `<section class="card"><h3>Where your trust in sources differs</h3><div class="table-wrap"><table class="split-table"><thead><tr><th>Source</th><th>${esc(me)}</th><th>${esc(them)}</th></tr></thead><tbody>` +
        res.trustSplit.map((t) => `<tr><td>${esc(M.kindLabel(t.kind))}</td><td>${trustWord(t.mine)}</td><td>${trustWord(t.theirs)}</td></tr>`).join("") + `</tbody></table></div></section>`;
    }
    if (cmp.canAdopt) {
      const counted = mine.counted.includes(theirs.id);
      s += `<section class="card"><h3>Count their agreement</h3><p class="muted">Each claim ${esc(them)} agrees with gets one more vote, which makes it a little broader and steadier.</p>
        <div class="row"><button data-action="count-votes" ${counted ? "disabled" : ""}>${counted ? "Already counted" : "Count it"}</button><button class="quiet" data-action="open-map" data-id="${esc(mine.id)}">Back to my map</button></div></section>`;
    }
    if (cmp.replyCode) {
      s += `<section class="card"><h3>Send your answers back</h3><p class="muted">Give this code to ${esc(theirs.author || "them")} so they can see the comparison too.</p>
        <div class="share-code" tabindex="0">${esc(cmp.replyCode)}</div><div class="row"><button class="primary" data-action="copy-reply">Copy the code</button></div></section>`;
    }
    return s;
  }

  function sourcesLine(c) {
    if (!c || !c.sources.length) return `<span class="hint">No sources given</span>`;
    return `<span class="hint">${c.sources.map((x) => esc(x.title || M.kindLabel(x.kind))).join(" · ")}</span>`;
  }

  function kindPill(kind) {
    return {
      agree: `<span class="pill solid">agree</span>`, bothDoubt: `<span class="pill neutral">both doubt</span>`,
      degree: `<span class="pill strained">how sure</span>`, disagree: `<span class="pill failing">disagree</span>`,
    }[kind];
  }

  function trustWord(t) {
    return { trust: "Trusts", unfamiliar: "Not sure", distrust: "Doesn't trust" }[t];
  }

  // ---------------------------------------------------------------- views: how it's scored

  function viewHow() {
    const k = M.K;
    return `<article class="sheet" style="max-width:760px"><span class="eyebrow">The rules</span><h1>How the tower is scored</h1>
      <p>Every number comes from what you entered. Nothing is judged by what you believe, only by how well it's held up.</p>
      <h2>Strength of a claim</h2>
      <p>Support comes from three places, added together and capped at 100%:</p>
      <ul>
        <li><strong>Sources.</strong> One counts as ${pct(k.tierValue[1])} (I), two as ${pct(k.tierValue[2])} (II), three or more independent ones as ${pct(k.tierValue[3])} (IXI). A source you don't trust counts for nothing, one you're unsure of counts ${pct(k.trustWeight.unfamiliar)} as much, and two with the same title count once.</li>
        <li><strong>Supporting points.</strong> Each passes up half of its own strength, scaled by how much the point above depends on it.</li>
        <li><strong>A belief cloud</strong> adds ${pct(k.cloudSupport)}.</li>
      </ul>
      <p>People who agree add up to ${pct(k.voteCap)}. Each unanswered counter-argument takes away ${k.counterUnanswered * 100}% per point of its strength (1 to 5); an answered one takes ${k.counterAnswered * 100}%.</p>
      <p>Then your conviction counts: the total is multiplied by ${k.confidenceFloor} plus ${(1 - k.confidenceFloor).toFixed(1)} × how sure you are. If you're ${k.termiteConfidence}% sure or more but rated your familiarity ${k.termiteFamiliarity} or less, termites eat ${pct(1 - k.termiteFactor)} of it.</p>
      <h2>Weight to carry</h2>
      <p>A claim your position leans on heavily has more to hold up: ${k.demandBase} + ${k.demandStep} × its importance (1 to 5). Stability is strength divided by that weight. At 100% or more it's <strong>solid</strong>, from 60% <strong>strained</strong>, from ${pct(k.fallThreshold)} <strong>sagging</strong>, and below that it's <strong>failing</strong>: in any stress test it falls.</p>
      <h2>The whole tower</h2>
      <p>The score is the average stability of your top-level reasons (capped at 100% each), weighted by importance. 85% and up is a fortress, 65% solid, 45% leaning, 25% sagging, and below 25% it topples. The tower leans toward whichever half has the weaker pillars.</p>
      <h2>Stress tests</h2>
      <ul>
        <li><strong>Wind</strong> blows every belief cloud away.</li>
        <li><strong>An earthquake</strong> shakes everything to ${pct(k.quakeShake)} of its strength and collapses anything with termites.</li>
        <li><strong>An opponent</strong> throws out the sources it doesn't trust, knocks out the premises you said it would reject, then pushes on every claim you're less than ${k.lowConviction}% sure of (down to ${pct(k.convictionPressure)}).</li>
      </ul>
      <h2>Comparing</h2>
      <p>A friend's rating keeps your claims, so they line up exactly. Maps built separately are matched by wording. The conversation starts at the foundations: there's no point arguing whether something is good until you agree it exists.</p>
      <div class="row"><button class="primary" data-action="start">Build my argument</button></div>
    </article>`;
  }

  // ---------------------------------------------------------------- rendering

  function route() {
    const h = location.hash.replace(/^#/, "");
    if (h.startsWith("m=")) {
      try {
        const map = M.decodeMap("MMA1." + h.slice(2).replace(/^MMA1\./, ""));
        history.replaceState(null, "", "#rate");
        receive(map);
        return;
      } catch (e) { ui.codeError = e.message; }
    }
    ui.view = ["build", "map", "rate", "compare", "how"].includes(h) ? h : "home";
    render();
  }

  function render(keepScroll) {
    const main = $("#main");
    const active = document.activeElement;
    const key = active && active.dataset ? [active.id, active.dataset.action, active.dataset.id, active.dataset.value].join("|") : "";
    const y = window.scrollY;
    main.innerHTML = { home: viewHome, build: viewBuild, map: viewMap, rate: viewRate, compare: viewCompare, how: viewHow }[ui.view]();
    document.querySelectorAll(".top nav a").forEach((a) => a.setAttribute("aria-current", a.getAttribute("href") === "#" + ui.view ? "page" : "false"));
    if (keepScroll) window.scrollTo(0, y);
    if (key && key !== "|||") {
      const [id, action, did, value] = key.split("|");
      let el = id ? document.getElementById(id) : null;
      if (!el && action) el = [...document.querySelectorAll(`[data-action="${action}"]`)].find((e) => (e.dataset.id || "") === did && (e.dataset.value || "") === value);
      if (el) el.focus({ preventScroll: true });
    }
  }

  function rerender() { render(true); }

  // ---------------------------------------------------------------- actions

  function editingMap() {
    if (ui.view === "build") return ui.draft;
    if (ui.view === "rate") return ui.rate && ui.rate.mine;
    const m = currentMap();
    return m && !isExample(m) ? m : null;
  }

  function persist(map) {
    if (!map) return;
    if (ui.view === "build") save();
    else if (ui.view === "map") upsert(map);
  }

  function findClaim(map, id) { return map && map.claims.find((c) => c.id === id); }

  function removeClaimTree(map, id) {
    const doomed = new Set([id]);
    let grew = true;
    while (grew) {
      grew = false;
      for (const c of map.claims) if (c.parent && doomed.has(c.parent) && !doomed.has(c.id)) { doomed.add(c.id); grew = true; }
    }
    map.claims = map.claims.filter((c) => !doomed.has(c.id));
  }

  function receive(map) {
    ui.codeError = "";
    const mineOriginal = store.maps.find((m) => m.id === map.basedOn && !m.basedOn);
    if (mineOriginal) {
      // Their answer to one of my maps.
      openCompare(mineOriginal, map, { canAdopt: true });
      return;
    }
    if (store.maps.some((m) => m.id === map.id)) {
      ui.current = map.id;
      save();
      go("map");
      toast("You already have this map");
      return;
    }
    // Someone else's map: rate it.
    const mine = M.normalize({
      ...map, id: M.newId("map"), basedOn: map.id, author: store.name, trust: { ...store.trust }, stance: "unsure",
      counted: [], created: now(), updated: now(),
      claims: map.claims.map((c) => ({ ...c, confidence: 50, familiarity: 3, votes: 0, counters: [], disputedBy: [], cloud: false, sources: [] })),
    });
    ui.rate = { theirs: map, mine };
    ui.rateStep = 0;
    go("rate");
  }

  function openCompare(mine, theirs, extra) {
    ui.compare = { mine, theirs, meLabel: "You", ...extra };
    ui.queueIndex = 0;
    go("compare");
  }

  function readCode(text) {
    try {
      return M.decodeMap(text);
    } catch (e) {
      ui.codeError = e.message;
      rerender();
      return null;
    }
  }

  async function runTest(kind, value) {
    const map = currentMap();
    if (!map || ui.testing) return;
    ui.testing = true;
    ui.dialogue = [];
    ui.testNote = null;
    rerender();
    const svg = $("#map-tower svg");
    const lab = labels(map);
    const byId = Object.fromEntries(map.claims.map((c) => [c.id, c]));
    let outcome;
    if (kind === "wind") {
      outcome = M.windTest(map);
      await T.animateWind(svg, map, outcome);
    } else if (kind === "quake") {
      outcome = M.earthquakeTest(map);
      await T.animateQuake(svg, map, outcome);
    } else {
      outcome = M.combat(map, value);
      const lines = M.combatLines(map, outcome).map((l) => ({ ...l, label: "The " + outcome.label }));
      const box = () => {
        let d = $("#main .dialogue");
        if (!d) {
          d = document.createElement("div");
          d.className = "dialogue";
          d.setAttribute("aria-live", "polite");
          $("#main .tests").appendChild(d);
        }
        return d;
      };
      for (let phase = 0; phase <= 3; phase++) {
        for (const l of lines.filter((x) => x.phase === phase)) {
          ui.dialogue.push(l);
          box().insertAdjacentHTML("beforeend", bubble(l));
          box().scrollTop = 1e6;
          await new Promise((r) => setTimeout(r, matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 650));
        }
        if (phase < 3) await T.animateCombatStep(svg, map, outcome, phase);
      }
    }
    const names = outcome.fallen.map((id) => `${lab[id]} “${M.short(byId[id].text, 40)}”`);
    const title = { wind: "After the wind", quake: "After the earthquake" }[kind] || `After the ${outcome.label.toLowerCase()}`;
    ui.testNote = {
      title: outcome.toppled ? `${title}: it toppled` : `${title}: ${pct(outcome.after)} stable (was ${pct(outcome.before)})`,
      body: names.length ? `${names.length === 1 ? "This fell" : "These fell"}: ${names.join("; ")}.` : "Nothing fell.",
      fallen: names.length, toppled: outcome.toppled,
    };
    // Show the note without redrawing the fallen tower.
    const tests = $("#main .tests");
    const note = document.createElement("div");
    note.className = `notice ${outcome.toppled ? "bad" : names.length ? "warn" : "good"}`;
    note.setAttribute("role", "status");
    note.innerHTML = `<strong>${esc(ui.testNote.title)}</strong><span>${esc(ui.testNote.body)}</span><div class="row"><button class="quiet" data-action="test-reset">Rebuild the tower</button></div>`;
    tests.insertBefore(note, $(".dialogue", tests));
    tests.querySelectorAll("button[data-action^='test-']:not([data-action='test-reset'])").forEach((b) => { b.disabled = true; });
  }

  async function homeTest(kind) {
    if (ui.homeTest) return;
    ui.homeTest = true;
    document.querySelectorAll("[data-action='home-wind'], [data-action='home-quake']").forEach((b) => { b.disabled = true; });
    const svg = $("#home-tower svg");
    if (kind === "wind") await T.animateWind(svg, example, M.windTest(example));
    else await T.animateQuake(svg, example, M.earthquakeTest(example));
  }

  const actions = {
    home: () => go("home"),
    start: () => {
      ui.draft = newMap("");
      ui.step = 0;
      save();
      go("build");
    },
    resume: () => go("build"),
    "open-map": (el) => {
      ui.current = el.dataset.id;
      ui.editing = null; ui.testing = false; ui.testNote = null; ui.dialogue = []; ui.confirmDelete = false; ui.codeError = "";
      save();
      go("map");
      window.scrollTo(0, 0);
    },
    "copy-example": () => {
      const copyMap = M.normalize({ ...example, id: M.newId("map"), author: store.name, created: now(), updated: now() });
      copyMap.claims = copyMap.claims.map((c) => ({ ...c }));
      upsert(copyMap);
      ui.current = copyMap.id;
      save();
      toast("Copied to your maps");
      rerender();
    },
    topic: (el) => {
      const d = ui.draft;
      if (!d.thesis.trim() || d.thesis === d.topic) d.thesis = el.dataset.value;
      d.topic = el.dataset.value;
      save();
      rerender();
    },
    "goto-step": (el) => { ui.step = Number(el.dataset.value); save(); render(); window.scrollTo(0, 0); },
    "next-step": () => {
      if (ui.step === 0 && !Object.keys(ui.draft.trust).length) ui.draft.trust = { ...store.trust };
      if (ui.step === 3 || ui.step === 4) ui.draft.claims = ui.draft.claims.filter((c) => c.text.trim() || c.sources.length);
      if (ui.step === 3 && !ui.draft.claims.length) return;
      ui.step = Math.min(STEPS.length - 1, ui.step + 1);
      save(); render(); window.scrollTo(0, 0);
    },
    "prev-step": () => { ui.step = Math.max(0, ui.step - 1); save(); render(); window.scrollTo(0, 0); },
    trust: (el) => { ui.draft.trust[el.dataset.id] = el.dataset.value; store.trust[el.dataset.id] = el.dataset.value; save(); rerender(); },
    stance: (el) => { ui.draft.stance = el.dataset.value; save(); rerender(); },
    "add-reason": () => {
      const c = newClaim(null);
      ui.draft.claims.push(c);
      save(); rerender();
      $(`#text-${CSS.escape(c.id)}`)?.focus();
    },
    "add-sub": (el) => {
      const map = editingMap();
      const c = newClaim(el.dataset.id);
      map.claims.push(c);
      persist(map); rerender();
      $(`#text-${CSS.escape(c.id)}`)?.focus();
    },
    importance: (el) => { const map = editingMap(); findClaim(map, el.dataset.id).importance = Number(el.dataset.value); persist(map); rerender(); },
    familiarity: (el) => { const map = editingMap(); findClaim(map, el.dataset.id).familiarity = Number(el.dataset.value); persist(map); rerender(); },
    "add-source": (el) => {
      const map = editingMap();
      const s = { id: M.newId("s"), title: "", url: "", kind: "news", lean: "neutral" };
      findClaim(map, el.dataset.id).sources.push(s);
      persist(map); rerender();
      $(`#st-${CSS.escape(s.id)}`)?.focus();
    },
    "remove-source": (el) => {
      const map = editingMap(), c = findClaim(map, el.dataset.id);
      c.sources = c.sources.filter((s) => s.id !== el.dataset.value);
      persist(map); rerender();
    },
    "remove-claim": (el) => { const map = editingMap(); removeClaimTree(map, el.dataset.id); persist(map); rerender(); },
    "counter-strength": (el) => { const map = editingMap(); findClaim(map, el.dataset.id).counters[0].strength = Number(el.dataset.value); persist(map); rerender(); },
    disputed: (el) => {
      const map = editingMap(), c = findClaim(map, el.dataset.id), p = el.dataset.value;
      c.disputedBy = c.disputedBy.includes(p) ? c.disputedBy.filter((x) => x !== p) : [...c.disputedBy, p];
      persist(map); rerender();
    },
    construct: () => {
      const d = ui.draft;
      d.claims = d.claims.filter((c) => c.text.trim());
      d.author = d.author || store.name;
      d.created = d.created || now();
      const map = M.normalize(d);
      upsert(map);
      ui.current = map.id;
      ui.draft = null;
      ui.step = 0;
      ui.testNote = null; ui.dialogue = []; ui.testing = false;
      save();
      go("map");
      window.scrollTo(0, 0);
      const svg = $("#map-tower svg");
      if (svg) svg.classList.add("rising");
    },
    "edit-claim": (el) => { ui.editing = el.dataset.id; rerender(); },
    "done-edit": () => { ui.editing = null; rerender(); },
    "add-reason-map": () => {
      const map = editingMap();
      const c = newClaim(null);
      map.claims.push(c);
      ui.editing = c.id;
      upsert(map); rerender();
      $(`#text-${CSS.escape(c.id)}`)?.focus();
    },
    "add-sub-map": (el) => {
      const map = editingMap();
      const c = newClaim(el.dataset.id);
      map.claims.push(c);
      ui.editing = c.id;
      upsert(map); rerender();
      $(`#text-${CSS.escape(c.id)}`)?.focus();
    },
    "remove-claim-map": (el) => { const map = editingMap(); removeClaimTree(map, el.dataset.id); upsert(map); rerender(); },
    "edit-position": () => {
      const map = currentMap();
      ui.draft = M.normalize(JSON.parse(JSON.stringify(map)));
      ui.step = 1;
      save();
      go("build");
    },
    "ask-delete": () => { ui.confirmDelete = true; rerender(); },
    "cancel-delete": () => { ui.confirmDelete = false; rerender(); },
    "delete-map": () => {
      store.maps = store.maps.filter((m) => m.id !== ui.current);
      ui.current = "";
      ui.confirmDelete = false;
      save();
      toast("Deleted");
      go("home");
    },
    "test-wind": () => runTest("wind"),
    "test-quake": () => runTest("quake"),
    "test-combat": (el) => runTest("combat", el.dataset.value),
    "test-reset": () => { ui.testing = false; ui.testNote = null; ui.dialogue = []; rerender(); },
    "home-wind": () => homeTest("wind"),
    "home-quake": () => homeTest("quake"),
    "home-reset": () => { ui.homeTest = false; rerender(); },
    "copy-code": () => copy(M.encodeMap({ ...currentMap(), author: store.name || currentMap().author }), "Code copied. Send it to a friend."),
    "copy-reply": () => copy(ui.compare.replyCode, "Code copied"),
    "open-code": () => {
      const map = readCode($("#code-in").value);
      if (map) receive(map);
    },
    "open-reply": () => {
      const reply = readCode($("#reply-in").value);
      if (!reply) return;
      const mine = currentMap();
      if (reply.basedOn !== mine.id && !M.compare(mine, reply).items.length) {
        ui.codeError = "That code doesn't seem to be about this map. Ask them to rate this map's code first.";
        rerender();
        return;
      }
      openCompare(mine, reply, { canAdopt: true });
    },
    "demo-compare": () => openCompare(example, exampleFriend, { meLabel: "Example", canAdopt: false }),
    "queue-next": () => { ui.queueIndex++; rerender(); },
    "queue-prev": () => { ui.queueIndex = Math.max(0, ui.queueIndex - 1); rerender(); },
    adopt: (el) => {
      const { mine, theirs } = ui.compare;
      const c = theirs.claims.find((x) => x.id === el.dataset.id);
      mine.claims.push({ ...c, id: M.newId("c"), parent: null, confidence: 50, votes: 1, counters: [], disputedBy: [] });
      upsert(mine);
      toast("Added to your map");
      rerender();
    },
    "count-votes": () => {
      const { mine, theirs } = ui.compare;
      const res = M.compare(mine, theirs);
      let n = 0;
      for (const it of res.items) {
        if (it.theirConfidence >= 50) { findClaim(mine, it.mine).votes += 1; n++; }
      }
      mine.counted.push(theirs.id);
      upsert(mine);
      toast(`${n} claim${n === 1 ? "" : "s"} got a vote`);
      rerender();
    },
    "rate-trust": (el) => { ui.rate.mine.trust[el.dataset.id] = el.dataset.value; store.trust[el.dataset.id] = el.dataset.value; save(); rerender(); },
    "rate-stance": (el) => { ui.rate.mine.stance = el.dataset.value; rerender(); },
    "rate-next": () => { ui.rateStep++; render(); window.scrollTo(0, 0); },
    "rate-back": () => { ui.rateStep = Math.max(0, ui.rateStep - 1); render(); window.scrollTo(0, 0); },
    "rate-add": () => { ui.rate.mine.claims.push(newClaim(null, { confidence: 70 })); rerender(); },
    "rate-finish": () => {
      const { theirs } = ui.rate;
      const mine = ui.rate.mine;
      mine.claims = mine.claims.filter((c) => c.text.trim());
      mine.author = store.name || "Friend";
      mine.thesis = mine.stance === theirs.stance ? theirs.thesis : (mine.stance === "unsure" ? "Not sure: " + theirs.topic : "Not convinced: " + (theirs.thesis || theirs.topic));
      upsert(mine);
      if (!store.maps.some((m) => m.id === theirs.id)) store.maps.push(M.normalize(theirs));
      save();
      ui.rate = null;
      const replyCode = M.encodeMap(mine);
      ui.compare = { mine, theirs, meLabel: "You", canAdopt: false, replyCode };
      ui.queueIndex = 0;
      go("compare");
    },
  };

  // Typing doesn't redraw, so the cursor stays put.
  function onInput(e) {
    const el = e.target;
    const what = el.dataset.input;
    if (!what) return;
    if (what === "name") { store.name = el.value; save(); return; }
    if (what === "topic") {
      const d = ui.draft;
      if (!d.thesis.trim() || d.thesis === d.topic) d.thesis = el.value;
      d.topic = el.value;
      save();
      const next = $("[data-action='next-step']");
      if (next) next.disabled = !el.value.trim();
      document.querySelectorAll("[data-action='topic']").forEach((b) => b.setAttribute("aria-pressed", "false"));
      return;
    }
    if (what === "thesis") {
      ui.draft.thesis = el.value;
      save();
      const next = $("[data-action='next-step']");
      if (next) next.disabled = !el.value.trim();
      return;
    }
    const map = editingMap();
    const c = findClaim(map, el.dataset.id);
    if (!c) return;
    if (what === "text") {
      c.text = el.value;
      const next = $("[data-action='next-step']");
      if (next && ui.view === "build" && ui.step === 3) next.disabled = !map.claims.some((x) => !x.parent && x.text.trim());
    } else if (what === "confidence") {
      c.confidence = Number(el.value);
      const out = el.parentElement.querySelector("output");
      if (out) out.textContent = el.value + "%";
    } else if (what.startsWith("src-")) {
      const s = c.sources.find((x) => x.id === el.dataset.src);
      if (s) s[{ "src-title": "title", "src-kind": "kind", "src-lean": "lean" }[what]] = el.value;
    } else if (what === "counter-text") {
      if (!c.counters.length) c.counters.push({ id: M.newId("x"), text: "", strength: 3, answered: false });
      const had = !!c.counters[0].text.trim();
      c.counters[0].text = el.value;
      if (!el.value.trim()) c.counters = [];
      if (had !== !!el.value.trim()) { persist(map); rerender(); return; }
    } else if (what === "cloud") {
      c.cloud = el.checked;
    } else if (what === "counter-answered") {
      if (c.counters[0]) c.counters[0].answered = el.checked;
    }
    persist(map);
  }

  function onChange(e) {
    // Selects and checkboxes fire change, not input, in some browsers. Ranges redraw the map once released.
    const el = e.target;
    if (el.tagName === "SELECT" || el.type === "checkbox") onInput(e);
    if (ui.view === "map" && (el.type === "range" || el.type === "checkbox" || el.tagName === "SELECT" || el.dataset.input === "text")) rerender();
  }

  function onClick(e) {
    const el = e.target.closest("[data-action]");
    if (!el || el.disabled) return;
    const fn = actions[el.dataset.action];
    if (fn) { e.preventDefault(); fn(el); }
  }

  document.addEventListener("click", onClick);
  document.addEventListener("input", onInput);
  document.addEventListener("change", onChange);
  window.addEventListener("hashchange", route);
  route();
})();

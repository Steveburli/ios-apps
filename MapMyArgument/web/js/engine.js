/*
 * Map My Argument: the scoring engine.
 *
 * Turns an argument map (a thesis held up by claims, which are held up by
 * sources, sub-claims and belief clouds) into a structure: how strong each
 * claim is, how much weight it has to carry, whether it stands, sags or falls,
 * and how the whole tower leans. The same rules live in Swift in
 * Packages/ArgumentKit (Engine.swift). Keep the two in step: the shared cases
 * in Packages/ArgumentKit/Tests/ArgumentKitTests/Fixtures/engine-cases.json
 * are checked by both test suites. ENGINE.md explains every number.
 *
 * Works as a plain <script> (defines window.MMA) and as a Node module.
 */
(function (root) {
  "use strict";

  // ---------------------------------------------------------------- vocabulary

  const SOURCE_KINDS = [
    { id: "study", label: "Peer-reviewed study" },
    { id: "government", label: "Government data" },
    { id: "news", label: "News report" },
    { id: "expert", label: "Expert or book" },
    { id: "reference", label: "Encyclopedia or reference" },
    { id: "advocacy", label: "Advocacy group" },
    { id: "social", label: "Social media post" },
    { id: "personal", label: "Personal experience" },
  ];

  const LEANS = [
    { id: "neutral", label: "Seen as neutral" },
    { id: "left", label: "Seen as left-leaning" },
    { id: "right", label: "Seen as right-leaning" },
  ];

  const TRUST = ["trust", "unfamiliar", "distrust"];

  const FAMILIARITY = [
    { value: 1, label: "I have no idea what that is" },
    { value: 2, label: "I've heard of it" },
    { value: 3, label: "I know the basics" },
    { value: 4, label: "I've read up on it" },
    { value: 5, label: "I've researched it thoroughly" },
  ];

  const PERSPECTIVES = [
    {
      id: "progressive", label: "Progressive",
      blurb: "Throws out right-leaning sources, then rejects the premises you said a progressive would.",
      distrustLeans: ["right"], distrustKinds: [],
    },
    {
      id: "conservative", label: "Conservative",
      blurb: "Throws out left-leaning sources, then rejects the premises you said a conservative would.",
      distrustLeans: ["left"], distrustKinds: [],
    },
    {
      id: "libertarian", label: "Libertarian",
      blurb: "Doesn't take government data on faith, then rejects the premises you said a libertarian would.",
      distrustLeans: [], distrustKinds: ["government"],
    },
    {
      id: "scientist", label: "Scientist",
      blurb: "Ignores anecdotes, social posts and advocacy groups, and blows away every belief cloud.",
      distrustLeans: [], distrustKinds: ["social", "personal", "advocacy"], removeClouds: true,
    },
    {
      id: "skeptic", label: "Skeptic",
      blurb: "Won't accept anything that rests on a single source, and ignores social posts.",
      distrustLeans: [], distrustKinds: ["social"], singleSourceCountsZero: true,
    },
  ];

  // ---------------------------------------------------------------- the numbers (see ENGINE.md)

  const K = {
    trustWeight: { trust: 1, unfamiliar: 0.7, distrust: 0 },
    tierValue: [0, 0.45, 0.75, 1],          // 0, I, II, IXI independent sources
    cloudSupport: 0.35,                      // a belief cloud holds a claim up a little
    childShare: 0.5,                         // a sub-claim passes on half its strength × importance / 5
    voteStep: 0.05, voteCap: 0.15,           // agreement from other people
    counterUnanswered: 0.05, counterAnswered: 0.01, // per point of counter-argument strength
    confidenceFloor: 0.6,                    // strength × (0.6 + 0.4 × confidence / 100)
    termiteFactor: 0.7,                      // sure of it but haven't looked into it
    termiteConfidence: 70, termiteFamiliarity: 2,
    humbleConfidence: 35, humbleFamiliarity: 4,
    demandBase: 0.2, demandStep: 0.14,       // weight to carry = 0.2 + 0.14 × importance
    fallThreshold: 0.35,
    quakeShake: 0.8,
    lowConviction: 50, convictionPressure: 0.75,
    leanScale: 24, leanMax: 20, singleLean: 12,
  };

  const STATUS = [
    { min: 1, id: "solid", label: "Solid" },
    { min: 0.6, id: "strained", label: "Strained" },
    { min: K.fallThreshold, id: "sagging", label: "Sagging" },
    { min: -Infinity, id: "failing", label: "Failing" },
  ];

  const GRADES = [
    { min: 0.85, id: "fortress", label: "Fortress", line: "Broad foundations. This one can take a hit." },
    { min: 0.65, id: "solid", label: "Solid", line: "It stands, with a few soft spots worth shoring up." },
    { min: 0.45, id: "leaning", label: "Leaning", line: "It's standing, but it leans toward its weakest pillars." },
    { min: 0.25, id: "sagging", label: "Sagging", line: "The roof is heavier than the foundations can carry." },
    { min: -Infinity, id: "toppled", label: "Toppled", line: "The weight of the claims is too much for the support under them." },
  ];

  // ---------------------------------------------------------------- helpers

  const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
  const clamp01 = (x) => clamp(x, 0, 1);
  const statusFor = (stability) => STATUS.find((s) => stability >= s.min).id;
  const gradeFor = (score) => GRADES.find((g) => score >= g.min);
  const demand = (importance) => K.demandBase + K.demandStep * clamp(importance, 1, 5);
  const trustOf = (map, kind) => (map.trust && map.trust[kind]) || "unfamiliar";

  function hasTermites(claim) {
    return (claim.confidence ?? 50) >= K.termiteConfidence && (claim.familiarity ?? 3) <= K.termiteFamiliarity;
  }

  function isHumble(claim) {
    return (claim.confidence ?? 50) <= K.humbleConfidence && (claim.familiarity ?? 3) >= K.humbleFamiliarity;
  }

  function normTitle(s) {
    return String(s || "").toLowerCase().replace(/\s+/g, " ").trim();
  }

  /** Roots are claims with no parent, or whose parent no longer exists. */
  function childrenIndex(map) {
    const ids = new Set(map.claims.map((c) => c.id));
    const kids = new Map();
    const roots = [];
    for (const c of map.claims) {
      if (c.parent && ids.has(c.parent) && c.parent !== c.id) {
        if (!kids.has(c.parent)) kids.set(c.parent, []);
        kids.get(c.parent).push(c);
      } else {
        roots.push(c);
      }
    }
    return { roots, kids };
  }

  function tierLabel(n) {
    return ["", "I", "II", "IXI"][Math.min(3, n)];
  }

  /**
   * The direct support a claim gets from its sources.
   * Distrusted sources count for nothing; duplicate titles count once; at most
   * three count (IXI is the top tier).
   */
  function sourceSupport(map, claim, opts) {
    const seen = new Set();
    const weights = [];
    const dropped = [];
    for (const s of claim.sources || []) {
      const key = normTitle(s.title) || s.id;
      if (seen.has(key)) continue;
      seen.add(key);
      let w = K.trustWeight[trustOf(map, s.kind)] ?? 0.7;
      if (opts.distrustKinds && opts.distrustKinds.includes(s.kind)) w = 0;
      if (opts.distrustLeans && opts.distrustLeans.includes(s.lean || "neutral")) w = 0;
      if (w > 0) weights.push(w);
      else dropped.push(s.id);
    }
    weights.sort((a, b) => b - a);
    const counted = weights.slice(0, 3);
    let n = counted.length;
    if (opts.singleSourceCountsZero && n === 1) n = 0;
    const avg = counted.length ? counted.reduce((a, b) => a + b, 0) / counted.length : 0;
    return { value: n ? K.tierValue[n] * avg : 0, count: n, tier: tierLabel(n), dropped };
  }

  function counterLoad(claim) {
    let load = 0;
    for (const c of claim.counters || []) {
      const s = clamp(c.strength ?? 3, 1, 5);
      load += s * (c.answered ? K.counterAnswered : K.counterUnanswered);
    }
    return load;
  }

  function voteBonus(votes) {
    if (!votes || votes <= 0) return 0;
    return Math.min(K.voteCap, K.voteStep * Math.log2(1 + votes));
  }

  // ---------------------------------------------------------------- evaluation

  /**
   * Scores every claim, bottom-up. Options (all optional) let the stress tests
   * and opponents change the world first:
   *   distrustKinds, distrustLeans  sources of these kinds or leans count for nothing
   *   singleSourceCountsZero        one source is no source
   *   removeClouds                  belief clouds hold nothing up
   *   removed                       claim ids knocked out entirely
   *   shake                         every claim's strength is multiplied by this
   *   collapseTermites              claims with termites fall outright
   *   lowConvictionPressure         claims under 50% confidence are multiplied by this
   *   fall                          claims whose stability drops below 0.35 fall,
   *                                 and fallen sub-claims hold nothing up
   */
  function evaluate(map, opts) {
    opts = opts || {};
    const { roots, kids } = childrenIndex(map);
    const removed = new Set(opts.removed || []);
    const results = {};

    function visit(claim, depth, ancestors) {
      if (ancestors.has(claim.id)) return null; // a cycle: ignore the loop
      const path = new Set(ancestors).add(claim.id);
      const children = (kids.get(claim.id) || []).map((k) => visit(k, depth + 1, path)).filter(Boolean);

      const src = sourceSupport(map, claim, opts);
      const cloud = claim.cloud && !opts.removeClouds ? K.cloudSupport : 0;
      let fromChildren = 0;
      for (const r of children) {
        if (!r.fallen) fromChildren += r.strength * (clamp(r.importance, 1, 5) / 5) * K.childShare;
      }
      const raw = src.value + cloud + fromChildren + voteBonus(claim.votes) - counterLoad(claim);
      const confidence = clamp(claim.confidence ?? 50, 0, 100);
      const termites = hasTermites(claim);
      let strength = clamp01(raw) * (K.confidenceFloor + (1 - K.confidenceFloor) * confidence / 100);
      if (termites) strength *= K.termiteFactor;
      if (opts.shake) strength *= opts.shake;
      if (opts.lowConvictionPressure && confidence < K.lowConviction) strength *= opts.lowConvictionPressure;

      const importance = clamp(claim.importance ?? 3, 1, 5);
      const stability = strength / demand(importance);
      let fallen = removed.has(claim.id);
      if (opts.collapseTermites && termites) fallen = true;
      if (opts.fall && stability < K.fallThreshold) fallen = true;

      const r = {
        id: claim.id, depth, importance,
        strength: fallen ? 0 : strength,
        stability: fallen ? 0 : stability,
        status: fallen ? "fallen" : statusFor(stability),
        tier: src.tier, sourceCount: src.count, droppedSources: src.dropped,
        cloud: !!claim.cloud && !opts.removeClouds,
        termites, humble: isHumble(claim),
        unsupported: src.count === 0 && !cloud && fromChildren === 0,
        unansweredCounters: (claim.counters || []).filter((c) => !c.answered).length,
        fallen,
        children: children.map((c) => c.id),
      };
      results[claim.id] = r;
      return r;
    }

    const rootResults = roots.map((c) => visit(c, 0, new Set())).filter(Boolean);
    return { claims: results, ...summarize(map, rootResults, results) };
  }

  function summarize(map, rootResults, all) {
    const total = rootResults.reduce((a, r) => a + r.importance, 0);
    const list = Object.values(all);
    if (!rootResults.length) {
      return {
        score: 0, grade: "empty", gradeLabel: "Empty lot", gradeLine: "Add a reason to start building.",
        lean: 0, weight: 0, toppled: false, flags: emptyFlags(),
      };
    }
    let score = 0;
    for (const r of rootResults) score += Math.min(1, r.stability) * r.importance;
    score /= total;

    let lean;
    if (rootResults.length === 1) {
      lean = (1 - score) * K.singleLean;
    } else {
      const half = Math.floor(rootResults.length / 2);
      const weak = (rs) => rs.reduce((a, r) => a + (1 - Math.min(1, r.stability)) * r.importance, 0);
      const left = weak(rootResults.slice(0, half));
      const right = weak(rootResults.slice(rootResults.length - half));
      lean = clamp((right - left) / total * K.leanScale, -K.leanMax, K.leanMax);
    }

    const g = gradeFor(score);
    const clouds = list.filter((r) => r.cloud).length;
    const counters = map.claims.reduce((a, c) => a + (c.counters || []).length, 0);
    return {
      score, grade: g.id, gradeLabel: g.label, gradeLine: g.line,
      lean, weight: total, toppled: score < GRADES[3].min,
      flags: {
        termites: list.filter((r) => r.termites && !r.fallen).map((r) => r.id),
        humble: list.filter((r) => r.humble).map((r) => r.id),
        unsupported: list.filter((r) => r.unsupported && !r.fallen).map((r) => r.id),
        headInClouds: clouds >= 2 && clouds / list.length > 1 / 3,
        clouds,
        cherryPicking: list.length >= 3 && counters === 0,
        unansweredCounters: list.reduce((a, r) => a + r.unansweredCounters, 0),
      },
    };
  }

  function emptyFlags() {
    return { termites: [], humble: [], unsupported: [], headInClouds: false, clouds: 0, cherryPicking: false, unansweredCounters: 0 };
  }

  // ---------------------------------------------------------------- stress tests

  function fallenIds(result) {
    return Object.values(result.claims).filter((r) => r.fallen).map((r) => r.id);
  }

  /** A gust of wind: belief clouds blow away, and whatever they held up may fall. */
  function windTest(map) {
    const before = evaluate(map);
    const after = evaluate(map, { removeClouds: true, fall: true });
    return {
      kind: "wind", before: before.score, after: after.score, result: after,
      fallen: fallenIds(after), toppled: after.toppled,
      blownAway: map.claims.filter((c) => c.cloud).map((c) => c.id),
    };
  }

  /** An earthquake: everything shakes, termite-eaten claims collapse, weak ones fall. */
  function earthquakeTest(map) {
    const before = evaluate(map);
    const after = evaluate(map, { shake: K.quakeShake, collapseTermites: true, fall: true });
    return {
      kind: "earthquake", before: before.score, after: after.score, result: after,
      fallen: fallenIds(after), toppled: after.toppled,
    };
  }

  /**
   * Perspective combat. The opponent (1) throws out the sources it doesn't
   * trust, (2) knocks out the premises you said it would reject, then (3)
   * leans on everything you aren't sure of. Each step is recorded so the
   * apps can play it back.
   */
  function combat(map, perspectiveId) {
    const p = PERSPECTIVES.find((x) => x.id === perspectiveId);
    if (!p) throw new Error("Unknown perspective " + perspectiveId);
    const base = {
      distrustKinds: p.distrustKinds, distrustLeans: p.distrustLeans,
      singleSourceCountsZero: !!p.singleSourceCountsZero, removeClouds: !!p.removeClouds,
    };
    const before = evaluate(map);

    const sourcesOut = [];
    const afterSources = evaluate(map, base);
    for (const c of map.claims) {
      const r = afterSources.claims[c.id];
      if (!r) continue;
      for (const sid of r.droppedSources) {
        const s = c.sources.find((x) => x.id === sid);
        // Sources the owner already distrusted were never counted, so the opponent can't take them.
        if (s && trustOf(map, s.kind) !== "distrust") sourcesOut.push({ claim: c.id, source: sid });
      }
      if (p.singleSourceCountsZero && r.sourceCount === 0 && (c.sources || []).length > 0 && !r.droppedSources.length) {
        sourcesOut.push({ claim: c.id, source: null, reason: "single" });
      }
    }
    const cloudsOut = p.removeClouds ? map.claims.filter((c) => c.cloud).map((c) => c.id) : [];

    const rejected = map.claims.filter((c) => (c.disputedBy || []).includes(p.id)).map((c) => c.id);
    const pressured = map.claims
      .filter((c) => !rejected.includes(c.id) && (c.confidence ?? 50) < K.lowConviction)
      .map((c) => c.id);

    const after = evaluate(map, {
      ...base, removed: rejected, lowConvictionPressure: K.convictionPressure, fall: true,
    });
    const fallen = fallenIds(after);
    return {
      kind: "combat", perspective: p.id, label: p.label,
      before: before.score, after: after.score, result: after, toppled: after.toppled,
      steps: [
        { phase: "sources", items: sourcesOut, clouds: cloudsOut },
        { phase: "premises", items: rejected },
        { phase: "attack", items: pressured, fallen: fallen.filter((id) => !rejected.includes(id)) },
      ],
      fallen,
    };
  }

  /** What the opponent says at each step: plain lines for the dialogue. */
  function combatLines(map, outcome) {
    const byId = Object.fromEntries(map.claims.map((c) => [c.id, c]));
    const label = outcome.label;
    const lines = [];
    const src = outcome.steps[0];
    for (const item of src.items) {
      const claim = byId[item.claim];
      if (item.source) {
        const s = claim.sources.find((x) => x.id === item.source);
        const why = s.lean && s.lean !== "neutral" ? `it's ${s.lean}-leaning` : `I don't trust ${kindLabel(s.kind).toLowerCase()}s`;
        lines.push({ phase: 0, who: "them", text: `“${s.title}”? I'm not taking that seriously; ${why}.` });
      } else {
        lines.push({ phase: 0, who: "them", text: `“${short(claim.text)}” rests on one source. Find me two more.` });
      }
    }
    for (const id of src.clouds) {
      lines.push({ phase: 0, who: "them", text: `You just believe “${short(byId[id].text)}”. Belief isn't evidence.` });
    }
    for (const id of outcome.steps[1].items) {
      lines.push({ phase: 1, who: "them", text: `I don't accept that “${short(byId[id].text)}”. That pillar's gone.` });
    }
    const attack = outcome.steps[2];
    for (const id of attack.items) {
      lines.push({ phase: 2, who: "them", text: `You're only ${Math.round(byId[id].confidence)}% sure that “${short(byId[id].text)}”. Why should I be?` });
    }
    for (const id of attack.fallen) {
      lines.push({ phase: 2, who: "narrator", text: `“${short(byId[id].text)}” gave way.` });
    }
    if (!lines.length) lines.push({ phase: 2, who: "them", text: `I looked for a weak spot and didn't find one. Fair enough.` });
    lines.push({
      phase: 3, who: "narrator",
      text: outcome.toppled
        ? `The ${label.toLowerCase()} knocked your tower over.`
        : `Your tower is still standing at ${Math.round(outcome.after * 100)}% after the ${label.toLowerCase()}'s attack.`,
    });
    return lines;
  }

  function short(text, n) {
    n = n || 60;
    const t = String(text || "").trim();
    return t.length > n ? t.slice(0, n - 1).trimEnd() + "…" : t;
  }

  function kindLabel(id) {
    const k = SOURCE_KINDS.find((x) => x.id === id);
    return k ? k.label : "Source";
  }

  // ---------------------------------------------------------------- knowledge vs. conviction

  /** The familiarity survey against the confidence survey, claim by claim. */
  function knowledgeReport(map) {
    return map.claims.map((c) => {
      const confidence = c.confidence ?? 50;
      const familiarity = c.familiarity ?? 3;
      let verdict = "grounded";
      if (hasTermites(c)) verdict = "termites";
      else if (isHumble(c)) verdict = "humble";
      else if (familiarity <= 2) verdict = "exploring";
      return { id: c.id, confidence, familiarity, verdict };
    });
  }

  // ---------------------------------------------------------------- comparing two maps

  const STOP = new Set(("the a an and or but of to in on for is are was were be been it its this that these those " +
    "with as at by from than then so if not no do does did can will would should could have has had i you we they " +
    "he she them our your their my me us more most less very").split(" "));

  function words(text) {
    return new Set(String(text || "").toLowerCase().replace(/[^a-z0-9\s]/g, " ").split(/\s+/)
      .filter((w) => w.length > 2 && !STOP.has(w)));
  }

  function similarity(a, b) {
    const A = words(a), B = words(b);
    if (!A.size || !B.size) return 0;
    let both = 0;
    for (const w of A) if (B.has(w)) both++;
    return both / (A.size + B.size - both);
  }

  function depthOf(map) {
    const { roots, kids } = childrenIndex(map);
    const depth = {};
    const walk = (c, d, seen) => {
      if (seen.has(c.id)) return;
      seen.add(c.id);
      depth[c.id] = d;
      for (const k of kids.get(c.id) || []) walk(k, d + 1, seen);
    };
    for (const r of roots) walk(r, 0, new Set());
    return depth;
  }

  /**
   * Lines up two maps of the same topic. Claims match by id first (a friend
   * who rated your map keeps your ids), then by wording (two people who built
   * maps separately). The discussion queue starts at the foundations: there's
   * no point arguing whether X is good until you agree X exists.
   */
  function compare(mine, theirs) {
    const pairs = [];
    const usedTheirs = new Set();
    const theirById = new Map(theirs.claims.map((c) => [c.id, c]));
    const unmatched = [];
    for (const c of mine.claims) {
      const t = theirById.get(c.id);
      if (t) { pairs.push([c, t, 1]); usedTheirs.add(t.id); } else unmatched.push(c);
    }
    const candidates = [];
    for (const c of unmatched) {
      for (const t of theirs.claims) {
        if (usedTheirs.has(t.id)) continue;
        const s = similarity(c.text, t.text);
        if (s >= 0.5) candidates.push([c, t, s]);
      }
    }
    candidates.sort((a, b) => b[2] - a[2]);
    const usedMine = new Set(pairs.map((p) => p[0].id));
    for (const [c, t, s] of candidates) {
      if (usedMine.has(c.id) || usedTheirs.has(t.id)) continue;
      pairs.push([c, t, s]);
      usedMine.add(c.id);
      usedTheirs.add(t.id);
    }

    const myDepth = depthOf(mine);
    const items = pairs.map(([c, t, s]) => {
      const a = c.confidence ?? 50, b = t.confidence ?? 50;
      let kind;
      if (a >= 50 && b >= 50) kind = Math.abs(a - b) >= 30 ? "degree" : "agree";
      else if (a < 50 && b < 50) kind = "bothDoubt";
      else kind = "disagree";
      const conflicts = [];
      for (const s2 of c.sources || []) if (trustOf(theirs, s2.kind) === "distrust") conflicts.push({ side: "mine", source: s2.id, kind: s2.kind });
      for (const s2 of t.sources || []) if (trustOf(mine, s2.kind) === "distrust") conflicts.push({ side: "theirs", source: s2.id, kind: s2.kind });
      return {
        mine: c.id, theirs: t.id, text: c.text, theirText: t.text, match: s,
        myConfidence: a, theirConfidence: b, kind, conflicts,
        depth: myDepth[c.id] ?? 0, importance: c.importance ?? 3,
      };
    });

    const onlyMine = mine.claims.filter((c) => !usedMine.has(c.id)).map((c) => c.id);
    const onlyTheirs = theirs.claims.filter((c) => !usedTheirs.has(c.id)).map((c) => c.id);

    const order = { disagree: 0, degree: 1, bothDoubt: 2, agree: 3 };
    const queue = items
      .filter((i) => i.kind === "disagree" || i.kind === "degree" || i.conflicts.length)
      .sort((x, y) => (y.depth - x.depth) || (order[x.kind] - order[y.kind]) || (y.importance - x.importance));

    const trustSplit = SOURCE_KINDS
      .filter((k) => trustOf(mine, k.id) !== trustOf(theirs, k.id))
      .map((k) => ({ kind: k.id, mine: trustOf(mine, k.id), theirs: trustOf(theirs, k.id) }));

    return {
      sameStance: (mine.stance || "unsure") === (theirs.stance || "unsure"),
      items, queue, onlyMine, onlyTheirs, trustSplit,
      agreeCount: items.filter((i) => i.kind === "agree" || i.kind === "bothDoubt").length,
      disagreeCount: items.filter((i) => i.kind === "disagree").length,
      degreeCount: items.filter((i) => i.kind === "degree").length,
    };
  }

  // ---------------------------------------------------------------- share codes

  const CODE_PREFIX = "MMA1.";

  function utf8ToBase64Url(text) {
    let b64;
    if (typeof Buffer !== "undefined") b64 = Buffer.from(text, "utf8").toString("base64");
    else {
      const bytes = new TextEncoder().encode(text);
      let bin = "";
      for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
      b64 = btoa(bin);
    }
    return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  }

  function base64UrlToUtf8(code) {
    let b64 = code.replace(/-/g, "+").replace(/_/g, "/");
    while (b64.length % 4) b64 += "=";
    if (typeof Buffer !== "undefined") return Buffer.from(b64, "base64").toString("utf8");
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder().decode(bytes);
  }

  /** A map as one line of text, to paste or put in a link. Same format in the iOS app. */
  function encodeMap(map) {
    return CODE_PREFIX + utf8ToBase64Url(JSON.stringify(normalize(map)));
  }

  function decodeMap(code) {
    const text = String(code || "").trim();
    const at = text.indexOf(CODE_PREFIX);
    if (at < 0) throw new Error("That isn't a Map My Argument code. Codes start with MMA1.");
    const body = text.slice(at + CODE_PREFIX.length).match(/^[A-Za-z0-9_-]+/);
    if (!body) throw new Error("The code is empty.");
    let parsed;
    try { parsed = JSON.parse(base64UrlToUtf8(body[0])); } catch (e) { throw new Error("The code is damaged. Copy the whole thing and try again."); }
    return normalize(parsed);
  }

  /** Fills in defaults and drops anything unknown, so old or hand-made maps load. */
  function normalize(m) {
    m = m || {};
    const num = (v, d, lo, hi) => (typeof v === "number" && isFinite(v) ? clamp(v, lo, hi) : d);
    const str = (v, d) => (typeof v === "string" ? v : d);
    const trust = {};
    for (const k of SOURCE_KINDS) if (m.trust && TRUST.includes(m.trust[k.id])) trust[k.id] = m.trust[k.id];
    return {
      version: 1,
      id: str(m.id, newId("map")),
      topic: str(m.topic, ""),
      thesis: str(m.thesis, ""),
      stance: ["for", "against", "unsure"].includes(m.stance) ? m.stance : "unsure",
      author: str(m.author, ""),
      basedOn: str(m.basedOn, ""),
      counted: (Array.isArray(m.counted) ? m.counted : []).filter((x) => typeof x === "string"),
      trust,
      created: str(m.created, ""),
      updated: str(m.updated, ""),
      claims: (Array.isArray(m.claims) ? m.claims : []).map((c) => ({
        id: str(c.id, newId("c")),
        parent: typeof c.parent === "string" && c.parent ? c.parent : null,
        text: str(c.text, ""),
        importance: Math.round(num(c.importance, 3, 1, 5)),
        confidence: Math.round(num(c.confidence, 50, 0, 100)),
        familiarity: Math.round(num(c.familiarity, 3, 1, 5)),
        cloud: !!c.cloud,
        votes: Math.round(num(c.votes, 0, 0, 1e6)),
        sources: (Array.isArray(c.sources) ? c.sources : []).map((s) => ({
          id: str(s.id, newId("s")),
          title: str(s.title, ""),
          url: str(s.url, ""),
          kind: SOURCE_KINDS.some((k) => k.id === s.kind) ? s.kind : "news",
          lean: ["neutral", "left", "right"].includes(s.lean) ? s.lean : "neutral",
        })),
        counters: (Array.isArray(c.counters) ? c.counters : []).map((x) => ({
          id: str(x.id, newId("x")),
          text: str(x.text, ""),
          strength: Math.round(num(x.strength, 3, 1, 5)),
          answered: !!x.answered,
        })),
        disputedBy: (Array.isArray(c.disputedBy) ? c.disputedBy : []).filter((p) => PERSPECTIVES.some((q) => q.id === p)),
      })),
    };
  }

  let counter = 0;
  function newId(prefix) {
    counter = (counter + 1) % 1e6;
    return prefix + "-" + Date.now().toString(36) + "-" + counter.toString(36) + Math.random().toString(36).slice(2, 6);
  }

  const MMA = {
    SOURCE_KINDS, LEANS, TRUST, FAMILIARITY, PERSPECTIVES, STATUS, GRADES, K,
    evaluate, windTest, earthquakeTest, combat, combatLines, knowledgeReport,
    compare, similarity, encodeMap, decodeMap, normalize, newId, demand, kindLabel, short,
  };

  if (typeof module !== "undefined" && module.exports) module.exports = MMA;
  root.MMA = MMA;
})(typeof globalThis !== "undefined" ? globalThis : this);

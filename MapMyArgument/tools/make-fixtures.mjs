// Writes the shared engine cases that both test suites check:
//   Packages/ArgumentKit/Tests/ArgumentKitTests/Fixtures/engine-cases.json
// The JavaScript engine (web/js/engine.js) is the reference. Run this after a
// deliberate change to the rules, then make the Swift engine match.
//   node MapMyArgument/tools/make-fixtures.mjs
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const M = require(join(here, "../web/js/engine.js"));
const C = require(join(here, "../web/js/catalog.js"));

const round = (x) => Math.round(x * 1e6) / 1e6;

function claimView(r) {
  return {
    strength: round(r.strength), stability: round(r.stability), status: r.status, tier: r.tier,
    sourceCount: r.sourceCount, fallen: r.fallen, termites: r.termites, humble: r.humble,
    unsupported: r.unsupported, cloud: r.cloud, depth: r.depth,
  };
}

function evalView(e) {
  return {
    score: round(e.score), grade: e.grade, lean: round(e.lean), weight: e.weight, toppled: e.toppled,
    flags: e.flags,
    claims: Object.fromEntries(Object.entries(e.claims).map(([k, v]) => [k, claimView(v)])),
  };
}

const testView = (t) => ({ after: round(t.after), fallen: [...t.fallen].sort(), toppled: t.toppled });

function mapCase(name, map) {
  map = M.normalize(map);
  const combat = {};
  for (const p of M.PERSPECTIVES) {
    const o = M.combat(map, p.id);
    combat[p.id] = {
      ...testView(o),
      sources: o.steps[0].items, clouds: o.steps[0].clouds,
      premises: o.steps[1].items, attack: o.steps[2].items, attackFallen: [...o.steps[2].fallen].sort(),
    };
  }
  return {
    name, map,
    expect: {
      evaluate: evalView(M.evaluate(map)),
      wind: testView(M.windTest(map)),
      earthquake: testView(M.earthquakeTest(map)),
      combat,
      knowledge: M.knowledgeReport(map),
    },
  };
}

const claim = (id, extra) => ({
  id, parent: null, text: id, importance: 3, confidence: 60, familiarity: 3, cloud: false, votes: 0,
  sources: [], counters: [], disputedBy: [], ...extra,
});
const src = (id, kind, extra) => ({ id, title: id, url: "", kind, lean: "neutral", ...extra });
const base = (id, claims, trust) => ({ id, topic: id, thesis: id, stance: "for", trust: trust || {}, claims });

const maps = [
  ["example", C.EXAMPLE],
  ["friend", C.EXAMPLE_FRIEND],
  ["empty", base("empty", [])],
  ["tiers-and-duplicates", base("tiers", [
    claim("one", { sources: [src("a", "study")] }),
    claim("two", { importance: 5, confidence: 100, sources: [src("a", "study"), src("b", "news", { lean: "left" })] }),
    claim("three", { importance: 1, sources: [src("a", "study"), src("b", "government"), src("c", "expert"), src("d", "news")] }),
    claim("dupes", { sources: [src("x", "study", { title: "Same" }), src("y", "study", { title: " same " })] }),
    claim("distrusted", { sources: [src("z", "social")] }),
  ], { study: "trust", government: "trust", social: "distrust" })],
  ["clouds-and-cherry-picking", base("clouds", [
    claim("c1", { cloud: true, confidence: 95, familiarity: 1 }),
    claim("c2", { cloud: true, confidence: 20, familiarity: 5 }),
    claim("c3", { votes: 7, sources: [src("p", "personal")] }),
    claim("c3a", { parent: "c3", cloud: true, importance: 5 }),
    claim("self", { parent: "self", sources: [src("q", "reference")] }),
  ])],
  ["counters-and-depth", base("deep", [
    claim("top", { importance: 5, confidence: 40, counters: [{ id: "k1", text: "k", strength: 5, answered: false }, { id: "k2", text: "k", strength: 2, answered: true }] }),
    claim("mid", { parent: "top", importance: 4, sources: [src("m1", "study"), src("m2", "government", { lean: "right" })] }),
    claim("low", { parent: "mid", importance: 2, confidence: 90, familiarity: 5, sources: [src("l1", "advocacy", { lean: "left" }), src("l2", "news")], disputedBy: ["conservative", "skeptic"] }),
    claim("side", { importance: 2, confidence: 30, sources: [src("s1", "expert")], disputedBy: ["scientist"] }),
  ], { study: "trust", government: "trust", advocacy: "trust", news: "trust", expert: "unfamiliar" })],
];

const independentA = base("indep-a", [
  claim("a1", { text: "Remote work makes people more productive" }),
  claim("a2", { text: "Commuting wastes hours every week", confidence: 90 }),
  claim("a3", { text: "Offices help junior staff learn faster", confidence: 30 }),
]);
independentA.stance = "for";
const independentB = base("indep-b", [
  claim("b1", { text: "Commuting wastes many hours every week", confidence: 40 }),
  claim("b2", { text: "Junior staff learn faster in offices", confidence: 85, sources: [src("bs", "advocacy")] }),
  claim("b3", { text: "Video calls are exhausting" }),
], { advocacy: "trust" });
independentB.stance = "against";
independentA.trust = { advocacy: "distrust" };

function compareView(c) {
  return {
    sameStance: c.sameStance, agreeCount: c.agreeCount, disagreeCount: c.disagreeCount, degreeCount: c.degreeCount,
    onlyMine: c.onlyMine, onlyTheirs: c.onlyTheirs,
    items: c.items.map((i) => ({ mine: i.mine, theirs: i.theirs, kind: i.kind, match: round(i.match), conflicts: i.conflicts })),
    queue: c.queue.map((i) => i.mine),
    trustSplit: c.trustSplit,
  };
}

const out = {
  note: "Generated by MapMyArgument/tools/make-fixtures.mjs from web/js/engine.js. Do not edit by hand.",
  maps: maps.map(([n, m]) => mapCase(n, m)),
  compares: [
    { name: "friend-rating", mine: M.normalize(C.EXAMPLE), theirs: M.normalize(C.EXAMPLE_FRIEND),
      expect: compareView(M.compare(C.EXAMPLE, C.EXAMPLE_FRIEND)) },
    { name: "independent-maps", mine: M.normalize(independentA), theirs: M.normalize(independentB),
      expect: compareView(M.compare(M.normalize(independentA), M.normalize(independentB))) },
  ],
  similarity: [
    ["Commuting wastes hours every week", "Commuting wastes many hours every week"],
    ["The spork is an inferior utensil", "A spork is a bad utensil"],
    ["", "anything"],
  ].map(([a, b]) => ({ a, b, value: round(M.similarity(a, b)) })),
  shareCode: { code: M.encodeMap(C.EXAMPLE), claims: C.EXAMPLE.claims.length, thesis: C.EXAMPLE.thesis },
};

const target = join(here, "../Packages/ArgumentKit/Tests/ArgumentKitTests/Fixtures/engine-cases.json");
writeFileSync(target, JSON.stringify(out, null, 1) + "\n");
console.log("Wrote", target);

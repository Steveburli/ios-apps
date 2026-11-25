// Tests for the scoring engine. Run from the repo root:
//   node --test MapMyArgument/web/tests/
import { test } from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const M = require(join(here, "../js/engine.js"));
const C = require(join(here, "../js/catalog.js"));
const cases = JSON.parse(readFileSync(join(here, "../../Packages/ArgumentKit/Tests/ArgumentKitTests/Fixtures/engine-cases.json"), "utf8"));

const close = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-6, `${msg}: ${a} vs ${b}`);

const claim = (id, extra) => ({
  id, parent: null, text: id, importance: 3, confidence: 60, familiarity: 3, cloud: false, votes: 0,
  sources: [], counters: [], disputedBy: [], ...extra,
});
const src = (id, kind, extra) => ({ id, title: id, url: "", kind, lean: "neutral", ...extra });
const map = (claims, trust) => M.normalize({ topic: "t", thesis: "t", trust: trust || {}, claims });

test("the shared cases still match the engine (rerun tools/make-fixtures.mjs after a deliberate change)", () => {
  for (const c of cases.maps) {
    const e = M.evaluate(c.map);
    const x = c.expect.evaluate;
    close(e.score, x.score, c.name + " score");
    assert.equal(e.grade, x.grade, c.name);
    close(e.lean, x.lean, c.name + " lean");
    assert.deepEqual(e.flags, x.flags, c.name);
    for (const [id, r] of Object.entries(x.claims)) {
      close(e.claims[id].strength, r.strength, `${c.name}/${id} strength`);
      assert.equal(e.claims[id].status, r.status, `${c.name}/${id}`);
    }
    for (const p of M.PERSPECTIVES) {
      const o = M.combat(c.map, p.id);
      close(o.after, c.expect.combat[p.id].after, `${c.name} vs ${p.id}`);
      assert.deepEqual([...o.fallen].sort(), c.expect.combat[p.id].fallen);
    }
  }
});

test("more independent sources make a claim stronger, up to three (IXI)", () => {
  const m = map([
    claim("one", { sources: [src("a", "study")] }),
    claim("two", { sources: [src("a", "study"), src("b", "study")] }),
    claim("three", { sources: [src("a", "study"), src("b", "study"), src("c", "study")] }),
    claim("four", { sources: [src("a", "study"), src("b", "study"), src("c", "study"), src("d", "study")] }),
  ], { study: "trust" });
  const r = M.evaluate(m).claims;
  assert.equal(r.one.tier, "I");
  assert.equal(r.two.tier, "II");
  assert.equal(r.three.tier, "IXI");
  assert.ok(r.one.strength < r.two.strength && r.two.strength < r.three.strength);
  close(r.three.strength, r.four.strength, "a fourth source adds nothing");
});

test("sources with the same title count once", () => {
  const m = map([claim("c", { sources: [src("a", "study", { title: "Report" }), src("b", "study", { title: "report " })] })]);
  assert.equal(M.evaluate(m).claims.c.tier, "I");
});

test("distrusted sources hold nothing up", () => {
  const m = map([claim("c", { sources: [src("a", "social")] })], { social: "distrust" });
  const r = M.evaluate(m).claims.c;
  assert.equal(r.strength, 0);
  assert.ok(r.unsupported);
});

test("being sure without knowing much brings termites", () => {
  const solid = map([claim("c", { confidence: 90, familiarity: 4, sources: [src("a", "study")] })]);
  const hollow = map([claim("c", { confidence: 90, familiarity: 1, sources: [src("a", "study")] })]);
  const a = M.evaluate(solid).claims.c, b = M.evaluate(hollow).claims.c;
  assert.ok(b.termites && !a.termites);
  close(b.strength, a.strength * M.K.termiteFactor, "termites eat 30%");
  assert.equal(M.knowledgeReport(hollow)[0].verdict, "termites");
});

test("more important claims have more weight to carry", () => {
  const light = map([claim("c", { importance: 1, sources: [src("a", "study")] })]);
  const heavy = map([claim("c", { importance: 5, sources: [src("a", "study")] })]);
  assert.ok(M.evaluate(light).claims.c.stability > M.evaluate(heavy).claims.c.stability);
});

test("a sub-claim holds its parent up; once it falls it doesn't", () => {
  const m = map([
    claim("top", {}),
    claim("under", { parent: "top", importance: 5, confidence: 100, sources: [src("a", "study"), src("b", "study"), src("c", "study")] }),
  ], { study: "trust" });
  const r = M.evaluate(m).claims;
  assert.ok(r.top.strength > 0);
  const knocked = M.evaluate(m, { removed: ["under"], fall: true }).claims;
  assert.equal(knocked.top.fallen, true);
});

test("the wind blows belief clouds away", () => {
  const m = map([claim("c", { cloud: true, importance: 5 }), claim("d", { sources: [src("a", "study"), src("b", "study")] })], { study: "trust" });
  const w = M.windTest(m);
  assert.deepEqual(w.fallen, ["c"]);
  assert.deepEqual(w.blownAway, ["c"]);
  assert.ok(w.after < w.before);
});

test("an earthquake collapses termite-eaten claims", () => {
  const m = map([claim("c", { confidence: 95, familiarity: 1, sources: [src("a", "study"), src("b", "study"), src("c", "study")] })], { study: "trust" });
  assert.deepEqual(M.earthquakeTest(m).fallen, ["c"]);
});

test("an opponent throws out the sources it doesn't trust and the premises it rejects", () => {
  const m = map([
    claim("c", { sources: [src("a", "news", { lean: "left" }), src("b", "news", { lean: "right" })] }),
    claim("d", { disputedBy: ["conservative"], sources: [src("e", "study")] }),
  ], { news: "trust", study: "trust" });
  const o = M.combat(m, "conservative");
  assert.deepEqual(o.steps[0].items, [{ claim: "c", source: "a" }]);
  assert.deepEqual(o.steps[1].items, ["d"]);
  assert.ok(o.fallen.includes("d"));
  const lines = M.combatLines(m, o);
  assert.ok(lines.some((l) => l.text.includes("left-leaning")));
});

test("the skeptic won't accept a single source", () => {
  const m = map([claim("c", { sources: [src("a", "study")] })], { study: "trust" });
  const o = M.combat(m, "skeptic");
  assert.equal(o.result.claims.c.sourceCount, 0);
});

test("an empty map is an empty lot, not a toppled tower", () => {
  const e = M.evaluate(map([]));
  assert.equal(e.grade, "empty");
  assert.equal(e.toppled, false);
});

test("a claim that names itself as its parent is treated as a top-level claim", () => {
  const e = M.evaluate(map([claim("c", { parent: "c" })]));
  assert.equal(e.claims.c.depth, 0);
});

test("comparing a friend's rating starts with the disagreements at the foundations", () => {
  const cmp = M.compare(C.EXAMPLE, C.EXAMPLE_FRIEND);
  assert.equal(cmp.disagreeCount, 3);
  assert.deepEqual(cmp.onlyTheirs, ["sam-renew"]);
  const deep = M.normalize({ claims: [claim("top"), claim("base", { parent: "top", confidence: 90 })] });
  const other = M.normalize({ claims: [claim("top", { confidence: 10 }), claim("base", { parent: "top", confidence: 10 })] });
  assert.deepEqual(M.compare(deep, other).queue.map((i) => i.mine), ["base", "top"]);
});

test("independent maps match claims by wording", () => {
  close(M.similarity("Commuting wastes hours every week", "Commuting wastes many hours every week"), 5 / 6, "jaccard");
  assert.equal(M.similarity("", "x"), 0);
});

test("share codes round-trip, including non-English text", () => {
  const m = M.normalize({ ...C.EXAMPLE, thesis: "Café ☕ means “coffee”" });
  const back = M.decodeMap("Here's my map: " + M.encodeMap(m) + " (from the app)");
  assert.deepEqual(back, m);
  assert.throws(() => M.decodeMap("hello"), /isn't a Map My Argument code/);
  assert.throws(() => M.decodeMap("MMA1.!!!"), /empty/);
});

test("normalize repairs bad input", () => {
  const m = M.normalize({ stance: "maybe", claims: [{ importance: 99, confidence: -5, sources: [{ kind: "tabloid", lean: "up" }], disputedBy: ["martian", "skeptic"] }] });
  assert.equal(m.stance, "unsure");
  assert.equal(m.claims[0].importance, 5);
  assert.equal(m.claims[0].confidence, 0);
  assert.equal(m.claims[0].sources[0].kind, "news");
  assert.equal(m.claims[0].sources[0].lean, "neutral");
  assert.deepEqual(m.claims[0].disputedBy, ["skeptic"]);
});

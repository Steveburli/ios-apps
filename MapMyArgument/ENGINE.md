# How the tower is scored

The JavaScript engine (`web/js/engine.js`) is the reference. The Swift engine
(`Packages/ArgumentKit/Sources/ArgumentKit/Engine.swift`, `Compare.swift`) follows it, and the
shared cases in `Packages/ArgumentKit/Tests/ArgumentKitTests/Fixtures/engine-cases.json` keep them
in step: Node's tests and `swift test` both check them. After a deliberate rule change, run
`node MapMyArgument/tools/make-fixtures.mjs`, then make the Swift engine match.

## A claim's strength (0–1)

Added together, then capped at 1:

| Part | Value |
|---|---|
| Sources | 1 counted source = 0.45 (I), 2 = 0.75 (II), 3+ = 1.0 (IXI), times the average trust of the counted ones |
| Trust in a source's kind | trust 1.0, not sure 0.7, don't trust 0 (doesn't count) |
| Same title twice | counts once |
| Each supporting point | its strength × its importance ÷ 5 × 0.5 |
| Belief cloud | 0.35 |
| Votes (people who agree) | min(0.15, 0.05 × log2(1 + votes)) |
| Each counter-argument | −0.05 × strength (1–5) if unanswered, −0.01 × strength if answered |

Then:

- × (0.6 + 0.4 × confidence ÷ 100)
- × 0.7 if termites (confidence ≥ 70 and familiarity ≤ 2)

## Weight and stability

- Weight to carry = 0.2 + 0.14 × importance (1–5).
- Stability = strength ÷ weight. ≥ 1 solid, ≥ 0.6 strained, ≥ 0.35 sagging, below that failing.
- In a stress test, anything below 0.35 falls and stops holding up the claim above it.

## The tower

- Score = Σ min(1, stability) × importance over top-level reasons, ÷ Σ importance.
- Grade: ≥ 0.85 Fortress, ≥ 0.65 Solid, ≥ 0.45 Leaning, ≥ 0.25 Sagging, else Toppled.
- Lean: with one pillar, (1 − score) × 12°. Otherwise (right-half weakness − left-half weakness) ÷ total importance × 24°, within ±20°, where weakness = Σ (1 − min(1, stability)) × importance.
- Flags: termites; humble (confidence ≤ 35, familiarity ≥ 4); unsupported (no counted source, cloud or sub-point); head in the clouds (2+ clouds and more than a third of claims); cherry-picking (3+ claims, no counter-arguments at all).

## Stress tests

- **Wind**: belief clouds hold nothing; then weak claims fall.
- **Earthquake**: every strength × 0.8, termite claims collapse; then weak claims fall.
- **Opponent**: (1) its distrusted source kinds and leans count for nothing (the Scientist also removes clouds; the Skeptic treats one source as none), (2) claims you marked "would reject" are knocked out, (3) claims under 50% confidence are × 0.75; then weak claims fall.

| Opponent | Distrusts |
|---|---|
| Progressive | right-leaning sources |
| Conservative | left-leaning sources |
| Libertarian | government data |
| Scientist | social posts, personal experience, advocacy groups; belief clouds |
| Skeptic | social posts; any claim resting on a single source |

## Comparing

- Claims match by id (a friend's rating keeps your ids), then by wording: word overlap (Jaccard, ignoring words of 1–2 letters and common words) of 0.5 or more, best matches first.
- Both ≥ 50% sure and within 30 points: agree. Both ≥ 50% but 30+ apart: "how sure". Both under 50%: both doubt. Otherwise: disagree.
- The discussion queue holds disagreements, "how sure" items and anything resting on a source kind the other person distrusts, deepest claims first.

## Share codes

`MMA1.` followed by the map's JSON in URL-safe base64 without padding. Both apps read a code anywhere inside a longer message.

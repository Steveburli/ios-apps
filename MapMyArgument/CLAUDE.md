# Map My Argument

An iPhone app and a website that turn an argument into a building and stress-test it. Started 2026-11-25 from Steve's 2017 notes ("MapMyArgument.com"): physics-style argument maps where weak foundations make the tower lean and topple, sources counted I / II / IXI, belief clouds, termites for confidence without knowledge, wind and earthquake tests, perspective combat, and comparing maps with a friend.

## Layout

- `web/`: the website, plain HTML/CSS/JS with no build step and no server. `js/engine.js` (scoring, the reference), `js/catalog.js` (topics and the example maps, the single source for both apps), `js/tower.js` (the SVG building and its animations), `js/app.js` (screens: home, build, map, rate, compare, how; picked by `#hash`). Maps are kept in localStorage (`mma.v1`).
- `Packages/ArgumentKit`: Foundation-only Swift logic plus XCTest. `Models.swift` (the same JSON shape as the website, decoded leniently), `Engine.swift`, `Compare.swift` (also `ShareCode`), `Catalog.swift` (generated).
- `MapMyArgument.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `MapMyArgument/` join the app target automatically; never edit `project.pbxproj` just to add a file.
- `MapMyArgument/App`: `Store` (@Observable; saves maps, source trust, name and the unfinished draft as JSON in UserDefaults under `maps.v1`; owns the navigation path, the map being rated and the open comparison).
- `MapMyArgument/Map`: `TowerView` (the building, drawn in the website's 640 × 560 coordinates and scaled), `MapScreen` (tests, diagnostics, outline, knowledge chart, sharing).
- `MapMyArgument/Build`: `BuildFlow` (the seven-step survey) and `ClaimEditor`. `MapMyArgument/Compare`: `RateFlow`, `CompareView`, `HowView`. `MapMyArgument/Home`.
- `tools/make-fixtures.mjs` writes the shared engine cases; `tools/gen-swift-catalog.mjs` writes `Catalog.swift` from `web/js/catalog.js`.

## Commands

```bash
node --test MapMyArgument/web/tests/*.test.mjs        # website engine + shared cases
node MapMyArgument/tools/make-fixtures.mjs            # after a deliberate rule change
node MapMyArgument/tools/gen-swift-catalog.mjs        # after editing web/js/catalog.js
cd MapMyArgument/Packages/ArgumentKit && swift test
xcodebuild -project MapMyArgument/MapMyArgument.xcodeproj -scheme MapMyArgument -destination 'generic/platform=iOS Simulator' build
```

## Rules

- The two engines must agree. Change `web/js/engine.js` first, regenerate the fixtures, then change the Swift engine until `swift test` passes. ENGINE.md lists every number.
- Share codes (`MMA1.` + base64url JSON) must stay readable by both apps. Add fields with defaults; never rename one.
- Opponents act only on what the person entered (source kinds, leans they assigned, premises they marked "would reject"). The app never decides on its own what a political group believes.
- Nothing is sent anywhere. Sharing is a code the person copies or sends with the share sheet.
- Swift 5 language mode, iOS 18, iPhone portrait, light and dark.
- `-screenshots <screen>` opens one screen with sample data: home, build, survey, map, test, combat, rate, compare, how (`Support/Screenshots.swift`).
- Commit, push, or change signing and the bundle ID only when the user asks.

## Status (2026-11-25)

First version of both. The website was clicked through end to end in a headless browser (build, stress tests, opponent, share, rate on a second "phone", compare). The Swift code has not been compiled yet: there's no Swift toolchain in the cloud session, so the first cloud Mac build will show any errors in `report-MapMyArgument/errors.txt`.

## Ideas not built yet

- Public polling: "how strong is this from the perspective of others", filtered by group. Needs a server to collect ratings.
- Matching with a stranger who disagrees, shared maps on the site, posting to social networks.
- Stacking maps into a whole belief system (meta-beliefs) and zooming into one supporting belief.
- A cartoon of two people arguing (the opponent dialogue is text bubbles for now).
- Universal links so `mapmyargument.com/#m=…` opens the app.

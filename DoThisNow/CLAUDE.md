# Do This Now

A native SwiftUI (iOS 18+, iPhone, portrait, light and dark) version of the Do This Now web app at steveburlison.com/do-this-now/. It picks the one thing to do right now from your priorities, the time you have, where you are, and your mood. It also has a day planner where work is a rock, tasks are soft clay, events are jelly with a hard core, and sleep moves but complains. The web app's `index.html` (in the user's Windows `Documents\Websites\hub\apps\do-this-now\`) is the reference, and this port follows it closely.

## Layout

- `DoThisNow.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `DoThisNow/` join the target automatically. Never edit `project.pbxproj` just to add a file.
- `Packages/DoThisNowKit` holds Foundation-only logic plus XCTest. It is a line-by-line port of the web app's math:
  - `Models`: `TaskItem`, `PlannerEvent`, `PlannerState` and the rest. Every type decodes field by field with defaults, so old saved files keep loading.
  - `Engine`: scoring, the recommender, the errand and sweep bundles, and check-ins (`nudges`)
  - `DayPlanner`: `planDay`, which does rocks, ghosts, jelly, and pressure relief at levels 0–2
  - `Actions` (the state changes behind each button) and `Examples` (the sample list)
- `DoThisNow/App/AppModel` owns the state. It saves `planner.json` in Application Support and re-syncs local notifications after every change.
- `Now/`, `Tasks/`, `Day/` and `Settings/` hold the screens. `Support/` holds the theme and chips, `FlowLayout`, the synthesized sounds, and `Notifier`.

## Commands

```bash
cd Packages/DoThisNowKit && swift test
xcodebuild -project DoThisNow.xcodeproj -scheme DoThisNow -destination 'generic/platform=iOS Simulator' build
```

## Rules

- Keep the Kit's behavior identical to the web app. When you change scoring or planning, change it in the Kit and add a test. Don't touch the views for that.
- Times of day are `Int` minutes after midnight in the model. Inside the planner they are `Double`, because "now" has a fractional part. Days are `CalendarDay` (`yyyy-MM-dd`), never `Date`.
- `stableSorted` exists because JavaScript's sort is stable. Use it wherever the web app sorted.
- Some types were renamed because their names clash with newer Swift or SwiftUI types. `TimeSpan` (not `Span`), `FocusLevel` (not `Focus`) and `PlannerSettings` (not `Settings`) have to keep those names.
- Swift 5 language mode is deliberate.
- Commit, push, or change signing and the bundle ID only when the user asks.

## Differences from the web app

- A local notification fires when a timed session runs out. "Not now → Remind me in…" now sends a real reminder at that time instead of waiting for you to open the app.
- On Tasks, swipe right to mark a task done, swipe left to let it go, and long-press to move it between tiers. To reorder, tap **Reorder**, or touch and hold a row.
- No cloud sync. Data stays on the phone, so the sync indicator is gone.
- The system rounded font replaces the web app's Recursive font, so no font file ships with the app.

## How this repo is worked on

- Code is edited on the user's Windows PC, which has no Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac. It runs `swift test` for the package and does an unsigned Simulator build of the app. Read results with `gh run list`, then `gh run download <run id> -n report-DoThisNow`. The report's `errors.txt` has one line per error.
- Each report also holds `screens/` (App Store-size Simulator screenshots: the app is launched with `-screenshots <screen>`, which opens one screen with sample data, see `DoThisNow/Support/Screenshots.swift`), `app-log.txt`, and any crash reports. Look at the screenshots after UI changes.
- TestFlight uploads run in the cloud too: push a tag `testflight-DoThisNow-<n>` and `.github/workflows/testflight.yml` signs and uploads (logs in the `testflight-logs-DoThisNow` artifact). It needs the four signing secrets, the same as the say-it-back repo. `./scripts/ship.sh DoThisNow` on the user's Mac is only a fallback.

## Status (2026-10-20)

The cloud build is green: the app compiles with no errors or warnings, every logic test passes, and the Simulator screenshots have been checked. The team ID (`DSH38XJG4K`) and the app icon are in place. It hasn't run on a real iPhone yet.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Ship a TestFlight build (tag `testflight-DoThisNow-<n>`; ask the user first). On their iPhone, they should tap **Try it with example tasks** and check:
   - the Now questions, **Tell me what to do**, **Not now** (with a snooze), **Already done**, **Start**, then pause, +15 min, and finish
   - Tasks: drag between tiers, the check-in cards, editing a task, the swipe actions
   - Day: the example soccer game, dragging its purple core, making something "must do" until bedtime gets pushed (the groan and the bubble), and the dinner options
3. Lock the phone during a 1-minute session and confirm the "Time's up" notification arrives.
4. Take the App Store screenshots (6.9-inch, 1320 × 2868) and submit for review.

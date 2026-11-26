# Littles

A native SwiftUI app (iOS 18+, iPhone, portrait, light and dark) for tracking everything about Griffin and Blake in one place. It combines what the family used Solid Starts (first foods) and Baby Tracker – MyBaby (feeds, diapers, sleep) for, plus activity ideas (like Bomi and Things to Do with Kids), the preschool schedule, CDC-style milestones (like CDC's Milestone Tracker) and short parenting scripts (like The Happy Child and How to Talk). All content is written for this app; nothing is copied from those apps. `FEATURE-IDEAS.md` has the research on those apps and the list of what could come next.

## Layout

- `Littles.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `Littles/` join the target automatically. Never edit `project.pbxproj` just to add a file.
- `Packages/LittlesKit` holds Foundation-only logic plus XCTest:
  - `Models`: `Kid`, `LogEntry` (one struct for every kind: bottle, nursing, pump, diaper, sleep, solids, potty, meds, temperature, growth, bath, note; fields that don't apply stay nil), `FoodBite` (a food in a meal, with liking and a reaction flag) and `FamilyState`, the one saved file. Every type decodes field by field with defaults, and an unknown log kind loads as a note, so old files keep loading.
  - `Dates`: day keys (`yyyy-MM-dd`), minutes after midnight, `Age` labels ("8 mo", "3 yr 4 mo")
  - `Summary`: a day's totals (sleep split at midnight), last of a kind, running timers, the typical feed gap (median, skipping overnight) and the next feed, which side to nurse on next, and the quick-log buttons by age
  - `Foods` (`FoodGuide`: 60+ foods with how to serve at 6–8, 9–11 and 12+ months, choking level, allergen, minimum age; `holdOffs`) and `FoodProgress` (foods tried toward 100, the nine allergens' states — not started, introducing, in rotation, due after 7 days, reaction — and `suggestions`: one allergen, two new foods, one refused food to retry, one favorite, rotating daily)
  - `Activities`: `ActivityLibrary` (40+ ideas with age ranges, minutes, place, energy, mess, skills, materials, steps) and `ActivityPicker` (every chosen kid's age must fit, so "Everyone" finds things both can do; favorites first, things done in the last 3 days last)
  - `Schedule`: `RoutineItem` (weekly, with weekdays, times, place, reminder and an end date for the school year), `OneOffEvent` ("No school" crosses off school, drop-off and pickup; `bring` goes on the pack list), `PackItem`, and `Agenda` (a day's entries, the pack list, the next thing up)
  - `Milestones`: the CDC 2022 checklists (2 months to 5 years), paraphrased; `current`, `upcoming`, `progress` and `toMention` (earlier ones still "not yet")
  - `Tips`: 20 short "instead of / try / why" scripts by situation, and a tip of the day
  - `Sample`: the screenshot family (a baby and a preschooler) and test data
- `Littles/` holds the app: `App/` (`LittlesApp` with the five tabs, `AppModel`, `Notifier`), `Today/` (timers, "since last", quick log, totals, timeline, `LogSheet`, `FoodPicker`), `Food/`, `Play/`, `Schedule/` (week strip, agenda, pack list, editors), `Grow/` (milestones, growth charts with Swift Charts, tips), `Family/` (kids, export, the first-launch welcome) and `Support/` (`Theme`, `Screenshots`).
- `AppModel` saves `family.json` in Application Support after every change (with complete file protection) and re-syncs the routine reminders: one weekly repeating local notification per routine weekday (`Notifier`, ids `routine-<id>-<weekday>`).

## Commands

```bash
cd Packages/LittlesKit && swift test
xcodebuild -project Littles.xcodeproj -scheme Littles -destination 'generic/platform=iOS Simulator' build
```

## Rules

- Logic lives in the Kit with a test. Views only show it.
- Days are `yyyy-MM-dd` strings, times of day are `Int` minutes after midnight. Log entries use `Date`, since they are moments.
- Food, allergen and milestone text is general guidance, written for this app. Keep the "not medical advice, ask your pediatrician" notes next to it. Don't copy text from Solid Starts, Wonder Weeks or other apps.
- Swift 5 language mode is deliberate.
- Commit, push, or change signing and the bundle ID only when the user asks.

## How this repo is worked on

- Code is edited on the user's Windows PC (or in a cloud session), neither of which has a Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac: `swift test` for the Kit and an unsigned Simulator build. The report artifact is `report-Littles`, with `errors.txt` and `screens/` (the app launched with `-screenshots <screen>`, see `Littles/Support/Screenshots.swift`).
- TestFlight: push a tag `testflight-Littles-<n>`. The App ID `com.steveburlison.littles` must exist in the developer account first (the workflow creates the provisioning profile). No iCloud, push or App Groups capabilities are needed yet.

## Status (2026-11-25)

Version 1 written: Today, Food, Play, Schedule and Grow tabs, local storage only. The cloud build is green on branch `claude/admiring-cori-elbx4l` (run 69): every Kit test passes, the app compiles, and all 14 screenshots were taken with no crash. The screenshots haven't been looked at yet. Not yet on a device or in TestFlight.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Set Griffin's and Blake's real birthdays on first launch, then ship a TestFlight build (ask the user first).
3. iCloud sharing so both parents (and a grandparent or sitter) log on their own phones: the Mutual / Trip pattern (`CKSyncEngine`, one zone shared with a zone-wide `CKShare`).
4. Widgets and a Live Activity for the sleep and nursing timers, and Siri / Shortcuts for "Log a bottle for Griffin".
5. The rest of `FEATURE-IDEAS.md`.

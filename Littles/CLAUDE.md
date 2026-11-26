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
  - `Family`: `Units` (values are always saved as oz, lb, in and °F; `isMetric` only changes display and editing), `NightMode`, `PottyPlan`, `FamilySettings`, `RoutineChart` (picture checklists, done keys `day|chart|kid|step`, streaks), `Contact`, `ShoppingItem`
  - `Growth` (WHO 0–5 percentiles from `WHOTables`, generated from the WHO anthro package every 15 days and interpolated) and `SleepGuide` (awake windows by age, the next sleep window)
  - `Health`: `HealthSchedule` (the CDC/AAP vaccine doses and checkups as of 2025, dose states, the next checkup), `MedicineTimer` (acetaminophen and ibuprofen intervals and daily limits; never doses), `SickAdvice` (when to call), `Teeth`, `Streaks`, `PottyStats`, `TimeTotals`
  - `MealPlanning`: `MealPlanner` (a week of meals by age, every started allergen twice, one new allergen three mornings in a row, new foods at dinner, a grocery list), `RecipeBook`, `FamilyDinners.adapt`, `PickyEater`
  - `Imports`: `CalendarImport` (.ics files and links, and text read from a photo of a printed list, with the year guessed from today) and `DailyReport` (a pasted daycare report into entries)
  - `Sync`: `FamilySync.merge` (log entries keep the newer `updated`; everything else is a union that keeps this phone's copy; `FamilyState.deleted` keeps deletions deleted), `PediatricianReport.html`, `Recap` (a month's highlights, memories) and `MilestoneActivities` (activities that practice the current milestones)
  - `Sample`: the screenshot family (a baby and a preschooler) and test data
- `Littles/` holds the app: `App/` (`LittlesApp` with the five tabs and night mode, `AppModel` (`AppModel.shared`, also used by Siri), `Notifier`, `LiveTimers`, `Shortcuts` (App Intents: log a bottle or diaper, start or end a nap, "when did … last …"), `Today/TodayCards` (countdown, medicine, sick, nap window, potty, picture charts), `Today/` (timers, "since last", quick log, totals, timeline, `LogSheet`, `FoodPicker`), `Food/`, `Play/`, `Schedule/` (week strip, agenda, pack list, editors), `Grow/` (milestones, growth charts with Swift Charts, tips), `Family/` (kids, export, the first-launch welcome) and `Support/` (`Theme`, `Screenshots`).
- `AppModel` saves `family.json` in Application Support after every change (readable after first unlock, so Siri works while locked), stamps `updated` on saved entries, records deletions, and re-syncs reminders (`Notifier`, ids `littles-…`: routines weekly, leave-for-school 15 minutes ahead for 7 days, potty for 2 days, the next fever-medicine dose, checkups a week ahead; 64 at most) and the Live Activities.
- `Widgets/` is the `LittlesWidgets` extension (`com.steveburlison.littles.widgets`): the Live Activity for running sleep and nursing timers. `Shared/TimerActivity.swift` (the `ActivityAttributes`) is compiled into both targets. Home Screen widgets need an App Group, which isn't set up yet.
- Photos are JPEGs (1600 px) in Application Support/photos; a log entry keeps the file name. Sync files (`.littles`, type `com.steveburlison.littles.family`) carry the data but not the photos.

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

## Status (2026-11-26)

The second round (all of `FEATURE-IDEAS.md` except the Apple Watch app, live iCloud sync and Home Screen widgets) was added on 2026-11-26. Caregiver sharing works now by swapping sync files; live iCloud sync needs an iCloud container (`iCloud.com.steveburlison.littles`) and the CloudKit setup Mutual uses. Home Screen widgets need an App Group registered for both App IDs.

## Status (2026-11-25)

Version 1 written: Today, Food, Play, Schedule and Grow tabs, local storage only. The cloud build is green on branch `claude/admiring-cori-elbx4l` (run 69): every Kit test passes, the app compiles, and all 14 screenshots were taken with no crash. The screenshots haven't been looked at yet. Not yet on a device or in TestFlight.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Set Griffin's and Blake's real birthdays on first launch, then ship a TestFlight build (ask the user first).
3. Live iCloud sync so both parents log on their own phones without swapping files: the Mutual / Trip pattern (`CKSyncEngine`, one zone shared with a zone-wide `CKShare`). Needs the container first.
4. Home Screen and Lock Screen widgets ("last bottle 2h ago"), once an App Group exists.
5. An Apple Watch app for one-tap bottle, diaper and sleep.

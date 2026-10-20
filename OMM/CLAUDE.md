# OMM: Old Man Maintenance

A native SwiftUI (iOS 18+, iPhone, portrait) version of the OMM workout web app at steveburlison.com/omm/. The program cycles supersets through upper body, lower body and core muscle groups until all 28 groups are crossed out. The behavior spec is `OMM-App-Specification.md` on the user's Windows desktop. The web app's `index.html` is the reference implementation, and this port follows it exactly unless noted below.

## Layout

- `OMM.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `OMM/` join the app target automatically, so never edit `project.pbxproj` just to add a file.
- `Packages/OMMKit` holds Foundation-only logic plus XCTest:
  - `Catalog` and `Exercises`: the 7 × 4 grid and 10 exercises per group
  - `ProgramState`: progress, weights, start date and daily sets, plus the completion and estimate math
  - `WorkoutPlan` and `GroupSelection`
- `OMM/App` has `AppModel`, which owns the state and saves `ProgramState` as JSON in UserDefaults (`program.v1`).
- `OMM/Workout/WorkoutSession` runs the set-by-set flow and the rest timer.
- `OMM/Support` has the theme, the chime (a WAV built in memory) and the rest notification.
- `Config/Info.plist` is merged into the generated Info.plist.

## Commands

```bash
cd Packages/OMMKit && swift test
xcodebuild -project OMM.xcodeproj -scheme OMM -destination 'generic/platform=iOS Simulator' build
```

If `xcodebuild` complains about the developer directory, ask the user to run `sudo xcode-select -s /Applications/Xcode.app`.

## Rules

- Keep the web app's storage keys and math. Thresholds are 3 / 6 / 12 sets. Rest is `round(minutes × 60 ÷ sets) − 30` seconds. The estimate is remaining sets ÷ average sets per workout day, rounded up.
- "Inner" is two different groups. Their keys are `Inner (Thighs)` and `Inner (Chest)`.
- The rest timer stores an end date and never counts ticks, so it stays right after the app is backgrounded. A local notification covers the locked-phone case. In the foreground the chime and a haptic play instead.
- Swift 5 language mode is deliberate.
- The app is light-mode only (`UIUserInterfaceStyle = Light`) because the design is white cards on a purple gradient.
- Commit, push, or change signing and the bundle ID only when the user asks.

## Differences from the web app

- **Back to Home** asks for confirmation before it throws away the workout.
- The duration slider remembers its last value.
- A local notification fires when rest ends while the app is in the background.

## How this repo is worked on

- Code is edited on the user's Windows PC, which has no Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac. It runs `swift test` for the package and does an unsigned Simulator build of the app. Read results with `gh run list`, then `gh run download <run id> -n report-OMM`. The report's `errors.txt` has one line per error, with repo-relative paths.
- Each report also holds `screens/` (App Store-size Simulator screenshots: the app is launched with `-screenshots <screen>`, which opens one screen with sample data, see `OMM/Support/Screenshots.swift`), `app-log.txt`, and any crash reports. Look at the screenshots after UI changes.
- The user's Mac only signs and uploads, with `./scripts/ship.sh OMM`. Keep the Mac's part to that one command.

## Status (2026-10-20)

Written without a compiler and not yet built. The app icon is in place (`Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024 × 1024, no alpha).

## Next tasks, in order

1. Get the GitHub build green: fix every error and warning it reports.
2. Have the user ship a TestFlight build (`./scripts/ship.sh OMM` on the Mac). On their iPhone, they should walk through a full 3-group workout at 9 minutes, where rest is 30 seconds:
   - the rest timer, and the notification when the phone is locked during rest
   - **Next Workout** while the timer is running
   - the weight sheet, including prefill on a second workout
   - the estimate on the home screen
   - **Reset Program**
3. Take the App Store screenshots: 6.9-inch, 1320 × 2868.
4. Submit for review from App Store Connect.

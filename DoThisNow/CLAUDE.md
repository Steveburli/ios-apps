# Do This Now

A native SwiftUI (iOS 18+, iPhone in portrait and iPad in any orientation, light and dark) version of the Do This Now web app at steveburlison.com/do-this-now/. It picks the one thing to do right now from your priorities, the time you have, where you are, and your mood. It also has a day planner where work is a rock, tasks are soft clay, events are jelly with a hard core, and sleep moves but complains. The web app's `index.html` (in the user's Windows `Documents\Websites\hub\apps\do-this-now\`) is the reference, and this port follows it closely.

## Layout

- `DoThisNow.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `DoThisNow/` join the target automatically. Never edit `project.pbxproj` just to add a file.
- `Packages/DoThisNowKit` holds Foundation-only logic plus XCTest. It is a line-by-line port of the web app's math:
  - `Models`: `TaskItem`, `PlannerEvent`, `PlannerState` and the rest. Every type decodes field by field with defaults, so old saved files keep loading.
  - `Engine`: scoring, the recommender, the errand and sweep bundles, and check-ins (`nudges`)
  - `DayPlanner`: `planDay`, which does rocks, ghosts, jelly, and pressure relief at levels 0–2
  - `Actions` (the state changes behind each button) and `Examples` (the sample list)
  - `TimeBlocks`: blocks you place on a day yourself, and `Reflow.move`, which pushes the blocks a moved one lands on (up if they sat mostly above it, down otherwise, hopping over event cores) so blocks never overlap
  - `Inbox`: `SourceTask` (a task from any source), per-source `SourceFilter`s, and `Engine.inbox(external:)`
  - `ReminderSync`: `PlannerState.syncReminders`, which keeps a `TaskItem` (`reminderID`) for each reminder that passes the filters, so Now, Tasks and the Day all use them. Reminder priority sets the starting tier only: high is Top priority, medium is High, low or none is Medium
  - `Tracking`: Track-tab activities and timings, and `Estimator` (title keys, outlier-free typical times from the last 20 runs, word-based guesses). `PlannerState.estimate` picks your own minutes, then history, then the task's estimate, then a guess
  - `Replan`: `Engine.missedBlocks` (blocks on today that ended undone), `Engine.replan()` (later-today gaps, then tomorrow's) and `PlannerState.apply` (tomorrow, back to the Inbox, or let go). `Engine.openSlots` is the shared gap finder
  - `Wake`: the morning routine, `Engine.wakePlan(for:)` (work or the first event, minus commute, buffer and routine, then the sleep goal), and the alarm's ring times with backups
- `DoThisNow/App/AppModel` owns the state. It saves `planner.json` in Application Support and re-syncs local notifications after every change.
- `Now/`, `Tasks/`, `Day/`, `Track/`, `Wake/` and `Settings/` hold the screens. `Day/DayFullScreen` is the timeline over the whole screen (remembered in `dayFullScreen`). On iPad (regular width) the Day tab is two columns: `Inbox/SideList` (Inbox or Do This Now tasks only) and the timeline; a block dragged over the left column goes back to the Inbox. `Day/ReplanSheet` previews a Replan, and the Day card offers it and then Undo. `Inbox/` holds the Day tab's Inbox drawer, the Inbox page (the Day tab's second segment: pick tasks, then put them in the first gaps) and its sources: `RemindersSource` (EventKit) and `InboxDropbox` (the Shortcuts/Siri intent writes a file the app picks up). `AppModel.commit` sends finished and restored tasks to Reminders through `pushReminderChanges`. `Wake/WakeAlarms` schedules AlarmKit alarms on iOS 26+ (weak-linked with `-weak_framework AlarmKit`) and notifications before that. `Support/` holds the theme and chips, `FlowLayout`, the synthesized sounds, and `Notifier`.

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
- On Tasks, tap a task's circle or swipe right to mark it done (repeating tasks have no circle, since they never finish), swipe left to let it go, and long-press to move it between tiers. To reorder, tap **Reorder**, or touch and hold a row.
- No cloud sync. Data stays on the phone, so the sync indicator is gone.
- New in the app only (not in the web app): the Inbox, hand-placed blocks, the Track tab and the Wake tab. They were modeled on Structured (Inbox and timeline), Atracker (one-tap timers) and Awake (scan-to-stop alarm). Turning off "Suggest tasks for the gaps" leaves only your own blocks on the Day.
- iPhone always shows its own Stop control on alarms, so "scan to stop" works by backup alarms every couple of minutes until a scan in the app. The scanner also has a 30-second hold for when a code can't be scanned.
- A Reminders list can carry a label (`InboxSettings.listLabels`, set under Task sources > Labels for shared lists), shown on Tasks, Inbox rows and blocks. Meant for a list someone shares with you, such as "From my wife".
- The system rounded font replaces the web app's Recursive font, so no font file ships with the app.

## How this repo is worked on

- Code is edited on the user's Windows PC, which has no Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac. It runs `swift test` for the package and does an unsigned Simulator build of the app. Read results with `gh run list`, then `gh run download <run id> -n report-DoThisNow`. The report's `errors.txt` has one line per error.
- Each report also holds `screens/` (App Store-size Simulator screenshots: the app is launched with `-screenshots <screen>`, which opens one screen with sample data, see `DoThisNow/Support/Screenshots.swift`), `app-log.txt`, and any crash reports. Look at the screenshots after UI changes.
- TestFlight uploads run in the cloud too: push a tag `testflight-DoThisNow-<n>` and `.github/workflows/testflight.yml` signs and uploads (logs in the `testflight-logs-DoThisNow` artifact). It needs the four signing secrets, the same as the say-it-back repo. `./scripts/ship.sh DoThisNow` on the user's Mac is only a fallback.

## Status (2026-10-23)

Version 1 was uploaded to TestFlight on 2026-10-21. On 2026-10-23 and 24, the Inbox, time blocks, Track and Wake tabs were added and merged to main (TestFlight build 202610240029). On 2026-10-30, at the user's request, Apple Reminders became the main task source and Google Tasks was taken out of the app, so Google's sensitive-scope verification isn't needed. `TaskSource.google` and `InboxSettings.google` stay in the Kit only so saved files keep loading. The Google Cloud project "Do This Now" (do-this-now-512600) is still published, and `git log` has the removed `GoogleTasks.swift` if it comes back.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Ship a TestFlight build (tag `testflight-DoThisNow-<n>`; ask the user first). On their iPhone, they should tap **Try it with example tasks** and check:
   - the Now questions, **Tell me what to do**, **Not now** (with a snooze), **Already done**, **Start**, then pause, +15 min, and finish
   - Tasks: drag between tiers, the check-in cards, editing a task, the swipe actions
   - Day: the example soccer game, dragging its purple core, making something "must do" until bedtime gets pushed (the groan and the bubble), and the dinner options
3. Lock the phone during a 1-minute session and confirm the "Time's up" notification arrives.
4. On the phone, check the new parts: connect Reminders from the Now tab's card, see reminders on Now and Tasks, finish one each way, and try the filters; drag Inbox tasks onto the Day and drag blocks into each other; time a few things on Track; on Wake, save a code and use "Test it: ring in a minute" (tap Scan to stop, then scan). To check the backups, set a fixed alarm two minutes ahead, stop it with the slider, and confirm it rings again until you scan.
5. Take the App Store screenshots (6.9-inch, 1320 × 2868) and submit for review.

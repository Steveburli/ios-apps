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
  - `BreakBank`: break credits. The focus timer and Now-tab sessions earn break time (`PlannerSettings.workPerBreak` minutes of work per minute of break, 5 by default). Breaks can run past the balance (debt the next work pays back). Leftover earned time resets to zero each day; debt carries over. The focus timer stops counting 90 minutes after the last "Still working?" yes. `breakFits` matches break ideas to the minutes you have, using Track timings when they exist
  - `Replan`: `Engine.missedBlocks` (blocks on today that ended undone), `Engine.replan()` (later-today gaps, then tomorrow's) and `PlannerState.apply` (tomorrow, back to the Inbox, or let go). `Engine.openSlots` is the shared gap finder
  - `Trip`: Trip mode. `Trip` and `TripStop` (kinds with default stay times, set times, must-do or want-to), `Leg` (walk at or under the trip's walk limit, 30 minutes by default, otherwise drive), `TripPlanner.schedule()` (arrival times and late warnings with fixes: move or drop a flexible stop) and `catchUp(now:here:)` ("We're off schedule": what still fits before the next set time, in order). `TripExample` is the Chicago sample
  - `Meetings`: `Meeting` (a timed event from a locked calendar) and `MeetingSettings` (on/off, and the locked calendars; nil means any calendar named "Alignops"). `planDay` treats meetings as hard busy time (`DayPlan.meetings` / `locked`), events on them become ghosts, `Reflow.move(locked:)` sends a block dropped on one to the gap right after it, and with meetings on `openSlots` opens work hours to your own tasks and blocks only the meetings
  - `PlaceTimers`: Track timers that start and stop by place. `WatchedPlace`, `PlaceRule` (start or stop an activity when you arrive at or leave a place), `PlannerState.crossed(placeID:_:at:)` (runs the rules, stops first), `undo(firingID:)`, and the "still running?" check an hour after a rule starts a timer (`placeCheckDue`, `postponePlaceCheck`)
  - `Wake`: the morning routine, `Engine.wakePlan(for:)` (work or the first event, minus commute, buffer and routine, then the sleep goal), and the alarm's ring times with backups
- `Widgets/` is the widgets extension (target `DoThisNowWidgets`, bundle ID `com.steveburlison.dothisnow.widgets`, built with `WIDGET_EXTENSION`): the Live Activity (`TimerLiveActivity`, Lock Screen and Dynamic Island; Track timers count up with a Stop button, the Now tab's session counts down), the "Timer" widget (Home Screen small, Lock Screen round, rectangle and inline) and the "Start buttons" widget (small 2, medium 4). It doesn't link DoThisNowKit. `Shared/` is compiled into both targets: `TimerBridge` (the App Group `group.com.steveburlison.dothisnow`; the app writes `timer-snapshot.json`, and buttons that run inside the extension queue `timer-commands.json` for the app to replay with their tap times), `TimerControl` (the app sets `handler` in `DoThisNowApp.init`, so buttons run in the app through `AppModel.shared` when iOS launches it for a `LiveActivityIntent`), `TimerIntents` and `LiveTimers` (starts, updates and ends the Live Activities; only the app can). `Track/AppModel+Widgets` calls `syncTimers()` from every `commit()`. The start buttons are picked in Settings > Start buttons (`UserDefaults` key `widgetActivityIDs`; never picked means the first four on Track).
- `DoThisNow/App/AppModel` owns the state. It saves `planner.json` in Application Support and re-syncs local notifications after every change.
- `Now/`, `Tasks/`, `Day/`, `Track/`, `Wake/` and `Settings/` hold the screens. `Day/DayFullScreen` is the timeline over the whole screen (remembered in `dayFullScreen`). A quick sideways swipe on the Day (`daySwipes()`, a UIKit swipe recognizer so it works inside the scroll view; ignored while something is being dragged) goes to the next or previous day, and a Today pill shows on any other day. The Week button beside the Day / Inbox / Trip switch opens `Day/WeekView` (`weekShown`): Monday to Sunday on one screen, colored bars with symbols for work, events, dinner and sleep, the alarm, and a dot per placed block. It's look-only: tap a day to open it, swipe for another week. Days before today or past today + 13 (`AppModel.daysAhead`) are dimmed. On iPad the week sits next to the task list. On iPad (regular width) the Day tab is two columns: `Inbox/SideList` (Inbox or Do This Now tasks only) and the timeline; a block dragged over the left column goes back to the Inbox. `Day/ReplanSheet` previews a Replan, and the Day card offers it and then Undo. `Trip/` is Trip mode, the Day tab's Trip segment (on iPad, a Day / Trip switch above the two columns): `TripView` and `TripSheets` (map, stops, legs, "We're here", "We're off schedule"), `PlaceSearch` (MapKit), `TripStore` (`trips.json` plus iCloud sync with `CKSyncEngine`; each trip is its own zone, shared whole with a zone-wide `CKShare`), `TripRecords` (record types `Trip` and `Stop`, each one String field `payload` holding JSON; deployed to Production, so never rename them) and `TripSharing` (share sheet, accepting invites, `HereFinder` for location). The container is `iCloud.com.steveburlison.dothisnow` (`Config/DoThisNow.entitlements`). `Inbox/` holds the Day tab's Inbox drawer, the Inbox page (the Day tab's second segment: pick tasks, then put them in the first gaps) and its sources: `RemindersSource` (EventKit) and `InboxDropbox` (the Shortcuts/Siri intent writes a file the app picks up). `AppModel.commit` sends finished and restored tasks to Reminders through `pushReminderChanges`. `Wake/WakeAlarms` schedules AlarmKit alarms on iOS 26+ (weak-linked with `-weak_framework AlarmKit`) and notifications before that. `Support/` holds the theme and chips, `FlowLayout`, the synthesized sounds, and `Notifier`.

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
- No cloud sync for tasks and the day. They stay on the phone, so the sync indicator is gone. Only trips sync, through iCloud, so they can be shared.
- Trip mode is new in the app only: a day of stops with travel times, shared with someone else through iCloud (like Mutual).
- New in the app only (not in the web app): the Inbox, hand-placed blocks, the Track tab and the Wake tab. They were modeled on Structured (Inbox and timeline), Atracker (one-tap timers) and Awake (scan-to-stop alarm). Turning off "Suggest tasks for the gaps" leaves only your own blocks on the Day.
- Suggested tasks (the soft ones the planner fills in) can be moved: touch and hold, then drag, or tap for **Move to…** and **Swap for something else** (`App/AppModel+Suggestions`). A moved or swapped-in task becomes a block you placed (`SourceRef(.app, taskID)`), so it stays put and `dayChunks` stops suggesting it elsewhere that day. Errand runs don't move. On iPad, dropping a suggestion on the left column takes it off the day.
- The break bank (Track tab card `Track/BreakBankCard`, balance bar on Now, ratio in Settings) is app-only. "Fill my break" starts a break for the whole balance and asks the Now tab for tasks that fit it.
- Track timers can start and stop by place (Track > Start and stop by place, or an activity's "By place"). `Track/PlaceWatcher` uses iOS region monitoring with "Always" location, so it works with the app closed; `AppDelegate` attaches it to `AppModel.shared` at launch, since iOS relaunches the app in the background for a crossing. A rule acts on its own and sends a quiet notification with Undo (`PlaceNotices`, handled by `NotificationActions`); an hour after a rule starts a timer, a notification asks "Still timing…?" with Stop it and Keep going.
- iPhone always shows its own Stop control on alarms, so "scan to stop" works by backup alarms every couple of minutes until a scan in the app. The scanner also has a 30-second hold for when a code can't be scanned.
- A Reminders list can carry a label (`InboxSettings.listLabels`, set under Task sources > Labels for shared lists), shown on Tasks, Inbox rows and blocks. Meant for a list someone shares with you, such as "From my wife". In a labeled list, a priority change or words added to a reminder's notes become a `Suggestion` (Kit `Suggestions`, `PlannerState.suggestions`), shown on the Suggestions card on Now and Tasks (`Now/SuggestionsCard`). A new priority applies at once and the task shows a "Changed by my wife" tag until you Keep it, Put it back (the old tier is saved on the suggestion) or Pick another. Your own, unlabeled lists still only set the starting tier. Texting your plan to her and getting replies back (a texting service plus a small online service) is agreed but not built yet.
- Locked work meetings (app only): Settings > Work meetings reads the Alignops calendar (or the calendars you pick) through EventKit (`Day/MeetingsSource`, read-only, all-day and declined events left out) and shows each meeting with a lock on the Day. `AppModel.refreshSources` refreshes them.
- The system rounded font replaces the web app's Recursive font, so no font file ships with the app.

## How this repo is worked on

- Code is edited on the user's Windows PC, which has no Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac. It runs `swift test` for the package and does an unsigned Simulator build of the app. Read results with `gh run list`, then `gh run download <run id> -n report-DoThisNow`. The report's `errors.txt` has one line per error.
- Each report also holds `screens/` (App Store-size Simulator screenshots: the app is launched with `-screenshots <screen>`, which opens one screen with sample data, see `DoThisNow/Support/Screenshots.swift`), `app-log.txt`, and any crash reports. Look at the screenshots after UI changes.
- TestFlight uploads run in the cloud too: push a tag `testflight-DoThisNow-<n>` and `.github/workflows/testflight.yml` signs and uploads (logs in the `testflight-logs-DoThisNow` artifact). It needs the four signing secrets, the same as the say-it-back repo. `./scripts/ship.sh DoThisNow` on the user's Mac is only a fallback. For Do This Now the workflow fetches two App Store profiles, one for the app and one for the widgets extension (`SHIP_WIDGETS_PROVISIONING_PROFILE`); both App IDs need the App Groups capability with `group.com.steveburlison.dothisnow`.

## Status (2026-11-03)

On 2026-11-03 Trip Planner version 1 was added as Trip mode (Day tab > Trip), not as its own app. It needed the iCloud and Push capabilities on the App ID, which replaced the old provisioning profiles. The Mutual step and importing calendar events wait for version 2.

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

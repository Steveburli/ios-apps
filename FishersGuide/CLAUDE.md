# Fishers Guide

A native SwiftUI (iOS 18+, iPhone, portrait) GPS driving tour of Fishers and Hamilton County, Indiana, in the style of the GyPsy Guide apps. The phone's GPS starts the right story as you approach a place, based on where you are, which way you're heading and how fast you're going. It says which side of the road the place is on. Everything is on the phone, so it works offline. This is an original app with its own content; nothing is copied from GyPsy Guide.

## Layout

- `FishersGuide.xcodeproj` is an Xcode 16 synchronized-folder project (objectVersion 77). Files added under `FishersGuide/` join the app target automatically, so never edit `project.pbxproj` just to add a file.
- `Packages/GuideKit` holds Foundation-only logic plus XCTest:
  - `Geo`: distance, bearing, destination, heading math, and `RelativeSide` (ahead / left / right / behind)
  - `Tour`: `Tour`, `Stop` (`poi` or `area`), `HeadingRange`, `DirectionalNarration`. The content is `Resources/FishersTour.json`, loaded with `Tour.bundledFishers()`.
  - `TriggerEngine`: picks what to say from a `Fix` (point, course, speed, time). The rules:
    - A POI plays inside its radius. If you're heading toward it (within `headingTolerance`, 60°), the radius grows by `speed × leadSeconds`, capped at `maxLead`, so the story starts before you arrive.
    - A POI you're driving away from (more than 110° off) and more than 60% of the way out of its circle is skipped as too late.
    - `approach` headings limit a stop to certain directions of travel. When parked inside the circle it plays anyway.
    - `directional` narrations swap in a different story for a direction of travel.
    - An `area` (a town welcome) plays anywhere inside its circle, in any direction, and gives way to any POI.
    - Teasers ("In about half a mile, …") play when a stop with a `teaser` is within 35° ahead and within `headsUpDistance` beyond its trigger reach.
    - Ranking: POIs before areas, then `priority`, then how deep inside the trigger reach you are. Arrivals beat teasers.
    - A stop doesn't repeat for `cooldown` (6 h). Below `minCourseSpeed` (2 m/s) the course is ignored as noise.
  - `Script`: the spoken intro ("Coming up on your left: …") and US distance words
  - `RouteSimulator`: drives waypoints at a set speed, for the demo drive, screenshots and tests
- `FishersGuide/App`: `GuideModel` owns everything. When a story is playing it holds the next arrival as `upNext` and plays it afterwards, with a fresh left/right intro, if you're still near. Otherwise it's logged as missed. Also `RootView` (the full-screen map with the bottom panel), `SettingsView`, `OnboardingView`. Saved in UserDefaults: `guide.played.v1`, `guide.history.v1`, `guide.settings.v1`, `guide.onboarded.v1`.
- `FishersGuide/Playback`:
  - `Narrator`: AVSpeechSynthesizer, or an `AVAudioPlayer` clip when a stop's `audioFile` is in the app bundle. It uses the `.playback` / `.spokenAudio` audio session with `.duckOthers` and has Lock Screen and car controls (play/pause, next = skip).
  - `LocationService`: Core Location set for driving. It asks for When In Use only, and `CLBackgroundActivitySession` plus the `location` background mode keeps updates coming with the screen off. Fixes worse than 100 m or older than 30 s are dropped.
  - `NowPlayingCard` and `TourPanel`
- `FishersGuide/Map/GuideMapView`: the MapKit map with pins, trigger circles, and the demo route and car
- `FishersGuide/Stops`: the stops list (nearest first) and stop detail (story text, Play, Directions)
- `Config/Info.plist` is merged into the generated Info.plist and adds `UIBackgroundModes` (`audio`, `location`). The location usage text is the `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` build setting.

## Commands

```bash
cd Packages/GuideKit && swift test
xcodebuild -project FishersGuide.xcodeproj -scheme FishersGuide -destination 'generic/platform=iOS Simulator' build
```

## Adding or editing stops

Edit `Packages/GuideKit/Sources/GuideKit/Resources/FishersTour.json`. `TourTests` checks that ids are unique, coordinates fall in Hamilton County, every story has real text, and the demo drive still reaches the main stops. Fields:

| Field | Required | Notes |
|---|---|---|
| `id`, `title`, `category`, `location`, `radius`, `narration` | yes | `category`: history, nature, arts, entertainment, landmark, area. `radius` is in meters: 200–400 for a building, 1000+ for a lake. |
| `kind` | no | `poi` (default) or `area` (town welcome, category `area`) |
| `subtitle`, `teaser`, `priority`, `address`, `website` | no | No `teaser` means no "coming up" heads-up. |
| `approach` | no | `[{"from": 300, "to": 60}]` means northbound only (clockwise, wraps through 0) |
| `directional` | no | `[{"heading": {"from":300,"to":60}, "text": "…"}]` replaces the story for that direction |
| `audioFile` | no | e.g. `conner-prairie.m4a`. Drop the file anywhere under `FishersGuide/` and it plays instead of the synthesized voice. |

Facts in the stories were checked against Wikipedia, the City of Fishers history pages, Indiana historical markers and similar sources (2026-11). Coordinates come from Wikipedia and mapping listings, and Ritchey Woods comes from a single listing. **Drive each stop before release** to confirm the radius and timing feel right on the real roads.

## Rules

- Swift 5 language mode is deliberate (same as the other apps).
- Supports light and dark mode.
- Never ask for Always location. When In Use plus the background mode is enough, and it's an easier App Review story.
- Keep the stories factual and sourced. Don't add a claim that can't be checked.
- Commit, push, or change signing and the bundle ID only when the user asks.

## How this repo is worked on

Same as the other apps (see the repo README): code is edited without a local compiler, and every push to `main` runs `.github/workflows/build.yml` (GuideKit tests, unsigned Simulator build, screenshots `map playing stops stop settings welcome` plus a dark `map`). Read `report-FishersGuide` → `errors.txt`. TestFlight uses the `testflight-FishersGuide-<n>` tag. The App ID `com.steveburlison.fishersguide` must exist in the developer account first; the workflow creates the profile.

## Status (2026-11-25)

The cloud build is green (run 68): all 29 GuideKit tests pass, the app builds for the Simulator, and the screenshots run without a crash. The screenshots haven't been looked at yet. It hasn't run on a real iPhone.

## Next tasks, in order

1. Look at the screenshots in `report-FishersGuide` and fix anything that looks off.
2. Register the App ID `com.steveburlison.fishersguide` and ship a TestFlight build (ask first).
3. Drive the demo route for real: City Hall, then Allisonville Rd north past Conner Prairie, the Noblesville square, Potter's Bridge, Ruoff and Geist. Tune `radius`, `leadSeconds` and the stories.
4. More stops (Fishers AgriPark, Saxony, Morse Reservoir, Cool Creek Park, the Carmel Arts & Design District, Westfield's Grand Park). Record real voice clips for the best ones.
5. App Store screenshots (6.9-inch, 1320 × 2868) and the listing.

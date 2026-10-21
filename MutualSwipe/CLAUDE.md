# Mutual (Mutual Swipe)

A native SwiftUI (iOS 18+, iPhone, portrait, light and dark) version of the user's "Mutual Swipe" Claude artifact. People swipe on shared decks of options: date nights, recipes, movies, restaurants, trips, anything. Then the app shows what everyone agrees on. The artifact stored data with claude.ai. This version stores it in **iCloud with CloudKit sharing**. The artifact's "Ask Claude for ideas" panel is left out of version 1.

## How sharing works

- A **group** is one CloudKit record zone. The owner's private database holds it, and it's shared as a whole with a zone-wide `CKShare`. Everyone in a group sees all of its decks.
- Record types and fields are listed in `Sync/Records.swift`:
  - `Group` (record name `group`)
  - `Deck`
  - `Card` (`deck` reference, `.deleteSelf`)
  - `Player`
  - `Pick` (`card` reference, `.deleteSelf`)
- A **Pick** is one person's vote on one card, stored as its own record named `pick_<card>_<player>`. Two people swiping at once never overwrite each other.
- Deleting a deck cascades through the references on the server. Picks reference their card, not the deck, which keeps them under CloudKit's limit of 750 `.deleteSelf` references per target.
- **Players** are names inside a group, not iCloud identities. That keeps the artifact's pass-the-phone mode working. Each phone remembers "who's swiping" per group in UserDefaults (`Session`).
- `Sync/CloudStore` is local-first. A JSON cache lives in Application Support, and two `CKSyncEngine`s do the syncing: one for the private database (groups you own) and one for the shared database (groups shared with you). Conflicts resolve as last writer wins: on `serverRecordChanged` it takes the server's change tag and saves again.
- The owner invites people with `UICloudSharingController` (`Sync/SharingPresenter`). Invitees tap the iCloud link. `SceneDelegate` receives the `CKShare.Metadata` and `CloudStore.accept` joins the group.
- Signing out of iCloud wipes the local cache, so the next person on the phone doesn't see the last person's decks.

## Layout

- `MutualSwipe.xcodeproj` is an Xcode 16 synchronized-folder project. Never edit `project.pbxproj` just to add a file.
- `Packages/MutualKit` holds Foundation-only logic plus tests:
  - the models
  - `DeckState` (the artifact's `classify` and `deckState`, ported exactly)
  - `CardText` (cleaning, link safety, the initial letter, the color hash, "Paste a list" parsing)
- `MutualSwipe/` holds the app: `App/` (entry point, `AppDelegate`/`SceneDelegate`, `Session`), `Sync/`, `Home/`, `Deck/` (the Swipe, Results and Cards tabs), `Sheets/`, and `Support/Theme`.
- `Config/MutualSwipe.entitlements` holds iCloud (CloudKit), the container `iCloud.com.steveburlison.mutualswipe`, and `aps-environment`. `Config/Info.plist` sets `CKSharingSupported` and the `remote-notification` background mode.

## Commands

```bash
cd Packages/MutualKit && swift test
xcodebuild -project MutualSwipe.xcodeproj -scheme MutualSwipe -destination 'generic/platform=iOS Simulator' build
```

## One-time iCloud setup (in a browser, no Mac needed)

TestFlight and App Store builds use CloudKit's **Production** environment. That environment only accepts record types that were deployed to it, so this setup has to be done before the first TestFlight build can save anything.

1. **Create the container.** On developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers**, switch the filter to **iCloud Containers** and press **+**. Name it `iCloud.com.steveburlison.mutualswipe`.
2. **Set up the App ID.** Under **Identifiers → App IDs**, open (or create) `com.steveburlison.mutualswipe`. Turn on **iCloud** (choose CloudKit, then **Configure** and tick the container) and **Push Notifications**, then save.
3. **Make the record types.** In the CloudKit Console (icloud.developer.apple.com), choose the container, go to **Development → Schema → Record Types**, and create these exactly (the names are case sensitive):

   | Record type | Fields (type) |
   |---|---|
   | `Group` | `name` (String), `createdAt` (Date/Time) |
   | `Deck` | `title` (String), `kind` (String), `blurb` (String), `createdAt` (Date/Time) |
   | `Card` | `deck` (Reference), `deckID` (String), `title` (String), `subtitle` (String), `details` (String), `tags` (String List), `link` (String), `order` (Double), `createdAt` (Date/Time) |
   | `Player` | `name` (String), `color` (Int(64)), `createdAt` (Date/Time) |
   | `Pick` | `card` (Reference), `deckID` (String), `cardID` (String), `playerID` (String), `vote` (String), `updatedAt` (Date/Time) |

4. **Deploy.** In the console, press **Deploy Schema Changes** to copy them to **Production**.

After any change to `Sync/Records.swift`, update this table and redeploy. Production can gain record types and fields, but it can never rename or remove them.

## Rules

- Never rename a CloudKit record type or field after the schema is deployed. Add new fields instead.
- Keep `DeckState` identical to the artifact's results logic, and change it only together with a test.
- Swift 5 language mode is deliberate.
- Commit, push, or change signing, the bundle ID or the container ID only when the user asks.

## How this repo is worked on

- Code is edited on the user's Windows PC, which has no Swift compiler.
- Every push to `main` runs `.github/workflows/build.yml` on a GitHub cloud Mac. It runs `swift test` for the package and does an unsigned Simulator build. Read results with `gh run list`, then `gh run download <run id> -n report-MutualSwipe`.
- Unsigned builds have no iCloud entitlement, so the cloud build only proves the app compiles. Real iCloud testing happens in TestFlight.
- Each report also holds `screens/` (App Store-size Simulator screenshots: the app is launched with `-screenshots <screen>`, which opens one screen with sample data, see `MutualSwipe/Support/Screenshots.swift`), `app-log.txt`, and any crash reports. Look at the screenshots after UI changes.
- TestFlight uploads run in the cloud too: push a tag `testflight-MutualSwipe-<n>` and `.github/workflows/testflight.yml` signs and uploads (logs in the `testflight-logs-MutualSwipe` artifact). It needs the four signing secrets, the same as the say-it-back repo. `./scripts/ship.sh MutualSwipe` on the user's Mac is only a fallback.

## Status (2026-10-20)

The cloud build is green: the app compiles with no errors or warnings, every logic test passes, and the Simulator screenshots (which use sample data, with iCloud off) have been checked. The team ID (`DSH38XJG4K`) and the app icon are in place. iCloud sync and sharing haven't been tried on a real device yet.

The one-time iCloud setup above is done. The container exists, the App ID has iCloud (CloudKit, 1 container) and Push on, and the five record types match the table and are deployed to Production. The app uses no CloudKit queries, so no indexes were added.

## Next tasks, in order

1. Keep the GitHub build green after every change.
2. Ship a TestFlight build (tag `testflight-MutualSwipe-<n>`; ask the user first). On one phone, they should:
   - create a deck and add cards, both one at a time and with **Paste a list**
   - add two names and swipe as each person
   - check the Results tiers, undo, **Clear my swipes** and **Delete deck**
3. Sync check: add a second Apple ID as a TestFlight tester on another iPhone. Invite that phone from **Groups → Invite people**, accept the link there, swipe on both phones, and confirm Results update within about 30 seconds.
4. Take the App Store screenshots and submit for review.

## Ideas for later

- Bring back "Ask Claude for ideas" through a small server that holds the Anthropic API key.
- Live Activities or widgets for "3 new matches".
- iCloud identity names for players, so you don't type your name on each phone.

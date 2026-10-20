# Mutual (Mutual Swipe)

The iPhone version of the Mutual Swipe artifact. Everyone swipes on shared decks (date nights, recipes, movies, restaurants, trips) on their own phone, and the app shows what you agree on. Sharing uses iCloud (CloudKit), so there's no server and no account to create.

**Status:** written without a compiler and not yet built. See `CLAUDE.md` for status, next steps and the one-time iCloud setup, and the README at the top of the repository for how it gets built and shipped.

## Run it on the Mac

1. Open `MutualSwipe.xcodeproj` in Xcode 16 or later.
2. Select the **MutualSwipe** target → **Signing & Capabilities**, pick your team, and confirm iCloud (CloudKit, container `iCloud.com.steveburlison.mutualswipe`), Push Notifications and Background Modes → Remote notifications are on.
3. Sign the simulator in to iCloud (Settings app in the simulator), then press **Run**.

Logic tests: `cd Packages/MutualKit && swift test`

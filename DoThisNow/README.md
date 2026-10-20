# Do This Now

The iPhone version of steveburlison.com/do-this-now/. It picks the one thing to do right now from your priorities, time, place and mood, and has a day planner where work is a rock, tasks are soft, events are jelly and sleep complains.

**Status:** written without a compiler and not yet built. See `CLAUDE.md` for status and next steps, and the README at the top of the repository for how it gets built and shipped.

## Run it on the Mac

1. Open `DoThisNow.xcodeproj` in Xcode 16 or later.
2. Select the **DoThisNow** target → **Signing & Capabilities** and pick your team. The bundle ID is `com.steveburlison.dothisnow`.
3. Pick an iPhone simulator, press **Run**, and tap **Try it with example tasks**.

Logic tests: `cd Packages/DoThisNowKit && swift test`

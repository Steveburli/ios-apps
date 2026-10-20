# OMM: Old Man Maintenance

The iPhone version of steveburlison.com/omm/: a long-term workout program of supersets across 28 muscle groups (upper body, lower body, core), with a rest timer, saved weights and a completion estimate.

**Status:** written without a compiler and not yet built. See `CLAUDE.md` for status and next steps, and the README at the top of the repository for how it gets built and shipped.

## Run it on the Mac

1. Open `OMM.xcodeproj` in Xcode 16 or later.
2. Select the **OMM** target → **Signing & Capabilities** and pick your team. The bundle ID is `com.steveburlison.omm`.
3. Pick an iPhone simulator and press **Run**.

Logic tests: `cd Packages/OMMKit && swift test`

The app icon is `OMM/Assets.xcassets/AppIcon.appiconset/AppIcon.png` (1024 × 1024, no transparency).

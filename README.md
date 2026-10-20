# iOS apps

Three native iPhone apps (SwiftUI, iOS 18+), each an Xcode project plus a small Swift package of tested logic:

| Folder | App | Bundle ID |
|---|---|---|
| `OMM/` | OMM: Old Man Maintenance, a superset workout program | `com.steveburlison.omm` |
| `DoThisNow/` | Do This Now, which picks the one thing to do now and includes a day planner | `com.steveburlison.dothisnow` |
| `MutualSwipe/` | Mutual, for swiping on shared decks with iCloud sharing | `com.steveburlison.mutualswipe` |

## How it's built

- **Code** is written and fixed on a Windows PC.
- **GitHub Actions** (`.github/workflows/build.yml`) checks every push to `main` on a cloud Mac. It runs each app's logic tests and builds the app for the iPhone Simulator. Those builds are unsigned, so this repository holds no Apple keys or passwords. Each run leaves a `report-<App>` artifact whose `errors.txt` lists the compiler errors.
- **A Mac** is used only to sign and upload, with `scripts/ship.sh`.

## On the Mac (once)

1. Update Xcode from the Mac App Store, open it once, and add your Apple ID under **Xcode → Settings → Accounts**.
2. In Terminal:

   ```bash
   git clone https://github.com/Steveburli/ios-apps.git ~/Developer/ios-apps
   ```

## On the Mac (each time an app is ready for TestFlight)

```bash
cd ~/Developer/ios-apps
./scripts/ship.sh OMM          # or DoThisNow, or MutualSwipe
```

It pulls the latest code, archives and signs the app with your Xcode account, and uploads it to App Store Connect. The build appears under TestFlight about 10–30 minutes later.

Each app's `CLAUDE.md` describes its layout, rules and current status.

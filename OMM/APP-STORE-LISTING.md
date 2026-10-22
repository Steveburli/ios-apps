# OMM: App Store listing

> **Steve, here's where each part goes** (appstoreconnect.apple.com → Apps → OMM):
> **App Information** (left sidebar) holds the name, subtitle, categories and age rating. **App Privacy** (left sidebar) holds the privacy answers and the privacy policy URL.
> **1.0 Prepare for Submission** (left sidebar, under iOS App) holds the promotional text, description, keywords, support URL and screenshots. For **What to Test**, open the **TestFlight** tab and click the build.
> On GitHub, each gray box has a copy button at its top right. Paste exactly what's inside the box.

## 1. App name

*Where: App Information → Name*

```text
OMM: Old Man Maintenance
```

**24 / 30 characters**

## 2. Subtitle

*Where: App Information → Subtitle*

```text
Supersets for 28 muscle groups
```

**30 / 30 characters**

## 3. Promotional text

*Where: 1.0 Prepare for Submission → Promotional Text. You can change this any time without sending a new version for review.*

```text
Pick an upper-body, lower-body and core group, set your time, and go. OMM times your rests, remembers your weights and crosses off groups until all 28 are done.
```

**160 / 170 characters**

## 4. Description

*Where: 1.0 Prepare for Submission → Description*

```text
OMM (Old Man Maintenance) is a long-term workout program built on supersets. It works through 28 muscle groups across your upper body, lower body and core, and crosses each one off as you train it, until the whole grid is done.

HOW A WORKOUT WORKS
Pick up to three groups on the home grid: one upper-body, one lower-body and one core. Choose how long you have, from 9 to 90 minutes. OMM runs your groups as a superset, three rounds of upper, lower and core, and sets the rest between sets so the workout fits your time.

Each group comes with ten exercises: five you can do with no equipment and five for the gym. Do whichever one suits you that day.

After each set, tap Start Timer. A big countdown shows your rest, and a chime and a buzz tell you when it's over. If your phone is locked, a notification tells you instead. The screen stays on while you work out.

KEEP TRACK
When the workout ends, write down the weight you used for each exercise. Next time, each exercise shows your last weight, and the form is already filled in.

Upper-body groups are crossed off after one workout, lower-body groups after two, and core groups after four. The home screen shows when you started and how many days are left at your current pace. Finish all 28 and OMM tells you how many days it took.

FEATURES
• 28 muscle groups in 7 body areas: core, thighs, calves, chest, back, shoulders and arms
• 280 exercises, half of them with no equipment
• Workouts from 9 to 90 minutes
• Rest timer with a chime, a buzz and a lock-screen notification
• Remembers the weight you used for every exercise, in pounds
• Start date and estimated finish on the home screen
• Reset the program any time to start over

YOUR DATA STAYS ON YOUR PHONE
There's no account to create and there are no ads. Your progress and weights are saved only on your iPhone, and nothing is sent anywhere.

Check with your doctor before starting a new exercise program.
```

**1,924 / 4,000 characters**

## 5. Keywords

*Where: 1.0 Prepare for Submission → Keywords. Words already in the name and subtitle are left out, because Apple searches those anyway.*

```text
workout,exercise,strength,gym,fitness,training,timer,weights,dumbbell,abs,routine,program,bodyweight
```

**100 / 100 bytes** (Apple counts this limit in bytes; plain letters and commas are 1 byte each)

## 6. Category

*Where: App Information → Category*

- **Primary:** Health & Fitness
- **Secondary:** Lifestyle

## 7. Age rating

*Where: App Information → Age Ratings → Set Up Age Ratings (or Edit). Apple's questionnaire changed in 2025, so the names below follow its current sections.*

| Section | Answer |
|---|---|
| In-App Controls | Parental Controls: **No**. Age Assurance: **No**. |
| Capabilities | Unrestricted Web Access, User-Generated Content, Social Media, Messaging and Chat, Advertising: all **No** |
| Mature Themes | All **None** |
| Medical or Wellness | Medical or Treatment Information: **None**. Health or Wellness Topics: **Yes** (if it asks how often, **Frequent**) |
| Sexuality or Nudity | All **None** |
| Violence | All **None**, including Guns or Other Weapons |
| Chance-Based Activities | Gambling: **No**. Simulated Gambling: **None**. Contests: **None**. Loot Boxes: **No**. |
| Age Categories and Override | **Not Applicable** |

**Expected rating: 9+** (Steve is fine with 9+). Why: the whole app is exercise recommendations, and Apple names "exercise recommendations" as an example of Health or Wellness Topics, which it rates 9+. Everything else is absent.

## 8. App Privacy (the "nutrition label")

*Where: App Privacy → Get Started*

**Answer:** "No, we do not collect data from this app." Click **Save**, then **Publish** if the button appears.

**Why:** Apple says data is "collected" only when it leaves the phone in a way that lets you or a partner access it, and that "data that is processed only on device is not 'collected'." OMM keeps everything (progress, weights, start date and the workout length) in the app's own storage on the iPhone. It has no account, no analytics, no ads and no other company's code, and it never connects to the internet. The rest-timer notification is scheduled on the phone itself. The app's privacy manifest already declares that no data is collected, so the two agree.

If you ever add sign-in, syncing, analytics or crash reporting from another company, this answer has to change.

## 9. Privacy policy URL

*Where: App Privacy → Privacy Policy → Edit*

```text
https://steveburlison.com/omm/privacy/
```

## 10. Support URL

*Where: 1.0 Prepare for Submission → Support URL*

```text
https://steveburlison.com/app-support/
```

One shared help page for all the apps, with a section for each app and a way to contact you. It has to be online before you submit for review.

## 11. TestFlight "What to Test"

*Where: TestFlight tab → click the build → What to Test*

```text
Thanks for testing OMM! The best test is one full, short workout. It takes about 10 minutes.

1. On the home screen, tap one box in an upper-body row (Chest, Back, Shoulders or Arms), one in a lower-body row (Thighs or Calves) and one in Core.
2. Slide Workout Duration all the way down to 9 min. Rest is then 30 seconds, so you don't wait long.
3. Tap Start Workout, and allow notifications when asked.
4. After the first set, tap Start Timer. Watch the countdown, and check that a chime and a buzz come when it reaches zero.
5. During the next rest, lock your phone and wait. A notification should arrive when rest is over.
6. During another rest, tap Next Workout while the timer is still running. It should move straight to the next set.
7. After the last set, the weight form opens. Type in a few weights and tap Save & Continue.
8. Back on the home screen, check the Started date and the Estimated completion. Your upper-body group should now be crossed out.
9. Start a second workout using the same core group. Its exercises should show "Last: ... lbs", and the weight form should already have your earlier numbers.
10. Also try Back to Home in the middle of a workout. It should ask before ending.
11. Last, tap Reset Program and confirm. Everything should clear.

Please let me know about:
- anything that crashes or freezes
- a timer that's wrong after you switch apps or lock the phone
- a notification that doesn't arrive, or arrives at the wrong time
- text that's cut off or hard to read
- anything that's confusing
```

**1,529 / 4,000 characters**

## 12. Screenshots (6.9-inch, 1320 × 2868)

*Where: 1.0 Prepare for Submission → Previews and Screenshots → iPhone 6.9" Display. Drag them in this order. Apple resizes them for smaller iPhones.*

The cloud build saves them in the `report-OMM` artifact under `screens/` (open the latest **Build** run on GitHub's Actions tab and scroll down to **Artifacts**). They're kept for 14 days, and **Run workflow** on the Build workflow makes a fresh set. I couldn't download them from here, so this order comes from `OMM/OMM/Support/Screenshots.swift` and `scripts/ci-screenshots.sh`.

| Order | File | What it shows | Caption idea |
|---|---|---|---|
| 1 | `01-home.png` | The home grid, 12 days in, with some groups crossed out | Work all 28 muscle groups |
| 2 | `02-workout.png` | A set in progress, with the exercise lists and the rest timer running | No gym? Every group has five exercises without equipment |
| 3 | `03-weights.png` | The weight form after a workout, with saved weights filled in | Your last weights, filled in for you |
| 4 | `04-complete.png` | "Program Complete!" | Cross off all 28 and see how long it took |

App Store Connect has no caption box. A caption only shows if it's added onto the picture itself. The plain screenshots are fine to upload as they are, and the captions are there in case you make framed versions later.

# Mutual: App Store listing

> **Steve, here's where each part goes** (appstoreconnect.apple.com → Apps → Mutual):
> **App Information** (left sidebar) holds the name, subtitle, categories and age rating. **App Privacy** (left sidebar) holds the privacy answers and the privacy policy URL.
> **1.0 Prepare for Submission** (left sidebar, under iOS App) holds the promotional text, description, keywords, support URL and screenshots. For **What to Test**, open the **TestFlight** tab and click the build.
> On GitHub, each gray box has a copy button at its top right. Paste exactly what's inside the box.

## 1. App name

*Where: App Information → Name*

**Your call.** My suggestion:

```text
Mutual: Decide Together
```

**23 / 30 characters**

Other names that fit:

| Name | Characters | Note |
|---|---|---|
| Mutual: Swipe to Decide | 23 / 30 | Says how it works rather than what it's for |
| Mutual: Swipe Together | 22 / 30 | Short, but "swipe" alone can sound like a dating app |
| Mutual: Pick Together | 21 / 30 | Plain and friendly |

App Store names must be unique, so if App Store Connect says a name is taken, try the next one. The subtitle and keywords below work with any of these names. "Mutual" by itself is likely taken, which is another reason to add the second part.

## 2. Subtitle

*Where: App Information → Subtitle*

```text
Swipe ideas, see what matches
```

**29 / 30 characters**

## 3. Promotional text

*Where: 1.0 Prepare for Submission → Promotional Text. You can change this any time without sending a new version for review.*

```text
Can't agree on dinner, a movie or a weekend away? Make a deck, everyone swipes on their own iPhone, and Mutual shows you what you all agree on.
```

**143 / 170 characters**

## 4. Description

*Where: 1.0 Prepare for Submission → Description*

```text
Can't agree on where to eat, what to watch or where to go? Mutual turns it into a quick swipe. Make a deck of options, everyone swipes on their own iPhone, and Mutual shows you what you agree on.

HOW IT WORKS
Make a deck for anything you're deciding together: date nights, recipes, movies, restaurants, trips or anything else. Add cards one at a time, with quick facts, details, tags and a link if you like, or paste in a whole list at once.

Then everyone swipes:
• Right to like it
• Left for nope
• Up to love it
• Down for never, which also takes the card out of everyone else's stack

Prefer tapping? There are buttons for all four. You can undo a swipe if you change your mind.

SEE WHAT YOU AGREE ON
Results sort every card into groups. Super match means everyone loved it, so start there. Match means every vote was a like or a love. Worth a pitch means someone loved it and someone said nope, so hear them out. Split and Trash are folded away at the bottom. You can also see who still has cards left to swipe.

SWIPE TOGETHER OR PASS THE PHONE
Make a group for each set of people, like family or friends. Invite people with an iCloud link, and everyone in the group sees the same decks on their own iPhone. They'll need Mutual and an iCloud account. Sharing one phone? Add everyone's name and switch who's swiping between turns.

NO ACCOUNT TO CREATE
Mutual has no sign-up, no ads and no server of its own. Each group is stored in the iCloud account of the person who made it, and shared only with the people they invite. If you're not signed in to iCloud, your decks stay on your iPhone.

FEATURES
• Decks for date nights, recipes, movies, restaurants, trips and more
• Add cards one by one or paste a list
• Four swipes: like, nope, love it and never
• Results sorted from Super match to Trash
• Groups shared through iCloud
• Pass-the-phone mode, with a name for each person
• Light and dark mode
```

**1,909 / 4,000 characters**

## 5. Keywords

*Where: 1.0 Prepare for Submission → Keywords. Words already in the name and subtitle are left out, because Apple searches those anyway.*

```text
couples,family,friends,group,vote,dinner,movies,restaurants,recipes,date,trip,plans,agree,decision
```

**98 / 100 bytes** (Apple counts this limit in bytes; plain letters and commas are 1 byte each)

## 6. Category

*Where: App Information → Category*

- **Primary:** Lifestyle
- **Secondary (optional):** Entertainment

I'd avoid Social Networking. Mutual has no public feed, and that category invites questions about social features it doesn't have.

## 7. Age rating

*Where: App Information → Age Ratings → Set Up Age Ratings (or Edit). Apple's questionnaire changed in 2025, so the names below follow its current sections.*

| Section | Answer |
|---|---|
| In-App Controls | Parental Controls: **No**. Age Assurance: **No**. |
| Capabilities | Unrestricted Web Access: **No**. User-Generated Content: **No** (see below). Social Media: **No**. Messaging and Chat: **No** (see below). Advertising: **No**. |
| Mature Themes | All **None** |
| Medical or Wellness | Medical or Treatment Information: **None**. Health or Wellness Topics: **No**. |
| Sexuality or Nudity | All **None** |
| Violence | All **None**, including Guns or Other Weapons |
| Chance-Based Activities | Gambling: **No**. Simulated Gambling: **None**. Contests: **None**. Loot Boxes: **No**. |
| Age Categories and Override | **Not Applicable** |

**Expected rating: 4+.** Why: people only see cards made by people they invited into a private group, there's no feed, and links on cards open in Safari, outside the app.

**Two judgment calls for you:**

- **User-Generated Content.** Apple defines it as "the broad distribution of content created by users." Cards are written by users, but they only reach people the group's owner invited, which isn't broad distribution, so I answered No.
- **Messaging and Chat.** Apple means features that let "users directly communicate with one another," like text or group messaging. Mutual has no messages, only cards and votes, so I answered No.

Answering Yes to either still gives 4+. The catch is that Yes on User-Generated Content can lead App Review to ask for a way to report content and block people (App Review Guideline 1.2), which Mutual doesn't have.

## 8. App Privacy (the "nutrition label")

*Where: App Privacy → Get Started*

**Recommended answer:** "No, we do not collect data from this app." Click **Save**, then **Publish** if the button appears.

**Why:**

- Apple's definition: "'Collect' refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time."
- Mutual's data (group names, decks, cards, names and votes) goes to iCloud through Apple's CloudKit, in the private and shared databases of the users' own iCloud accounts. It never uses CloudKit's public database. You have no server, and you can't read what people store in their own iCloud.
- Apple's guidance says "You are not responsible for disclosing data collected by Apple." It also names CloudKit as a service where you should check whether *you* collect anything through it. Here you don't.
- There's no account, no analytics, no ads and no other company's code. The privacy manifest inside the app already declares that no data is collected, so the two agree.

**What I'm not sure about:** Apple's page doesn't spell out how data in a user's own iCloud should be labelled. It mentions CloudKit only in passing. "Data Not Collected" is the usual reading for apps that store data only in the user's iCloud, and it follows from Apple's definition, but I couldn't find an official Apple statement that says so in plain words. If you'd rather be extra careful, the alternative is to declare **User Content → Other User Content**, used for **App Functionality**, **linked** to the user, **not** used for tracking. That would wrongly suggest you can see people's cards, though, so I don't recommend it.

The answer has to change if you ever add the "Ask Claude for ideas" server from the ideas list, analytics, crash reporting from another company, or anything stored in CloudKit's public database.

## 9. Privacy policy URL

*Where: App Privacy → Privacy Policy → Edit*

```text
https://steveburlison.com/mutual/privacy/
```

Make sure the policy says what the listing says: data lives in iCloud, the person who made a group decides who can see it, and you can't read it.

## 10. Support URL

*Where: 1.0 Prepare for Submission → Support URL*

TBD — Steve to choose. Apple requires a working web page that has a way to contact you, starting with `https://`.

## 11. TestFlight "What to Test"

*Where: TestFlight tab → click the build → What to Test*

```text
Thanks for testing Mutual! Please make sure you're signed in to iCloud first (Settings app, then your name at the top). Mutual saves and shares everything through iCloud.

ON ONE PHONE
1. Tap New deck, give it a name and choose what kind it is.
2. On the Cards tab, add a card or two one at a time. Then use "Paste a list" to add several at once, one per line, for example:
   Tacos | Mexican, 20 min | Quick weeknight dinner
3. Tap "Who's swiping?" at the top and add two names, such as yours and a friend's.
4. Swipe the cards as the first person: right to like, left for nope, up to love it, down for never. Try the buttons under the cards too, and Undo.
5. Switch to the second name and swipe through again.
6. Open Results. Check that each card lands where you'd expect: Super match, Match, Worth a pitch, Split or Trash.
7. On the Cards tab, under Deck settings, try "Clear my swipes", and then "Delete deck".

WITH A SECOND PHONE (if you can)
8. On the first phone, tap the two-people icon at the top, then Invite people. Send the invite to the other phone (Messages works well).
9. On the second phone, tap the link. Mutual should open and join the group. That person needs Mutual installed from TestFlight and must be signed in to iCloud.
10. Both people swipe the same deck. Results should update on both phones within about half a minute. Pull down on the deck list to refresh if needed.

Please let me know about:
- anything that crashes or freezes
- changes that don't show up on the other phone, or show up very late
- any iCloud error message (please send a screenshot)
- cards that land in the wrong Results group
- text that's cut off or hard to read, in light or dark mode
- anything that's confusing
```

**1,718 / 4,000 characters**

## 12. Screenshots (6.9-inch, 1320 × 2868)

*Where: 1.0 Prepare for Submission → Previews and Screenshots → iPhone 6.9" Display. Drag them in this order. Apple resizes them for smaller iPhones.*

The cloud build saves them in the `report-MutualSwipe` artifact under `screens/` (open the latest **Build** run on GitHub's Actions tab and scroll down to **Artifacts**). They're kept for 14 days, and **Run workflow** on the Build workflow makes a fresh set. I couldn't download them from here, so this order comes from `MutualSwipe/MutualSwipe/Support/Screenshots.swift` and `scripts/ci-screenshots.sh`. They use sample decks (date nights, dinners and a weekend trip) with two people, Alex and Sam.

| Order | File | What it shows | Caption idea |
|---|---|---|---|
| 1 | `02-swipe.png` | The "Date nights" deck mid-swipe, with the four swipe buttons | Everyone swipes on their own iPhone |
| 2 | `03-results.png` | Results for that deck, from Super match down | See what you all agree on |
| 3 | `01-home.png` | The deck list: date nights, dinners and a weekend trip | A deck for anything you're deciding |
| 4 | `04-card.png` | The "Sunset picnic" card opened, with its details and everyone's votes | Tap a card for the details |
| 5 (optional) | `05-home-dark.png` | The deck list in dark mode | Dark mode too |

The swipe screen comes first because it shows what the app is for in one look. App Store Connect has no caption box. A caption only shows if it's added onto the picture itself. The plain screenshots are fine to upload as they are, and the captions are there in case you make framed versions later.

# Shipping to the App Store

What's ready in the repository, and what has to happen in App Store Connect and Xcode to ship
Momentum for iPhone, iPad, Apple Watch and Mac.

## Where it stands

Everything in the repository is ready: the apps, privacy manifests, a [privacy policy](PRIVACY.md),
the listing text below, screenshots (`./scripts/app-store-screenshots.sh`) and a script that
archives and uploads both apps (`./scripts/archive.sh`).

What's missing is a paid developer account. The team Xcode signs with today, **636N6HY5DT
("Hassan Mohsen (Personal Team)")**, is a free Personal Team: it runs the apps on your own devices
but can't sign for the App Store, and `scripts/archive.sh` stops on it.

## What the owner does

These steps need you: an account, agreements and payment can't be done on your behalf.

1. **Join the [Apple Developer Program](https://developer.apple.com/programs/enroll/)** with your
   Apple ID (US$99 a year). Enrolled as an individual, the store lists your name as the seller.
2. **Give the scripts the paid team.** Its team ID differs from the Personal Team's: put it in
   `Config/Local.xcconfig` as `DEVELOPMENT_TEAM` (copy `Local.xcconfig.example`). Sign in to that
   team in Xcode (Settings, Accounts), or create an App Store Connect API key (Users and Access,
   Integrations, role App Manager) for `scripts/archive.sh --upload`.
3. **Register the identifiers** in the next section. Automatic signing registers the bundle IDs on
   the first archive; check that the app groups are enabled on them.
4. **Create the app in App Store Connect**: platforms iOS and macOS, bundle ID
   `<prefix>.Momentum`, a SKU of your choosing, and a name. "Momentum" alone is almost certainly
   taken; the listing below uses "Momentum: Goals and Focus".
5. **Choose the price.** Free needs nothing more; a paid app needs the Paid Apps agreement, tax and
   banking in App Store Connect (Business).
6. **Fill in the listing** from the table and texts below, App Privacy as **Data Not Collected**,
   and the age rating questionnaire (4+).
7. **Upload and test**: `./scripts/archive.sh --upload KEY KEY_ID ISSUER` (or archive in Xcode and
   upload from the Organizer), install the build from TestFlight on a device, then submit it for
   review in App Store Connect.

## Already in place

- **Privacy manifests** (`PrivacyInfo.xcprivacy`) in the apps, the widgets and the watch app and
  its complications: no tracking, no data collected, and the reasons for the two required-reason
  APIs used (user defaults: `CA92.1`, and `1C8F.1` for the watch's app-group defaults; file dates
  of the app's own files `C617.1` and of the sync folder the user picks `3B52.1`).
- **Export compliance**: `ITSAppUsesNonExemptEncryption` is `false` on Mac and iOS (no encryption
  beyond HTTPS).
- **Photo library**: saving a shared image asks with `NSPhotoLibraryAddUsageDescription`; nothing
  else needs a permission but notifications.
- **Opaque iOS icon** at 1024 px, generated with the Mac icon by `swift scripts/make_icon.swift`.
- **One bundle ID across platforms** (`$(BUNDLE_ID_PREFIX).Momentum`), so the iPhone, iPad and
  Mac apps can be one universal purchase.
- **Sandboxed Mac app** with only the entitlements it uses: the app group, user-selected files
  (links and the sync folder), app-scoped bookmarks, outgoing network (book search).

## In the Apple Developer account

1. Register the bundle IDs `<prefix>.Momentum`, `<prefix>.Momentum.Widget` (both platforms),
   `<prefix>.Momentum.watchkitapp` (the watch app, embedded in the iPhone app) and
   `<prefix>.Momentum.watchkitapp.Widget` (its complications).
2. Register the app groups: `<team>.<prefix>.momentum` (macOS) and `group.<prefix>.momentum` (iOS
   and watchOS), and enable them on the bundle IDs of each platform.
3. In `Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`. Day-to-day builds
   sign manually with your development certificate; `scripts/archive.sh` switches to automatic
   signing for the store, which creates the distribution certificate and profiles.

## In App Store Connect

| Field | Value |
|-------|-------|
| Name | Momentum: Goals and Focus |
| Subtitle | Streaks, focus timer, journal |
| Category | Productivity (secondary: Health & Fitness) |
| Age rating | 4+ (no objectionable content) |
| Price | Free, or paid once; there are no accounts or subscriptions to support |
| App Privacy | **Data Not Collected** |
| Privacy Policy URL | https://github.com/Leeevai/momentum/blob/main/docs/PRIVACY.md |
| Support URL | https://github.com/Leeevai/momentum/issues |
| Marketing URL | https://github.com/Leeevai/momentum |

**Promotional text.** Show up for what matters, every day: goals, focus sessions, streaks and a
daily journal, with widgets and a Live Activity.

**Description.**

> Momentum helps you do a little of what matters every day. Set goals for time, counts, amounts,
> books or projects; start a focus session in one tap; keep streaks that are fair about rest days;
> and let a coach suggest what's worth doing next.
>
> - Focus sessions with Pomodoro cycles, on the Lock Screen and in the Dynamic Island
> - Rate each session and learn the hour you focus best
> - Streaks with breaks and a minimum for hard days
> - A daily plan and an evening reflection, with mood and energy
> - Challenges from 7 to 100 days, with a dot for every day
> - More than forty awards to earn, from First Step to Year of Momentum
> - Insights into when and how you work best
> - Reading goals with a library, Open Library search and Goodreads import
> - Habit stacking: one goal right after another
> - Widgets for the Home Screen and Lock Screen, and Control Center
> - An Apple Watch app to start sessions and check in from your wrist
> - Sync through your own iCloud Drive folder, with the Mac app
> - No account, no ads, no tracking

**Keywords.** habit,streak,focus,pomodoro,goals,tracker,journal,reading,challenge,routine

**Review notes.** No account or sign-in. To see a running timer, tap Start on any time goal;
the Live Activity appears on the Lock Screen. Sync needs a folder picked in Settings and is
optional. Background audio is used only for the optional focus sounds (Settings, Focus sound),
which keep playing with the screen locked during a session. The Apple Watch app shows what the
iPhone app sends it and needs the iPhone app installed.

## Screenshots

App Store sizes: 6.9" iPhone (1320 × 2868), 13" iPad (2064 × 2752), Apple Watch 46 mm
(416 × 496) and Mac (2880 × 1800). One command makes all of them:

```bash
./scripts/app-store-screenshots.sh   # into AppStoreScreenshots/ (gitignored)
```

It runs the debug build on fresh simulators it creates and deletes (an iPhone paired with a watch,
and an iPad), so your own simulators are left alone, with a clean status bar, in light and dark;
the watch set comes from the iPhone app sending its demo data. The Mac set comes from
`scripts/screenshots/render.sh` at a 1440 × 900 window. The watch needs the watchOS simulator
runtime (`xcodebuild -downloadPlatform watchOS`).

To capture a screen by hand, debug builds of the iPhone
app open demo data with `MOMENTUM_DEMO=1` (`empty` for a first run), a tab with `MOMENTUM_TAB`
(`journal`, `insights`, `awards`, `goal`) and a sheet with `MOMENTUM_SHEET` (`new`, `plan`,
`reflect`, `edit`, `review`, `focus`); by hand:

```bash
SIMCTL_CHILD_MOMENTUM_DEMO=1 SIMCTL_CHILD_MOMENTUM_TAB=journal xcrun simctl launch booted <bundle id>
xcrun simctl io booted screenshot journal.png
```

For the watch by hand, pair a watch simulator with an iPhone simulator, install both apps, and launch the
iPhone app with `MOMENTUM_DEMO=seed` (demo data written to the real data file, which the watch is
sent from). Debug builds of the watch app open a goal with `MOMENTUM_WATCH_GOAL=<name>` and press
one of its buttons with `MOMENTUM_WATCH_ACTION` (`start`, `pause`, `stop` or `log`):

```bash
SIMCTL_CHILD_MOMENTUM_DEMO=seed xcrun simctl launch <iPhone> <bundle id>
SIMCTL_CHILD_MOMENTUM_WATCH_GOAL="Deep work" SIMCTL_CHILD_MOMENTUM_WATCH_ACTION=start \
  xcrun simctl launch <watch> <bundle id>.watchkitapp
```

## Before each submission

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project (all targets).
2. `swift test --package-path Packages/MomentumKit`, and build both schemes for Release.
3. `./scripts/archive.sh` archives both apps and exports them for App Store Connect, or uploads
   them with `--upload KEY KEY_ID ISSUER` (an App Store Connect API key). Xcode's Product, Archive
   and the Organizer do the same by hand. Try the build in TestFlight on a device with an older
   data file before releasing.
4. Update `CHANGELOG.md` and tag the release.

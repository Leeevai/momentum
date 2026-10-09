# Shipping to the App Store

What's ready in the repository, and what has to happen in App Store Connect and Xcode to ship
Momentum for iPhone, iPad and Mac.

## Already in place

- **Privacy manifests** (`PrivacyInfo.xcprivacy`) in both apps and the widgets: no tracking, no
  data collected, and the reasons for the two required-reason APIs used (user defaults: `CA92.1`;
  file dates of the app's own files `C617.1` and of the sync folder the user picks `3B52.1`).
- **Export compliance**: `ITSAppUsesNonExemptEncryption` is `false` (no encryption beyond HTTPS).
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
3. In `Config/Local.xcconfig`, set `DEVELOPMENT_TEAM` and `BUNDLE_ID_PREFIX`. For distribution,
   switch the Mac targets to `CODE_SIGN_STYLE = Automatic` (or create Mac App Store profiles).

## In App Store Connect

| Field | Value |
|-------|-------|
| Name | Momentum: Goals and Focus |
| Subtitle | Streaks, focus timer, journal |
| Category | Productivity (secondary: Health & Fitness) |
| Age rating | 4+ (no objectionable content) |
| Price | Free, or paid once; there are no accounts or subscriptions to support |
| App Privacy | **Data Not Collected** |
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

App Store sizes: 6.9" iPhone (1320 × 2868), 13" iPad (2064 × 2752), Mac (2880 × 1800), and
Apple Watch (Ultra: 422 × 514). The watch screenshots need a watchOS simulator, installed with
`xcodebuild -downloadPlatform watchOS`.

```bash
./scripts/app-store-screenshots.sh   # iPhone 6.9" and iPad 13", light and dark, into AppStoreScreenshots/
```

It runs the debug build on the simulators with a clean status bar. Debug builds of the iPhone
app open demo data with `MOMENTUM_DEMO=1` (`empty` for a first run), a tab with `MOMENTUM_TAB`
(`journal`, `insights`, `awards`, `goal`) and a sheet with `MOMENTUM_SHEET` (`new`, `plan`,
`reflect`, `edit`, `review`, `focus`); by hand:

```bash
SIMCTL_CHILD_MOMENTUM_DEMO=1 SIMCTL_CHILD_MOMENTUM_TAB=journal xcrun simctl launch booted <bundle id>
xcrun simctl io booted screenshot journal.png
```

The Mac screenshots come from `./scripts/screenshots/render.sh`.

## Before each submission

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project (all targets).
2. `swift test --package-path Packages/MomentumKit`, and build both schemes for Release.
3. Archive each scheme in Xcode (Product → Archive) and upload through the Organizer; try the
   build in TestFlight on a device with an older data file before releasing.
4. Update `CHANGELOG.md` and tag the release.

<div align="center">

<img src="Momentum/Assets.xcassets/AppIcon.appiconset/icon_256x256@1x.png" width="128" alt="Momentum app icon">

# Momentum

**Show up for what matters, every day.**
Goals, focus sessions, streaks and reading, with interactive widgets on your Mac's desktop.

[![CI](https://github.com/Leeevai/momentum/actions/workflows/ci.yml/badge.svg)](https://github.com/Leeevai/momentum/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/today-dark.png">
  <img src="docs/images/today-light.png" alt="The Today screen: a running focus session, and every goal due today with its ring, streak and one-click action" width="900">
</picture>

</div>

Momentum is a native macOS app for the hardest part of any goal: doing a little of it every day.
Pick what you want to show up for, and Momentum keeps it in front of you, in a window, in the
menu bar and on your desktop, so starting is always one click away.

## Features

### Five kinds of goals

| Kind | Tracks | Example |
|------|--------|---------|
| ⏱ **Time** | Focused minutes, with a timer or logged by hand | 2 hours of deep work on weekdays |
| ✅ **Count** | Things you do a number of times | 4 workouts a week |
| 🔢 **Amount** | Any number with a unit | 20 pages a day, 100 km a month, $500 saved |
| 📚 **Books** | A reading list: pages read and books finished | 24 books this year |
| 🏁 **Milestones** | A project broken into steps | Launch my portfolio in 6 steps |

Every goal can be **daily** (on the weekdays you choose), **weekly**, **monthly**, **yearly**, or an
**overall** target with a deadline. Momentum projects whether you're on pace.

### Focus that gets you started
- **One-click focus sessions** with Pomodoro lengths, pause and resume, and a note for what you're working on.
- **Links on every goal**: docs, repos, courses, app links like `notion://` or `obsidian://`, even local files and folders.
  Mark a link with ⚡︎ and it **opens automatically when a session starts**, so your workspace is ready.
- **Time's up notifications** with *Stop and save* and *5 more minutes* buttons.
- A **live timer in the menu bar**, and a mini player in the sidebar.

### Reading, properly
A books goal is a small library: *reading*, *up next*, *finished* and *set aside*. Log pages with
one click, set your page, finish books with a rating, and the goal counts the books you finish while
the streak counts the days you read.

### Streaks that are fair
- Days a goal isn't scheduled never break its streak, and **breaks** (a trip, a sick week) protect it entirely.
- Weekly and monthly goals keep **week and month streaks**.
- **Smart reminders** at the time you choose, skipped on days the goal is already done.
- **Streak protection**: an evening nudge when a streak would end at midnight.

### Insights
Focus time per day by goal, your strongest weekday, the hour you focus best, hit rates, streaks,
books and milestones, over 7 days up to a year.

### Widgets
Four interactive widgets in every size. **Start and stop timers, check in, and log pages
right from the desktop** without opening the app.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/widgets-dark.png">
  <img src="docs/images/widgets-light.png" alt="The Today, Goal, Focus and Streaks widgets in small, medium and large sizes" width="760">
</picture>

| Widget | Shows |
|--------|-------|
| **Today** | Every goal due today with its action button; the large size adds a week at a glance |
| **Goal** | One goal you choose: ring, streaks, heatmap, the book you're reading, or next milestones |
| **Focus** | A live countdown with pause and stop, or one-tap starts |
| **Streaks** | Your streaks, longest first |

### And the rest
- **Shortcuts and Siri**: *Start focusing in Momentum*, *Log progress in Momentum*, *How am I doing in Momentum*.
- **Control Center** (macOS 26): a focus toggle for Control Center and the menu bar.
- **Editable history**: fix the time, amount or note of anything you logged.
- **Templates** for common goals, **categories** for grouping, **archive**, **duplicate**, and full **undo**.
- **Export** a JSON backup or a CSV of every entry; **import** a backup.
- **Private by design**: everything stays on your Mac. No account, no network access, no analytics.

## Screenshots

<table>
  <tr>
    <td><img src="docs/images/goal-time-light.png" alt="A time goal: live session, stats, minutes-per-day chart, heatmap, links and history"></td>
    <td><img src="docs/images/goal-books-light.png" alt="A books goal: currently reading, pace, library with ratings, and pages read"></td>
  </tr>
  <tr>
    <td><img src="docs/images/insights-dark.png" alt="Insights: focus time per day by goal, weekday and time-of-day charts, and goal scores"></td>
    <td><img src="docs/images/goal-milestones-dark.png" alt="A milestones goal: checklist with due dates and progress"></td>
  </tr>
</table>

## Keyboard shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘N | New goal |
| ⌘1 / ⌘2 | Today / Insights |
| ⌘3 to ⌘9 | Jump to a goal |
| ⌘E | Edit the selected goal |
| ⌘↩ | Start focus, or log progress, on the selected goal |
| ⇧⌘P | Pause or resume the session |
| ⇧⌘S | Stop and save the session |
| ⌘Z | Undo |

## Install

Momentum builds from source with Xcode. It isn't notarized, so there is no download yet.

**Requirements:** macOS 14 Sonoma or later, Xcode 16 or later (Xcode 26+ for the Liquid Glass look).

```bash
git clone https://github.com/Leeevai/momentum.git
cd momentum
cp Config/Local.xcconfig.example Config/Local.xcconfig   # then set your team ID
./scripts/install.sh
```

`install.sh` builds a Release copy, installs it to `/Applications` and launches it. Then
right-click the desktop → **Edit Widgets…** → search for **Momentum**.

> **Why a team ID?** The app and its widgets are separate processes that share data through an
> app group, and macOS only grants that to signed code. Any Apple ID works, including a free
> one: find your team ID in Xcode → Settings → Accounts.

## Development

```bash
swift test --package-path Packages/MomentumKit   # the core's test suite
open Momentum.xcodeproj                          # run the app from Xcode
./scripts/screenshots/render.sh                  # regenerate docs/images from demo data
```

The project is split so the logic is testable without a UI:

| Path | What lives there |
|------|------------------|
| `Packages/MomentumKit` | **MomentumCore**: the model, the progress engine (periods, streaks, pace, insights), persistence and migrations, reminder planning, CSV export. Swift 6, no UI, fully tested. |
| `Momentum/` | The SwiftUI app: store, side effects (notifications, links), screens, menu bar, Settings, App Shortcuts. |
| `MomentumWidgets/` | The WidgetKit extension. |
| `Shared/` | Code both processes compile: storage location, App Intents for widget buttons, shared views. |
| `Config/` | Signing (`Shared.xcconfig`), entitlements and Info.plists. |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how data flows between the app and the widgets,
and [CONTRIBUTING.md](CONTRIBUTING.md) to get involved.

## Roadmap

- [ ] iCloud sync between Macs
- [ ] An iPhone companion with Lock Screen widgets
- [ ] Control Center controls for the focus timer
- [ ] Book search with covers and page counts
- [ ] Notarized releases

## License

[MIT](LICENSE) © 2026 Leeevai

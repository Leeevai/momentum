# Changelog

All notable changes to Momentum are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-10-08

The first public release: a full rebuild of the 0.1 prototype.

### Added
- Five kinds of goals: time, count, amount (with any unit), books, and milestones.
- Daily (per weekday), weekly, monthly, yearly, and overall targets with deadlines and pace projection.
- Focus sessions with Pomodoro lengths, pause and resume, session notes, and time's-up notifications
  with *Stop and save* and *5 more minutes* actions.
- Links on every goal, including app links and local files and folders, that can open automatically
  when a focus session starts. Drop links or files onto a goal to attach them.
- Books goals with a library (reading, up next, finished, set aside), page logging, ratings, and
  Open Library search that fills in the title, author, page count and cover.
- Milestone checklists with due dates, on any goal.
- Fair streaks: unscheduled days are skipped, breaks protect a streak, and weekly and monthly goals
  keep week and month streaks.
- Smart reminders that skip days a goal is already done, and an evening nudge when a streak would
  end at midnight.
- Editable history: change the time, amount or note of any entry.
- A Control Center focus toggle on macOS 26.
- Insights: focus per day by goal compared with the period before, weekday and time-of-day
  patterns, hit rates, books and milestones.
- Quick actions (⌘K): find any goal and start, log or open it from the keyboard.
- Widgets: Today, Goal (configurable), Focus and Streaks, all interactive.
- Menu bar timer and panel; Settings; App Shortcuts for Shortcuts, Spotlight and Siri.
- Goal templates, categories, archive, duplicate, full undo, keyboard shortcuts.
- Share cards: an image of a goal's ring, streak, numbers and history to save, copy or share.
- JSON backup and restore, CSV export, and automatic daily copies (the last 14 days) you can
  restore from Settings.
- Liquid Glass design on macOS 26 and later, with a material fallback on macOS 14 and 15.

### Changed
- The data file moved to a versioned format. 0.1 data migrates automatically on first launch, and
  the original file is kept as `data.v1-backup.json`.

## 0.1.0 - 2026-10-08

An unpublished prototype.

### Added
- Daily goals tracked by focus time or check-ins, with streaks and an activity heatmap.
- Today and Goal widgets with start/stop and check-in buttons.
- Menu bar timer.

[1.0.0]: https://github.com/Leeevai/momentum/releases/tag/v1.0.0

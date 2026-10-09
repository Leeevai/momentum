# Changelog

All notable changes to Momentum are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **An iPhone and iPad app**, sharing the Mac app's store and screens: Today with goal cards that
  zoom open into their pages, Journal, Insights and Awards in tabs with the Liquid Glass tab bar,
  and Settings. Lock Screen widgets, the Home Screen widgets, a Control Center focus toggle, and
  Siri and Shortcuts come with it.
- **A Live Activity** for the focus timer and Pomodoro breaks, on the Lock Screen and in the
  Dynamic Island, with pause, stop, start-next-block and skip-break buttons.
- **Sync** through a folder in iCloud Drive or any shared folder. Each device writes its own file
  and merges the others' record by record; the merge always converges.
- **Pomodoro cycles**: a planned session that reaches its length is saved exactly and a short
  break begins, with a long break after every few blocks; the next block can start by itself.
  Notifications mark the end of each block and break.
- **A daily journal**: plan the morning with an intention and up to three priorities, shown on
  Today; reflect in the evening with mood, energy, a win and notes. The Journal is a month calendar
  of how each day went.
- **How did it go?** After a focus session, one tap rates it scattered, steady or in the flow.
  Insights shows the share of time in the flow and the hour your sessions go best.
- **Challenges**: commit a goal to a run of days, from a week to a hundred. The goal's page shows
  a dot for every day (kept, missed, a day off, today), Today shows which day it is, and finishing
  without a miss earns an award.
- **Awards**: forty-three achievements in four tiers, measured from history, with progress on the
  ones still locked and a banner when one is earned.
- **A coach** on Today: a streak at risk, the next goal in a stack, a goal's usual hour, targets to
  raise or lower, deadlines falling behind, idle goals, books nearly done, milestones due.
- **Habit stacking**: do a goal right after another; Today orders them and the celebration
  offers the next one.
- **A focus timeline** of the day's sessions on Today and in the Journal.
- **Focus mode**: the running session full screen, over a glow in the goal's colors that breathes
  about six times a minute; Pomodoro breaks show in place, and the iPhone stays awake.
- **A week in review**: focus against the week before, perfect days, each goal's record, the
  wins from the journal and awards earned, from the Journal or the weekly recap notification.
- **Year in pixels**: every day of the past year, colored by progress or by mood.
- **Siri and Shortcuts**: log today's mood (and a win), and hear your week in review.
- Templates for steps, an instrument, yoga, sleep and coding every day.
- On iPad, the tabs become a sidebar.
- **Home Screen quick actions** on iPhone: open the running timer, focus on a goal that still
  needs it today, plan or reflect on the day, or add a goal.
- **Goals in Spotlight** (iOS 18, macOS 15), opening straight to the goal.
- **Haptics** on iPhone that match what happened: start, pause, stop, a break, logging up or
  down, reaching a goal, earning an award.
- **A quick panel from any app** on the Mac, with a global shortcut (Control-Option-M by default).
- **Mood in Insights**: how mood lines up with progress and focus.
- Focus filters: in System Settings → Focus, choose which goal categories Momentum shows while a
  Focus is on. Today, the menu bar and the widgets follow it, with a "Show all" way past it.
- Focus sounds: white, pink or brown noise during a focus session, generated on the fly, fading in
  and out with the timer.
- Book covers from Open Library are saved on the device, so widgets show them and the library
  works offline.

### Changed
- **A new look**: Liquid Glass throughout, mesh-gradient backdrops, vivid glass buttons, Activity
  style rings, goal icons as SF Symbols on gradient tiles in place of emoji, and a new app icon.
  Today's cards morph open into their goals, and Start splits into Pause and Stop.
- **Much faster with long histories**: on five years of heavy use, rebuilding progress after a
  change went from 29 to 5 ms and every streak from 60 to 4 ms; a save no longer re-reads the file
  it just wrote; undo and sync diff only what changed.
- An unknown goal color or book status written by a newer version no longer makes the data file
  unreadable, and a damaged journal entry is skipped rather than failing the file.
- Dates are saved to the exact fraction of a second, so a saved copy always equals the one in
  memory; files with whole-second dates from earlier versions still open.

### Fixed
- Synced devices: a restored backup kept its history only until the next sync; a Pomodoro block
  finished on two devices was logged twice; a session from one device and a break from another
  could both stay active; files from devices gone for months could bring back deleted goals; a
  file still downloading wasn't read again once it arrived.
- Lock Screen, widget and Live Activity buttons first catch up with other devices, and each does
  exactly what it showed: a stale Stop or Pause no longer starts or resumes a session. A paused
  block shows the time left, and the clock counts overtime past the planned end.
- Sync no longer drops a session started on one device when another skips a break, and a stop
  undone on one device no longer erases the same session's stop on another.
- Undo: undoing a journal edit kept nothing written since, and undoing a skipped break could put
  it back over a running session.
- A cached streak could stay stale after entries moved between days.
- Awards: Comeback no longer comes from imported finish dates, weekday goals can earn Flawless
  Week, and a session running past midnight no longer earns Night Owl.
- Goals couldn't be deleted on iPhone; switching tabs could leave widget links and award banners
  doing nothing.
- A reminder's Start stopped a timer already running; a goal's links reopened for every
  Pomodoro block and for sessions started on another device; the day's change could go
  unnoticed after a wake; a banner could be lost or cut short.
- On iPhone, the break's end is always notified, and focus sound keeps playing with the screen
  locked.
- Dragging the volume slider rewrote the data file on every step.
- A deleted goal held one of the day's three priorities; backup names followed the device
  calendar.

## [1.1.0] - 2026-10-08

### Added
- Hover a day in a goal's activity heatmap to see its amount; click it to log progress for that day.
- Session statistics for time goals: how many, the average length and the longest.
- Insights shows where focus time went by category, as an interactive donut.
- Reminders can repeat through the day (every 1, 2 or 3 hours until a set time), and stop once
  the goal is done. The water template uses it.
- Import a Goodreads library export into a books goal: shelves, finish dates, ratings and pages
  carry over, and books already on the list are skipped.

### Changed
- Much faster on long histories: streak history is cached, the data file is written compactly, and
  the app no longer re-reads its own saves.

### Fixed
- Undo no longer reverts changes made after the action (a session started from a widget, a log
  from Shortcuts, a milestone checked off): it reverses only the goal settings, milestones, books,
  links, entries and session the action itself changed, and never discards logged focus time.
- Siri and Shortcuts could start a focus timer on a count or books goal, logging seconds as its unit.
- A break now protects the whole day it starts; "Until Tomorrow" protected nothing.
- Editing a time entry could round it, or turn a correction positive.
- Turning on a deadline without changing the date saved no deadline.
- Reading a finished book again does nothing silently anymore: it starts a new copy and keeps the
  original finish.
- Widget rings froze after 55 minutes of a running session.
- Editing a goal or book while a widget changed it could revert the widget's change.
- Retyping a file link's path kept opening the old file.
- Turning off goal reminders also turned off streak nudges and the weekly recap.
- A correction logged on a different day didn't reduce weekly and monthly totals.
- Pace for a goal less than two weeks old was understated.
- Finishing a time goal with the timer didn't celebrate.
- Quick actions did nothing for a project with every milestone done; it now opens the goal.
- Marking a book finished in the book editor now logs its remaining pages.
- A goal's tracking type can't be changed while its timer runs.
- Imported books count toward a new goal's pace.
- Editing an entry shorter than 30 seconds no longer stretches it to a minute.
- Restoring a backup refreshes the Control Center focus toggle.
- A change from Shortcuts at the same moment as an in-app save could be missed until the next one.
- Once today's goal was done, tomorrow's first reminder could be skipped too.
- A book finished exactly at midnight on New Year's Day counted toward both years.
- Reminders and nudges could fire an hour off on daylight-saving days.
- A new focus session could inherit the previous session's note in the Today banner.
- A negative page count in the book editor could crash the app.

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
- Fair streaks: unscheduled days are skipped, breaks protect a streak, weekly and monthly goals
  keep week and month streaks, and an optional minimum keeps a streak alive on hard days.
- Smart reminders that skip days a goal is already done, an evening nudge when a streak would
  end at midnight, and a weekly recap.
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

[1.1.0]: https://github.com/Leeevai/momentum/releases/tag/v1.1.0
[1.0.0]: https://github.com/Leeevai/momentum/releases/tag/v1.0.0

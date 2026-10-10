---
name: review
description: Review a Momentum pull request or diff for the bugs this codebase has actually had - data compatibility, sync merges, watch and widget payloads, phone-width layouts, CI type-check risks, privacy. Use before marking a big PR ready, after large changes, or when asked to review.
---

# Review a change

Nothing runs on the owner's Mac, so reading closely is the main defence besides CI. Past review
passes after big changes found real sync and watch bugs every time.

```bash
gh pr diff <number>            # or: git diff origin/develop...HEAD
```

Go through, in order:

1. **The ticket** (`.github/CONTRIBUTING.md`, "Pull requests"): the title is
   `[NNNN]-[area] description` and the body opens with `Closes #N` for the same open issue. The
   diff does what the issue's acceptance criteria ask and stays in its one area; anything beyond
   that belongs in an issue of its own, or a sub-issue if the work spans areas.
2. **Saved data** (`data-format` skill): new fields decode when missing, nothing renamed, bad values
   dropped rather than thrown, the version bumped only with a migration and a fixture test.
3. **Sync**: two devices editing the same goal or session; one ending a session the other resumed;
   a delete racing an edit; anything saved without its stamp, or stamped during a merge.
4. **Watch**: commands carry ids and tap dates and apply once; complication pushes are gated on
   `remainingComplicationUserInfoTransfers` alone (`isComplicationEnabled` stays false with a
   WidgetKit complication); a plain `transferUserInfo` doesn't wake a suspended watch app.
5. **Widgets**: timelines come from `WidgetSchedule`; buttons are App Intents in `Shared/Intents`;
   white content on a fill uses `WidgetFilledLabel`; nothing updates every second.
6. **UI**: works at phone width (`ViewThatFits`), and on both Mac and iPhone for anything in
   `SharedUI/`; `Color.accent`, never `accentColor`; the design system in `SharedUI/Components/`;
   Liquid Glass behind `#if compiler(>=6.2)` and `#available`; live time through `LiveClock` or
   `SessionClockText`; mutations through `GoalStore.perform`.
7. **CI risk** (`fix-ci` skill): big view bodies, long expressions in `#expect`, APIs newer than
   the 26 SDK, Swift 6 concurrency in the package.
8. **Privacy**: nothing leaves the device except Open Library book searches. A new network call,
   permission or use of data belongs in `docs/PRIVACY.md` and in the Info.plist usage strings.
9. **Docs**: `CHANGELOG.md` `[Unreleased]` for user-visible changes; the README and
   `docs/ARCHITECTURE.md` when behaviour or data flow changed.

Report each finding with `file:line`, the concrete failure (what the person does, what goes wrong)
and a fix. Post review comments on the PR only when the owner asks.

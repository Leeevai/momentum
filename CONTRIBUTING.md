# Contributing to Momentum

Thanks for helping make Momentum better. Bug reports, ideas and pull requests are all welcome.

## Getting set up

1. Install Xcode 16 or later (Xcode 26+ to see the Liquid Glass design).
2. Clone the repository and create your signing override:
   ```bash
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```
   Set `DEVELOPMENT_TEAM` to your team ID (Xcode → Settings → Accounts; a free Apple ID works) and
   `BUNDLE_ID_PREFIX` to something you own, such as `com.yourname`.
3. Open `Momentum.xcodeproj` and run the **Momentum** scheme, or run `./scripts/install.sh`.

## Before you open a pull request

- **Logic belongs in MomentumCore.** Anything about periods, streaks, amounts or the data format
  goes in `Packages/MomentumKit` with tests; views only display what the engine computes.
- **Run the tests:**
  ```bash
  swift test --package-path Packages/MomentumKit
  ```
  Tests use a fixed calendar and time zone; add one for every behavior you change.
- **Keep data compatible.** Every persisted field decodes with a default when missing. Never rename
  or repurpose a stored field; add a new one. If a format change is unavoidable, bump
  `AppData.currentVersion` and add a migration with a fixture test, as `LegacyDataV1` does.
- **Build both targets** (the app scheme builds the widget extension too) and try the change in the
  app and, if relevant, in a widget.
- **Update the screenshots** if you changed what a screen looks like:
  `./scripts/screenshots/render.sh`.
- Add a line to `CHANGELOG.md` under *Unreleased*.

## Style

- Swift API Design Guidelines; four-space indentation (see `.editorconfig`).
- Prefer small views and small functions. Comment the *why*, not the *what*.
- New UI follows the existing design system in `Momentum/Views/Components/DesignSystem.swift`:
  `glassCard`, `PillButtonStyle`, `AmbientBackground`.
- Live time goes through `LiveClock` or `SessionClockText`, so only the views showing a running
  timer redraw every second.

## Reporting bugs

Open an issue with the bug template: what you did, what you expected, what happened, and your
macOS version. If your data looks wrong, a JSON export (Settings → Data) helps a lot; remove
anything private first.

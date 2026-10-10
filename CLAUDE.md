# Momentum: project guide

Native goal tracker for macOS and iOS: two SwiftUI apps sharing a store and screens, WidgetKit
extensions (with an iPhone Live Activity), and a UI-free core package.
Read `docs/ARCHITECTURE.md` before changing how data flows between the app and the widgets.

## Workflow

- **Every change is a pull request into `develop`**, from a `<type>/<description>` branch; `main`
  only receives release PRs from `develop`, and both are protected. The `ship` skill walks through
  it; `.github/CONTRIBUTING.md` has the full conventions.
- **Conventional Commits** for every commit and every PR title (`commit` skill): small commits that
  each compile, staged by explicit path.
- **Merge commits only.** Squash and rebase merging are off, so every commit keeps its author and
  counts. The owner merges; don't merge PRs yourself.
- Never credit an assistant: no co-author trailers or generated-with lines in commits, PRs or
  comments.

## Building and testing

CI builds and tests every pull request on GitHub (macos-15, Xcode 26.3), running each check as a
parallel job. **Don't run builds, tests or simulators on the owner's Mac**: they pin its CPU. Push
and read the checks instead (`fix-ci` skill). What CI runs:

```bash
swift test --parallel --package-path Packages/MomentumKit
xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' build
xcodebuild -project Momentum.xcodeproj -scheme MomentumMobile -destination 'generic/platform=iOS Simulator' build
```

Local-only scripts, run only on the owner's request: `scripts/install.sh` (Release build into
/Applications), `scripts/screenshots/render.sh` (docs/images from demo data),
`scripts/app-store-screenshots.sh` and `scripts/archive.sh`.

**The guard.** `.claude/settings.json` runs `.claude/hooks/guard_bash.py` before every shell
command. It always refuses pushes straight to `main` or `develop` and commits that skip their hooks
(`--no-verify`, `-n`). On a checkout with `git config momentum.noLocalBuilds true` (the owner's
Mac) it also refuses builds, tests, simulators and the scripts above. When the owner asks for a
local build or install in the conversation, prefix that command with `MOMENTUM_ALLOW_LOCAL_BUILD=1`.

## Where things go

- **Logic and data format → `Packages/MomentumKit/Sources/MomentumCore`**, with a test in
  `Tests/MomentumCoreTests` (fixed calendar from `TestSupport.swift`). The package builds in
  Swift 6 language mode; keep it UI-free.
- **Shared app code → `SharedUI/`** (store, side effects, sync, screens for both platforms);
  Mac-only UI in `Momentum/`, iPhone-only UI in `MomentumMobile/`. Mutations go through
  `GoalStore.perform(_ undoName:_:)`, never straight to the file. Side effects (notifications,
  links, sounds, the Live Activity) belong in `SharedUI/Store/SideEffects.swift`.
- **Widgets → `MomentumWidgets/`.** Widget buttons are App Intents in `Shared/Intents`.
- **Shared by both processes → `Shared/`.** Storage location, intents, shared views.

## Rules

- Never break existing data files: every persisted field decodes with a default when missing.
  Format changes bump `AppData.currentVersion` and add a migration plus a fixture test.
- Live time uses `LiveClock`/`SessionClockText` (app) or `Text` timer styles (widgets); never
  a store-wide per-second tick.
- UI uses the design system in `SharedUI/Components/` (`DesignSystem.swift`, `Glass.swift`).
  Layouts must work at phone width: use `ViewThatFits` for rows that need to stack.
- The look follows glasscn (see "The look" in `docs/ARCHITECTURE.md`): `Color.accent` or the
  `.tint` style for the palette's accent (never `accentColor`), `Aurora()` behind a screen
  (`Aurora(accent: goal.tint)` for a goal's), `glassCard` for panes, `GlassTokens` for numbers.
  Widget content that is white on a fill goes through `WidgetFilledLabel`.
- Liquid Glass APIs go behind `#if compiler(>=6.2)` and `#available(macOS 26.0, iOS 26.0, *)`;
  deployment targets are macOS 14 and iOS 17, and CI may build with an older SDK.
- Every save is stamped for sync by `FileStore.transform`; a merge from another device is written
  with `stamping: false`.
- Measure hot paths against five years of history before adding per-change work (see
  "Performance" in `docs/ARCHITECTURE.md`).
- Signing lives in `Config/Shared.xcconfig`; personal overrides in gitignored `Config/Local.xcconfig`.

## Known traps

- **Grey widget placeholders on the Mac** after a stray build: every `xcodebuild` registers its
  copy with LaunchServices, and a record of another version breaks the desktop widgets. Run
  `scripts/unregister-copies.sh` before deleting a build (`install.sh` does it itself).
- **Watch complications** update only when `transferCurrentComplicationUserInfo` is gated on
  `remainingComplicationUserInfoTransfers` alone; `isComplicationEnabled` stays false with a
  WidgetKit complication.
- **Links to other apps' media** (Instagram and the like) can't be downloaded without signing in,
  and scraping them breaks their terms and App Store guideline 5.2.3: import saved files and keep
  the link.

## Skills

Project skills in `.claude/skills/`:

- `ship`: a change from branch to a green pull request into `develop`.
- `commit`: the Conventional Commits format, and splitting work into commits that each compile.
- `fix-ci`: read and fix a failing check without building locally.
- `release`: the version bump, changelog, release PR to `main`, tag and GitHub release.
- `data-format`: change saved data without breaking existing files, sync, the watch or widgets.
- `review`: check a diff for the bugs this codebase has had.

`.claude/settings.json` also enables the `apple-skills` plugin (Apple platform development skills)
from the `indie-apple-stack` marketplace. Claude Code offers to install it when the project is
trusted.

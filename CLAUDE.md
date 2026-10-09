# Momentum: project guide

Native goal tracker for macOS and iOS: two SwiftUI apps sharing a store and screens, WidgetKit
extensions (with an iPhone Live Activity), and a UI-free core package.
Read `docs/ARCHITECTURE.md` before changing how data flows between the app and the widgets.

## Commands

```bash
swift test --package-path Packages/MomentumKit        # core tests (fast; run after any core change)
xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' build
xcodebuild -project Momentum.xcodeproj -scheme MomentumMobile -destination 'generic/platform=iOS Simulator' build
./scripts/install.sh                                    # Release build, install to /Applications, launch
./scripts/screenshots/render.sh                         # regenerate docs/images from demo data
```

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

## Skills

`.claude/settings.json` enables the `apple-skills` plugin (Apple platform development skills)
from the `indie-apple-stack` marketplace. Claude Code offers to install it when the project is
trusted.

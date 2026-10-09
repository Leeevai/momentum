# Momentum: project guide

Native macOS goal tracker: SwiftUI app + WidgetKit extension + a UI-free core package.
Read `docs/ARCHITECTURE.md` before changing how data flows between the app and the widgets.

## Commands

```bash
swift test --package-path Packages/MomentumKit        # core tests (fast; run after any core change)
xcodebuild -project Momentum.xcodeproj -scheme Momentum -destination 'platform=macOS' build
./scripts/install.sh                                    # Release build, install to /Applications, launch
./scripts/screenshots/render.sh                         # regenerate docs/images from demo data
```

## Where things go

- **Logic and data format → `Packages/MomentumKit/Sources/MomentumCore`**, with a test in
  `Tests/MomentumCoreTests` (fixed calendar from `TestSupport.swift`). The package builds in
  Swift 6 language mode; keep it UI-free.
- **App UI → `Momentum/`.** Mutations go through `GoalStore.perform(_ undoName:_:)`, never straight
  to the file. Side effects (notifications, links, Siri) belong in `Store/SideEffects.swift`.
- **Widgets → `MomentumWidgets/`.** Widget buttons are App Intents in `Shared/Intents`.
- **Shared by both processes → `Shared/`.** Storage location, intents, shared views.

## Rules

- Never break existing data files: every persisted field decodes with a default when missing.
  Format changes bump `AppData.currentVersion` and add a migration plus a fixture test.
- Live time uses `LiveClock`/`SessionClockText` (app) or `Text` timer styles (widgets); never
  a store-wide per-second tick.
- UI uses the design system in `Momentum/Views/Components/DesignSystem.swift`.
- Liquid Glass APIs go behind `#if compiler(>=6.2)` and `#available(macOS 26.0, *)`; the
  deployment target is macOS 14 and CI may build with an older SDK.
- Signing lives in `Config/Shared.xcconfig`; personal overrides in gitignored `Config/Local.xcconfig`.

## Skills

`.claude/settings.json` enables the `apple-skills` plugin (Apple platform development skills)
from the `indie-apple-stack` marketplace. Claude Code offers to install it when the project is
trusted.

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
4. Have git check each commit message as you write it:
   ```bash
   ./scripts/install-hooks.sh
   ```

## Branches

`develop` is the default branch, where changes come together, and `main` holds what has been
released. Nobody pushes to either one: every change is a branch and a pull request into `develop`,
and `main` only takes release pull requests from `develop`, and hotfixes.

Name a branch `<type>/<description>`: one of the commit types below, then a few words in lowercase
kebab-case.

```text
feat/video-todos
fix/streak-after-midnight
docs/watch-simulators
chore/release-2.3.0
```

## Commits

Every commit follows [Conventional Commits 1.0](https://www.conventionalcommits.org/en/v1.0.0/):

```text
<type>(<scope>)!: <subject>

<body>

<footers>
```

- The **type** is required: one from the table below.
- The **scope** is optional: the part of the project, in lowercase kebab-case.
- **`!`** marks a breaking change, such as a data format older versions can't read. A
  `BREAKING CHANGE: <what breaks>` footer does too, and says more.
- The **subject** says what the commit does, in the imperative ("add", not "added"). It starts with
  a lowercase letter and has no period at the end.
- The whole first line is at most 72 characters.
- The **body** is optional. Wrap it at 72 characters and explain why, not how.

| Type | For |
|------|-----|
| `feat` | Something new people can see or do |
| `fix` | A bug fix |
| `perf` | The same behavior, faster or lighter |
| `refactor` | A code change that neither fixes a bug nor adds a feature |
| `style` | Formatting only; the code means the same |
| `test` | Adding or correcting tests |
| `docs` | Documentation only |
| `build` | The Xcode project, the package manifest, build settings and signing |
| `ci` | The GitHub workflows and the checks they run |
| `chore` | Upkeep that changes no app code, such as releases and dependency settings |
| `revert` | Undoing an earlier commit |

Common scopes, though any lowercase kebab-case word works:

| Scope | Covers |
|-------|--------|
| `core` | MomentumCore, in `Packages/MomentumKit` |
| `mac` | The Mac app |
| `ios` | The iPhone and iPad app |
| `watch` | The watch app and its complications |
| `widgets` | The widgets and the Live Activity |
| `ui` | The screens and the design system both apps share, in `SharedUI/` |
| `import` | Importing goals, books and backups |
| `sync` | Sync between devices |
| `scripts` | `scripts/` |
| `ci` | The workflows |
| `deps` | Dependency updates |
| `release` | Versions and release pull requests |
| `readme`, `privacy`, `changelog` | `README.md`, `docs/PRIVACY.md` and `CHANGELOG.md` |

Good:

```text
feat(widgets): add a lock screen widget for the current streak
fix(sync): keep the newer journal entry when two devices edit it
perf(core): compute streaks once a day instead of on every change
docs(readme): explain running the watch app on a simulator
ci: build the iPhone app in its own job
chore(release): v2.3.0
feat(core)!: store focus sessions in their own file
```

Not good:

```text
Add a lock screen widget                  no type
feat: Add a lock screen widget            the subject starts with a capital letter
fix(Sync): keep the newer journal entry   the scope isn't lowercase
fix(sync): keep the newer journal entry.  a period at the end
feature(widgets): add a streak widget     not a type: use feat
fix(widgets): show the right streak on the lock screen widget after midnight
                                          longer than 72 characters
```

To revert a commit, give the revert the subject `revert: ` followed by the subject it undoes:

```bash
git revert --no-commit 1a2b3c4
git commit -m "revert: feat(widgets): add a lock screen widget" -m "This reverts commit 1a2b3c4."
```

Merge commits are exempt: GitHub writes their message.

### Checking commits

The **Conventional commits** check runs on every pull request and lists each commit subject that
breaks the format. The same script runs locally:

```bash
./scripts/install-hooks.sh                                # check each message as you commit
./scripts/check-commits.sh --range origin/develop..HEAD   # check a branch before pushing
```

To fix a subject, amend the last commit (`git commit --amend`) or reword older ones
(`git rebase -i origin/develop`), then push with `git push --force-with-lease`.

## Pull requests

- Open it against `develop`, the default branch. Only releases and hotfixes go to `main`.
- Fill in the template.
- If people will notice the change, add a line to `CHANGELOG.md` under *Unreleased*.
- CI must be green before it's merged.
- Merge it with **Create a merge commit**. Squash and rebase merging are turned off, so every
  commit keeps its author; tidy the commits before merging, and squash any `fixup!` commits.
- The branch is deleted once it's merged.

### What CI runs

| Check | What it does |
|-------|--------------|
| Detect changes | Lets a pull request that only touches documentation skip the macOS jobs |
| Core tests | `swift test --parallel` for MomentumCore |
| Build Mac app and widgets | Builds the **Momentum** scheme |
| Build iPhone and watch apps | Builds **MomentumMobile**, which embeds the watch app |
| Merge gate | Passes when every job above passed or was skipped |
| Conventional commits | Checks every commit subject, merges excepted |

**Merge gate** and **Conventional commits** are the checks `develop` and `main` require. CI runs on
pull requests into either branch, on pushes to them, and from the Actions tab.

CI builds and tests every pull request, so you don't have to before pushing. To run the core tests
yourself:

```bash
swift test --package-path Packages/MomentumKit
```

## Writing code

- **Logic belongs in MomentumCore.** Anything about periods, streaks, amounts or the data format
  goes in `Packages/MomentumKit` with tests; views only display what the engine computes. Tests
  use a fixed calendar and time zone; add one for every behavior you change.
- **Keep data compatible.** Every persisted field decodes with a default when missing. Never rename
  or repurpose a stored field; add a new one. If a format change is unavoidable, bump
  `AppData.currentVersion` and add a migration with a fixture test, as `LegacyDataV1` does.
- **Try the change** in the app and, if relevant, in a widget (each app's scheme builds its widgets
  too).
- **Update the screenshots** if you changed what a screen looks like:
  `./scripts/screenshots/render.sh`.

### Style

- Swift API Design Guidelines; four-space indentation (see `.editorconfig`).
- Prefer small views and small functions. Comment the *why*, not the *what*.
- New UI uses the design system in `SharedUI/Components/` (`DesignSystem.swift`, `Glass.swift`):
  `glassCard` for panes, `Aurora()` behind a screen, `GlassTokens` for numbers and `Color.accent`
  for the palette's accent. "The look" in `docs/ARCHITECTURE.md` explains it.
- Live time goes through `LiveClock` or `SessionClockText`, so only the views showing a running
  timer redraw every second.

## Releases

1. On a branch from `develop`, such as `chore/release-2.3.0`, set `MARKETING_VERSION` to the new
   version and raise `CURRENT_PROJECT_VERSION` by one, in every target of the Xcode project. Move
   the *Unreleased* entries in `CHANGELOG.md` under a `## [2.3.0] - YYYY-MM-DD` heading and update
   the links at the bottom. Merge it into `develop` with a pull request.
2. Open a pull request from `develop` into `main` with the version's notes from the changelog as
   its description, and merge it once CI is green.
3. Tag the merge commit on `main` and push the tag:
   ```bash
   git fetch origin
   git tag -a v2.3.0 origin/main -m "Momentum 2.3.0"
   git push origin v2.3.0
   ```
4. Publish the release with the version's notes; GitHub attaches the source code:
   ```bash
   gh release create v2.3.0 --verify-tag --title "Momentum 2.3.0" --notes-file notes.md
   ```

## Hotfixes

A fix that can't wait for the next release goes to `main` directly:

1. Branch from `main`: `git switch -c fix/<description> origin/main`.
2. Make the fix, with a test. Bump the patch version as a release does (`2.3.0` to `2.3.1`) and
   give it a section of its own in `CHANGELOG.md`.
3. Open a pull request into `main` and merge it once CI is green.
4. Tag and publish `v2.3.1` from `main`, as for a release.
5. Bring the fix back with a pull request from `main` into `develop`. If the two conflict, open it
   from a branch of `main` instead (`git switch -c chore/back-merge-v2.3.1 origin/main`), and merge
   `origin/develop` into that branch to resolve the conflicts there.

## Reporting bugs

Open an issue with the bug template: what you did, what you expected, what happened, and your
macOS version. If your data looks wrong, a JSON export (Settings → Data) helps a lot; remove
anything private first.

---
name: release
description: Cut a Momentum release - pick the version, bump it, close the changelog, open the release PR from develop to main, then tag and publish the GitHub release. Use when the owner asks to release, tag or publish a version, or for a hotfix to main.
---

# Release

A release is source plus notes on GitHub. The App Store is the owner's: never sign in, enroll,
accept agreements, upload or submit (`docs/APP_STORE.md` lists their steps). Don't merge release
PRs; the owner does.

1. **Pick the version with the owner**, by Semantic Versioning over what `[Unreleased]` holds:
   anything breaking → major, any `feat` → minor, only fixes → patch.

2. **Prepare it on a branch** from `develop` (`chore/release-X.Y.Z`):
   - Bump every `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in
     `Momentum.xcodeproj/project.pbxproj`. All targets share them, and the watch app must match the
     iPhone app. Count the matches before and after:

     ```bash
     grep -c 'MARKETING_VERSION = <old>;' Momentum.xcodeproj/project.pbxproj
     sed -i '' 's/MARKETING_VERSION = <old>;/MARKETING_VERSION = <new>;/' Momentum.xcodeproj/project.pbxproj
     sed -i '' 's/CURRENT_PROJECT_VERSION = <build>;/CURRENT_PROJECT_VERSION = <build + 1>;/' Momentum.xcodeproj/project.pbxproj
     ```

   - In `CHANGELOG.md`, rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`, start a new empty
     `## [Unreleased]` above it, and add
     `[X.Y.Z]: https://github.com/Leeevai/momentum/releases/tag/vX.Y.Z` at the top of the link list
     at the bottom.
   - Commit (`chore(release): bump the version to X.Y.Z (build N)`, then
     `docs(changelog): close X.Y.Z`) and ship it as a PR into `develop` (`ship` skill).

3. **Open the release PR** once that has merged. CI must be green; the owner merges it with a merge
   commit.

   ```bash
   gh pr create --base main --head develop --title 'chore(release): vX.Y.Z' --body-file <the X.Y.Z changelog section>
   ```

4. **Tag and publish** after it merges:

   ```bash
   git fetch origin
   git tag -a vX.Y.Z origin/main -m 'Momentum X.Y.Z'
   git push origin vX.Y.Z
   gh release create vX.Y.Z --verify-tag --title 'Momentum X.Y.Z' --notes-file <the X.Y.Z changelog section>
   ```

## Hotfix

For a fix that can't wait for the next release: branch `fix/<description>` from `origin/main`, and
PR it into `main` with the patch bump and its changelog entry. Tag and publish as above, then open a
PR from `main` into `develop` titled `chore(release): bring vX.Y.Z back to develop`, so `develop`
has the fix too.

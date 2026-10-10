---
name: release
description: Cut a Momentum release - pick the version, open the release issue, bump it, close the changelog, open the release PR from develop to main, then tag, publish the GitHub release and close the milestone. Use when the owner asks to release, tag or publish a version, or for a hotfix to main.
---

# Release

A release is source plus notes on GitHub. The App Store is the owner's: never sign in, enroll,
accept agreements, upload or submit (`docs/APP_STORE.md` lists their steps). Don't merge release
PRs; the owner does. `.github/CONTRIBUTING.md` ("Releases" and "Hotfixes") has the full flow.

1. **Pick the version with the owner**, by Semantic Versioning over what `[Unreleased]` holds:
   anything breaking → major, any `feat` → minor, only fixes → patch. Its milestone, named after
   the version, should hold nothing open but the release itself:

   ```bash
   gh issue list --milestone X.Y.Z --state open
   ```

2. **Open the release issue first** (`ticket` skill): `Release X.Y.Z`, with `type: release`,
   `area: release` and the `X.Y.Z` milestone, and a sub-issue `Prepare the X.Y.Z release`, labeled
   the same way. The sub-issue's PR merges into `develop`, which closes it; the parent stays open
   for the release PR into `main`.

3. **Prepare it on a branch** from `develop` (`chore/<NNNN>-release-X.Y.Z`, with the sub-issue's
   number):
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
     `docs(changelog): close X.Y.Z`) and ship it as a PR into `develop` (`ship` skill), titled
     `[NNNN]-[release] prepare X.Y.Z` with `Closes #NNNN`.

4. **Open the release PR** once that has merged, with the parent issue's ticket. CI must be green;
   the owner merges it with a merge commit.

   ```bash
   { echo "Closes #<parent>"; echo; cat <the X.Y.Z changelog section>; } > release-body.md
   gh pr create --base main --head develop --title '[<parent, 4 digits>]-[release] release X.Y.Z' --body-file release-body.md
   ```

5. **Tag and publish** after it merges. `--generate-notes` adds the pull requests after the
   changelog section, grouped by type label (`.github/release.yml`):

   ```bash
   git fetch origin
   git tag -a vX.Y.Z origin/main -m 'Momentum X.Y.Z'
   git push origin vX.Y.Z
   gh release create vX.Y.Z --verify-tag --title 'Momentum X.Y.Z' --notes-file <the X.Y.Z changelog section> --generate-notes
   ```

6. **Close the release issue and the milestone.** GitHub closes issues only for PRs into the
   default branch, so the merge into `main` leaves the parent open. Move anything still open to the
   next milestone first, creating it if needed:

   ```bash
   gh issue close <parent> --comment "Released in vX.Y.Z: https://github.com/Leeevai/momentum/releases/tag/vX.Y.Z"
   gh api repos/Leeevai/momentum/milestones -f title=<next version>
   gh issue list --milestone X.Y.Z --state open --json number --jq '.[].number' |
     xargs -I{} gh issue edit {} --milestone <next version>
   gh api -X PATCH "repos/Leeevai/momentum/milestones/$(gh api repos/Leeevai/momentum/milestones --jq '.[] | select(.title == "X.Y.Z") | .number')" -f state=closed
   ```

## Hotfix

For a fix that can't wait for the next release:

1. **The issue first** (`ticket` skill), usually `type: bug`, in a milestone for the patch version.
2. Branch `fix/<NNNN>-<description>` from `origin/main`, and PR it into `main` with the patch bump,
   its changelog entry, and the issue's ticket: `[NNNN]-[<area>] <description>`, `Closes #NNNN`.
   The issue stays open, since `main` isn't the default branch.
3. Tag and publish as above, and close the patch milestone.
4. Open a PR from `main` into `develop` with the same ticket, such as
   `[NNNN]-[<area>] bring the X.Y.Z fix back to develop` and `Closes #NNNN`, so `develop` has the
   fix too. Merging it closes the issue.

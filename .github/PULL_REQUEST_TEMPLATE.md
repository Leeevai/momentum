Closes #

<!--
Put the issue's number after "Closes #", on this line, and title the pull request with the same
issue: [NNNN]-[area] description, such as [0007]-[ui] show the next video beside the ring. NNNN is
the number padded to four digits, and area is one area label without "area: ". The Ticket check
holds the pull request to both. No issue yet? Open one first.
-->

## What changed

<!-- One or two sentences on what this does and why. -->

## How it was tested

- [ ] `swift test --package-path Packages/MomentumKit` passes
- [ ] Built and ran the app (and the widget, if affected)
- [ ] Screenshots regenerated, if a screen changed

## Checklist

- [ ] Targets `develop`, or `main` for a release or a hotfix
- [ ] The title carries the ticket of the issue it closes, like
      `[0007]-[ui] show the next video beside the ring`
- [ ] `CHANGELOG.md` has a line under *Unreleased*, if people will notice the change

## Notes for review

<!-- Anything a reviewer should look at closely: data format, migrations, widget timelines. -->

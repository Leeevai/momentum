---
name: ticket
description: Find or open the GitHub issue before any Momentum work - type and area labels, one sub-issue per area, the milestone, the board - then name the branch <type>/<NNNN>-<description> and title the PR [NNNN]-[area] description. Use first, before changing anything, for a feature, bug, enhancement, docs or chore alike, and for an open PR that has no ticket.
---

# Ticket: the issue comes first

Everything that changes in Momentum starts as a GitHub issue, and the branch and the pull request
carry its number. `.github/CONTRIBUTING.md` ("Issues first" and "Pull requests") is the full
convention; the required **Ticket** check holds every pull request to it.

## 1. Find the issue

The owner may name one ("do #12"). Otherwise look before opening a duplicate:

```bash
gh issue list --state open --search "<a few words>" --json number,title,labels,milestone
gh issue view <number>
```

An issue that covers the work is the ticket. If it spans several areas and has no sub-issues yet,
split it (step 3) before starting.

## 2. Open it

- **Title**: what to do, in sentence case, with no prefix and no period:
  `Show the next video beside the ring`.
- **One type label**: `type: feature` (new), `type: enhancement` (improves something that
  exists), `type: bug`, `type: docs` (documentation only), `type: task` (refactors, CI, tooling,
  chores) or `type: release`.
- **Area labels**, one per part touched: `ui` (screens and components in `SharedUI/`, `Momentum/`,
  `MomentumMobile/`), `core` (MomentumCore models, engine, persistence), `sync`, `watch`,
  `widgets`, `mac`, `ios`, `import`, `ci`, `docs`, `tooling`, `release`.
  `.github/labels.yml` has every label.
- **The upcoming milestone**, the lowest open version:
  `gh api repos/Leeevai/momentum/milestones --jq '.[].title' | sort -V | head -1`.
- **The body**: what and why, then `### Acceptance criteria` as checkboxes someone can verify.
  No `status: needs triage`: an issue opened this way is triaged already.

```bash
gh issue create --title "Show the next video beside the ring" --body-file <file> \
  --label "type: feature" --label "area: ui" --milestone 2.3.0
```

Nothing in an issue credits an assistant, as in commits and pull requests.

## 3. Split work across areas

Work that touches several areas, such as a new field in `core` and the screen that shows it in
`ui`, gets a parent issue with one sub-issue per area. Each pull request closes one sub-issue, so
each stays in one area. The parent keeps the type and every area; each sub-issue has the type and
its one area, and the same milestone.

```bash
child=$(gh issue create --title "Store the next video's length" --body-file <file> \
  --label "type: feature" --label "area: core" --milestone 2.3.0)
gh api -X POST repos/Leeevai/momentum/issues/<parent>/sub_issues \
  -F sub_issue_id="$(gh api "repos/Leeevai/momentum/issues/${child##*/}" --jq .id)"
```

`sub_issue_id` is the issue's id, not its number. Close the parent when its last sub-issue closes.

## 4. Put it on the board

The [Momentum project](https://github.com/users/Leeevai/projects/1) has a Status for each issue:
**Todo**, **In progress** (a branch exists), **In review** (its pull request is open) and **Done**.
Add the issue, then move it as the work moves:

```bash
item=$(gh project item-add 1 --owner Leeevai --url <issue-url> --format json --jq .id)
gh project item-edit --project-id PVT_kwHOBpnfM84BmfLQ --field-id PVTSSF_lAHOBpnfM84BmfLQzhlIBEs \
  --id "$item" --single-select-option-id 2306ad66
```

| Status | Option id |
|--------|-----------|
| Todo | `3dcb9c57` |
| In progress | `2306ad66` |
| In review | `f2579c49` |
| Done | `7db58ef7` |

If the ids stop matching: `gh project field-list 1 --owner Leeevai --format json`. For an issue
already on the board, find its item with
`gh project item-list 1 --owner Leeevai --format json --jq '.items[] | select(.content.number == <n>) | .id'`.

## 5. Name the branch and the pull request

- **Branch**: `<type>/<NNNN>-<kebab-description>`, with a commit type and the issue's number padded
  to four digits: `feat/0021-next-video-length`, `fix/0012-streak-after-midnight`,
  `ci/0007-issue-first-workflow`.
- **Title**: `[NNNN]-[area] <description>`, with the issue's area, in the imperative, starting in
  lowercase, no period: `[0021]-[core] store the next video's length`. It becomes the merge
  commit's title. Commits keep the Conventional Commits format (`commit` skill).
- **Body**: the template's first line, `Closes #21`, with the same number.

Check a title before opening the pull request, or an open one:

```bash
./scripts/check-ticket.sh --title '[0021]-[core] store the length of the next video'
./scripts/check-ticket.sh --pr <number>
```

Then carry on with the `ship` skill, and move the board item to In review when the pull request
opens.

## An open pull request without a ticket

Find or open its issue (steps 1 and 2), then retitle it and put the Closes line first in its body.
Editing reruns the Ticket check.

```bash
gh pr edit <number> --title '[NNNN]-[area] <description>'
gh pr view <number> --json body --jq .body > body.md   # add "Closes #N" as the first line
gh pr edit <number> --body-file body.md
```

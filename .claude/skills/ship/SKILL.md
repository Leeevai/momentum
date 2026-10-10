---
name: ship
description: Take a Momentum change from its issue to a pull request merged into develop - the ticket, branch naming, Conventional Commits, push, the PR title and template, CI, and the merge. Use for every code, docs or config change once it is ready to commit, or when asked to open, update or merge a PR.
---

# Ship a change

Every change starts as an issue (`ticket` skill) and reaches `develop` through a pull request that
closes it, which whoever opened it merges once it's green; `main` only changes through the release
PR (`release` skill). Both branches are protected: GitHub refuses direct pushes to them.
`.github/CONTRIBUTING.md` has the full conventions.

## Never

- **Build or test on the owner's Mac.** No `xcodebuild`, `swift build`/`test`/`run`, simulators,
  or the scripts that build (`install.sh`, `archive.sh`, `app-store-screenshots.sh`,
  `screenshots/render.sh`): they pin the CPU at 100%. CI builds and tests the PR. Build locally
  only when the owner asks for it in the conversation.
- **Squash, rebase or `--admin`-merge a PR, or merge one into `main`.** A merge commit keeps every
  commit's author, so each counts on the owner's contribution graph. PRs into `main` are the main
  session's to merge.
- **Rewrite a pushed branch** (amend, rebase, force-push) without the owner's go-ahead. Fix forward
  with a new commit; bring in a moved `develop` with a merge.
- **Credit an assistant** anywhere: no co-author trailers, no generated-with lines, no mentions in
  commits, PR titles or bodies, comments or branch names. Commit as the repo's git identity; never
  pass `--author`.

## Steps

1. **Issue first** (`ticket` skill): find or open the issue, with one type label, its area labels
   and the upcoming milestone, split into one sub-issue per area if the work spans several, and
   put it In progress on the board. Its number, padded to four digits, is the ticket: issue #7 is
   `0007`.

2. **Branch from fresh `develop`**, in a worktree if another session may be using the checkout:

   ```bash
   git fetch origin
   git switch -c <type>/<NNNN>-<kebab-description> origin/develop
   ```

   The type is a commit type: `feat/`, `fix/`, `perf/`, `refactor/`, `test/`, `docs/`, `build/`,
   `ci/`, `chore/`. For example `feat/0007-next-video`.

3. **Make the change** following `CLAUDE.md`, and keep to the issue: anything outside it gets an
   issue of its own. Anything saved to disk → `data-format` skill. A user-visible change adds a
   line under `## [Unreleased]` in `CHANGELOG.md` in the same PR.

4. **Commit** with the `commit` skill: small Conventional Commits, explicit paths, each compiling.

5. **Check the branch** before pushing:

   ```bash
   git status --short
   git log origin/develop..HEAD --format='%h %s'
   git log origin/develop..HEAD --format=%B | grep -niE 'claude|anthropic|co-authored|generated with' && echo 'STRIP IT'
   ```

6. **Push and open a draft PR into `develop`.** Title it with the ticket,
   `[NNNN]-[area] <description>` (the issue's area, imperative, lowercase start, no period),
   because it becomes the merge commit's title. The body starts with `Closes #N` for the same
   issue: the first line of `.github/PULL_REQUEST_TEMPLATE.md`. Fill every heading of the template,
   and say how the change was verified (CI, reasoning, or a run the owner did); never claim a local
   run that didn't happen.

   ```bash
   ./scripts/check-ticket.sh --title '[NNNN]-[area] <description>'
   git push -u origin HEAD
   gh pr create --draft --base develop --title '[NNNN]-[area] <description>' --body-file <file>
   ```

   Move the issue to In review on the board (`ticket` skill).

7. **Watch CI on GitHub.** The required checks are **Merge gate**, **Conventional commits** and
   **Ticket**.

   ```bash
   gh pr checks <number> --watch
   ```

   A failure → `fix-ci` skill, then push the fix and watch again. For a big change, run the
   `review` skill over the diff while CI runs.

8. **Merge it once every required check is green and the branch is up to date with `develop`.**
   If `develop` moved, merge it in, push, and wait for the checks again. Then merge with a merge
   commit, never `--squash`, `--rebase` or `--admin`:

   ```bash
   gh pr ready <number>
   git fetch origin
   git merge-base --is-ancestor origin/develop HEAD || echo 'behind: git merge origin/develop, push, watch again'
   gh pr merge <number> --merge
   ```

   `Closes #N` only closes the issue when `develop` is the default branch. If the issue is still
   open after the merge, close it (`gh issue close <issue> --comment "Done in #<number>."`), and
   move it to Done on the board if it didn't move by itself. Give the owner the PR URL.

9. **Clean up** once it's merged: `git worktree remove <path>` for any worktree you created (its
   status must be clean), then `git branch -d <branch>`.

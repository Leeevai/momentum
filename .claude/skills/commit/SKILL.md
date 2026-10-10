---
name: commit
description: Write Momentum commits in the Conventional Commits format and split work into small commits that each compile. Use whenever you commit in this repo.
---

# Commit

`CONTRIBUTING.md` holds the full convention. The **Conventional commits** check on every PR, and
the local commit-msg hook once installed (see `CONTRIBUTING.md`), refuse headers that don't match.

## The header

```
<type>(<scope>)!: <subject>
```

- **type**: `feat`, `fix`, `perf`, `refactor`, `style`, `test`, `docs`, `build`, `ci`, `chore`,
  `revert`.
- **scope** (optional): lowercase kebab-case, the area touched: `core`, `mac`, `ios`, `watch`,
  `widgets`, `ui`, `import`, `sync`, `scripts`, `ci`, `deps`, `release`, `readme`, `privacy`,
  `changelog`, `skills`.
- **subject**: imperative, starts lowercase, no trailing period; the whole header fits in 72
  characters.
- **breaking**: `!` after the scope, or a `BREAKING CHANGE:` footer (an incompatible data format,
  for example).
- **body**: only when the why isn't obvious from the diff. No trailers crediting anyone or anything.

Good:

```
feat(watch): show the streak on the corner complication
fix(sync): keep the newer session when two devices end it
refactor(core): move streak math into DayMath
docs(readme): describe to-dos from videos
```

Bad: `Update stuff`, `feat: Added streaks.`, `fix(Sync): crash`, `feat(ui): Add the new screen`,
`wip`.

## Splitting the work

Small commits are preferred: the owner keeps every commit (merge commits, never squash), and a
reviewer reads the sequence. But **every commit must compile on its own**: CI only builds the
branch tip, and nothing is built locally to check.

- Plan the order first: model and core → logic with its tests → shared UI → platform wiring →
  docs → changelog.
- Keep together what can't compile apart: a new enum case and every `switch` over it, a renamed
  symbol and its call sites, a new type and the first code that needs it.
- Stage explicit paths: `git add <path> <path>`. Never `git add -A`, `git add .`, or a directory
  without reading `git status` first (stray build output has been committed that way).
- Stage whole files; interactive staging (`git add -p`) isn't available here. If one file holds two
  steps, commit it with the later step and say so in the body.
- Read `git diff --cached --stat` before every commit.

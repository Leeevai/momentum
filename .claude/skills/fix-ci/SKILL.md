---
name: fix-ci
description: Diagnose and fix a failing check on a Momentum pull request from its logs, without building locally. Use when gh pr checks shows a failure or a stuck check, when Merge gate, Conventional commits or Ticket is red, or when the type checker times out in CI.
---

# Fix a failing check

CI is the only place Momentum is built and tested. It runs on GitHub's `macos-15` runners with
**Xcode 26.3**, older than the Xcode on the owner's Mac, so code that compiles there can fail in CI.
Don't reproduce it locally: read the log, reason about the fix, push it, and watch again.

## Read the failure

```bash
gh pr checks <number>
gh run list --branch <branch> --limit 5
gh run view <run-id> --log-failed | grep -nE 'error:|failed|Testing failed|✘' | head -40
gh run view <run-id> --log-failed | tail -120
```

**Merge gate** only reports on the jobs it needs: open the job that failed, not the gate.

## Known causes with Xcode 26.3

- **"unable to type-check this expression in reasonable time"**: a long SwiftUI modifier chain, a
  big `body`, or a ternary mixing types. Split it into helper views or computed properties, and
  give literals explicit types.
- **Long expressions inside `#expect` / `#require`** time out the same way: bind the values to
  `let`s first, then `#expect(a == b)`.
- **A local named like the function it calls** (`let status = try #require(status(...))`) fails
  there.
- **APIs newer than the 26 SDK**: `#available(macOS 26.0, iOS 26.0, *)` for 26 APIs, and
  `#if compiler(>=6.2)` or `#if canImport(FoundationModels)` around code that needs a newer
  compiler or framework. An API that only exists in a newer SDK can't ship until CI's Xcode moves.
- **Swift 6 language mode** in `Packages/MomentumKit`: `Sendable` and actor-isolation errors that
  the Swift 5 app targets don't show.
- **Regex literals**: use `#/…/#`; a bare `/…/` doesn't parse in the Swift 5 app targets.

## Conventional commits

The job prints every commit header it refused. A pushed commit subject only changes by rewriting
the branch: ask the owner first, then reword and `git push --force-with-lease`. Never on `develop`
or `main`.

## Ticket

The job says what's wrong with the title or the `Closes` line and prints a corrected title. Fix
the pull request, not the code: editing it reruns the check.

```bash
./scripts/check-ticket.sh --pr <number>
gh pr edit <number> --title '[NNNN]-[area] <description>'
gh pr view <number> --json body --jq .body > body.md   # fix the Closes #N line
gh pr edit <number> --body-file body.md
```

No issue behind the ticket, a closed one, or the number of a pull request: `ticket` skill.

## After the fix

Commit it (`fix(<scope>): …`, `test(<scope>): …` or `ci: …`), push, and run
`gh pr checks <number> --watch` until **Merge gate**, **Conventional commits** and **Ticket** are
green. A job that failed for reasons outside the code (runner outage, cancelled run) gets a rerun:
`gh run rerun <run-id> --failed`.

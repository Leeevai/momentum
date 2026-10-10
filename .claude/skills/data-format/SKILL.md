---
name: data-format
description: Change what Momentum saves - add or change a field on a persisted model (AppData, Goal, Milestone, sessions, Book, Challenge, Journal, Preferences) without breaking existing files, sync, the watch or the widgets. Use before touching any Codable type in MomentumCore.
---

# Change the saved data

A person's whole history is one JSON file. Older app versions read it, other devices merge it
through sync, the widgets read it, and the watch gets a summary of it. A decoding mistake loses
data quietly, so:

1. **Add; never rename or repurpose.** A stored key keeps its name and meaning forever. To change a
   meaning, add a new field and fall back to the old one when reading.

2. **Decode with a default.** A new field is optional, or decoded with `c.decode(.key, default: …)`
   (`Support/Decoding.swift`). A bad value is dropped rather than thrown: one odd field must never
   fail the whole file. `Milestone.duration` is the pattern: a non-finite or non-positive value
   decodes as `nil`.

3. **Bump the version only for an incompatible change.** Additive fields leave
   `AppData.currentVersion` alone. A real format change bumps it, migrates in `FileStore.decode`,
   and adds a fixture test, as `LegacyDataV1` does. `FileStore.decode` refuses a file from a newer
   format, so it's never saved over, and `SyncEnvelope` refuses a sync file in one; keep it that
   way. Sync files don't go through `FileStore.decode`: a migration has to cover
   `SyncEnvelope.init(from:)` too.

4. **Sync.** Saves are stamped by `FileStore.transform`, and a merge from another device is written
   with `stamping: false`. A new field on an existing record travels with its record. A new
   collection or a new kind of record needs merge rules in `Sync/SyncMerge.swift`, with tests. The
   session bookkeeping (`endedSessions`, `startedSessions`, `resumedSessions`) is where two devices
   disagree most: read it before changing anything about sessions.

5. **Watch and widgets.** The watch gets a `WatchSnapshot` (`Watch/WatchSnapshot.swift`) from the
   iPhone, not the file; widgets read the shared file. If they need the field, add it there with
   the same default rules, and expect an older watch app to receive a newer snapshot.

6. **Tests**, in `Packages/MomentumKit/Tests/MomentumCoreTests`: decode a JSON literal written before
   the change (field absent), and round-trip a value with the field set. Bind values to `let`s
   before `#expect` (CI's type checker). CI runs them; don't run them locally.

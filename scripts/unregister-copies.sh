#!/bin/zsh
# Unregisters from LaunchServices every copy of an app (and of its extensions) except one.
#
# Usage: ./scripts/unregister-copies.sh BUNDLE_ID KEEP_PATH
#
# The desktop only draws a widget whose version matches the copy LaunchServices has on record.
# Every Xcode build registers its own copy, and deleting the build leaves the record, so a build
# product or an old build of another version makes each widget reload fail ("Bundle version did
# not match") and leaves grey placeholders. Records under KEEP_PATH stay; records for paths that
# no longer exist are removed too.
set -euo pipefail
(( $# == 2 )) || { print -u2 "Usage: $0 BUNDLE_ID KEEP_PATH"; exit 64; }
BUNDLE_ID="$1"
KEEP="$2"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

"$LSREGISTER" -dump | awk -v id="$BUNDLE_ID" -v keep="$KEEP" '
  function flush() { if (matched && path != "" && index(path, keep) != 1) print path; path = ""; matched = 0 }
  /^-{20,}/ { flush(); next }
  /^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
  /^identifier:/ { if ($2 == id || index($2, id ".") == 1) matched = 1 }
  END { flush() }
' | sort -u | while IFS= read -r stale; do
  "$LSREGISTER" -u "$stale" 2>/dev/null || true
done

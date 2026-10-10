#!/bin/sh
# Has git run the hooks in scripts/hooks for this clone: commit-msg checks each commit message.
git config core.hooksPath scripts/hooks && echo "Git now runs the hooks in scripts/hooks."

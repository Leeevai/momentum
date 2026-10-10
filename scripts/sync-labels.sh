#!/usr/bin/env bash
# Makes the repository's labels match .github/labels.yml: creates the missing ones, renames the
# ones listed under renamed-from, and updates colors and descriptions. Labels on GitHub that the
# file doesn't list are left alone and named at the end.
#
# Usage:
#   ./scripts/sync-labels.sh                    apply the file to the repository
#   ./scripts/sync-labels.sh --dry-run          only print what would change
#   ./scripts/sync-labels.sh --repo owner/name  another repository (default: this checkout's)
#   ./scripts/sync-labels.sh --file <path>      another labels file
#
# Needs gh, signed in with access to the repository's issues. The Labels workflow runs it on each
# push to develop that changes the file, and as a dry run on pull requests that do.
#
# Plain bash 3.2 and awk, so it runs with the tools that ship with macOS.
set -euo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$0")/.." && pwd)
file="$root/.github/labels.yml"
repo=${GITHUB_REPOSITORY:-}
dry_run=false
sep=$'\037'

usage() {
  sed -n '/^# Usage:/,/^# *$/s/^# \{0,1\}//p' "$0" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run) dry_run=true; shift ;;
    --repo | --file)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      case $1 in
        --repo) repo=$2 ;;
        --file) file=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [[ ! -r $file ]]; then
  echo "Can't read $file." >&2
  exit 66
fi
if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

# One line per label: name, color, description and renamed-from, separated by \037. The file must
# keep the shape its header describes; anything else stops the sync with the line number.
wanted=$(awk -v sep="$sep" '
  function fail(message) {
    printf "%s:%d: %s\n", FILENAME, NR, message > "/dev/stderr"
    bad = 1
  }
  function value(line,    rest, end) {
    sub(/^[^:]*:[ \t]*/, "", line)
    if (substr(line, 1, 1) != "\"") {
      fail("put the value in double quotes")
      return ""
    }
    rest = substr(line, 2)
    end = index(rest, "\"")
    if (end == 0 || substr(rest, end + 1) !~ /^[ \t]*(#.*)?$/) {
      fail("one value in double quotes, with no double quotes inside")
      return ""
    }
    return substr(rest, 1, end - 1)
  }
  function flush() {
    if (!open) return
    if (color !~ /^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$/)
      fail("\"" name "\": the color is six hex digits without a #")
    if (description == "")
      fail("\"" name "\": the description is missing")
    else if (length(description) > 100)
      fail("\"" name "\": the description is longer than 100 characters")
    print name sep tolower(color) sep description sep from
    open = 0
  }
  /^[ \t]*(#.*)?$/ { next }
  /^- name:/ {
    flush()
    name = value($0); color = ""; description = ""; from = ""; open = 1
    if (name == "") fail("the name is empty")
    if (tolower(name) in seen) fail("\"" name "\" is listed twice")
    seen[tolower(name)] = 1
    next
  }
  open && /^  color:/ { color = value($0); next }
  open && /^  description:/ { description = value($0); next }
  open && /^  renamed-from:/ { from = value($0); next }
  { fail("expected \"- name:\", \"  color:\", \"  description:\" or \"  renamed-from:\"") }
  END {
    flush()
    exit bad
  }
' "$file")

# The labels on GitHub, one per line: name, color and description, separated by \037.
existing=$(gh label list --repo "$repo" --limit 1000 --json name,color,description \
  --jq '.[] | [.name, (.color | ascii_downcase), (.description // "")] | join("\u001f")')

# Prints the line of the label on GitHub with this name, ignoring case as GitHub does.
find_label() {
  LABEL="$1" awk -F "$sep" 'tolower($1) == tolower(ENVIRON["LABEL"]) { print; exit }' <<EOF
$existing
EOF
}

created=0
renamed=0
updated=0
unchanged=0
failed=0
listed=""
report=""

say() {
  report="$report$1"$'\n'
  printf '%s\n' "$1"
}

run() {
  if [[ $dry_run == true ]]; then
    return 0
  fi
  if ! gh "$@" </dev/null >/dev/null; then
    failed=$((failed + 1))
    say "failed   gh $*"
    return 1
  fi
}

# Past tense for what was done, "would" for a dry run.
if [[ $dry_run == true ]]; then
  did_create="would create" did_rename="would rename" did_update="would update"
else
  did_create="created" did_rename="renamed" did_update="updated"
fi

while IFS="$sep" read -r name color description from; do
  [[ -n $name ]] || continue
  listed="$listed$name"$'\n'
  current=$(find_label "$name")
  if [[ -z $current && -n $from ]]; then
    old=$(find_label "$from")
    if [[ -n $old ]]; then
      listed="$listed${old%%"$sep"*}"$'\n'
      if run label edit "${old%%"$sep"*}" --repo "$repo" --name "$name" --color "$color" \
        --description "$description"; then
        renamed=$((renamed + 1))
        say "$did_rename ${old%%"$sep"*} → $name"
      fi
      continue
    fi
  fi
  if [[ -z $current ]]; then
    if run label create "$name" --repo "$repo" --color "$color" --description "$description"; then
      created=$((created + 1))
      say "$did_create $name"
    fi
    continue
  fi
  IFS="$sep" read -r current_name current_color current_description <<EOF
$current
EOF
  changes=""
  if [[ $current_name != "$name" ]]; then
    changes="name"
  fi
  if [[ $current_color != "$color" ]]; then
    changes="${changes:+$changes, }color"
  fi
  if [[ $current_description != "$description" ]]; then
    changes="${changes:+$changes, }description"
  fi
  if [[ -z $changes ]]; then
    unchanged=$((unchanged + 1))
    continue
  fi
  if run label edit "$current_name" --repo "$repo" --name "$name" --color "$color" \
    --description "$description"; then
    updated=$((updated + 1))
    say "$did_update $name ($changes)"
  fi
done <<EOF
$wanted
EOF

others=""
while IFS="$sep" read -r name _; do
  [[ -n $name ]] || continue
  if ! LABEL="$name" awk 'tolower($0) == tolower(ENVIRON["LABEL"]) { found = 1 } END { exit !found }' <<EOF
$listed
EOF
  then
    others="${others:+$others, }$name"
  fi
done <<EOF
$existing
EOF

if [[ $dry_run == true ]]; then
  summary="Labels in $repo, dry run: $created to create, $renamed to rename, $updated to update, $unchanged unchanged."
else
  summary="Labels in $repo: $created created, $renamed renamed, $updated updated, $unchanged unchanged."
fi
echo
echo "$summary"
if [[ -n $others ]]; then
  echo "Not in .github/labels.yml, left alone: $others"
fi

if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  {
    echo "## Labels"
    echo
    echo "$summary"
    if [[ -n $report ]]; then
      echo
      echo '```text'
      printf '%s' "$report"
      echo '```'
    fi
    if [[ -n $others ]]; then
      echo
      echo "Not in \`.github/labels.yml\`, left alone: $others. Add them to the file, or delete them on GitHub."
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

if [[ $failed -gt 0 ]]; then
  echo "$failed change(s) failed." >&2
  exit 1
fi

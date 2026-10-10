#!/usr/bin/env bash
# Gives an issue the area labels picked in its form's Area dropdown (.github/ISSUE_TEMPLATE). Given
# the description from before an edit too, it follows a changed answer: the areas no longer picked
# lose their label, and an unchanged answer changes nothing, so labels set by hand during triage
# stay.
#
# Usage:
#   ./scripts/label-issue-area.sh --number <n> --body <text>                    a new issue
#   ./scripts/label-issue-area.sh --number <n> --body <text> --old-body <text>  an edited one
#     --repo <owner/name>                                     another repository (default: this one)
#
# The Issue area workflow runs it when an issue is opened or its description is edited.
#
# Plain bash 3.2, so it runs with the bash that ships with macOS. Needs gh.
set -euo pipefail
export LC_ALL=C

repo=${GITHUB_REPOSITORY:-}
number=""
body=""
old_body=""
edited=false

usage() {
  sed -n '/^# Usage:/,/^# *$/s/^# \{0,1\}//p' "$0" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --number | --body | --old-body | --repo)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      case $1 in
        --number) number=$2 ;;
        --body) body=$2 ;;
        --old-body) old_body=$2 edited=true ;;
        --repo) repo=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done
if [[ -z $number ]]; then
  usage
fi
if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi

areas=$(gh api "repos/$repo/labels?per_page=100" --paginate \
  --jq '.[].name | select(startswith("area: ")) | ltrimstr("area: ")')

# The areas a form's answer names, one per line. GitHub writes the answer under "### Area" and
# joins the options picked with commas; each option starts with its area, as in "ui: screens…".
# Options that aren't areas, such as "not sure", are left out.
picked() {
  local word
  printf '%s\n' "$1" | tr -d '\r' | awk '
    /^### / { answer = ($0 == "### Area"); next }
    answer { print }
  ' | tr ',' '\n' | sed -nE 's/^[[:space:]]*([a-z]+)((:|[[:space:]]).*)?$/\1/p' | sort -u |
    while IFS= read -r word; do
      if printf '%s\n' "$areas" | grep -Fxq -- "$word"; then
        echo "$word"
      fi
    done
}

new=$(picked "$body")
old=""
if [[ $edited == true ]]; then
  old=$(picked "$old_body")
  if [[ $new == "$old" ]]; then
    echo "Issue #$number: the Area answer didn't change, so its labels stay as they are."
    exit 0
  fi
fi

# A label name as it goes in a URL path, byte by byte.
uri() {
  local text=$1 out="" char i
  for ((i = 0; i < ${#text}; i++)); do
    char=${text:i:1}
    case $char in
      [A-Za-z0-9._~-]) out=$out$char ;;
      *) out=$out$(printf '%%%02X' "$(($(printf '%d' "'$char") & 255))") ;;
    esac
  done
  printf '%s' "$out"
}

current=$(gh api "repos/$repo/issues/$number/labels?per_page=100" --jq '.[].name | select(startswith("area: ")) | ltrimstr("area: ")')
has() {
  printf '%s\n' "$2" | grep -Fxq -- "$1"
}

# Labels as one name per line, for the API, and as a list for people.
to_add=""
while IFS= read -r area; do
  if [[ -n $area ]] && ! has "$area" "$current"; then
    to_add="${to_add}area: $area"$'\n'
  fi
done <<<"$new"
if [[ -n $to_add ]]; then
  fields=()
  while IFS= read -r name; do
    if [[ -n $name ]]; then
      fields+=(-f "labels[]=$name")
    fi
  done <<<"$to_add"
  gh api -X POST "repos/$repo/issues/$number/labels" "${fields[@]}" >/dev/null
fi
added=$(printf '%s' "$to_add" | paste -sd, - | sed 's/,/, /g')

removed=""
while IFS= read -r area; do
  if [[ -n $area ]] && ! has "$area" "$new" && has "$area" "$current"; then
    gh api -X DELETE "repos/$repo/issues/$number/labels/$(uri "area: $area")" >/dev/null
    removed="${removed:+$removed, }area: $area"
  fi
done <<<"$old"

if [[ -z $added$removed ]]; then
  echo "Issue #$number already has the areas its form names${new:+: $(printf '%s\n' "$new" | paste -sd, - | sed 's/,/, /g')}."
else
  echo "Issue #$number:${added:+ added $added}${added:+${removed:+;}}${removed:+ removed $removed}."
fi
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  {
    echo "## Issue area"
    echo
    if [[ -n $added$removed ]]; then
      echo "#$number:${added:+ added $added}${added:+${removed:+;}}${removed:+ removed $removed}."
    else
      echo "#$number already has the areas its form names, or names none."
    fi
  } >>"$GITHUB_STEP_SUMMARY"
fi

#!/usr/bin/env bash
# Checks that a pull request carries its ticket, as "Pull requests" in .github/CONTRIBUTING.md
# describes:
#
#   [NNNN]-[area] description    the title, such as [0007]-[ui] show the next video beside the ring
#   Closes #N                    a line of its own in the description
#
# NNNN is the number of an open issue in this repository, padded to four digits, and N is the same
# number. The area is the name of an area label without its "area: " prefix. The description is
# imperative, starts in lowercase and has no period at the end. Dependabot's pull requests are
# exempt.
#
# Usage:
#   ./scripts/check-ticket.sh --pr <number>        check an open pull request
#   ./scripts/check-ticket.sh --title "<title>"    check a title before opening its pull request
#     --body <text> | --body-file <file>           check a description's Closes line too
#     --branch <name>                              the head branch, which can suggest the ticket
#     --author <login>                             the author: Dependabot's pull requests are exempt
#     --number <n> --apply-labels                  copy the issue's type and area labels onto n
#     --repo <owner/name>                          another repository (default: this checkout's)
#
# The Ticket workflow runs it on every pull request. It lists what to change with a corrected
# example and exits 1 when the pull request breaks the format, and writes a summary to
# $GITHUB_STEP_SUMMARY when that's set.
#
# Plain bash 3.2, so it runs with the bash that ships with macOS. Needs gh, and jq for labels.
set -euo pipefail
export LC_ALL=C

TYPES="feat fix perf refactor style test docs build ci chore revert"
GUIDE='"Pull requests" in .github/CONTRIBUTING.md'

repo=${GITHUB_REPOSITORY:-}
pr=""
number=""
title=""
title_given=false
body=""
body_given=false
branch=""
author=""
apply_labels=false

usage() {
  sed -n '/^# Usage:/,/^# *$/s/^# \{0,1\}//p' "$0" >&2
  exit 64
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --apply-labels)
      apply_labels=true
      shift
      ;;
    --pr | --number | --title | --body | --body-file | --branch | --author | --repo)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      case $1 in
        --pr) pr=$2 ;;
        --number) number=$2 ;;
        --title) title=$2 title_given=true ;;
        --body) body=$2 body_given=true ;;
        --body-file) body=$(cat -- "$2") body_given=true ;;
        --branch) branch=$2 ;;
        --author) author=$2 ;;
        --repo) repo=$2 ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [[ -z $pr && $title_given == false ]]; then
  usage
fi
if [[ $apply_labels == true && -z $pr && -z $number ]]; then
  echo "--apply-labels needs the pull request: --pr or --number." >&2
  exit 64
fi
if [[ -z $repo ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
fi
if [[ -n $pr ]]; then
  meta=$(gh pr view "$pr" --repo "$repo" --json number,title,headRefName,author \
    --jq '[.number, .title, .headRefName, .author.login] | map(tostring) | join("\u001f")')
  IFS=$'\037' read -r number title branch author <<<"$meta"
  body=$(gh pr view "$pr" --repo "$repo" --json body --jq '.body // ""')
  body_given=true
fi

# --- Helpers ------------------------------------------------------------------------------------

summary() {
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf '%s\n' "$@" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# A GitHub annotation, when running in Actions. Newlines are encoded, so nothing from the pull
# request can start a line: every line this script prints begins with fixed text, and the title
# can't pass for a workflow command.
annotate() {
  local level=$1 message=$2
  if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    message=${message//'%'/%25}
    message=${message//$'\r'/%0D}
    message=${message//$'\n'/%0A}
    printf '::%s title=Ticket::%s\n' "$level" "$message"
  fi
}

# Inline code in Markdown, with table pipes escaped.
code() {
  local text=${1//|/\\|}
  case $text in
    *'`'*) printf '`` %s ``' "$text" ;;
    *) printf '`%s`' "$text" ;;
  esac
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

trim() {
  local text=$1
  text=${text#"${text%%[![:space:]]*}"}
  printf '%s' "${text%"${text##*[![:space:]]}"}"
}

# A description as the title wants it: no period at the end, and a lowercase first letter unless
# the first word is an abbreviation, such as "UI".
tidy() {
  local text first rest
  text=$(trim "$1")
  while [[ $text == *. ]]; do
    text=${text%.}
  done
  first=${text:0:1}
  rest=${text:1}
  if [[ $first == [A-Z] && ${rest:0:1} != [A-Z] ]]; then
    first=$(lower "$first")
  fi
  printf '%s' "$first$rest"
}

# Lines from stdin, joined with commas.
listed() {
  sed '/^$/d' | paste -sd, - | sed 's/,/, /g'
}

is_type() {
  case " $TYPES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

is_area() {
  [[ -n $1 ]] && printf '%s\n' "$areas" | grep -Fxq -- "$1"
}

# The area a commit scope or a common word most likely means.
area_for() {
  case $1 in
    backend | engine | model | persistence) echo core ;;
    frontend | screens | design) echo ui ;;
    iphone | ipad | mobile) echo ios ;;
    macos) echo mac ;;
    watchos | complications) echo watch ;;
    widget | live-activity) echo widgets ;;
    scripts | skills | hooks) echo tooling ;;
    deps | workflows | actions) echo ci ;;
    readme | privacy | changelog | documentation) echo docs ;;
    app-store | version) echo release ;;
    *) echo "$1" ;;
  esac
}

problems=""
warnings=""

problem() {
  problems="$problems$1"$'\n'
}

warning() {
  warnings="$warnings$1"$'\n'
}

# --- Dependabot ---------------------------------------------------------------------------------

case $author in
  'dependabot[bot]' | 'app/dependabot')
    echo "Ticket: Dependabot's pull requests are exempt from the ticket rule, so this one passes."
    annotate notice "Dependabot's pull requests are exempt from the ticket rule: they update dependencies and have no issue."
    summary "## Ticket" "" \
      "✅ Exempt: Dependabot's pull requests update dependencies and have no issue, so they need no ticket."
    exit 0
    ;;
esac

# --- The title ----------------------------------------------------------------------------------

title=${title//$'\r'/ }
title=${title//$'\n'/ }
title=${title//$'\t'/ }
title=$(trim "$title")

ticket=""        # the issue number the title names
area=""          # the title's area, lowercased and without a prefix
description=""   # what follows the area
hinted_area=""   # an area written some other way, for the corrected example
cc_scope=""      # the scope, when the title is in the commit format
title_ok=true

title_problem() {
  title_ok=false
  problem "$1"
}

check_ticket() {
  local digits=$1
  ticket=$((10#$digits))
  if [[ $ticket -eq 0 ]]; then
    title_problem "[$digits] isn't an issue number."
    ticket=""
  elif [[ $digits != "$(printf '%04d' "$ticket")" ]]; then
    title_problem "Pad the issue number to four digits: [$(printf '%04d' "$ticket")], not [$digits]."
  fi
}

check_area() {
  local written=$1 text reported=false
  text=$(trim "$written")
  case $(lower "$text") in
    area:*)
      text=$(trim "${text#*:}")
      title_problem "Write the area without its prefix: [$(lower "$text")], not [$written]."
      reported=true
      ;;
  esac
  if [[ -z $text ]]; then
    title_problem "The area is empty: name one, such as [ui]."
  elif [[ $text == *[\ ,/+\&]* ]]; then
    title_problem "Name one area, not [$written]: a pull request covers one area, and work across areas is one sub-issue per area."
    text=${text%%[ ,/+&]*}
  elif [[ $reported == false && $text != "$written" ]]; then
    title_problem "Leave out the spaces inside the brackets: [$(lower "$text")], not [$written]."
  elif [[ $reported == false && $text != "$(lower "$text")" ]]; then
    title_problem "Write the area in lowercase: [$(lower "$text")], not [$written]."
  fi
  area=$(lower "$text")
}

check_description() {
  local text=$1 commit_format='^([a-z]+)(\([^)]*\))?!?:[[:space:]]*(.*)$'
  if [[ -z $text ]]; then
    title_problem "Add a description after the area: what the pull request does, in the imperative, such as \"show the next video beside the ring\"."
    return
  fi
  if [[ $text =~ $commit_format ]] && is_type "${BASH_REMATCH[1]}"; then
    title_problem "Leave the commit type out of the description: \"$(tidy "${BASH_REMATCH[3]}")\", not \"$text\". Commits keep the commit format; the title doesn't need it."
  elif [[ $text == [A-Z]* ]]; then
    title_problem "Start the description in lowercase: \"$(tidy "$text")\"."
  fi
  if [[ $text == *. ]]; then
    title_problem "Leave out the period at the end of the description."
  fi
}

full='^\[([0-9]+)\]-\[([^]]*)\]( *)(.*)$'
leading_ticket='^\[([0-9]+)\]'
bare_number='^(\[?#[0-9]+|[0-9]+([^0-9]|$))'
placeholder='^\[[Nn]+\]'
commit_title='^([a-z]+)(\(([^)]*)\))?!?:[[:space:]]*(.*)$'
some_area='^\[[^]]*\][[:space:]]*-?[[:space:]]*\[([^]]*)\]'
spaced_hyphen='^[[:space:]]*-[[:space:]]*\['
bare_area='^-([A-Za-z][A-Za-z0-9-]*)'

if [[ $title =~ $full ]]; then
  written_area=${BASH_REMATCH[2]}
  spaces=${BASH_REMATCH[3]}
  description=${BASH_REMATCH[4]}
  check_ticket "${BASH_REMATCH[1]}"
  check_area "$written_area"
  if [[ -n $description && -z $spaces ]]; then
    title_problem "Put a space between [$written_area] and the description."
  elif [[ ${#spaces} -gt 1 ]]; then
    title_problem "Put one space between [$written_area] and the description, not ${#spaces}."
  fi
  check_description "$description"
else
  if [[ $title =~ $some_area ]]; then
    hinted_area=$(lower "$(trim "${BASH_REMATCH[1]#*:}")")
  fi
  if [[ $title =~ $leading_ticket ]]; then
    digits=${BASH_REMATCH[1]}
    check_ticket "$digits"
    padded=$(printf '%04d' "${ticket:-0}")
    after=${title#"[$digits]"}
    if [[ $after == '['* ]]; then
      title_problem "Put a hyphen between the ticket and the area: [$padded]-[area]."
    elif [[ $after =~ $spaced_hyphen ]]; then
      title_problem "Leave out the spaces around the hyphen: [$padded]-[area]."
    elif [[ $after =~ $bare_area ]]; then
      hinted_area=$(lower "${BASH_REMATCH[1]}")
      title_problem "Put the area in square brackets: [$padded]-[$hinted_area]."
    else
      title_problem "Follow the ticket with the area in square brackets: [$padded]-[area], such as [$padded]-[ui]."
    fi
  elif [[ $title =~ $bare_number ]]; then
    title_problem "Write the ticket as the issue number in square brackets, padded to four digits, such as [0007]."
  elif [[ $title =~ $placeholder ]]; then
    title_problem "Replace NNNN with the issue number, padded to four digits."
  elif [[ $title =~ $commit_title ]] && is_type "${BASH_REMATCH[1]}"; then
    cc_scope=$(lower "${BASH_REMATCH[3]}")
    title_problem "The title is in the commit format, which commits keep. A pull request title starts with its ticket and area instead: [NNNN]-[area] description."
  else
    title_problem "Start the title with the ticket and the area: [NNNN]-[area], the issue number padded to four digits, then the name of an area label."
  fi
fi

# --- The description: which issues it closes ----------------------------------------------------

# One finding per line: "closes N", "empty", "inline N" or "other <line>". HTML comments, code
# blocks and inline code are left out: examples there close nothing.
scan=""
if [[ $body_given == true ]]; then
  scan=$(printf '%s\n' "$body" | tr -d '\r' | awk '
    { text = text $0 "\n" }
    END {
      kept = ""
      while ((start = index(text, "<!--")) > 0) {
        kept = kept substr(text, 1, start - 1)
        text = substr(text, start + 4)
        stop = index(text, "-->")
        if (stop == 0) { text = ""; break }
        text = substr(text, stop + 3)
      }
      count = split(kept text, lines, "\n")
      for (i = 1; i <= count; i++) {
        line = lines[i]
        if (line ~ /^[ \t]*(```|~~~)/) { fenced = !fenced; continue }
        if (fenced) continue
        gsub(/`[^`]*`/, "", line)
        gsub(/^[ \t>*-]+|[ \t]+$/, "", line)
        low = tolower(line)
        if (low ~ /^closes[ \t]+#[0-9]+$/) {
          sub(/^closes[ \t]+#/, "", low)
          print "closes " (low + 0)
        } else if (low ~ /^closes[ \t]*#?$/) {
          print "empty"
        } else if (low ~ /^(close|closed|closes|fix|fixes|fixed|resolve|resolves|resolved)[: \t]/ && low ~ /#[0-9]+|\/issues\/[0-9]+/) {
          print "other " line
        } else if (match(low, /closes[ \t]+#[0-9]+/)) {
          found = substr(low, RSTART, RLENGTH)
          sub(/^closes[ \t]+#/, "", found)
          print "inline " (found + 0)
        }
      }
    }')
fi
closed=$(sed -n 's/^closes //p' <<<"$scan")

# The issue the corrected example uses: the title's ticket, or else a number written another way,
# the description's Closes line or the branch name.
written_number='^(\[#?|#)0*([1-9][0-9]*)'
branch_number='^[a-z]+/0*([1-9][0-9]*)-'
suggested_number=$ticket
if [[ -z $suggested_number ]]; then
  if [[ $title =~ $written_number ]]; then
    suggested_number=${BASH_REMATCH[2]}
  elif [[ -n $closed ]]; then
    suggested_number=$(head -1 <<<"$closed")
  elif [[ $branch =~ $branch_number ]]; then
    suggested_number=${BASH_REMATCH[1]}
  fi
fi

# --- The area -----------------------------------------------------------------------------------

areas=$(gh api "repos/$repo/labels?per_page=100" --paginate \
  --jq '.[].name | select(startswith("area: ")) | ltrimstr("area: ")')
area_list=$(printf '%s\n' "$areas" | listed)

area_ok=false
if [[ -n $area ]]; then
  if is_area "$area"; then
    area_ok=true
  elif is_area "$(area_for "$area")"; then
    problem "\"$area\" isn't an area label; \"$(area_for "$area")\" is probably the one. Areas: $area_list."
  else
    problem "\"$area\" isn't an area label. Areas: $area_list."
  fi
fi

# --- The issue ----------------------------------------------------------------------------------

issue_ok=false
issue_found=false
issue_state=""
issue_title=""
issue_labels=""
issue_subs=0
issue_detail=""
lookup=${ticket:-$suggested_number}
if [[ -n $lookup ]]; then
  if found=$(gh api "repos/$repo/issues/$lookup" \
    --jq '.state, (if .pull_request then "pull request" else "issue" end), (.sub_issues_summary.total // 0), .title, (.labels[].name)' 2>&1); then
    issue_state=$(sed -n 1p <<<"$found")
    issue_kind=$(sed -n 2p <<<"$found")
    issue_subs=$(sed -n 3p <<<"$found")
    if [[ $issue_kind == issue ]]; then
      issue_found=true
      issue_title=$(sed -n 4p <<<"$found")
      issue_labels=$(sed -n '5,$p' <<<"$found")
    else
      issue_detail="#$lookup is a pull request"
    fi
  elif [[ $found == *"(HTTP 404)"* || $found == *"(HTTP 410)"* ]]; then
    issue_detail="no issue #$lookup"
  else
    issue_detail="couldn't read #$lookup: $(head -1 <<<"$found")"
  fi
fi
issue_types=$(printf '%s\n' "$issue_labels" | grep '^type: ' || true)
issue_areas=$(printf '%s\n' "$issue_labels" | sed -n 's/^area: //p')

# Only the title's own ticket can fail the check; a number found elsewhere only shapes the example.
if [[ -n $ticket ]]; then
  if [[ $issue_found == true && $issue_state == open ]]; then
    issue_ok=true
  elif [[ $issue_found == true ]]; then
    issue_detail="#$ticket is closed"
    problem "Issue #$ticket is closed. Reopen it if its work isn't done, or open an issue for this change."
  elif [[ $issue_detail == *"pull request" ]]; then
    problem "#$ticket is a pull request, not an issue: use the number of the issue this one closes."
  elif [[ $issue_detail == "no issue"* ]]; then
    problem "There's no issue #$ticket in $repo. Open the issue first (the ticket skill, or the issue forms), then use its number."
  else
    problem "Couldn't read issue #$ticket (${issue_detail#*: })."
  fi
  if [[ $issue_found == true ]]; then
    if [[ -z $issue_types ]]; then
      warning "#$ticket has no type label, so release notes list this pull request under Other changes. Give the issue one: type: feature, bug, enhancement, docs, task or release."
    fi
    if [[ $area_ok == true && -n $issue_areas ]] && ! printf '%s\n' "$issue_areas" | grep -Fxq -- "$area"; then
      warning "The title's area, $area, isn't one of #$ticket's areas ($(printf '%s\n' "$issue_areas" | listed)). Check the ticket, or add area: $area to the issue."
    fi
    if [[ ${issue_subs:-0} -gt 0 ]]; then
      warning "#$ticket has sub-issues. A pull request usually closes one of them, one sub-issue per area."
    fi
  fi
fi

# --- The Closes line ----------------------------------------------------------------------------

# What's wrong with the description's closing line, given the issue it should close.
closes_problem() {
  local expected=$1 other
  other=$(sed -n 's/^other //p' <<<"$scan" | head -1)
  if [[ -n $closed && -n $ticket ]]; then
    problem "The description closes #$(head -1 <<<"$closed"), but the title's ticket is #$ticket. Close the issue the title names: Closes #$ticket."
  elif [[ -n $other ]]; then
    problem "Write the closing line as \"Closes #$expected\", on a line of its own, instead of \"$other\"."
  elif grep -q '^empty$' <<<"$scan"; then
    problem "The Closes line has no issue number: write Closes #$expected."
  elif grep -q '^inline ' <<<"$scan"; then
    problem "Put \"Closes #$expected\" on a line of its own; it's part of a sentence now."
  elif [[ $expected == N ]]; then
    problem "Add a line to the description: Closes #N, with the issue's number."
  else
    problem "Add a line to the description: Closes #$expected."
  fi
}

closes_ok=skip
closes_detail="not checked"
if [[ $body_given == true && -n $ticket ]]; then
  if printf '%s\n' "$closed" | grep -Fxq -- "$ticket"; then
    closes_ok=pass
    closes_detail="Closes #$ticket"
    others=$(printf '%s\n' "$closed" | grep -Fxv -- "$ticket" | sed 's/^/#/' | listed || true)
    if [[ -n $others ]]; then
      warning "The description also closes $others. A pull request usually closes one issue."
    fi
  else
    closes_ok=fail
    closes_detail="no Closes #$ticket line"
    closes_problem "$ticket"
  fi
elif [[ $body_given == true && -z $closed ]]; then
  closes_ok=fail
  closes_detail="no Closes line"
  closes_problem "${suggested_number:-N}"
elif [[ $body_given == true ]]; then
  closes_detail="checked once the title has its ticket"
fi

# --- A corrected example ------------------------------------------------------------------------

if [[ -n $suggested_number ]]; then
  suggested_ticket=$(printf '%04d' "$suggested_number")
else
  suggested_ticket="NNNN"
fi

suggested_area=""
for written in "$area" "$hinted_area" "$cc_scope"; do
  for candidate in "$written" "$(area_for "$written")"; do
    if [[ -z $suggested_area ]] && is_area "$candidate"; then
      suggested_area=$candidate
    fi
  done
done
if [[ -z $suggested_area && -n $issue_areas && $issue_areas != *$'\n'* ]]; then
  suggested_area=$issue_areas
fi

# What follows the ticket, the area and any commit type; else the issue's title.
rest=$description
if [[ -z $rest ]]; then
  rest=$(sed -E '
    s/^\[#?[0-9]+\][[:space:]]*//
    s/^#[0-9]+[[:space:]:-]*//
    s/^\[[Nn]+\][[:space:]]*//
    s/^-?[[:space:]]*\[[^]]*\][[:space:]]*//
    s/^-[A-Za-z][A-Za-z0-9-]*[[:space:]]+//' <<<"$title")
fi
commit_format='^([a-z]+)(\([^)]*\))?!?:[[:space:]]*(.*)$'
if [[ $rest =~ $commit_format ]] && is_type "${BASH_REMATCH[1]}"; then
  rest=${BASH_REMATCH[3]}
fi
rest=$(tidy "$rest")
if [[ -z $rest && -n $issue_title ]]; then
  rest=$(tidy "$issue_title")
fi
suggested_title="[$suggested_ticket]-[${suggested_area:-area}] ${rest:-describe the change}"
suggested_closes="Closes #${suggested_number:-N}"

# --- Labels -------------------------------------------------------------------------------------

labels_note=""
if [[ $apply_labels == true && -n $ticket && $issue_found == true ]]; then
  # The pull request's type and area labels follow its issue's, with the title's area added.
  wanted=$(printf '%s\n' "$issue_labels" | grep -E '^(type|area): ' || true)
  if [[ $area_ok == true ]]; then
    wanted=$(printf '%s\narea: %s\n' "$wanted" "$area")
  fi
  wanted=$(printf '%s\n' "$wanted" | sed '/^$/d' | sort -u)
  if current=$(gh api "repos/$repo/issues/$number/labels?per_page=100" --jq '.[].name' 2>&1); then
    current=$(printf '%s\n' "$current" | grep -E '^(type|area): ' | sort -u || true)
    add=""
    remove=""
    while IFS= read -r name; do
      if [[ -n $name ]] && ! printf '%s\n' "$current" | grep -Fxq -- "$name"; then
        add="$add$name"$'\n'
      fi
    done <<<"$wanted"
    while IFS= read -r name; do
      if [[ -n $name ]] && ! printf '%s\n' "$wanted" | grep -Fxq -- "$name"; then
        remove="$remove$name"$'\n'
      fi
    done <<<"$current"
    label_error=""
    if [[ -n $add ]]; then
      payload=$(printf '%s' "$add" | jq -R . | jq -sc '{labels: .}')
      if ! output=$(gh api -X POST "repos/$repo/issues/$number/labels" --input - <<<"$payload" 2>&1 >/dev/null); then
        label_error=$output
      fi
    fi
    while IFS= read -r name; do
      [[ -n $name ]] || continue
      if ! output=$(gh api -X DELETE "repos/$repo/issues/$number/labels/$(jq -rn --arg name "$name" '$name | @uri')" 2>&1 >/dev/null); then
        label_error=$output
      fi
    done <<<"$remove"
    if [[ -n $label_error ]]; then
      warning "Couldn't update the pull request's labels ($(head -1 <<<"$label_error")). Give it the issue's labels by hand: $(printf '%s\n' "$wanted" | listed)."
    elif [[ -n $add$remove ]]; then
      labels_note="Labels from #$ticket:${add:+ added $(printf '%s' "$add" | listed)}"
      if [[ -n $add && -n $remove ]]; then
        labels_note="$labels_note;"
      fi
      labels_note="$labels_note${remove:+ removed $(printf '%s' "$remove" | listed)}."
    elif [[ -n $wanted ]]; then
      labels_note="Labels from #$ticket, already on the pull request: $(printf '%s\n' "$wanted" | listed)."
    fi
  else
    warning "Couldn't read the pull request's labels ($(head -1 <<<"$current"))."
  fi
fi

# --- Report -------------------------------------------------------------------------------------

mark() {
  case $1 in
    pass | true) printf '✅' ;;
    fail | false) printf '❌' ;;
    *) printf '➖' ;;
  esac
}

issue_label_list=$(printf '%s\n' "$issue_labels" | grep -E '^(type|area): ' | listed || true)

if [[ -z $problems ]]; then
  echo "Ticket: #$ticket $issue_title"
  echo "  title        $title"
  echo "  issue        #$ticket is open${issue_label_list:+: $issue_label_list}"
  echo "  area         $area"
  echo "  description  $closes_detail"
  if [[ -n $labels_note ]]; then
    echo "  $labels_note"
  fi
else
  echo "Ticket: the pull request doesn't carry its ticket yet."
  echo
  echo "  Title: $title"
  echo
  printf '%s' "$problems" | sed 's/^/  - /'
  echo
  echo "  Corrected title:"
  echo "    $suggested_title"
  if [[ $closes_ok == fail ]]; then
    echo "  And on a line of its own in the description:"
    echo "    $suggested_closes"
  fi
  if [[ $suggested_ticket == NNNN ]]; then
    echo "  NNNN is the issue's number, padded to four digits. Open the issue first if there isn't one."
  fi
  echo
  if [[ -n $number ]]; then
    echo "  To fix the title: gh pr edit $number --title '$(printf '%s' "$suggested_title" | sed "s/'/'\\\\''/g")'"
  fi
  echo "  Editing the pull request runs this check again. $GUIDE has the rules."
  annotate error "$(printf '%s' "$problems")"$'\n'"Corrected title: $suggested_title"
fi
if [[ -n $warnings ]]; then
  echo
  printf '%s' "$warnings" | sed 's/^/  Note: /'
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      annotate warning "$line"
    fi
  done <<<"$warnings"
fi

if [[ -n $ticket ]]; then
  if [[ $issue_ok == true ]]; then
    issue_row="#$ticket $issue_title"
  else
    issue_row=$issue_detail
  fi
else
  issue_row="no ticket in the title"
fi
if [[ -z $area ]]; then
  area_row="no area in the title"
elif [[ $area_ok == true ]]; then
  area_row=$(code "$area")
else
  area_row="$(code "$area") isn't one: $area_list"
fi

summary "## Ticket" ""
if [[ -z $problems ]]; then
  summary "✅ Closes #$ticket, $issue_title${issue_label_list:+ ($issue_label_list)}."
else
  summary "❌ The pull request doesn't carry its ticket yet."
fi
summary "" \
  "| | Check | Result |" \
  "|---|---|---|" \
  "| $(mark "$title_ok") | The title is \`[NNNN]-[area] description\` | $(code "${title:-(empty)}") |" \
  "| $(mark "$issue_ok") | The ticket is an open issue | ${issue_row//|/\\|} |" \
  "| $(mark "$area_ok") | The area is an area label | $area_row |" \
  "| $(mark "$closes_ok") | The description has \`Closes #${ticket:-N}\` | $closes_detail |"
if [[ -n $problems ]]; then
  summary "" "### What to change" ""
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      summary "- $line"
    fi
  done <<<"$problems"
  summary "" "Corrected title:" "" '```text' "$suggested_title" '```'
  if [[ $closes_ok == fail ]]; then
    summary "" "And on a line of its own in the description:" "" '```text' "$suggested_closes" '```'
  fi
  if [[ $suggested_ticket == NNNN ]]; then
    summary "" "NNNN is the issue's number, padded to four digits. Open the issue first if there isn't one."
  fi
  summary "" "Editing the pull request runs this check again. $GUIDE has the rules."
fi
if [[ -n $warnings ]]; then
  summary "" "### Worth knowing" ""
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      summary "- $line"
    fi
  done <<<"$warnings"
fi
if [[ -n $labels_note ]]; then
  summary "" "$labels_note"
fi

if [[ -n $problems ]]; then
  exit 1
fi

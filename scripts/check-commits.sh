#!/usr/bin/env bash
# Checks commit subjects against the commit format in .github/CONTRIBUTING.md, Conventional
# Commits 1.0:
#
#   <type>(<scope>)!: <subject>
#
# The scope and the ! are optional. The scope is lowercase kebab-case, the subject starts with a
# lowercase letter (or a digit) and has no period at the end, and the header is at most 72
# characters long.
#
# Usage:
#   ./scripts/check-commits.sh --range <base>..<head>   each commit in the range, merges excepted
#   ./scripts/check-commits.sh --message-file <file>    a commit message (the commit-msg hook)
#
# Every subject that breaks the format is printed with the reasons, and the script exits 1 if
# there was one. The Conventions workflow runs it on each pull request.
#
# Plain bash 3.2, so the hook runs with the bash that ships with macOS.
set -euo pipefail
export LC_ALL=C

TYPES="feat fix perf refactor style test docs build ci chore revert"
MAX_LENGTH=72

checked=0
failed=0
message_file=""

usage() {
  sed -n '/^# Usage:/,/^# *$/s/^# \{0,1\}//p' "$0" >&2
  exit 64
}

is_type() {
  case " $TYPES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# Prints why a header breaks the format, one reason per line, or nothing when it follows it.
problems_with() {
  local header=$1
  local shape='^([A-Za-z]+)(\(([^)]*)\))?(!?): (.*)$'
  local kebab='^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
  local lowercase_start='^[a-z0-9]'
  local type scope_part scope subject length

  case $header in
    'fixup! '* | 'squash! '* | 'amend! '*)
      echo "a fixup commit: squash it into its target first (git rebase -i --autosquash)"
      return 0
      ;;
  esac

  if [[ $header =~ $shape ]]; then
    type=${BASH_REMATCH[1]}
    scope_part=${BASH_REMATCH[2]}
    scope=${BASH_REMATCH[3]}
    subject=${BASH_REMATCH[5]}
    if ! is_type "$type"; then
      echo "\"$type\" is not a type; use one of: $TYPES"
    fi
    if [[ -n $scope_part && -z $scope ]]; then
      echo "the scope is empty; leave out the parentheses"
    elif [[ -n $scope && ! $scope =~ $kebab ]]; then
      echo "the scope \"$scope\" is not lowercase kebab-case"
    fi
    if [[ -z $subject ]]; then
      echo "the subject is empty"
    elif [[ $subject == [[:space:]]* ]]; then
      echo "more than one space after the colon"
    elif [[ ! $subject =~ $lowercase_start ]]; then
      echo "the subject does not start with a lowercase letter"
    fi
    if [[ $subject == *. ]]; then
      echo "the subject ends with a period"
    fi
  else
    echo "not in the form <type>(<scope>)!: <subject>"
  fi

  # Characters, not bytes: UTF-8 continuation bytes are left out of the count.
  length=$(printf '%s' "$header" | tr -d '\200-\277' | wc -c)
  length=$((length))
  if [[ $length -gt $MAX_LENGTH ]]; then
    echo "$length characters long; the limit is $MAX_LENGTH"
  fi
}

# Reports a header that breaks the format; as a GitHub annotation too when running in Actions.
# Every printed line starts with fixed text, so a header can't pass for a workflow command.
report() {
  local label=$1 header=$2 problems=$3 annotation
  printf '%s: %s\n' "$label" "$header"
  printf '%s\n' "$problems" | sed 's/^/  - /'
  if [[ ${GITHUB_ACTIONS:-} == true ]]; then
    annotation="$label: $header"$'\n'"$problems"
    annotation=${annotation//'%'/%25}
    annotation=${annotation//$'\r'/%0D}
    annotation=${annotation//$'\n'/%0A}
    printf '::error title=Conventional commits::%s\n' "$annotation"
  fi
}

check() {
  local label=$1 header=$2 problems
  checked=$((checked + 1))
  # Trailing whitespace is not part of the header: git drops it from commit messages too.
  header=${header%"${header##*[![:space:]]}"}
  problems=$(problems_with "$header")
  if [[ -n $problems ]]; then
    failed=$((failed + 1))
    report "$label" "$header" "$problems"
  fi
}

check_range() {
  local range=$1 log line
  if ! log=$(git log --no-merges --reverse --format='%h%x09%s' "$range" --); then
    echo "Can't read the commits in $range." >&2
    exit 66
  fi
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      check "commit ${line%%$'\t'*}" "${line#*$'\t'}"
    fi
  done <<EOF
$log
EOF
}

# The subject as git will record it: the message's first paragraph on one line, leaving out
# comment lines and the diff that git commit --verbose adds below the scissors line.
subject_of() {
  local file=$1 comment line subject=""
  comment=$(git config core.commentChar 2>/dev/null || true)
  case $comment in
    '' | auto) comment='#' ;;
  esac
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    case $line in
      "$comment ------------------------ >8 ------------------------"*) break ;;
      "$comment"*) continue ;;
    esac
    line=${line%"${line##*[![:space:]]}"}
    if [[ -n $line ]]; then
      subject=${subject:+$subject }$line
    elif [[ -n $subject ]]; then
      break
    fi
  done <"$file"
  printf '%s' "$subject"
}

check_message_file() {
  local subject
  message_file=$1
  if [[ ! -r $message_file ]]; then
    echo "Can't read $message_file." >&2
    exit 66
  fi
  # Merge commits are exempt, and git writes their message.
  if git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
    return 0
  fi
  subject=$(subject_of "$message_file")
  case $subject in
    # Git aborts a commit with an empty message on its own.
    '') return 0 ;;
    # Squashed into another commit before the branch is merged; CI reports any left over.
    'fixup! '* | 'squash! '* | 'amend! '*) return 0 ;;
  esac
  check "commit" "$subject"
}

if [[ $# -eq 0 ]]; then
  usage
fi
while [[ $# -gt 0 ]]; do
  case $1 in
    --range | --message-file)
      if [[ $# -lt 2 ]]; then
        usage
      fi
      case $1 in
        --range) check_range "$2" ;;
        --message-file) check_message_file "$2" ;;
      esac
      shift 2
      ;;
    *) usage ;;
  esac
done

if [[ $failed -gt 0 ]]; then
  echo
  echo "Commit format: $((checked - failed)) of $checked passed."
  echo "See .github/CONTRIBUTING.md for the format."
  if [[ -n $message_file ]]; then
    echo "To edit the message and commit again: git commit -e -F $message_file"
  fi
  exit 1
fi
if [[ -z $message_file ]]; then
  if [[ $checked -eq 0 ]]; then
    echo "Commit format: nothing to check."
  else
    echo "Commit format: $checked of $checked passed."
  fi
fi

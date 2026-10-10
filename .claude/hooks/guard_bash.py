#!/usr/bin/env python3
"""Refuses shell commands that break how this repository is worked on.

- Builds, tests and simulators, on a machine that opted in with
  `git config momentum.noLocalBuilds true` (the owner's Mac, where they pin the CPU). CI builds
  and tests every pull request instead. A command prefixed with MOMENTUM_ALLOW_LOCAL_BUILD=1 is
  let through, for the times a local build was explicitly asked for.
- Pushes straight to main or develop, and commits that skip the commit-msg hook: those branches
  only change through pull requests, with Conventional Commits headers.

Runs as a PreToolUse hook for Bash: reads the event on stdin, and exit code 2 refuses the command
with the reason on stderr. Anything it can't parse is let through; branch protection and CI are
the real gates, this only stops the mistake early.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys
from collections.abc import Iterator

OVERRIDE = "MOMENTUM_ALLOW_LOCAL_BUILD"
PROTECTED_BRANCHES = {"main", "develop"}

BUILD_SCRIPTS = {"install.sh", "archive.sh", "app-store-screenshots.sh", "render.sh"}
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
WRAPPERS = {"env", "time", "nice", "nohup", "command", "exec", "sudo", "caffeinate", "timeout", "arch"}
XCODEBUILD_INFO = {"-version", "-showsdks", "-list", "-help", "-usage", "-checkFirstLaunchStatus"}
XCODEBUILD_ACTIONS = {
    "build", "test", "archive", "analyze", "install", "installsrc", "build-for-testing",
    "test-without-building", "docbuild", "-exportArchive", "-resolvePackageDependencies",
    "-exportLocalizations", "-importLocalizations",
}
SWIFT_INFO = {"--version", "-version", "--help", "-help", "-h"}
SWIFT_BUILDS = {"build", "test", "run", "repl"}
SIMCTL_ALLOWED = {
    "list", "shutdown", "delete", "erase", "help", "create", "unpair", "terminate", "uninstall",
    "get_app_container", "listapps", "appinfo", "getenv",
}
XCRUN_INFO = {
    "-f", "--find", "--show-sdk-path", "--show-sdk-version", "--show-sdk-build-version",
    "--show-sdk-platform-path", "--show-sdk-platform-version", "--show-toolchain-path",
    "-h", "--help", "--version",
}
XCRUN_VALUE_OPTIONS = {"-sdk", "--sdk", "-toolchain", "--toolchain"}
GIT_VALUE_OPTIONS = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
PUSH_VALUE_OPTIONS = {"--repo", "-o", "--push-option", "--receive-pack", "--exec"}
REDIRECTIONS = {"<", ">", ">>", "<<", "<<<", ">&", "&>", "&>>", "<&", ">|", "<>"}
OPERATOR_CHARS = set("();<>|&")

ASSIGNMENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
DURATION = re.compile(r"^\d+(\.\d+)?[smhd]?$")
SHORT_NO_VERIFY = re.compile(r"^-[A-Za-z]*n[A-Za-z]*$")
HEREDOC = re.compile(r"(?<!<)<<-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")

BUILD_REASON = (
    "Refused: builds, tests and simulators don't run on this Mac (git config "
    "momentum.noLocalBuilds is on, because they pin the CPU). Push the branch and let CI build "
    "and test the pull request; see the ship and fix-ci skills. Only if the owner explicitly "
    f"asked for a local build or install in this conversation, prefix the command with {OVERRIDE}=1."
)
PUSH_REASON = (
    "Refused: main and develop only change through pull requests. Push a "
    "<type>/<description> branch and open a PR into develop; see the ship skill."
)
NO_VERIFY_REASON = (
    "Refused: commits keep their hooks (the commit-msg hook checks the Conventional Commits "
    "header). Fix the message instead of skipping the hook; see the commit skill."
)


def main() -> int:
    try:
        event = json.load(sys.stdin)
        command = event.get("tool_input", {}).get("command", "")
        if not isinstance(command, str) or not command.strip():
            return 0
        project = os.environ.get("CLAUDE_PROJECT_DIR") or event.get("cwd") or os.getcwd()
        reason = verdict(command, guard_builds=opted_in(project))
    except Exception:  # A broken guard must never block work; CI still checks everything.
        return 0
    if reason:
        print(reason, file=sys.stderr)
        return 2
    return 0


def opted_in(project: str) -> bool:
    """Whether this checkout asked for local builds to be refused (shared by its worktrees)."""
    result = subprocess.run(
        ["git", "-C", project, "config", "--bool", "--get", "momentum.noLocalBuilds"],
        capture_output=True, text=True, timeout=5,
    )
    return result.stdout.strip() == "true"


def verdict(command: str, guard_builds: bool, override: bool = False, depth: int = 0) -> str | None:
    """The reason to refuse `command`, or None to let it run."""
    if depth > 3:
        return None
    for words in simple_commands(command):
        reason = check(words, guard_builds, override, depth)
        if reason:
            return reason
    return None


def simple_commands(command: str) -> Iterator[list[str]]:
    """Splits a command line into simple commands, each a list of words."""
    text = strip_heredocs(command).replace("\\\n", " ").replace("\n", " ; ").replace("`", " ; ")
    lexer = shlex.shlex(text, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        tokens = list(lexer)
    except ValueError:  # Unbalanced quotes: let the shell report it.
        return
    words: list[str] = []
    skip_target = False
    for token in tokens:
        if skip_target:
            skip_target = False
            continue
        if token in REDIRECTIONS:
            skip_target = True
            continue
        if token and set(token) <= OPERATOR_CHARS:
            if words:
                yield words
            words = []
            continue
        words.append(token)
    if words:
        yield words


def strip_heredocs(command: str) -> str:
    """Drops here-document bodies, which are data, not commands."""
    kept: list[str] = []
    waiting: list[str] = []
    for line in command.split("\n"):
        if waiting:
            if line.strip() == waiting[0]:
                waiting.pop(0)
            continue
        kept.append(line)
        waiting.extend(match.group(2) for match in HEREDOC.finditer(line))
    return "\n".join(kept)


def check(words: list[str], guard_builds: bool, override: bool, depth: int) -> str | None:
    index = 0
    while index < len(words):
        word = words[index]
        if ASSIGNMENT.match(word):
            name, _, value = word.partition("=")
            if name == OVERRIDE and value not in ("", "0", "false"):
                override = True
            index += 1
        elif os.path.basename(word) in WRAPPERS:
            index += 1
            while index < len(words) and (words[index].startswith("-") or DURATION.match(words[index])):
                index += 1
        else:
            break
    if index >= len(words):
        return None
    program = os.path.basename(words[index])
    args = words[index + 1:]

    if program == "git":
        return check_git(args)
    if program in SHELLS:
        if "-c" in args:
            script_at = args.index("-c") + 1
            if script_at < len(args):
                return verdict(args[script_at], guard_builds, override, depth + 1)
            return None
        script = next((arg for arg in args if not arg.startswith("-")), None)
        if script and os.path.basename(script) in BUILD_SCRIPTS and guard_builds and not override:
            return BUILD_REASON
        return None
    if guard_builds and not override and (program in BUILD_SCRIPTS or builds(program, args)):
        return BUILD_REASON
    return None


def builds(program: str, args: list[str]) -> bool:
    """Whether running `program` with `args` builds, tests, profiles or boots a simulator."""
    if program == "xcrun":
        tool = xcrun_tool(args)
        return tool is not None and builds(os.path.basename(tool[0]), tool[1:])
    if program == "xcodebuild":
        asks_for_info = any(arg in XCODEBUILD_INFO for arg in args)
        return not asks_for_info or any(arg in XCODEBUILD_ACTIONS for arg in args)
    if program == "swift":
        if not args:
            return True  # The REPL.
        first = args[0]
        if first in SWIFT_INFO:
            return False
        return first in SWIFT_BUILDS or first.endswith(".swift") or first.startswith("-")
    if program == "swiftc":
        return not args or not all(arg in SWIFT_INFO or arg == "-v" for arg in args)
    if program == "simctl":
        subcommand = next((arg for arg in args if not arg.startswith("-")), None)
        return subcommand is not None and subcommand not in SIMCTL_ALLOWED
    if program == "open":
        return any("Simulator" in arg for arg in args)
    return program in ("xctrace", "instruments")


def xcrun_tool(args: list[str]) -> list[str] | None:
    """The tool and arguments xcrun would run, or None when it only looks something up."""
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in XCRUN_INFO:
            return None
        if arg in XCRUN_VALUE_OPTIONS:
            index += 2
        elif arg.startswith("-"):
            index += 1
        else:
            return args[index:]
    return None


def check_git(args: list[str]) -> str | None:
    index = 0
    while index < len(args) and args[index].startswith("-"):
        index += 2 if args[index] in GIT_VALUE_OPTIONS else 1
    if index >= len(args):
        return None
    subcommand, rest = args[index], args[index + 1:]
    if subcommand == "commit" and any(arg == "--no-verify" or SHORT_NO_VERIFY.match(arg) for arg in rest):
        return NO_VERIFY_REASON
    if subcommand == "push":
        return check_push(rest)
    return None


def check_push(args: list[str]) -> str | None:
    positional: list[str] = []
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in PUSH_VALUE_OPTIONS:
            index += 2
            continue
        if not arg.startswith("-"):
            positional.append(arg)
        index += 1
    for refspec in positional[1:]:  # positional[0] is the remote.
        destination = refspec.lstrip("+").split(":")[-1].removeprefix("refs/heads/")
        if destination in PROTECTED_BRANCHES:
            return PUSH_REASON
    return None


if __name__ == "__main__":
    sys.exit(main())

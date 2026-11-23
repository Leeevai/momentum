#!/bin/zsh
# Keeps Momentum installed on your iPhone and Apple Watch when a free (Personal Team) Apple account
# signs it. Those provisioning profiles last 7 days, and iOS and watchOS stop opening the app once
# they run out. Every few days, while the iPhone is unlocked and within reach of this Mac (a cable
# or the same Wi-Fi), this replaces the profiles about to run out, builds the latest develop at
# background priority, and reinstalls the app on both. A paid Apple Developer Program team makes
# it unnecessary: its profiles last a year.
#
# Usage:
#   scripts/keep-installed.sh --install    find the iPhone and watch, then run every hour from a
#                                          LaunchAgent (it only reinstalls when it's due)
#   scripts/keep-installed.sh --now        re-sign and reinstall now
#   scripts/keep-installed.sh --status     when it last reinstalled, and until when that lasts
#   scripts/keep-installed.sh --uninstall  remove the LaunchAgent and everything it keeps
#
# It keeps everything in ~/Library/Application Support/Momentum Keeper: its settings (config), its
# own clone of the repository, the build (about 1 GB), and keeper.log.
set -uo pipefail

SCRIPT="${0:A}"   # read here: inside a function, zsh sets $0 to the function's name
SUPPORT="$HOME/Library/Application Support/Momentum Keeper"
CONFIG="$SUPPORT/config"
LOG="$SUPPORT/keeper.log"
STAMP="$SUPPORT/last-install"
WARNED="$SUPPORT/last-warning"
CHECKOUT="$SUPPORT/checkout"
DERIVED="$SUPPORT/DerivedData"
LOCK="$SUPPORT/lock"
LABEL="dev.momentum.keep-installed"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")

EVERY_DAYS=3          # reinstall once the last install is this old
RENEW_WITHIN_DAYS=5   # replace profiles that run out within this many days
WARN_AFTER_DAYS=5     # notify (once a day) when the last install is this old and it can't reinstall

OWNS_LOCK=0
cleanup() { (( OWNS_LOCK )) && rmdir "$LOCK" 2>/dev/null; return 0; }
trap cleanup EXIT

log() { mkdir -p "$SUPPORT"; print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
say() { print -r -- "$*"; log "$*"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Momentum\"" >/dev/null 2>&1 || true; }
age_days() { [[ -e "$1" ]] || { print 999; return; }; print $(( ($(date +%s) - $(stat -f %m "$1")) / 86400 )); }
epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || print 0; }
profile_field() { security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null; }

# Settings saved by --install: REPO, REF, TEAM, PREFIX, IPHONE, WATCH.
load_config() {
    [[ -f "$CONFIG" ]] || { say "Not set up yet: run scripts/keep-installed.sh --install"; exit 1; }
    source "$CONFIG"
    APP="$DERIVED/Build/Products/Release-iphoneos/MomentumMobile.app"
}

# The paired physical iPhone and Apple Watch, as "IPHONE=<udid>" and "WATCH=<udid>" lines.
find_devices() {
    local json="$SUPPORT/devices.json"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || return 1
    /usr/bin/python3 -I - "$json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1]))["result"]["devices"]
for kind, key in (("iPhone", "IPHONE"), ("appleWatch", "WATCH")):
    for d in devices:
        hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
        if hw.get("deviceType") == kind and hw.get("reality") == "physical" and conn.get("pairingState") == "paired":
            print(f'{key}={hw["udid"]}')
            break
PY
    rm -f "$json"
}

install_agent() {
    # The main checkout, even when this runs from a worktree that will come and go.
    local common; common=$(git -C "${SCRIPT:h}" rev-parse --path-format=absolute --git-common-dir) || exit 1
    local repo="${common:h}"
    mkdir -p "$SUPPORT" "${AGENT:h}"
    local devices; devices=$(find_devices) || { print -u2 "Couldn't list devices: is Xcode installed?"; exit 1; }
    [[ "$devices" == *IPHONE=* ]] || { print -u2 "No paired iPhone found. Connect it once with a cable and trust this Mac."; exit 1; }
    local xcconfig="$repo/Config/Shared.xcconfig" local_xcconfig="$repo/Config/Local.xcconfig"
    local team prefix
    team=$(grep -h '^DEVELOPMENT_TEAM' "$xcconfig" "$local_xcconfig" 2>/dev/null | tail -1 | sed -E 's/.*= *//')
    prefix=$(grep -h '^BUNDLE_ID_PREFIX' "$xcconfig" "$local_xcconfig" 2>/dev/null | tail -1 | sed -E 's/.*= *//')
    {
        print -r -- "REPO=${(q)repo}"
        print -r -- "REF=origin/develop"
        print -r -- "TEAM=$team"
        print -r -- "PREFIX=$prefix"
        print -r -- "$devices"
    } > "$CONFIG"
    # The agent runs a copy, so switching branches in the repository never changes what it runs.
    cp "$SCRIPT" "$SUPPORT/keep-installed.sh"
    cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>/bin/zsh</string><string>$SUPPORT/keep-installed.sh</string></array>
    <key>StartInterval</key><integer>3600</integer>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>LowPriorityIO</key><true/>
    <key>Nice</key><integer>10</integer>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin</string></dict>
    <key>StandardOutPath</key><string>$SUPPORT/agent.log</string>
    <key>StandardErrorPath</key><string>$SUPPORT/agent.log</string>
</dict>
</plist>
PLIST
    launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    launchctl bootstrap "gui/$UID" "$AGENT"
    say "Installed. It checks every hour and reinstalls Momentum every $EVERY_DAYS days, when the iPhone is unlocked and within reach."
    print -r -- "Settings: $CONFIG"
}

uninstall_agent() {
    launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    rm -f "$AGENT"
    # Forget the build's copy first, so the Mac's widgets keep matching the installed app.
    if [[ -f "$CONFIG" ]]; then
        load_config
        [[ -x "$REPO/scripts/unregister-copies.sh" && -d /Applications/Momentum.app ]] &&
            "$REPO/scripts/unregister-copies.sh" "$PREFIX.Momentum" /Applications/Momentum.app
    fi
    rm -rf "${SUPPORT:?}"
    print "Removed the LaunchAgent and $SUPPORT."
}

status() {
    load_config
    if [[ -f "$STAMP" ]]; then
        print -r -- "Last reinstalled: $(date -r "$(stat -f %m "$STAMP")" '+%a %d %b %H:%M') ($(age_days "$STAMP") days ago)"
        print -r -- "$(<"$STAMP")"
    else
        print "Not reinstalled yet."
    fi
    launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 && print "The LaunchAgent is running every hour." || print "The LaunchAgent isn't loaded."
    print -r -- "Log: $LOG"
}

# Deletes this app's cached profiles that run out within RENEW_WITHIN_DAYS days, so the build asks
# Apple for fresh ones (Xcode reuses a cached profile until it has expired).
renew_profiles() {
    local limit=$(( $(date +%s) + RENEW_WITHIN_DAYS * 86400 )) dir file id expires
    for dir in "${PROFILE_DIRS[@]}"; do
        for file in "$dir"/*.mobileprovision(N); do
            id=$(profile_field "$file" Entitlements.application-identifier)
            [[ "$id" == "$TEAM.$PREFIX.Momentum" || "$id" == "$TEAM.$PREFIX.Momentum."* ]] || continue
            expires=$(profile_field "$file" ExpirationDate)
            if (( $(epoch "$expires") < limit )); then
                rm -f "$file" && log "Replacing the profile for $id (runs out $expires)"
            fi
        done
    done
}

update_checkout() {
    # Its own clone (hardlinked objects, little extra disk), with the repository's view of GitHub
    # under upstream/: REF=origin/develop builds upstream/develop.
    git -C "$REPO" fetch -q origin 2>>"$LOG" || log "Couldn't fetch origin; building what's already there"
    if [[ ! -d "$CHECKOUT/.git" ]]; then
        git clone -q --no-checkout "$REPO" "$CHECKOUT" || return 1
    fi
    git -C "$CHECKOUT" fetch -q "$REPO" "+refs/remotes/origin/*:refs/remotes/upstream/*" || return 1
    git -C "$CHECKOUT" checkout -q -f --detach "upstream/${REF#origin/}" || return 1
    git -C "$CHECKOUT" clean -q -fdx
    # Personal signing overrides are gitignored: bring them along.
    [[ -f "$REPO/Config/Local.xcconfig" ]] && cp "$REPO/Config/Local.xcconfig" "$CHECKOUT/Config/Local.xcconfig"
    return 0
}

reinstall() {
    local interactive=$1
    load_config
    if (( ! interactive )) && (( $(age_days "$STAMP") < EVERY_DAYS )); then
        exit 0
    fi
    # One run at a time; a lock left by a run that was killed goes after 3 hours.
    [[ -d "$LOCK" ]] && (( $(date +%s) - $(stat -f %m "$LOCK") > 10800 )) && rmdir "$LOCK"
    mkdir "$LOCK" 2>/dev/null || { log "Another run is in progress"; exit 0; }
    OWNS_LOCK=1

    # Reachable and unlocked: listing its apps needs both.
    if ! xcrun devicectl --timeout 60 device info apps --device "$IPHONE" >/dev/null 2>&1; then
        log "The iPhone isn't reachable or is locked; trying again later"
        if (( $(age_days "$STAMP") >= WARN_AFTER_DAYS )) && (( $(age_days "$WARNED") >= 1 )); then
            notify "Unlock your iPhone near your Mac so Momentum can be renewed before it stops opening."
            touch "$WARNED"
        fi
        (( interactive )) && { say "The iPhone isn't reachable or is locked. Unlock it near this Mac and try again."; exit 75; }
        exit 0
    fi

    say "Renewing Momentum on the iPhone and watch"
    update_checkout || { say "Couldn't update its checkout of the repository"; exit 1; }
    renew_profiles
    local commit; commit=$(git -C "$CHECKOUT" rev-parse --short HEAD)
    local priority=(); (( interactive )) || priority=(/usr/sbin/taskpolicy -b)
    if ! ( cd "$CHECKOUT" && "${priority[@]}" xcodebuild -project Momentum.xcodeproj -scheme MomentumMobile \
            -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
            -allowProvisioningUpdates -quiet build ) >> "$SUPPORT/build.log" 2>&1; then
        say "The build of $commit failed: see $SUPPORT/build.log"
        notify "Couldn't build Momentum to renew it on your iPhone. See the keeper's build log."
        exit 1
    fi
    # Every build registers its copy with LaunchServices, which breaks the Mac's widgets.
    [[ -d /Applications/Momentum.app ]] && "$CHECKOUT/scripts/unregister-copies.sh" "$PREFIX.Momentum" /Applications/Momentum.app

    local out
    out=$(xcrun devicectl device install app --device "$IPHONE" "$APP" 2>&1)
    if [[ "$out" != *"App installed"* ]]; then
        log "$out"
        say "Couldn't install on the iPhone; trying again next hour"
        exit 1
    fi
    log "Installed $commit on the iPhone"
    local watch_ok=1
    if [[ -n "${WATCH:-}" ]]; then
        watch_ok=0
        for attempt in 1 2 3 4 5; do
            out=$(xcrun devicectl device install app --device "$WATCH" "$APP/Watch/MomentumWatch.app" 2>&1)
            if [[ "$out" == *"App installed"* ]]; then
                watch_ok=1; log "Installed $commit on the watch (attempt $attempt)"; break
            fi
            log "Watch attempt $attempt: ${${(f)out}[1]}"
            sleep 20
        done
    fi
    local expires; expires=$(profile_field "$APP/embedded.mobileprovision" ExpirationDate)
    local until; until=$(date -r "$(epoch "$expires")" '+%a %d %b')
    if (( ! watch_ok )); then
        say "Installed on the iPhone, but the watch didn't answer; trying again next hour"
        exit 1
    fi
    print -r -- "Build $commit, signed until $expires" > "$STAMP"
    rm -f "$WARNED"
    say "Momentum $commit is reinstalled on the iPhone and watch, and opens until $until"
    notify "Renewed on your iPhone and Apple Watch: it opens until $until."
    tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

case "${1:-}" in
    --install) install_agent ;;
    --uninstall) uninstall_agent ;;
    --status) status ;;
    --now) reinstall 1 ;;
    "") reinstall 0 ;;
    *) print -u2 "Usage: $0 [--install | --now | --status | --uninstall]"; exit 64 ;;
esac

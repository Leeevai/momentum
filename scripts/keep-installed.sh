#!/bin/zsh
# Keeps Momentum installed on your iPhone and Apple Watch when a free (Personal Team) Apple account
# signs it. Those provisioning profiles last 7 days, and iOS and watchOS stop opening the app once
# they run out. Every few days, while the iPhone is unlocked and within reach of this Mac (a cable
# or the same Wi-Fi), this replaces the profiles about to run out, builds the latest develop at
# background priority, and reinstalls the app on each device. A paid Apple Developer Program team
# makes it unnecessary: its profiles last a year.
#
# Usage:
#   scripts/keep-installed.sh --install [IPHONE_UDID [WATCH_UDID]]
#                                          set it up for the paired iPhone and watch (name them
#                                          when more than one is paired), then run every hour
#                                          from a LaunchAgent; it only reinstalls when it's due
#   scripts/keep-installed.sh --now        re-sign and reinstall now
#   scripts/keep-installed.sh --status     when each device was renewed, and until when
#   scripts/keep-installed.sh --uninstall  remove the LaunchAgent and everything it keeps
#
# It keeps everything in ~/Library/Application Support/Momentum Keeper: its settings (config), its
# own clone of the repository, the build (about 1 GB), and keeper.log. The LaunchAgent never reads
# the repository itself: macOS keeps background jobs out of ~/Documents, so --install clones it
# and copies Config/Local.xcconfig there, and each run updates that clone from GitHub.
set -uo pipefail

SCRIPT="${0:A}"   # read here: inside a function, zsh sets $0 to the function's name
SUPPORT="$HOME/Library/Application Support/Momentum Keeper"
CONFIG="$SUPPORT/config"
LOG="$SUPPORT/keeper.log"
WARNED="$SUPPORT/last-warning"
CHECKOUT="$SUPPORT/checkout"
DERIVED="$SUPPORT/DerivedData"
LOCK="$SUPPORT/lock.pid"
LABEL="dev.momentum.keep-installed"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")

EVERY_DAYS=3          # renew a device once its last install is this old
RENEW_WITHIN_DAYS=5   # replace profiles that run out within this many days
WARN_AFTER_DAYS=5     # notify, once a day, when a device's last install is this old and renewing fails
BUILD_TIMEOUT=5400    # seconds before a stuck build is stopped, so a later run can retry
INSTALL_TIMEOUT=600   # the same for each install

OWNS_LOCK=0
cleanup() { (( OWNS_LOCK )) && rm -f "$LOCK"; return 0; }
trap cleanup EXIT

log() { mkdir -p "$SUPPORT"; print -r -- "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"; }
say() { print -r -- "$*"; log "$*"; }
notify() { /usr/bin/osascript -e "display notification \"$1\" with title \"Momentum\"" >/dev/null 2>&1 || true; }
age_days() { [[ -e "$1" ]] || { print 999; return; }; print $(( ($(date +%s) - $(stat -f %m "$1")) / 86400 )); }
epoch() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null || print 0; }
profile_field() { security cms -D -i "$1" 2>/dev/null | plutil -extract "$2" raw -o - - 2>/dev/null; }
stamp() { print -r -- "$SUPPORT/$1-installed"; }
label() { [[ "$1" == iphone ]] && print iPhone || print "Apple Watch"; }

# One lock for the whole Momentum Keeper, held by a live process: shlock frees a lock whose
# process has died, and never one whose process is still running, however long it takes.
take_lock() { mkdir -p "$SUPPORT"; /usr/bin/shlock -p $$ -f "$LOCK" && OWNS_LOCK=1; }

# Settings saved by --install, read as plain KEY=value lines (never run as shell), each checked
# against the form it must have.
load_config() {
    [[ -f "$CONFIG" ]] || { say "Not set up yet: run scripts/keep-installed.sh --install"; exit 1; }
    REPO= REMOTE= REF=origin/develop TEAM= PREFIX= IPHONE= WATCH=
    local key value
    while IFS='=' read -r key value; do
        case "$key" in
            REPO) REPO="$value" ;;
            REMOTE) [[ "$value" =~ '^[A-Za-z0-9@:/._~-]+$' ]] && REMOTE="$value" ;;
            REF) [[ "$value" =~ '^[A-Za-z0-9._/-]+$' ]] && REF="$value" ;;
            TEAM) [[ "$value" =~ '^[A-Z0-9]{10}$' ]] && TEAM="$value" ;;
            PREFIX) [[ "$value" =~ '^[A-Za-z0-9.-]+$' ]] && PREFIX="$value" ;;
            IPHONE) [[ "$value" =~ '^[0-9A-Fa-f-]+$' ]] && IPHONE="$value" ;;
            WATCH) [[ "$value" =~ '^[0-9A-Fa-f-]*$' ]] && WATCH="$value" ;;
        esac
    done < "$CONFIG"
    if [[ -z "$REMOTE" || -z "$TEAM" || -z "$PREFIX" || -z "$IPHONE" ]]; then
        say "Its settings in $CONFIG are incomplete or invalid: run scripts/keep-installed.sh --install again"
        exit 1
    fi
    APP="$DERIVED/Build/Products/Release-iphoneos/MomentumMobile.app"
    # Before each device had its own record, one stamp stood for both.
    if [[ -f "$SUPPORT/last-install" ]]; then
        [[ -f "$(stamp iphone)" ]] || cp -p "$SUPPORT/last-install" "$(stamp iphone)"
        [[ -n "$WATCH" && ! -f "$(stamp watch)" ]] && cp -p "$SUPPORT/last-install" "$(stamp watch)"
        rm -f "$SUPPORT/last-install"
    fi
}

# Every paired physical iPhone and Apple Watch, one per line: "<kind> <udid> <name>".
list_devices() {
    local json="$SUPPORT/devices.json"
    xcrun devicectl list devices --json-output "$json" >/dev/null 2>&1 || return 1
    /usr/bin/python3 -I - "$json" <<'PY'
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw, conn = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hw.get("reality") == "physical" and conn.get("pairingState") == "paired" and hw.get("deviceType") in ("iPhone", "appleWatch"):
        print(hw["deviceType"], hw["udid"], d.get("deviceProperties", {}).get("name", ""))
PY
    rm -f "$json"
}

install_agent() {
    # The main checkout, even when this runs from a worktree that will come and go.
    local common; common=$(git -C "${SCRIPT:h}" rev-parse --path-format=absolute --git-common-dir) || exit 1
    local repo="${common:h}"
    mkdir -p "$SUPPORT" "${AGENT:h}"
    local iphone="${1:-}" watch="${2:-}"
    if [[ -z "$iphone" ]]; then
        local devices; devices=$(list_devices) || { print -u2 "Couldn't list devices: is Xcode installed?"; exit 1; }
        local iphones=(${(f)"$(print -r -- "$devices" | grep '^iPhone ')"}) watches=(${(f)"$(print -r -- "$devices" | grep '^appleWatch ')"})
        if (( ${#iphones} == 0 )); then
            print -u2 "No paired iPhone found. Connect it once with a cable and trust this Mac."; exit 1
        elif (( ${#iphones} > 1 || ${#watches} > 1 )); then
            print -u2 "More than one iPhone or Apple Watch is paired. Name the ones to keep Momentum on:"
            print -u2 "  scripts/keep-installed.sh --install IPHONE_UDID [WATCH_UDID]"
            print -u2 -l -- "${iphones[@]}" "${watches[@]}"
            exit 1
        fi
        iphone=${${iphones[1]}[(w)2]}
        (( ${#watches} )) && watch=${${watches[1]}[(w)2]}
    fi
    [[ "$iphone" =~ '^[0-9A-Fa-f-]+$' && "$watch" =~ '^[0-9A-Fa-f-]*$' ]] || { print -u2 "That doesn't look like a device's UDID."; exit 1; }
    local xcconfig="$repo/Config/Shared.xcconfig" local_xcconfig="$repo/Config/Local.xcconfig"
    local team prefix
    team=$(grep -h '^DEVELOPMENT_TEAM' "$xcconfig" "$local_xcconfig" 2>/dev/null | tail -1 | sed -E 's/.*= *//')
    prefix=$(grep -h '^BUNDLE_ID_PREFIX' "$xcconfig" "$local_xcconfig" 2>/dev/null | tail -1 | sed -E 's/.*= *//')
    [[ "$team" =~ '^[A-Z0-9]{10}$' && "$prefix" =~ '^[A-Za-z0-9.-]+$' ]] || {
        print -u2 "Couldn't read the team and bundle prefix from Config/Shared.xcconfig and Config/Local.xcconfig."; exit 1
    }
    local remote; remote=$(git -C "$repo" remote get-url origin)
    [[ "$remote" =~ '^[A-Za-z0-9@:/._~-]+$' ]] || { print -u2 "Couldn't read the repository's origin."; exit 1; }
    print -l -- "REPO=$repo" "REMOTE=$remote" "REF=origin/develop" "TEAM=$team" "PREFIX=$prefix" "IPHONE=$iphone" "WATCH=$watch" > "$CONFIG"
    # Its own clone, made here (the LaunchAgent can't read ~/Documents): from the local repository,
    # which hardlinks its objects, then pointed at GitHub, which each run fetches from.
    if [[ ! -d "$CHECKOUT/.git" ]]; then
        git clone -q --no-checkout "$repo" "$CHECKOUT" || { print -u2 "Couldn't clone the repository."; exit 1; }
    fi
    git -C "$CHECKOUT" remote set-url origin "$remote"
    git -C "$CHECKOUT" fetch -q origin || print -u2 "Couldn't fetch from $remote yet; each run tries again."
    rm -f "$SUPPORT/Local.xcconfig"
    [[ -f "$local_xcconfig" ]] && cp "$local_xcconfig" "$SUPPORT/Local.xcconfig"
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
    if ! launchctl bootstrap "gui/$UID" "$AGENT"; then
        say "Couldn't load the LaunchAgent at $AGENT, so nothing will renew the apps. Check it with: plutil -lint \"$AGENT\""
        exit 1
    fi
    [[ -z "$watch" ]] && say "No paired Apple Watch: it will keep Momentum on the iPhone only."
    say "Installed. It checks every hour and renews Momentum every $EVERY_DAYS days, when the iPhone is unlocked and within reach."
    print -r -- "Settings: $CONFIG"
}

uninstall_agent() {
    launchctl bootout "gui/$UID/$LABEL" >/dev/null 2>&1 || true
    rm -f "$AGENT"
    # Wait for a renewal that's already running (one started with --now, say) rather than pull
    # its checkout and build out from under it.
    if [[ -d "$SUPPORT" ]] && ! take_lock; then
        print -u2 "A renewal is running (process $(<"$LOCK")). The agent is unloaded; run --uninstall again once it has finished."
        exit 1
    fi
    # Forget the build's copy first, so the Mac's widgets keep matching the installed app. Read
    # leniently: a damaged settings file mustn't stop the uninstall.
    local repo prefix
    repo=$(grep -m1 '^REPO=' "$CONFIG" 2>/dev/null | cut -d= -f2-)
    prefix=$(grep -m1 '^PREFIX=' "$CONFIG" 2>/dev/null | cut -d= -f2-)
    if [[ -x "$repo/scripts/unregister-copies.sh" && "$prefix" =~ '^[A-Za-z0-9.-]+$' && -d /Applications/Momentum.app ]]; then
        "$repo/scripts/unregister-copies.sh" "$prefix.Momentum" /Applications/Momentum.app
    fi
    OWNS_LOCK=0
    rm -rf "${SUPPORT:?}"
    print "Removed the LaunchAgent and $SUPPORT."
}

status() {
    load_config
    local device file
    for device in iphone watch; do
        [[ "$device" == watch && -z "$WATCH" ]] && continue
        file=$(stamp "$device")
        if [[ -f "$file" ]]; then
            print -r -- "$(label "$device"): renewed $(date -r "$(stat -f %m "$file")" '+%a %d %b %H:%M') ($(age_days "$file") days ago). $(<"$file")"
        else
            print -r -- "$(label "$device"): not renewed yet."
        fi
    done
    launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1 && print "The LaunchAgent runs every hour." || print "The LaunchAgent isn't loaded."
    print -r -- "Log: $LOG"
}

# Notifies, at most once a day, when a device hasn't been renewed for WARN_AFTER_DAYS days and
# renewing it is failing, so the app never runs out without a word.
warn_if_overdue() {
    local device=$1 message=$2
    (( $(age_days "$(stamp "$device")") >= WARN_AFTER_DAYS )) || return 0
    (( $(age_days "$WARNED") >= 1 )) || return 0
    notify "$message"
    touch "$WARNED"
}

# Sets aside this app's cached profiles that run out within RENEW_WITHIN_DAYS days, so the build
# asks Apple for fresh ones (Xcode reuses a cached profile until it has expired). If the build
# fails, put_back_profiles returns them; once it succeeds, drop_old_profiles deletes them.
OLD_PROFILES="$SUPPORT/old-profiles"
renew_profiles() {
    local limit=$(( $(date +%s) + RENEW_WITHIN_DAYS * 86400 )) dir file id expires
    for dir in "${PROFILE_DIRS[@]}"; do
        for file in "$dir"/*.mobileprovision(N); do
            id=$(profile_field "$file" Entitlements.application-identifier)
            [[ "$id" == "$TEAM.$PREFIX.Momentum" || "$id" == "$TEAM.$PREFIX.Momentum."* ]] || continue
            expires=$(profile_field "$file" ExpirationDate)
            if (( $(epoch "$expires") < limit )); then
                mkdir -p "$OLD_PROFILES/${dir:t}"
                mv "$file" "$OLD_PROFILES/${dir:t}/" && log "Replacing the profile for $id (runs out $expires)"
            fi
        done
    done
}
put_back_profiles() {
    local dir file
    for dir in "${PROFILE_DIRS[@]}"; do
        for file in "$OLD_PROFILES/${dir:t}"/*.mobileprovision(N); do
            [[ -e "$dir/${file:t}" ]] || mv "$file" "$dir/"
        done
    done
    rm -rf "${OLD_PROFILES:?}"
}
drop_old_profiles() { rm -rf "${OLD_PROFILES:?}"; }

update_checkout() {
    # Its own clone, made by --install, fetched straight from GitHub. If GitHub can't be reached,
    # it re-signs what it already has: renewing matters more than the newest code.
    [[ -d "$CHECKOUT/.git" ]] || { log "Its clone is missing: run scripts/keep-installed.sh --install again"; return 1; }
    git -C "$CHECKOUT" fetch -q origin 2>>"$LOG" || log "Couldn't fetch from GitHub; building what's already there"
    git -C "$CHECKOUT" checkout -q -f --detach "$REF" || return 1
    git -C "$CHECKOUT" clean -q -fdx
    # Personal signing overrides are gitignored: --install saved a copy.
    [[ -f "$SUPPORT/Local.xcconfig" ]] && cp "$SUPPORT/Local.xcconfig" "$CHECKOUT/Config/Local.xcconfig"
    return 0
}

# Runs a command, stopping it after a number of seconds. Returns its status, or 124 if stopped.
run_with_timeout() {
    local seconds=$1; shift
    "$@" & local pid=$!
    ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null; sleep 30; kill -KILL "$pid" 2>/dev/null ) &
    local watchdog=$!
    wait "$pid"; local code=$?
    pkill -P "$watchdog" 2>/dev/null; kill "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
    (( code == 143 || code == 137 )) && return 124
    return $code
}

build() {
    local interactive=$1 commit=$2
    local priority=() taskpolicy
    # In the background, the build runs at background priority (taskpolicy is in /usr/sbin).
    if (( ! interactive )) && taskpolicy=$(command -v taskpolicy); then priority=("$taskpolicy" -b); fi
    cd "$CHECKOUT" || return 1
    : > "$SUPPORT/build.log"   # only the last build's output
    run_with_timeout "$BUILD_TIMEOUT" "${priority[@]}" xcodebuild -project Momentum.xcodeproj -scheme MomentumMobile \
        -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates -quiet build >> "$SUPPORT/build.log" 2>&1
    local code=$?
    cd - >/dev/null
    (( code == 124 )) && log "The build of $commit took over $(( BUILD_TIMEOUT / 60 )) minutes and was stopped"
    (( code == 0 )) && print -r -- "$commit" > "$SUPPORT/built-commit"
    return $code
}

# Installs the build on a device: returns 0 when the device confirms it.
install_on() {
    local udid=$1 app=$2 out
    out=$(xcrun devicectl --timeout "$INSTALL_TIMEOUT" device install app --device "$udid" "$app" 2>&1)
    [[ "$out" == *"App installed"* ]] && return 0
    log "${${(f)out}[1]:-no answer}"
    return 1
}

reinstall() {
    local interactive=$1
    load_config
    local iphone_due watch_due commit expires until fresh=0
    due() {
        iphone_due=$(( interactive || $(age_days "$(stamp iphone)") >= EVERY_DAYS ))
        watch_due=$(( ${#WATCH} > 0 && (interactive || $(age_days "$(stamp watch)") >= EVERY_DAYS) ))
    }
    due
    (( iphone_due || watch_due )) || exit 0
    take_lock || { log "Another renewal is running"; (( interactive )) && say "Another renewal is running."; exit 0; }
    # Checked again: another run may have renewed while this one waited for the lock.
    due
    (( iphone_due || watch_due )) || exit 0

    # Reachable and unlocked: listing its apps needs both, and the watch is reached through it.
    if ! xcrun devicectl --timeout 60 device info apps --device "$IPHONE" >/dev/null 2>&1; then
        log "The iPhone isn't reachable or is locked; trying again later"
        warn_if_overdue iphone "Unlock your iPhone near your Mac so Momentum can be renewed before it stops opening."
        (( watch_due )) && warn_if_overdue watch "Unlock your iPhone near your Mac so Momentum can be renewed on your Apple Watch."
        (( interactive )) && { say "The iPhone isn't reachable or is locked. Unlock it near this Mac and try again."; exit 75; }
        exit 0
    fi

    local due_on=(); (( iphone_due )) && due_on+=(iPhone); (( watch_due )) && due_on+=("Apple Watch")
    say "Renewing Momentum on the ${(j: and :)due_on}"
    update_checkout || { say "Couldn't update its checkout of the repository"; warn_if_overdue iphone "Couldn't renew Momentum: see the keeper's log."; exit 1; }
    commit=$(git -C "$CHECKOUT" rev-parse --short HEAD)
    # Rebuild unless only the watch is due and the last build's profile is still fresh: a flaky
    # watch is retried hourly with the same build, not a new one.
    if [[ -d "$APP" ]]; then
        expires=$(profile_field "$APP/embedded.mobileprovision" ExpirationDate)
        (( $(epoch "$expires") > $(date +%s) + RENEW_WITHIN_DAYS * 86400 )) && fresh=1
    fi
    if (( iphone_due || ! fresh )); then
        renew_profiles
        if ! build "$interactive" "$commit"; then
            put_back_profiles
            if grep -q "No Accounts" "$SUPPORT/build.log"; then
                # Without an Apple ID in Xcode, no profile can be renewed: say so straight away.
                say "Xcode has no Apple ID signed in, so the profiles can't be renewed"
                if (( $(age_days "$WARNED") >= 1 )); then
                    notify "Sign in to Xcode (Settings → Accounts) with your Apple ID so Momentum can be renewed on your iPhone."
                    touch "$WARNED"
                fi
            else
                say "The build of $commit failed: see $SUPPORT/build.log"
                warn_if_overdue iphone "Couldn't build Momentum to renew it. See the keeper's build log."
            fi
            exit 1
        fi
        drop_old_profiles
        # Every build registers its copy with LaunchServices, which breaks the Mac's widgets.
        if [[ -d /Applications/Momentum.app ]] && ! "$CHECKOUT/scripts/unregister-copies.sh" "$PREFIX.Momentum" /Applications/Momentum.app; then
            log "Couldn't unregister the build's copy; if the Mac's widgets turn grey, run scripts/unregister-copies.sh"
            notify "If Momentum's widgets on your Mac turn grey, run scripts/unregister-copies.sh in the repository."
        fi
    fi
    expires=$(profile_field "$APP/embedded.mobileprovision" ExpirationDate)
    until=$(date -r "$(epoch "$expires")" '+%a %d %b')
    # The build being installed, which may be older than the checkout when only the watch is due.
    if [[ -f "$SUPPORT/built-commit" ]]; then
        commit=$(<"$SUPPORT/built-commit")
    else
        commit=$(sed -nE 's/^Build ([0-9a-f]+),.*/\1/p' "$(stamp iphone)" 2>/dev/null); commit=${commit:-unknown}
    fi

    local renewed=() failed=()
    if (( iphone_due )); then
        if install_on "$IPHONE" "$APP"; then
            print -r -- "Build $commit, signed until $expires" > "$(stamp iphone)"; renewed+=(iPhone)
        else
            failed+=(iPhone)
            warn_if_overdue iphone "Couldn't reinstall Momentum on your iPhone. See the keeper's log."
        fi
    fi
    if (( watch_due )); then
        local ok=0 attempt
        for attempt in 1 2 3 4 5; do
            if install_on "$WATCH" "$APP/Watch/MomentumWatch.app"; then ok=1; break; fi
            sleep 20
        done
        if (( ok )); then
            print -r -- "Build $commit, signed until $expires" > "$(stamp watch)"; renewed+=("Apple Watch")
        else
            failed+=("Apple Watch")
            warn_if_overdue watch "Couldn't reinstall Momentum on your Apple Watch. Keep it near your iPhone, unlocked."
        fi
    fi
    tail -n 2000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    if (( ${#renewed} )); then
        say "Momentum $commit is renewed on the ${(j: and :)renewed}, and opens until $until"
        notify "Renewed on your ${(j: and :)renewed}: it opens until $until."
    fi
    if (( ${#failed} )); then
        say "Couldn't install on the ${(j: and :)failed}; trying again next hour"
        exit 1
    fi
    rm -f "$WARNED"
}

case "${1:-}" in
    --install) shift; install_agent "$@" ;;
    --uninstall) uninstall_agent ;;
    --status) status ;;
    --now) reinstall 1 ;;
    "") reinstall 0 ;;
    *) print -u2 "Usage: $0 [--install [IPHONE_UDID [WATCH_UDID]] | --now | --status | --uninstall]"; exit 64 ;;
esac

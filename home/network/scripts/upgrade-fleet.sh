#!/usr/bin/env bash
# Upgrade every MikroTik in sequence -- both the RouterOS package and, where
# needed, the RouterBOARD firmware (two independent things; a device can be
# package-current while its firmware still lags) -- waiting for each to
# fully come back up and confirming it reports working internet/DNS
# connectivity before moving on to the next one. Stops immediately on any
# failure -- never cascades a bad upgrade across the fleet unattended;
# whatever device failed is left for you to check by hand before re-running.
#
# Usage: ./upgrade-fleet.sh <expected-routeros-version>
#   e.g. ./upgrade-fleet.sh 7.24.5
#
# Run /system/package/update/check-for-updates by hand first to confirm
# what the real latest version actually is -- this script trusts the
# version you pass it, it doesn't look it up itself.
#
# Order matters and is deliberate: mikrotik4 first (lowest stakes -- it's
# standalone, nothing else depends on it, and it's usually already current,
# making it a cheap smoke test of the skip-logic below), then the switches
# (smaller blast radius if something goes wrong), edge router last.
#
# A device already on the target version is skipped (safe to re-run after
# a partial failure without re-upgrading devices that already succeeded).

set -uo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <expected-routeros-version>" >&2
    exit 1
fi
EXPECTED_VERSION="$1"

HOSTS=(
    "router4.home.ledcom.fr"   # mikrotik4 -- cAP XL ac, standalone
    "router3.home.ledcom.fr"   # mikrotik3 -- office switch
    "router5.home.ledcom.fr"   # mikrotik5 -- living room switch
    "router2.home.ledcom.fr"   # mikrotik2 -- main switch
    "router1.home.ledcom.fr"   # mikrotik1 -- edge router, last on purpose
)
SSH_USER="admin"
SSH_OPTS=(-o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new)
MAX_WAIT_DOWN=90
MAX_WAIT_UP=180
POLL_INTERVAL=3

is_reachable() {
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${1}" '/system/identity/print' >/dev/null 2>&1
}

wait_for_down() {
    local host="$1" waited=0
    echo "  waiting for ${host} to go down..."
    while is_reachable "$host"; do
        sleep "$POLL_INTERVAL"
        waited=$((waited + POLL_INTERVAL))
        if [ "$waited" -ge "$MAX_WAIT_DOWN" ]; then
            echo "  note: ${host} still reachable after ${MAX_WAIT_DOWN}s -- it may have rebooted and come back already faster than we could poll. Continuing."
            return 0
        fi
    done
    echo "  ${host} is down, ${waited}s in."
}

wait_for_up() {
    local host="$1" waited=0
    echo "  waiting for ${host} to come back up..."
    until is_reachable "$host"; do
        sleep "$POLL_INTERVAL"
        waited=$((waited + POLL_INTERVAL))
        if [ "$waited" -ge "$MAX_WAIT_UP" ]; then
            echo "  ERROR: ${host} did not come back within ${MAX_WAIT_UP}s" >&2
            return 1
        fi
    done
    echo "  ${host} is back up after ${waited}s."
}

get_installed_version() {
    local host="$1"
    # check-for-updates can emit the installed-version line more than once
    # as it reports progress (confirmed live) -- "exit" after the first
    # match, otherwise piping multiple matching lines through `tr -d
    # '[:space:]'` concatenates them (e.g. "7.24.57.24.5") since it strips
    # the newline between them too, breaking the version comparison below.
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" \
        '/system/package/update/check-for-updates; :delay 3s; /system/package/update/print' \
        2>/dev/null | awk -F': ' '/installed-version/ {print $2; exit}' | tr -d '[:space:]'
}

check_version_and_connectivity() {
    local host="$1" out
    out="$(ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" \
        '/system/package/update/check-for-updates; :delay 3s; /system/package/update/print')"
    echo "$out" | sed 's/^/    /'
    if ! grep -q "installed-version: ${EXPECTED_VERSION}" <<<"$out"; then
        echo "  ERROR: ${host} is not reporting installed-version ${EXPECTED_VERSION}" >&2
        return 1
    fi
    if ! grep -qi "already up to date" <<<"$out"; then
        echo "  ERROR: ${host} did not report 'already up to date' -- either check-for-updates failed (no outbound DNS/HTTPS) or a newer version has appeared since this script started" >&2
        return 1
    fi
    echo "  OK: ${host} confirmed on ${EXPECTED_VERSION} with working internet connectivity."
}

get_routerboard_field() {
    local host="$1" field_pattern="$2"
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" '/system/routerboard/print' \
        2>/dev/null | awk -F': ' -v pat="$field_pattern" '$0 ~ pat {print $2; exit}' | tr -d '[:space:]'
}

# RouterOS package version and RouterBOARD firmware are independent -- a
# device can be fully package-current while its firmware still lags, and a
# plain reboot does NOT apply a pending firmware upgrade on its own
# (confirmed live on mikrotik4: current-firmware stayed behind
# upgrade-firmware through several ordinary reboots until
# /system/routerboard/upgrade was run explicitly). So this always runs,
# regardless of whether the package itself needed upgrading above.
upgrade_routerboard_if_needed() {
    local host="$1" current upgrade

    current="$(get_routerboard_field "$host" "current-firmware")"
    upgrade="$(get_routerboard_field "$host" "upgrade-firmware")"
    echo "  routerboard firmware: current=${current:-?} available=${upgrade:-?}"

    if [ -z "$current" ] || [ -z "$upgrade" ]; then
        echo "  WARNING: could not read routerboard firmware fields on ${host} -- skipping firmware step, check by hand" >&2
        return 0
    fi

    if [ "$current" = "$upgrade" ]; then
        echo "  routerboard firmware already current."
        return 0
    fi

    echo "  staging routerboard firmware upgrade..."
    timeout 15 ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" '/system/routerboard/upgrade' || true

    echo "  rebooting to apply it (staging alone does not apply it)..."
    timeout 15 ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" '/system/reboot' || true

    wait_for_down "$host"

    if ! wait_for_up "$host"; then
        echo "  ${host} did not come back up after the firmware reboot -- STOPPING." >&2
        exit 1
    fi

    echo "  giving services 10s to settle after boot..."
    sleep 10

    current="$(get_routerboard_field "$host" "current-firmware")"
    upgrade="$(get_routerboard_field "$host" "upgrade-firmware")"
    echo "  routerboard firmware after reboot: current=${current:-?} available=${upgrade:-?}"
    if [ "$current" != "$upgrade" ]; then
        echo "  ERROR: ${host}'s routerboard firmware still doesn't match after the reboot -- STOPPING." >&2
        exit 1
    fi
    echo "  OK: ${host} routerboard firmware now current."
}

for host in "${HOSTS[@]}"; do
    echo "=== ${host} ==="

    current="$(get_installed_version "$host")"
    echo "  current installed-version: ${current:-<unknown -- could not reach ${host}>}"

    if [ -z "$current" ]; then
        echo "  ERROR: could not determine ${host}'s current version -- is it reachable? STOPPING." >&2
        exit 1
    fi

    if [ "$current" = "$EXPECTED_VERSION" ]; then
        echo "  already on ${EXPECTED_VERSION}, skipping RouterOS package upgrade."
    else
        echo "  triggering /system/package/update/install (this reboots the device)..."
        timeout 15 ssh "${SSH_OPTS[@]}" "${SSH_USER}@${host}" '/system/package/update/install' || true

        wait_for_down "$host"

        if ! wait_for_up "$host"; then
            echo "  ${host} did not come back up -- STOPPING. Check it by hand before re-running this script." >&2
            exit 1
        fi

        echo "  giving services 10s to settle after boot..."
        sleep 10

        if ! check_version_and_connectivity "$host"; then
            echo "  ${host} failed post-upgrade verification -- STOPPING. Check it by hand before continuing to the next device." >&2
            exit 1
        fi
    fi

    # Always check RouterBOARD firmware, independent of the package step above.
    upgrade_routerboard_if_needed "$host"

    echo "=== ${host} done ==="
    echo
done

echo "All devices checked/upgraded successfully: ${HOSTS[*]}"

#!/usr/bin/env bash
# Dump the RouterOS log of every MikroTik on the network for offline review.
#
# The edge router's log carries the firewall evidence: the log=yes deny-all
# rules at the end of every Phase 5 jump chain (services2internet,
# iot2internet, users2services, users2iot, services2users, services2iot,
# iot2users, iot2services), plus the anti-scan/anti-spam rules, all under
# topic "firewall". See firewall.md for what each chain's rules actually
# allow, and changelog.md's Phase 5 entries for why this logging exists.
# The other devices' logs carry everything else (link flaps, CAPsMAN/wifi
# events, logins, errors), which is why every topic is collected, not only
# "firewall".
#
# Usage:
#   ./dump-logs.sh [output-dir]
#
# Defaults to ../logs (i.e. home/network/logs, regardless of this script's
# own location). One file per device. Each run overwrites the previous
# dump — no historical data kept, just the latest snapshot. RouterOS's own
# memory log buffer is small and rotates, so anything not captured before
# it fills is gone for good. Run this regularly (a periodic cron job, or by
# hand every so often) rather than only once something's already
# suspected, so recent evidence is actually available when you go looking
# for it (see vlan.md's Phase 5 section for what this was originally meant
# to support).
#
# Override the login with MIKROTIK_USER=someone ./dump-logs.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${1:-$SCRIPT_DIR/../logs}"
USER_NAME="${MIKROTIK_USER:-admin}"

# name:hostname — same list as dump-configs.sh; edit both as devices come
# and go. Hostnames resolve via Pi-hole's local DNS records
# (<name>.home.ledcom.fr), so a renumber doesn't require editing this.
# Names are the device identities (README maps the old mikrotik<N> names).
# The RB2011 (old mikrotik1) is off the LAN. Add it here if it is redeployed.
HOSTS=(
  "router:router.home.ledcom.fr"
  "switch-main:switch-main.home.ledcom.fr"
  "switch-office:switch-office.home.ledcom.fr"
  "ap-main:ap-main.home.ledcom.fr"
  "switch-livingroom:switch-livingroom.home.ledcom.fr"
)

mkdir -p "$OUTDIR"
failed=0

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  host="${entry##*:}"
  out="$OUTDIR/$name.txt"

  echo "=== $name ($host) ==="

  # Reachable at all? Keeps a retired or powered-off device from stalling the run.
  if ! timeout 5 bash -c "</dev/tcp/$host/22" 2>/dev/null; then
    echo "  port 22 unreachable — skipping"
    { echo "# $name ($host)"; echo "# UNREACHABLE on port 22 at $(date -Is)"; } > "$out"
    failed=1
    continue
  fi

  {
    echo "# $name ($host) logs, all topics"
    echo "# collected $(date -Is) as user $USER_NAME"
    echo
  } > "$out"

  # -T: no PTY, so RouterOS does not wrap output or emit control characters.
  if ! timeout 30 ssh -T -o ConnectTimeout=10 "$USER_NAME@$host" '/log/print' >> "$out" 2>&1; then
    echo "# (log fetch failed or timed out)" >> "$out"
    echo "  log fetch failed or timed out"
    failed=1
    continue
  fi
  echo "  -> $out"
done

echo
echo "Done. Files in $OUTDIR/"
echo "Firewall entries carry their chain as log-prefix — grep for one to isolate it, e.g.:"
echo "  grep services2users '$OUTDIR/router.txt'"
exit "$failed"

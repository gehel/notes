#!/usr/bin/env bash
# Dump mikrotik1's firewall logs for offline review — the log=yes deny-all
# rules at the end of every Phase 5 jump chain (services2internet,
# iot2internet, users2services, users2iot, services2users, services2iot,
# iot2users, iot2services), plus the anti-scan/anti-spam rules, all under
# topic "firewall". See firewall.md for what each chain's rules actually
# allow, and changelog.md's Phase 5 entries for why this logging exists.
#
# Usage:
#   ./dump-logs.sh [output-dir]
#
# Defaults to ../logs (i.e. home/network/logs, regardless of this script's
# own location). Each run writes a new timestamped file rather than
# overwriting one — RouterOS's own memory log buffer is small and rotates,
# so anything not captured before it fills is gone for good. Run this
# regularly (a periodic cron job, or by hand every so often) rather than
# only once something's already suspected, so a week of evidence is
# actually available when you go looking for it (see vlan.md's Phase 5
# section for what this was originally meant to support).
#
# Override the login with MIKROTIK_USER=someone ./dump-logs.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${1:-$SCRIPT_DIR/../logs}"
USER_NAME="${MIKROTIK_USER:-admin}"
HOST="192.168.10.1"
NAME="mikrotik1-main"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/${NAME}-$(date +%Y-%m-%d_%H%M%S).txt"

if ! timeout 5 bash -c "</dev/tcp/$HOST/22" 2>/dev/null; then
  echo "port 22 unreachable on $HOST — aborting" >&2
  exit 1
fi

{
  echo "# $NAME ($HOST) firewall logs"
  echo "# collected $(date -Is) as user $USER_NAME"
  echo
} > "$OUT"

# -T: no PTY, so RouterOS does not wrap output or emit control characters.
if ! timeout 30 ssh -T "$USER_NAME@$HOST" '/log/print where topics~"firewall"' >> "$OUT" 2>&1; then
  echo "log fetch failed or timed out" >&2
  exit 1
fi

echo "-> $OUT"
echo
echo "Each entry's log-prefix names its chain — grep for one to isolate it, e.g.:"
echo "  grep services2users '$OUT'"

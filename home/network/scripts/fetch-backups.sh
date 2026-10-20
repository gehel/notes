#!/usr/bin/env bash
# Download backup files from every MikroTik to the local machine.
#
# Usage:
#   ./fetch-backups.sh [backup-name] [output-dir]
#
# Defaults to "pre-vlan" and ../backups (i.e. home/network/backups, regardless
# of this script's own location). Downloads <backup-name>.backup and
# <backup-name>.rsc from each device, skipping either one that isn't present
# rather than failing the whole run.
#
# Override the login with MIKROTIK_USER=someone ./fetch-backups.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_NAME="${1:-pre-vlan}"
OUTDIR="${2:-$SCRIPT_DIR/../backups}"
USER_NAME="${MIKROTIK_USER:-admin}"
CTLDIR="$(mktemp -d)"
trap 'rm -rf "$CTLDIR"' EXIT

# name:hostname — keep in sync with dump-configs.sh. Hostnames resolve via
# Pi-hole's local DNS records (<name>.home.ledcom.fr), not IP addresses.
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

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  host="${entry##*:}"
  ctl="$CTLDIR/${name}.sock"

  echo "=== $name ($host) ==="

  # Reachable at all? Keeps a retired or powered-off device from stalling the run.
  if ! timeout 5 bash -c "</dev/tcp/$host/22" 2>/dev/null; then
    echo "  port 22 unreachable — skipping"
    continue
  fi

  # One authenticated connection, reused by both file transfers.
  if ! ssh -M -S "$ctl" -o ControlPersist=60 -o ConnectTimeout=10 \
           -fN "$USER_NAME@$host"; then
    echo "  login failed — skipping"
    continue
  fi

  got_one=0
  for ext in backup rsc; do
    remote="$BACKUP_NAME.$ext"
    local="$OUTDIR/${name}-${BACKUP_NAME}.$ext"
    if scp -o ControlPath="$ctl" "$USER_NAME@$host:$remote" "$local" 2>/dev/null; then
      echo "  -> $local"
      got_one=1
    else
      echo "  $remote not found on device — skipping"
    fi
  done
  [ "$got_one" -eq 1 ] || echo "  no backup files found for '$BACKUP_NAME' on $name"

  ssh -S "$ctl" -O exit "$USER_NAME@$host" 2>/dev/null
done

echo
echo "Done. Files in $OUTDIR/"
ls -la "$OUTDIR/"

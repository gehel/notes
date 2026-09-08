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

# name:address — keep in sync with dump-configs.sh
HOSTS=(
  "mikrotik1-main:192.168.10.1"
  "mikrotik2-switch:192.168.10.2"
  "mikrotik3-office:192.168.10.3"
  "mikrotik4:192.168.10.4"
)

mkdir -p "$OUTDIR"

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  addr="${entry##*:}"
  ctl="$CTLDIR/${name}.sock"

  echo "=== $name ($addr) ==="

  # Reachable at all? Keeps a retired or powered-off device from stalling the run.
  if ! timeout 5 bash -c "</dev/tcp/$addr/22" 2>/dev/null; then
    echo "  port 22 unreachable — skipping"
    continue
  fi

  # One authenticated connection, reused by both file transfers.
  if ! ssh -M -S "$ctl" -o ControlPersist=60 -o ConnectTimeout=10 \
           -fN "$USER_NAME@$addr"; then
    echo "  login failed — skipping"
    continue
  fi

  got_one=0
  for ext in backup rsc; do
    remote="$BACKUP_NAME.$ext"
    local="$OUTDIR/${name}-${BACKUP_NAME}.$ext"
    if scp -o ControlPath="$ctl" "$USER_NAME@$addr:$remote" "$local" 2>/dev/null; then
      echo "  -> $local"
      got_one=1
    else
      echo "  $remote not found on device — skipping"
    fi
  done
  [ "$got_one" -eq 1 ] || echo "  no backup files found for '$BACKUP_NAME' on $name"

  ssh -S "$ctl" -O exit "$USER_NAME@$addr" 2>/dev/null
done

echo
echo "Done. Files in $OUTDIR/"
ls -la "$OUTDIR/"

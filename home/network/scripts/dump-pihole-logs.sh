#!/usr/bin/env bash
# Sync Pi-hole's on-disk logs (FTL.log, pihole.log, webserver.log and their
# rotated/.gz/.backup siblings under /var/log/pihole/) for offline review.
# No API token is configured on this Pi-hole, so this reads straight off
# disk via rsync+sudo instead of the web UI's API.
#
# Usage:
#   ./dump-pihole-logs.sh [output-dir]
#
# Defaults to ../logs/pihole (i.e. home/network/logs/pihole, regardless of
# this script's own location). Re-run anytime — rsync only transfers what
# changed, and rotated/.gz files never change once written so repeat runs
# stay cheap.
#
# Requires passwordless sudo on the Pi-hole host for the login user, scoped
# to running rsync on /var/log/pihole (e.g. a sudoers entry limited to
# `rsync` — avoid a blanket NOPASSWD ALL just for this). Checked up front
# with `sudo -n`; if that fails, this script reports it and exits rather
# than hanging on a password prompt.
#
# Override the login with PIHOLE_USER=someone ./dump-pihole-logs.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${1:-$SCRIPT_DIR/../logs/pihole}"
USER_NAME="${PIHOLE_USER:-$USER}"
HOST="pihole.home.ledcom.fr"
REMOTE_DIR="/var/log/pihole/"

if ! timeout 5 bash -c "</dev/tcp/$HOST/22" 2>/dev/null; then
  echo "port 22 unreachable on $HOST — aborting" >&2
  exit 1
fi

if ! timeout 10 ssh "$USER_NAME@$HOST" 'sudo -n true' 2>/dev/null; then
  echo "passwordless sudo not available for $USER_NAME@$HOST — aborting." >&2
  echo "Set up a sudoers entry scoped to running rsync on $REMOTE_DIR, then re-run." >&2
  exit 1
fi

mkdir -p "$OUTDIR"

rsync -av --rsync-path="sudo rsync" \
  "${USER_NAME}@${HOST}:${REMOTE_DIR}" "$OUTDIR/"

echo
echo "-> $OUTDIR/"
ls -la "$OUTDIR/"
echo
echo "Per-query log is pihole.log (dnsmasq-style, shows 'from <client-ip>' on"
echo "query lines); FTL.log is Pi-hole v6's own consolidated log (matches the"
echo "web UI's Diagnosis/Messages view) but doesn't show the requesting client."

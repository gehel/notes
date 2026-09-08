#!/usr/bin/env bash
# Dump configuration from every MikroTik on the network for offline review.
#
# Usage:
#   ./dump-configs.sh [output-dir]
#
# Defaults to ../dumps (i.e. home/network/dumps, regardless of this script's
# own location). One file per device. Uses SSH connection multiplexing, so
# you are prompted for each device's password once, not once per command.
#
# Override the login with MIKROTIK_USER=someone ./dump-configs.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${1:-$SCRIPT_DIR/../dumps}"
USER_NAME="${MIKROTIK_USER:-admin}"
CTLDIR="$(mktemp -d)"
trap 'rm -rf "$CTLDIR"' EXIT

# name:address — edit as devices come and go
HOSTS=(
  "mikrotik1-main:192.168.10.1"
  "mikrotik2-switch:192.168.10.2"
  "mikrotik3-office:192.168.10.3"
  "mikrotik4:192.168.10.4"
)

# Read-only commands. Nothing here changes state.
COMMANDS=(
  "/export hide-sensitive"
  "/system/resource/print"
  "/system/routerboard/print"
  "/system/package/print"
  "/system/logging/print"
  "/system/clock/print"
  "/ip/service/print"
  "/user/print detail"
  "/user/group/print detail"
  "/user/ssh-keys/print"
  "/ip/address/print"
  "/ip/route/print"
  "/ip/dns/print"
  "/ip/firewall/filter/print"
  "/ip/firewall/nat/print"
  "/ip/firewall/address-list/print"
  "/ip/firewall/connection/tracking/print"
  "/ip/firewall/mangle/print"
  "/ip/pool/print"
  "/ip/dhcp-server/print"
  "/ip/dhcp-server/network/print"
  "/ip/dns/static/print"
  "/routing/ospf/area/print"
  "/routing/ospf/instance/print"
  "/interface/ovpn-server/server/print detail"
  "/queue/simple/print"
  "/queue/tree/print"
  "/queue/interface/print"
  "/queue/type/print"
  "/ip/neighbor/print"
  "/ip/neighbor/discovery-settings/print"
  "/ip/cloud/print"
  "/ip/ssh/print"
  "/ipv6/settings/print"
  "/ipv6/address/print"
  "/ipv6/firewall/filter/print"
  "/interface/print detail"
  "/interface/bridge/print detail"
  "/interface/bridge/port/print detail"
  "/interface/bridge/settings/print"
  "/interface/bridge/vlan/print detail"
  "/interface/vlan/print detail"
  "/interface/ethernet/print detail"
  "/interface/list/print"
  "/interface/list/member/print"
  "/interface/wireless/print detail"
  "/interface/wireless/cap/print"
  "/caps-man/manager/print"
  "/caps-man/configuration/print detail"
  "/caps-man/registration-table/print"
  "/snmp/print"
  "/tool/mac-server/print"
  "/tool/mac-server/mac-winbox/print"
  "/tool/bandwidth-server/print"
)

mkdir -p "$OUTDIR"

for entry in "${HOSTS[@]}"; do
  name="${entry%%:*}"
  addr="${entry##*:}"
  out="$OUTDIR/$name.txt"
  ctl="$CTLDIR/${name}.sock"

  echo "=== $name ($addr) ==="

  # Reachable at all? Keeps a retired or powered-off device from stalling the run.
  if ! timeout 5 bash -c "</dev/tcp/$addr/22" 2>/dev/null; then
    echo "  port 22 unreachable — skipping"
    { echo "# $name ($addr)"; echo "# UNREACHABLE on port 22 at $(date -Is)"; } > "$out"
    continue
  fi

  # One authenticated connection, reused by every command below.
  if ! ssh -M -S "$ctl" -o ControlPersist=120 -o ConnectTimeout=10 \
           -fN "$USER_NAME@$addr"; then
    echo "  login failed — skipping"
    { echo "# $name ($addr)"; echo "# LOGIN FAILED at $(date -Is)"; } > "$out"
    continue
  fi

  {
    echo "# $name ($addr)"
    echo "# collected $(date -Is) as user $USER_NAME"
  } > "$out"

  for cmd in "${COMMANDS[@]}"; do
    {
      echo
      echo "########################################"
      echo "# $cmd"
      echo "########################################"
    } >> "$out"
    # -T: no PTY, so RouterOS does not wrap output or emit control characters.
    # Failures are recorded rather than fatal: menus differ across models and
    # RouterOS versions, and an absent menu is itself useful information.
    if ! timeout 30 ssh -T -S "$ctl" "$USER_NAME@$addr" "$cmd" >> "$out" 2>&1; then
      echo "# (command failed, timed out, or menu not present on this device)" >> "$out"
    fi
    echo "  $cmd"
  done

  ssh -S "$ctl" -O exit "$USER_NAME@$addr" 2>/dev/null
  echo "  -> $out"
done

echo
echo "Done. Files in $OUTDIR/"
ls -la "$OUTDIR/"
echo
echo "Note: /export hide-sensitive redacts passwords and PSKs, but these files still"
echo "contain MAC addresses, DHCP reservations, serial numbers, and network layout."
echo "Do not commit them to a repository with a remote."

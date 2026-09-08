#!/usr/bin/env bash
# Measure latency-under-load, and locate WHERE the queue is.
#
# Run from the desktop (192.168.1.90, wired). Nothing here changes any config.
#
#   ./measure-bufferbloat.sh
#
# Three ping targets are probed simultaneously in every phase, which is the
# point of the exercise:
#
#   192.168.1.1  mikrotik1        - the LAN side of the router
#   10.1.1.1     Internet-Box     - one hop further, across the router's WAN port
#   1.1.1.1      the internet     - everything beyond
#
# Latency that rises only on the far target is a queue you do not control.
# Latency that rises at the Internet-Box is a queue in the router's WAN egress.
# That distinction decides whether shaping on the MikroTik can help at all.

set -uo pipefail

DUR="${DUR:-20}"          # seconds per phase
STREAMS="${STREAMS:-4}"   # parallel transfers used to fill the link
DOWN_URL="https://fsn1-speed.hetzner.com/1GB.bin"
UP_URL="https://speed.cloudflare.com/__up"

TARGETS=("192.168.1.1:mikrotik1" "10.1.1.1:internet-box" "1.1.1.1:internet")
IFACE="${IFACE:-$(ip route show default | awk '/default/{print $5; exit}')}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; kill $(jobs -p) 2>/dev/null' EXIT

command -v curl >/dev/null || { echo "curl not found"; exit 1; }

ctr() { cat "/sys/class/net/$IFACE/statistics/$1_bytes" 2>/dev/null || echo 0; }

# Ping every target at once for DUR seconds, parking results in $TMP/<phase>.<label>.
# NIC byte counters are read either side of the window, so the report can state
# how fast the link was actually running -- without that, a "no bufferbloat"
# result is unfalsifiable: an unsaturated link never fills a buffer.
probe() {
  local phase="$1" count pids=() rx0 tx0 rx1 tx1 secs
  count=$(( DUR * 5 ))                     # -i 0.2 -> 5 samples/second
  rx0=$(ctr rx); tx0=$(ctr tx); secs=$(date +%s.%N)
  for entry in "${TARGETS[@]}"; do
    ping -n -c "$count" -i 0.2 -W 2 "${entry%%:*}" > "$TMP/$phase.${entry##*:}" 2>&1 &
    pids+=($!)
  done
  wait "${pids[@]}" 2>/dev/null
  rx1=$(ctr rx); tx1=$(ctr tx)
  awk -v r0="$rx0" -v r1="$rx1" -v t0="$tx0" -v t1="$tx1" -v s="$secs" \
      'BEGIN{ e=systime()-int(s); if(e<1)e=1;
              printf "%.1f|%.1f\n", (r1-r0)*8/e/1e6, (t1-t0)*8/e/1e6 }' > "$TMP/$phase.rate"
}

# "rtt min/avg/max/mdev = 8.1/9.4/31.2/3.0 ms" -> the four numbers
stats() {
  local f="$1"
  if ! grep -q "min/avg/max" "$f"; then echo "-|-|-|-"; return; fi
  grep "min/avg/max" "$f" | sed 's#.*= ##; s# ms##' | tr '/' '|'
}

loss() { grep -o '[0-9.]*% packet loss' "$1" 2>/dev/null | head -1 || echo "?"; }

echo "Phase 1/3: idle baseline (${DUR}s) — keep the network quiet"
probe idle

echo "Phase 2/3: saturating DOWNLOAD with $STREAMS streams (${DUR}s)"
for _ in $(seq "$STREAMS"); do
  curl -4 -s -o /dev/null --max-time $((DUR + 15)) "$DOWN_URL" &
done
sleep 3                                    # let the transfers ramp up
probe download
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null
sleep 5

echo "Phase 3/3: saturating UPLOAD with $STREAMS streams (${DUR}s)"
up_ok=1
for _ in $(seq "$STREAMS"); do
  ( head -c 400000000 /dev/zero \
      | curl -4 -s -o /dev/null --max-time $((DUR + 15)) \
             -H "Content-Type: application/octet-stream" \
             --data-binary @- "$UP_URL" ) &
done
sleep 3
probe upload
kill $(jobs -p) 2>/dev/null; wait 2>/dev/null

printf '\nLink throughput measured on %s (what the buffers were actually asked to hold):\n' "$IFACE"
for phase in idle download upload; do
  IFS='|' read -r rx tx < "$TMP/$phase.rate"
  printf '  %-10s down %8s Mbps   up %8s Mbps\n' "$phase" "$rx" "$tx"
done

printf '\n%-14s %-12s %9s %9s %9s %9s\n' TARGET PHASE MIN AVG MAX MDEV
printf '%s\n' "----------------------------------------------------------------------"
for entry in "${TARGETS[@]}"; do
  label="${entry##*:}"
  base_avg=""
  for phase in idle download upload; do
    IFS='|' read -r mn av mx md <<< "$(stats "$TMP/$phase.$label")"
    [ "$phase" = idle ] && base_avg="$av"
    delta=""
    if [ "$phase" != idle ] && [ "$av" != "-" ] && [ -n "$base_avg" ] && [ "$base_avg" != "-" ]; then
      delta=$(awk -v a="$av" -v b="$base_avg" 'BEGIN{printf "  (+%.1f ms)", a-b}')
    fi
    printf '%-14s %-12s %9s %9s %9s %9s%s\n' "$label" "$phase" "$mn" "$av" "$mx" "$md" "$delta"
  done
  printf '%s\n' "----------------------------------------------------------------------"
done

echo
echo "Packet loss per phase:"
for entry in "${TARGETS[@]}"; do
  label="${entry##*:}"
  printf '  %-14s idle=%-8s download=%-8s upload=%s\n' "$label" \
    "$(loss "$TMP/idle.$label")" "$(loss "$TMP/download.$label")" "$(loss "$TMP/upload.$label")"
done

echo
echo "If the upload phase shows no latency change at all, the Cloudflare upload"
echo "endpoint probably refused the POST — check with:"
echo "  head -c 10000000 /dev/zero | curl -s -o /dev/null -w '%{speed_upload}\\n' \\"
echo "    -H 'Content-Type: application/octet-stream' --data-binary @- $UP_URL"

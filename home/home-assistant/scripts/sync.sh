#!/usr/bin/env bash
# Sync Home Assistant's /config directory, plus a fresh core log, for offline
# review.
#
# Usage:
#   ./sync.sh [output-dir]
#
# Defaults to ../config (i.e. home/home-assistant/config, regardless of this
# script's own location). Gitignored — see home/home-assistant/README.md.
#
# Override host/user/port/Z-Wave JS App slug with:
#   HA_HOST=home.ledcom.fr HA_USER=hassio HA_SSH_PORT=22 ZWAVE_JS_APP=core_zwave_js ./sync.sh
#
# Excludes:
#   - Recorder/zigbee/watchman databases and their -shm/-wal/-journal
#     siblings: large, binary, not configuration.
#   - www/, tts/, .cache/, deps/: media, generated cache, installed Python
#     packages — not configuration.
#   - .storage/auth*, .storage/core.config, .storage/core.labs,
#     .storage/core.uuid, .storage/http, .storage/onboarding: HA's own
#     internal auth/session state. The SSH user (hassio) can't read these
#     anyway (root-owned, 0600) — excluding them explicitly keeps that a
#     documented decision rather than a wall of permission-denied noise,
#     and keeps this script's exit code clean.
#   - esphome/.device-builder*: ESPHome dashboard's own internal state
#     (peer-link key, preferences), same permission story as above.
#   - custom_components/hacs/: HACS's own installed integration code (52 MB)
#     — identical for every HACS install, not user configuration. HACS's
#     actual tracked state (installed repos, versions, critical/archived
#     flags) lives in .storage/hacs.*, which is NOT excluded.
#
# .storage/ itself is NOT excluded otherwise: most of a modern HA config
# (automations, integrations, registries) lives there rather than in YAML
# if the UI was used for any of it, and it's needed for a real review.
#
# The current core log isn't a file on disk (HA OS logs to journald) — `ha
# core logs` reads it via the Supervisor API, which needs a login shell to
# pick up the token (a plain `ssh host command` runs a non-login shell that
# doesn't source the profile setting it up, and fails 401). Also pulls the
# Z-Wave JS App's own log the same way (`ha apps logs core_zwave_js`) —
# App-level events like "device interview failed" show up there, not in
# HA Core's log. `ha host logs` is the equivalent for OS-level issues, not
# fetched here — run by hand the same way if a problem points that way.
#
# Also pulls Supervisor's own log and the installed add-ons list. `ha core
# logs` only covers HA Core's own process — traffic from a Supervisor-
# managed add-on container (or Supervisor itself) never shows up there, so
# these are the next place to look when something network-related doesn't
# appear in the core log at all (confirmed 2026-09-14: a continuous plain-
# HTTP retry loop to three Cloudflare IPs, port 80, showed nothing in a
# core log pulled during an active burst).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="${1:-$SCRIPT_DIR/../config}"
HA_HOST="${HA_HOST:-home.ledcom.fr}"
HA_USER="${HA_USER:-hassio}"
HA_SSH_PORT="${HA_SSH_PORT:-22}"
ZWAVE_JS_APP="${ZWAVE_JS_APP:-core_zwave_js}"

mkdir -p "$OUTDIR"

rsync -av -e "ssh -p $HA_SSH_PORT" \
  --exclude='home-assistant_v2.db*' \
  --exclude='zigbee.db*' \
  --exclude='.storage/watchman_v2.db*' \
  --exclude='www/' \
  --exclude='tts/' \
  --exclude='.cache/' \
  --exclude='deps/' \
  --exclude='.storage/auth' \
  --exclude='.storage/auth.session' \
  --exclude='.storage/auth_provider.homeassistant' \
  --exclude='.storage/core.config' \
  --exclude='.storage/core.labs' \
  --exclude='.storage/core.uuid' \
  --exclude='.storage/http' \
  --exclude='.storage/onboarding' \
  --exclude='esphome/.device-builder-peer-link-key.bin' \
  --exclude='esphome/.device-builder-preferences.json' \
  --exclude='esphome/.device-builder.json' \
  --exclude='custom_components/hacs/' \
  "${HA_USER}@${HA_HOST}:/config/" "$OUTDIR/"

ssh -p "$HA_SSH_PORT" "${HA_USER}@${HA_HOST}" 'bash -l -c "ha core logs"' \
  > "$OUTDIR/home-assistant-current.log"

ssh -p "$HA_SSH_PORT" "${HA_USER}@${HA_HOST}" \
  "bash -l -c \"ha apps logs $ZWAVE_JS_APP\"" \
  > "$OUTDIR/zwave-js-current.log"

ssh -p "$HA_SSH_PORT" "${HA_USER}@${HA_HOST}" 'bash -l -c "ha supervisor logs"' \
  > "$OUTDIR/supervisor-current.log"

ssh -p "$HA_SSH_PORT" "${HA_USER}@${HA_HOST}" 'bash -l -c "ha apps list"' \
  > "$OUTDIR/apps-list.txt"

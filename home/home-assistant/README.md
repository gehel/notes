# Home Assistant

Working notes for reviewing and maintaining Guillaume's Home Assistant instance. New project,
started 2026-09-08. Home Assistant runs at `192.168.20.60` on the `services` VLAN — see
`home/network/` for the network side.

## Why

An app integration Home Assistant depends on is no longer available (deprecated/removed, exact
one not yet identified — **round 1 of the review below didn't turn up an obvious match**;
several other real issues did, see [config-review.md](config-review.md)). First step: review
the whole configuration and logs to understand current state before deciding on a fix or
replacement.

## Status

**Round 1 of the config review is done — see [config-review.md](config-review.md).** Eight
open findings, three integrations (Pi-hole, IotaWatt, OctoPrint) broken by the `home/network`
VLAN renumber being the highest priority. `automations.yaml`, scenes, dashboards, and the
Z-Wave mesh health question are flagged but not yet gone through in depth.

## Getting the config for review

`scripts/sync.sh` pulls `/config` (via `rsync` over SSH) plus a fresh `ha core logs` capture
into `config/` — see the script's own header for exact exclusions and why. Needs the
**Advanced SSH & Web Terminal** App configured with your SSH key
(App's Configuration tab → `authorized_keys`); override host/user/port with
`HA_HOST`/`HA_USER`/`HA_SSH_PORT` env vars if needed.

## Convention: raw config is never committed

`config/` (gitignored, see `.gitignore`) holds a copy of the actual HA config directory for
review — it is expected to contain `secrets.yaml`-embedded keys, long-lived access tokens in
`.storage/`, the recorder database, and device/person location history. None of that belongs in
git, ever, mirroring `home/network/dumps/` and `backups/`.

Findings, decisions, and anything worth keeping long-term go into tracked documents in this
directory instead — [config-review.md](config-review.md) for what's open, `changelog.md` (not
created yet — nothing's been fixed here so far) for what's been closed and verified, mirroring
`home/network`'s split.

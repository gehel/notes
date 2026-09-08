# Home Assistant

Working notes for reviewing and maintaining Guillaume's Home Assistant instance. New project,
started 2026-09-08. Home Assistant runs at `192.168.20.60` on the `services` VLAN — see
`home/network/` for the network side.

## Why

An app integration Home Assistant depends on is no longer available (deprecated/removed) —
**still not identified.** The leading candidate (a detached App repair, see
[changelog.md](changelog.md)'s finding 10) disappeared on its own before it could be confirmed.
Pick this up again if it recurs or if Guillaume identifies it after the fact.

## Status

**Round 1 of the config review is done — see [config-review.md](config-review.md).** Eight
items closed so far, see [changelog.md](changelog.md) — most recently OctoPrint, reimaged
and reconfigured onto `vlan-iot` with a fresh hostname-based config entry. IotaWatt's address
fix is the only piece of finding 1 left (device currently powered off); the un-ignored
`dlna_dmr` entries (watching) remain open; `automations.yaml`, scenes, dashboards, and the
Z-Wave TRV battery question not yet gone through in depth.

Convention for address fixes: **hostname, not IP** — Pi-hole runs its own local DNS, so pointing
integrations at e.g. `pihole.home.ledcom.fr` survives any future re-addressing that a bare IP
wouldn't.

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
directory instead — [config-review.md](config-review.md) for what's open,
[changelog.md](changelog.md) for what's been closed and verified, mirroring `home/network`'s
split.

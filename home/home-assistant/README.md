# Home Assistant

Working notes for reviewing and maintaining Guillaume's Home Assistant instance. New project,
started 2026-09-08. Home Assistant runs at `192.168.20.60` on the `services` VLAN — see
`home/network/` for the network side.

## Why

An app integration Home Assistant depends on is no longer available (deprecated/removed) —
**identified 2026-09-09: InfluxDB**, removed from the repository it was installed from. See
[config-review.md](config-review.md) finding 6 for what that means in practice and the
decision still needed on how to handle it.

## Standing operational context (not bugs — don't misdiagnose these)

- **OctoPrint runs on-demand only**, shut down most of the time. A `octoprint.coordinator`
  connection error in the logs is the expected state whenever it's off, not a regression —
  only worth investigating if it's still failing while OctoPrint is actually powered on.

## Status

**Round 1 of the config review is done, including `automations.yaml`/scenes/dashboards — see
[config-review.md](config-review.md).** Ten items closed so far, see
[changelog.md](changelog.md) — most recently the Living Room Z-Wave thermostat, which
recovered fully once charged (dead battery confirmed as the actual cause, no re-pairing
needed). Bathroom Upstairs is mid-recovery, currently charging. Open: **finding 6, InfluxDB
detached from its repository — this project's original motivation, now identified, decision
needed on what to do about it** — plus IotaWatt's address (device currently powered off), the
un-ignored `dlna_dmr` entries (watching), fragile ZHA `device_id` usage in three automations
(finding 11), a broken "All cold" scene wired to a physical remote button (finding 12), and a
fully-explained, safe-to-clean-up battery-entity duplication affecting 6 of 7 Z-Wave
thermostats (finding 14).

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

# Home Assistant

Working notes for reviewing and maintaining Guillaume's Home Assistant instance. New project,
started 2026-09-08. Home Assistant runs at `192.168.20.60` on the `services` VLAN — see
`home/network/` for the network side.

## Why

An app integration Home Assistant depends on is no longer available (deprecated/removed).
**Best current candidate: [config-review.md](config-review.md) finding 10** — an App detached
from its repository, showing live in Settings → System → Repairs, possibly Prometheus or
InfluxDB — pending confirmation of the exact name.

## Status

**Round 1 of the config review is done — see [config-review.md](config-review.md).** Six
findings closed so far, see [changelog.md](changelog.md): Pi-hole's stale post-renumber
address, `configuration.yaml`'s malformed `logger:`/`zha:` block (which was silently keeping
ZHA's custom water-valve quirk from loading), the Irrigation automation's misdirected
`numeric_state` trigger, the unused `smart_thermostat` HACS component, a `repairs.issue_registry`
investigation that turned out mostly stale except for one real find (finding 10, see above),
and mikrotik2's outdated RouterBOARD firmware. IotaWatt's address fix is pending (device
currently powered off); OctoPrint (mid-reimage), the un-ignored `dlna_dmr` entries (watching),
and the detached App remain open; `automations.yaml`, scenes, dashboards, and the Z-Wave TRV
battery question not
yet gone through in depth.

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

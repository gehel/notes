# Home Assistant

Working notes for reviewing and maintaining Guillaume's Home Assistant instance. New project,
started 2026-09-08. Home Assistant runs at `192.168.20.60` on the `services` VLAN — see
`home/network/` for the network side.

## Why

The project's original motivation — an app integration no longer available — is **resolved**:
it was InfluxDB (detached from its repository), and Guillaume removed it entirely rather than
migrate or replace, since HA's native Long-term Statistics already covers what mattered (the
Energy dashboard). See [changelog.md](changelog.md)'s finding 6 for the full story. Now
tracking whatever findings turn up on their own merits rather than one overarching mystery.

## Standing operational context (not bugs — don't misdiagnose these)

- **OctoPrint runs on-demand only**, shut down most of the time. A `octoprint.coordinator`
  connection error in the logs is the expected state whenever it's off, not a regression —
  only worth investigating if it's still failing while OctoPrint is actually powered on.

## Status

**Round 1 of the config review is done, including `automations.yaml`/scenes/dashboards — see
[config-review.md](config-review.md).** Thirteen items closed so far, see
[changelog.md](changelog.md) — most recently HA's internal DNS plugin leaking private reverse
lookups to Cloudflare over DNS-over-TLS (found via `home/network`'s firewall logs; fixed by
disabling HA's DNS fallback and adding Pi-hole Conditional Forwarding to mikrotik1). Before
that, Bathroom Upstairs's Z-Wave thermostat recovered after charging (bumpier than Living
Room's, but same root cause and same fix) — two of the three original problem valves are now
fixed, only Parent's Bedroom remains. IotaWatt's back online and its stale-address finding (1)
is closed, but that surfaced a new one: the Energy dashboard references four aggregate sensors
that don't exist anywhere in the config (finding 15). Open: the un-ignored `dlna_dmr` entries
(watching), fragile ZHA `device_id` usage in three automations (finding 11), a broken
"All cold" scene wired to a physical remote button (finding 12), and a fully-explained,
safe-to-clean-up battery-entity duplication affecting 6 of 7 Z-Wave thermostats (finding 14).

Convention for address fixes: **hostname, not IP** — Pi-hole runs its own local DNS, so pointing
integrations at e.g. `pihole.home.ledcom.fr` survives any future re-addressing that a bare IP
wouldn't.

## Getting the config for review

`scripts/sync.sh` pulls `/config` (via `rsync` over SSH) plus fresh `ha core logs`,
`ha apps logs core_zwave_js`, `ha supervisor logs`, and `ha addons list` captures into
`config/` — see the script's own header for exact exclusions and why. **`ha core logs` only
covers HA Core's own process** — a Supervisor-managed add-on container's traffic (or
Supervisor's own) never shows up there; `supervisor-current.log`/`addons-list.txt` are the
next place to look when that's the gap (confirmed 2026-09-14, see `changelog.md`). Needs the
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

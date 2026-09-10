# Changelog — closed findings

Closed and verified findings for Home Assistant. Live review document:
[config-review.md](config-review.md), which holds only what is still open. Nothing is recorded
here on the strength of a change having been made — every entry carries the evidence that
verified it.

## Pi-hole pointed at a pre-VLAN-renumber address (was finding 1, high, closed 2026-09-08)

`config-review.md`'s finding 1: the `pi_hole` config entry still held `192.168.1.40`, a subnet
that no longer exists since `home/network`'s VLAN renumber — failing outright
(`Error setting up entry Pi-Hole for pi_hole`, both v6 and v5 API attempts).

No "Reconfigure" option was available for this integration, so fixed via delete + re-add
(**+ Add Integration**), pointed at **`pihole.home.ledcom.fr`** — a hostname, not the new IP,
per Guillaume's preference (Pi-hole defines its own local DNS records, so this survives any
future re-addressing). Confirmed beforehand this was safe: Pi-hole's entities key off a
generated device ID (`01JHRBV8JAD3R0FANNBCV1ACP3/...`), not the host, so no entity_id changes
were expected or observed.

**Verified:** `.storage/core.config_entries` shows `data.host: "pihole.home.ledcom.fr:80"`,
`modified_at: 2026-09-08T17:03:57`. A fresh `ha core logs` capture spanning 12:00-18:46 that
day — before and after the fix — shows the previous constant stream of `pi_hole`/`hole.v5`
connection errors, then **zero** Pi-hole-related log lines for the 1h40m following the fix.

## `configuration.yaml`'s malformed `logger:`/`zha:` block (was finding 2, medium, closed 2026-09-08)

`config-review.md`'s finding 2: `default:`/`logs:` were indented as siblings of `logger:`
rather than children, and `zha:`'s `database_path`/`enable_quirks`/`custom_quirks_path` ended
up nested inside `logs:` instead of being their own top-level key — so `logger:` was
effectively empty and ZHA never learned about its custom quirks folder.

Took three rounds to actually land, worth recording why:

1. First fix attempt only re-indented the `zha:` block, leaving `logger:` itself still broken
   (`default:`/`logs:` still flush-left) — an easy mistake since the two bugs look identical
   and it's natural to fix the one you're looking at and miss its twin a few lines up.
2. Second attempt fixed the indentation correctly, but no full Core restart had happened yet —
   confirmed via `.ha_run.lock` (`start_ts` unchanged across the edit). `zha:`'s legacy YAML
   settings are read once at integration setup, not on a generic reload, so this silently
   didn't take effect either.
3. Third round: indentation correct, restart confirmed (`.ha_run.lock`'s `pid`/`start_ts` both
   changed), and a log sync landed in the new session's actual output — first two rounds'
   syncs had raced the restart itself and only captured the *old* session's shutdown sequence
   (`s6-rc: ... stopping`), not any fresh post-restart log lines. Lesson for next time: wait a
   beat after a restart before syncing, and check `.ha_run.lock` first if verification looks
   inconclusive.

**Verified:** fresh log has multiple `DEBUG (MainThread) [zigpy.device]`/`[zigpy...]` lines
(zero before). Guillaume reconfigured the SONOFF SWV garden valve afterward and the entity
registry now shows its full quirk-defined entity set — per-channel irrigation schedules,
seasonal adjustment multipliers, rain delay, capacity units, flow rate — rather than a generic
switch; confirmed live by Guillaume ("it now shows the flow rate").

## Irrigation automation's `numeric_state` trigger pointed at switches instead of sensors (was finding 3, medium, closed 2026-09-08)

`config-review.md`'s finding 3: the `high_flow_rate` trigger in the "Irrigation" automation
used `numeric_state` against `switch.garden_water_east_switch`/`_switch_2` (on/off entities),
so it never initialized — logged as a recurring warning, not a hard error, so it went unnoticed
for a while.

Fixed by repointing the trigger at the entities it actually needed:
`sensor.water_west_volume_flow_rate` / `sensor.garden_water_east_volume_flow_rate` (the
existing flow-rate sensors — `above: 300` for 3 minutes, notifying about a possible leak). Not
a generic template/state-trigger rewrite — the automation's own intent was already a numeric
threshold, it was just wired to the wrong entities.

**Verified:** read directly from `automations.yaml` post-fix — trigger now targets the two
`_volume_flow_rate` sensors. No "Irrigation" or `numeric_state`-on-switch warnings anywhere in
the post-restart log (the "Irrigation" warnings visible in the round-2 sync were from the
*old*, pre-restart session still running the previous broken version, consistent with that
sync having raced the restart per finding 2 above).

## `smart_thermostat` (HACS) removed (was finding 5, low, closed 2026-09-08)

`config-review.md`'s finding 5: `custom_components/smart_thermostat`
(`ScratMan/HASmartThermostat`) had no config entry at all, unmaintained since `2024.12.0`, dead
weight superseded by `better_thermostat`. Removed via HACS.

**Verified:** `.storage/hacs.repositories`'s `smart_thermostat` entry no longer has
`installed`/`installed_commit`/`version_installed` — HACS itself no longer considers it
installed. The `custom_components/smart_thermostat` folder is still on disk as of this sync —
expected, HACS can't delete a loaded integration's files from a running instance, so that
finishes on the next restart. Not worth restarting just for this; it'll clear on its own next
time HA restarts for another reason.

## `repairs.issue_registry`'s stale entries sorted out (was finding 8, closed 2026-09-08)

`config-review.md`'s finding 8 started as "HACS restart-required entries never clear, probably
just needs a restart." That theory didn't survive a check against a restart that had actually
happened (finding 2's fix): all 23 stored issues, unchanged, byte-for-byte. Broke the list down
instead of guessing further:

- **13 HACS "restart required" entries** (oldest 2025-02-09) — survived the restart, so
  permanent cosmetic noise, not a live signal. HACS/hassio never seem to purge a
  `repairs.issue_registry` entry once superseded by a newer one; they just stop being shown as
  active. Left alone — no functional impact either way, safe to dismiss for tidiness only.
- **Two `mikrotik` reauth issues** — referenced config entry IDs
  (`01KZRMCPZXVWTAXGX5C7YRTBTG`, `01KZRM9Y1G2SSZ1PQFAT1NYNJG`) that no longer exist; the three
  current `mikrotik` entries were all freshly created 2026-09-08T11:18. Stale, moot.
- **`unhealthy_system_setup`/`unhealthy_system_supervisor` and three opaque-hex `hassio`
  entries** — also stale. **Verified directly** against Settings → System → Repairs (the live
  UI, not the storage file): only 3 issues actually show there — the 2 `better_thermostat`
  missing-entity ones (tracked against the Z-Wave mesh health question in `config-review.md`),
  and one detached-App issue, promoted to its own finding 10.
- The `octoprint` reauth issue is the one real, current entry in the list — already tracked
  under finding 1, not a separate problem.

**General lesson recorded for future rounds:** `repairs.issue_registry`'s storage file is not a
reliable signal for "is this currently active" — it accumulates historical entries that HA
itself has stopped surfacing. The live Settings → System → Repairs page is authoritative;
reading the storage file alone will overstate what's actually open.

## `mikrotik2`'s RouterBOARD firmware upgraded (was finding 9, low, closed 2026-09-08)

`config-review.md`'s finding 9: `update.under_the_stairs_mikrotik_2_routerboard` showed
`installed_version: '7.23.3'` against `latest_version: '7.24.2'` — genuinely behind, not stale
integration cache (mikrotik2's RouterOS package itself was already correctly 7.24.2; RouterBOARD
firmware is a separate layer). Guillaume upgraded it directly via RouterOS, out of band from
HA — consistent with the finding's prediction that the `homeassistant` API user's `!write,!reboot`
policy would likely block triggering it from HA's own "Install" button.

**Verified against `home/network`'s own fresh dump** (`dumps/mikrotik2-switch.txt`,
2026-09-08 21:57:25): `/system/routerboard/print` shows `current-firmware: 7.24.2` matching
`upgrade-firmware: 7.24.2`. **Also confirmed from HA's side** on the next sync:
`update.under_the_stairs_mikrotik_2_routerboard` now shows `installed_version`/`latest_version`
both `7.24.2`, state `off` (no update pending).

## OctoPrint reimaged, reconfigured, and moved to `vlan-iot` (was part of finding 1, high, closed 2026-09-08)

`config-review.md`'s finding 1: OctoPrint's HA integration held the pre-renumber
`192.168.1.81` and had a separate open reauth issue since 2026-06-11. Guillaume lost the
system password, backed up OctoPrint's config via its own Settings → Backup & Restore, and
reimaged the SD card fresh — which resolved both problems at once by necessity, same pattern
as finding 9's prediction: a fresh OS means a fresh OctoPrint install with a new API key, so
the HA integration entry had to be recreated regardless.

New entry points at **`octoprint-wifi.home.ledcom.fr`** (hostname, matching the
`iot-internet` address-list naming already used on mikrotik1 —
`home/network/dumps/mikrotik1-main.txt`), fresh `entry_id`
(`01M21CPY0KC4Z8ZG96KGJ5A6PA`, replacing the old reauth-flagged
`01KBN54W3AQH7RP37SPW9XGM62` — that old reauth issue is now stale/moot, same pattern as the
mikrotik ones in finding 8).

**Verified:** zero `octoprint`-related log lines across 2+ hours since the new entry was
created (20:52 to 22:53), where the old entry had been erroring or flagged for reauth.
`home/network`'s fresh CAPsMAN registration table shows a freshly-connected client on
`LEDCOM-IoT` (uptime ~53 minutes at dump time, matching the reimage timeline) — consistent
with OctoPrint rejoining the correct SSID/VLAN post-reimage. `home/network/vlan.md`'s device
migration table updated to mark OctoPrint fully verified, not just router-side-applied.

## Detached-App repair, closed unresolved (was finding 10, closed 2026-09-08)

`config-review.md`'s finding 10: a live `hassio: issue_addon_detached_addon_remove` repair,
Guillaume's guess was Prometheus or InfluxDB, and the best candidate so far for the project's
original "app no longer available" motivation.

**Closed without being identified — it disappeared from Settings → System → Repairs on its
own.** Guillaume didn't dismiss it; nothing else changed that he's aware of. The one piece of
circumstantial evidence found in `.storage/repairs.issue_registry`: a `hassio`-domain issue
created this morning (9 seconds after that day's first restart) went from
`dismissed_version: null` to `dismissed_version: '2026.9.1'` (the currently-running version)
between two syncs — plausibly this one, but `hassio`-domain issue IDs are opaque hashes in
storage, not the human-readable slug shown in the UI, so this was never confirmed to be the
same issue.

**Left open, unresolved:** the original "app integration no longer available" motivation for
this whole project — this was the leading candidate and it evaporated before being identified.
If it recurs, or if Guillaume identifies which App it was after the fact, worth a fresh look
then; not worth chasing further right now with no reproducible evidence.

**Update 2026-09-09: it recurred and was identified.** The repair came back with its actual
text this time: *"App InfluxDB has been removed from the repository it was installed from."*
Confirms Guillaume's original guess. Rolled into `config-review.md` finding 6 (InfluxDB) rather
than reopening this finding number — see there for what "detached" means in practice and the
decision Guillaume still needs to make about it. This entry stays as the historical record of
the first (unconfirmed) sighting.

## Heating dashboard's Living Room low-battery badge fixed (was finding 13, medium, closed 2026-09-09)

`config-review.md`'s finding 13: the Living Room low-battery badge's visibility condition
checked `binary_sensor.thermostat_living_room_2_charge_battery_soon` (misplaced "_2", entity
doesn't exist) instead of `binary_sensor.thermostat_living_room_charge_battery_soon` — could
never fire, for one of the three thermostats currently having problems.

Fixed by Guillaume via the dashboard's own "Edit in YAML" badge editor (not a direct
`.storage` edit, per this project's convention of never hand-editing HA's internal state).

**Verified:** `.storage/lovelace.dashboard_heating`'s Living Room badge now has matching
entities in both the displayed `entity` field and the `visibility` condition
(`binary_sensor.thermostat_living_room_charge_battery_soon` in both), consistent with the
other six badges.

## Living Room Z-Wave thermostat recovered after charging (closed 2026-09-09)

One of the three Fibaro FGT-001 valves `better_thermostat` had been reporting `unavailable`
(no dedicated finding number — tracked under config-review.md's "Not yet reviewed" Z-Wave
note). Guillaume charged it (along with Kitchen and Hall, which weren't showing a problem).

**Verified, both live and from the next sync:** `climate.thermostat_living_room` reports
`state=heat` again; `sensor.thermostat_living_room_battery_level_2` reads 99%;
`.storage/repairs.issue_registry` no longer has a `missing_entity_climate.thermostat_living_room`
entry (only Parent's Bedroom and Bathroom Upstairs remain); the Heating dashboard's low-battery
badge for Living Room (finding 13, fixed above) shows no alert. Confirms the root cause was
simply a dead/empty battery, not a Z-Wave mesh or hardware fault — the device reconnected on
its own once powered, no re-pairing needed.

## InfluxDB App removed, config cleaned up (was finding 6, medium, closed 2026-09-09)

`config-review.md`'s finding 6: InfluxDB's App was detached from its repository (the original
"app integration no longer available" motivation for this whole project, per finding 10) and
separately throwing connection timeouts. Guillaume wasn't actively using it — decided to drop
it rather than migrate or replace, since `home/home-assistant`'s Energy dashboard already runs
entirely on HA's native Long-term Statistics (grid + 8 device-level consumption sensors fed by
IotaWatt, confirmed still intact and requiring no InfluxDB dependency) — nothing of practical
value was lost by removing it.

Removed via Settings → Add-ons → the App itself, **not just the App** — `configuration.yaml`'s
`influxdb:` block and `secrets.yaml`'s `influxdb_username`/`influxdb_password` needed a
separate manual removal (uninstalling the App doesn't touch HA Core's YAML config), which
Guillaume did in a follow-up step after the first sync showed a `ConnectionResetError` where
the previous `timeout` had been — expected transitional symptom of removing the App before
its config, not a new problem.

**Verified:** `configuration.yaml` and `secrets.yaml` both confirmed clean of any InfluxDB
reference. Required a full restart (a YAML reload alone won't un-set-up a still-declared
component) — confirmed via `.ha_run.lock`'s `start_ts` changing. Post-restart log (100 lines,
~2 minutes of fresh activity) has zero errors of any kind and zero mentions of InfluxDB.

**This also closes out finding 10's open thread** (`changelog.md`, above) — the project's
original "app no longer available" motivation is resolved by removal, not by identifying a
replacement or fix. Whether Grafana (also mentioned as possibly unused) gets removed too is
Guillaume's call, not tracked here unless it surfaces its own finding.

## Bathroom Upstairs Z-Wave thermostat recovered after charging (closed 2026-09-10)

The second of the three Fibaro FGT-001 valves `better_thermostat` had been reporting
`unavailable` (tracked under `config-review.md`'s "Not yet reviewed" Z-Wave note, alongside
Living Room and Parent's Bedroom). Battery had been empty for an extended period.

Bumpier recovery than Living Room's, worth recording: an interview attempt on 2026-09-09
failed outright (`ZW0201`/`ZW0204` errors, node presumed dead) after a few hours of charging;
several more hours of charging were needed before it started responding at all, and even after
the `missing_entity` repair cleared, the Z-Wave JS log still showed ~9 timeouts across a
90-minute window the next morning before a query finally succeeded cleanly. Battery now
reports 100%.

**Verified:** `.storage/repairs.issue_registry` no longer has
`missing_entity_climate.thermostat_bathroom_upstairs` (only Parent's Bedroom remains).
`zwave-js-current.log` shows a clean successful `Air temperature sensor reading` after the
timeout streak stopped. Guillaume confirmed battery level at 100% live in HA.

Only Parent's Bedroom left of the original three — same fix expected to apply, not yet
started.

## HA's internal DNS was leaking private reverse-lookups to Cloudflare over DoT (closed 2026-09-10)

Found from `home/network`'s firewall logs (`dump-logs.sh`): recurring bursts of hundreds of TCP
SYNs from Home Assistant itself (`192.168.20.60`, not Pi-hole) to `1.1.1.1`/`1.0.0.1:853`
(DNS-over-TLS), all denied — `services2internet`'s DoT accept was scoped to Pi-hole's address
only. Root-caused via `ha dns info`/`ha dns logs`, not just the firewall side:

- `ha dns info` showed `fallback: true`, `servers: []`, `locals: [dns://192.168.20.40]` (Pi-hole) —
  Supervisor's internal DNS plugin (`hassio_dns`) had no explicit upstream forwarder, so
  anything Pi-hole couldn't answer cleanly fell back to its hardcoded Cloudflare DoT resolvers.
- `ha dns logs` showed the actual queries: **PTR (reverse-DNS) lookups for a `/26`-sized block
  of `192.168.20.0/24`** (`.193`-`.254`) — private RFC1918 space Cloudflare could never answer
  even if the firewall let it through. Each query hung the full 30-second dial timeout because
  the firewall was silently dropping the fallback attempt, rather than failing fast.
- The swept range didn't match the DHCP pool (`192.168.20.100`-`.200`, confirmed from
  `home/network`'s router dump) or a misconfigured netmask on HA's own interface (confirmed
  correctly `/24` via `ha network info`) — the exact integration/component issuing the sweep
  wasn't identified (checked config entries, `configuration.yaml`, and a fresh core log; nothing
  obviously explained it), but wasn't needed to fix the actual problem.

**Two-part fix, per Guillaume's direction ("all queries should go through Pi-hole; we're
blocking direct internet access anyway, so the fallback doesn't work"):**

1. **`ha dns options --fallback=false`** — Supervisor's DNS plugin no longer falls back to
   Cloudflare at all. Verified: `ha dns info` now shows `fallback: false`.
2. **Pi-hole Conditional Forwarding added** (Settings → DNS, web UI) — a single rule,
   `192.168.0.0/16` → `192.168.10.1` (mikrotik1, the DHCP server for all three VLANs), so
   Pi-hole actually has somewhere to ask for hostnames of devices it never DHCP'd itself,
   instead of returning nothing. Confirmed mikrotik1 would answer such a query beforehand
   (`allow-remote-requests: yes` in its dump, and `chain=input`'s DNS accept rules aren't
   scoped to any particular VLAN).

**Verified (fallback half only):** `ha dns info` confirms `fallback: false` — the leak itself is
fully closed regardless of anything below, since HA no longer attempts external DNS at all.

**Correction, same day: the Conditional Forwarding half wasn't actually verified.** The
`dig -x 192.168.20.60 @192.168.20.40` test above returned `home.ledcom.fr`, but that's a
manually-curated Pi-hole local record for `.60` (this project's own established convention for
named devices) — it would have answered identically with or without the new forwarding rule,
and proved nothing about whether Pi-hole could actually reach mikrotik1 for data it doesn't
already have. Guillaume caught this. A clean test (`dig -x 192.168.10.194 @192.168.10.1`, a
plain dynamic lease with no Pi-hole record) showed mikrotik1 itself returning `NXDOMAIN` —
RouterOS doesn't expose DHCP leases via DNS at all natively. Full root-cause and the
lease-script fix that makes it actually work are in `home/network/changelog.md` — mikrotik1 now
gives real answers, and Pi-hole's forward is confirmed relaying them correctly end-to-end (the
`SERVFAIL` was a cached negative answer from the many earlier failed attempts; `pihole
reloaddns` cleared it).

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

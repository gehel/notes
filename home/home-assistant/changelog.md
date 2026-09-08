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

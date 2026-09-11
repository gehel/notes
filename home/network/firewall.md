# Firewall rules — current live state

Generated 2026-09-10 from that day's [dumps/](dumps/) (17:30 collection — post-Phase-5
jump-chain reorg, the forward-chain hygiene reorder, Pi-hole's DNS/TCP accept, and the two new
`chain=input` NTP rules). This is the actual ruleset, in the actual order it's evaluated in —
not the design intent. For the intended policy and the reasoning behind it, see
[vlan.md](vlan.md)'s policy matrix; for open issues, see [config-review.md](config-review.md)
finding 21, referenced inline below as **[21]**.

RouterOS evaluates each chain top to bottom and stops at the first match, so **position is
part of the rule** — a correct-looking rule in the wrong place is a bug. That's why this is a
table in rule order, not a summary.

## Quick reference: what can reach what

The steady-state policy, as actually implemented — `vlan-users` on mikrotik1's `bridge-main`
is VLAN 10, `vlan-services` is VLAN 20, `vlan-iot` is VLAN 30. Since the Phase 5 reorg, every
cell below corresponds to exactly one jump-chain, named the same way:

| From \ To | internet | users | services | iot | router mgmt |
|---|---|---|---|---|---|
| **users** | allow (`users2internet`) | — | `mgmt` full; DNS (53); HA web (443) for everyone else (`users2services`) | `mgmt` full; everyone -> OctoPrint web UI, port 80 (`users2iot`) | `mgmt` list only, + NTP (123) to gateway |
| **services** | HTTP/HTTPS from any services host; Pi-hole's own DNS (53, UDP+TCP) and DoT (853) (`services2internet`, IPv4 only — **[21]**) | HA -> printer (CUPS/631), HA -> Samsung TV (8002) (`services2users`) | — | HA: ESPHome/IotaWatt (6053, 80), Tuya local (6668) (`services2iot`) | `mgmt` list only, + NTP (123) to gateway |
| **iot** | DROP by default; named exception `octoprint` list, ports 80/443 (`iot2internet`) | deny by default, logged (`iot2users`) | ceiling fan's DNS explicitly dropped first, then Pi-hole DNS (53, UDP only), MQTT to HA (1883) (`iot2services`) | — | NTP (123) to gateway only |

Every VLAN now has its own NTP-to-gateway accept in `chain=input` (added 2026-09-10 — see
`changelog.md`'s finding 23 closure; `vlan-iot`'s existed since Phase 3, `vlan-services`/
`vlan-users` were a genuine gap until then).

**ICMP (ping) is not governed by the table above at all — it's handled uniformly for every
cell**, VLAN-pair-blind, by the general `chain=ICMP` jump (moved ahead of the dispatch section
on 2026-09-10, see below). Rate-limited ping now works between every VLAN pair and to/from the
internet, including combinations the table would otherwise suggest are fully denied (e.g.
`iot <-> services`/`users`) — a deliberate widening, not an oversight.

All three VLANs now have their own IPv6 dispatch chains — see **[21]** and the IPv6 section
below. `services`'s is narrower than its IPv4 row (HTTP/HTTPS + HA-only access to the
printer/TV, no IPv6 equivalent of Pi-hole's own DNS/DoT exception yet, since nothing needs it);
`iot`'s deny-by-default now matches IPv4's intent deliberately rather than by accident, with the
same `octoprint` internet exception mirrored. `vlan-iot`'s rules are applied but not yet
functionally verified (OctoPrint was offline) — see `changelog.md`.

## mikrotik1 (RB2011UiAS, edge router) — `chain=input`

| # | Action | Match | Comment |
|---|---|---|---|
| 1 | accept | `connection-state=established,related` | defconf: accept established,related |
| 2 | add-to-list | `protocol=tcp tcp-flags=syn connection-limit=30,32 in-interface-list=WAN` -> `Syn_Flooder` | Add Syn Flood IP to the list |
| 3 | drop | `src-address-list=Syn_Flooder in-interface-list=WAN` | Drop to syn flood list |
| 4 | add-to-list | `protocol=tcp psd=21,3s,3,1 in-interface-list=WAN` -> `Port_Scanner` | Port Scanner Detect |
| 5 | drop | `src-address-list=Port_Scanner in-interface-list=WAN` | Drop to port scan list |
| 6 | drop | `in-interface-list=WAN` | defconf: drop all from WAN |
| 7 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp input flow |
| 8 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=8728` | HA API access (post-renumber) |
| 9 | accept | `src-address-list=mgmt` | mgmt hosts to router |
| 10 | accept | `protocol=udp port=53` | Accept DNS - UDP |
| 11 | accept | `protocol=tcp port=53` | Accept DNS - TCP |
| 12 | accept | `protocol=udp in-interface=vlan-users dst-port=67` | DHCP server (vlan-users) |
| 13 | accept | `connection-state=new protocol=udp in-interface=vlan-services dst-port=123` | services: NTP from gateway |
| 14 | accept | `connection-state=new protocol=udp in-interface=vlan-users dst-port=123` | users: NTP from gateway |
| 15 | accept | `connection-state=new protocol=udp in-interface=vlan-iot dst-port=123` | iot: NTP from gateway |
| 16 | drop | *(none — catch-all)* | Drop anything else! |

Rules 8-12 don't declare `connection-state=new` — informational-only (finding 22, still open,
low priority): rule 1's established/related accept already intercepts non-new traffic before
any of these could ever see it, so there's no known live impact. Rules 13-15 (all three added
with `connection-state=new` from the start) are consistent with the forward chain's standard.

## mikrotik1 — `chain=forward`

| # | Action | Match | Comment |
|---|---|---|---|
| 17 | fasttrack-connection | `connection-state=established,related` | defconf: fasttrack |
| 18 | accept | `connection-state=established,related` | defconf: accept established,related |
| 19 | add-to-list | `protocol=tcp tcp-flags=syn connection-nat-state=dstnat connection-limit=30,32 in-interface-list=WAN` -> `Syn_Flooder` | Syn flood detect - any forwarded port |
| 20 | drop | `src-address-list=Syn_Flooder in-interface-list=WAN` | Drop syn flooders - inbound |
| 21 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp forward flow |
| 22 | drop | `dst-address-list=bogons` | Drop to bogon list |
| 23 | add-to-list | `protocol=tcp connection-limit=30,32 dst-port=25,587 limit=30/1m,0` -> `spammers` | Add Spammers to the list for 3 hours |
| 24 | drop | `protocol=tcp src-address-list=spammers dst-port=25,587` | Avoid spammers action |
| 25 | drop | `connection-state=invalid` | defconf: drop invalid |
| 26 | jump -> `users2internet` | `in-interface=vlan-users out-interface-list=WAN` | dispatch: users -> internet |
| 27 | jump -> `users2services` | `in-interface=vlan-users out-interface=vlan-services` | dispatch: users -> services |
| 28 | jump -> `users2iot` | `in-interface=vlan-users out-interface=vlan-iot` | dispatch: users -> iot |
| 29 | jump -> `services2internet` | `in-interface=vlan-services out-interface-list=WAN` | dispatch: services -> internet |
| 30 | jump -> `services2users` | `in-interface=vlan-services out-interface=vlan-users` | dispatch: services -> users |
| 31 | jump -> `services2iot` | `in-interface=vlan-services out-interface=vlan-iot` | dispatch: services -> iot |
| 32 | jump -> `iot2internet` | `in-interface=vlan-iot out-interface-list=WAN` | dispatch: iot -> internet |
| 33 | jump -> `iot2users` | `in-interface=vlan-iot out-interface=vlan-users` | dispatch: iot -> users |
| 34 | jump -> `iot2services` | `in-interface=vlan-iot out-interface=vlan-services` | dispatch: iot -> services |
| 35 | jump -> `internet2services` | `connection-nat-state=dstnat out-interface=vlan-services in-interface-list=WAN` | dispatch: internet -> services |
| 36 | drop | *(none — catch-all)* | Drop all other forward traffic |

Rules 19-25 (syn-flood, ICMP jump, bogon, spammer, invalid) were reordered ahead of the
dispatch section on 2026-09-10 — they used to sit after it, where the dispatch jumps'
unconditional termination made them dead or misattributed (see `changelog.md`'s Phase 5
entries for the full story, including the deliberate ICMP-widening tradeoff this involved).

Every VLAN-pair jump (26-35) uses `WAN`/`vlan-*` on both sides, no exceptions, and no old
individual per-relationship rule survives past the dispatch section — the reorg and its
cleanup (Phase 5, see [changelog.md](changelog.md)) removed every one of them.

## mikrotik1 — `chain=ICMP` (jump target)

| # | Action | Match | Comment |
|---|---|---|---|
| 37 | accept | `protocol=icmp icmp-options=8:0 limit=10,50:packet` | Echo request - Avoiding Ping Flood |
| 38 | accept | `protocol=icmp icmp-options=0:0` | Echo reply |
| 39 | accept | `protocol=icmp icmp-options=11:0` | Time Exceeded |
| 40 | accept | `protocol=icmp icmp-options=3:0-1` | Destination unreachable |
| 41 | accept | `protocol=icmp icmp-options=3:4` | PMTUD |
| 42 | drop | `protocol=icmp` | Drop to the other ICMPs |
| 43 | jump (from `chain=output`) | `protocol=icmp` | Jump for icmp output |

Reached directly from `chain=forward` rule 21, **before** the VLAN-pair dispatch section —
every forwarded ICMP packet is fully decided here (rate-limited echo accepted, a few other
types accepted, everything else dropped) regardless of which VLAN pair it belongs to. See the
Quick reference section above for what this means in practice.

## mikrotik1 — jump chains (Phase 5 reorg)

One chain per VLAN-pair traffic relationship, dispatched into from `chain=forward` rules
26-35 above. Every accept declares `connection-state=new`; every chain not otherwise noted
ends in a logged deny-all (`log-prefix` matches the chain name, for log review — see
`scripts/dump-logs.sh`).

**`users2internet`** (# 44)

| # | Action | Match | Comment |
|---|---|---|---|
| 44 | accept | `connection-state=new` | users2internet: internet |

No deny-all — nothing else needed since this chain has one rule that accepts everything, by
design (`vlan-users` keeps unrestricted internet access).

**`services2internet`** (# 45-49)

| # | Action | Match | Comment |
|---|---|---|---|
| 45 | accept | `protocol=tcp dst-port=80,443` | services2internet: HTTP/HTTPS from any services host |
| 46 | accept | `protocol=udp src-address=192.168.20.40 dst-port=53` | services2internet: Pi-hole's own upstream DNS |
| 47 | accept | `protocol=tcp src-address=192.168.20.40 dst-port=53` | services2internet: Pi-hole's own upstream DNS (TCP) |
| 48 | accept | `protocol=tcp src-address=192.168.20.40 dst-port=853` | services2internet: Pi-hole's own upstream DNS-over-TLS |
| 49 | drop, logged | *(catch-all)* | services2internet: deny everything else |

Rule 47 (TCP/53) added 2026-09-10 — found via `dump-logs.sh`: Pi-hole falls back to DNS-over-TCP
for large/DNSSEC-heavy responses, which only the UDP accept had covered until then. Pi-hole's
own NTP is **not** in this chain — as of 2026-09-10 it's pinned directly at mikrotik1
(`192.168.20.1`) via `timesyncd.conf`, reaching it through `chain=input` rule 13 above, not
through the internet at all (finding 23, closed).

**`iot2internet`** (# 50-52)

| # | Action | Match | Comment |
|---|---|---|---|
| 50 | accept | `protocol=tcp src-address-list=octoprint dst-port=80,443` | iot2internet: octoprint updates exception |
| — | drop | `src-address=192.168.30.63` | iot2internet: ceiling fan phone-home (silenced, expected) |
| 51 | drop, logged | *(catch-all)* | iot2internet: deny everything else |

The ceiling fan drop is unlogged, added 2026-09-11: it was 97% of the firewall log's volume
(953 of 981 lines in one collection) — the fan retrying its cloud phone-home every ~2s against
the default deny, correctly blocked but dominating the log buffer (`README.md` already flags
this as a risk on RouterOS's small, rotating log). Still dropped, just not logged; anything
else hitting the catch-all still is.

**`users2services`** (# 52-55)

| # | Action | Match | Comment |
|---|---|---|---|
| 52 | accept | `src-address-list=mgmt` | users2services: mgmt hosts full |
| 53 | accept | `protocol=udp dst-address=192.168.20.40 port=53` | users2services: DNS |
| 54 | accept | `protocol=tcp dst-address=192.168.20.60 dst-port=443` | users2services: HA web |
| 55 | drop, logged | *(catch-all)* | users2services: deny everything else |

**`users2iot`** (# 56-58)

| # | Action | Match | Comment |
|---|---|---|---|
| 56 | accept | `src-address-list=mgmt` | users2iot: mgmt hosts full |
| 57 | accept | `protocol=tcp dst-address-list=octoprint dst-port=80` | users2iot: everyone -> octoprint web UI |
| 58 | drop, logged | *(catch-all)* | users2iot: deny everything else |

**`services2users`** (# 59-62)

| # | Action | Match | Comment |
|---|---|---|---|
| 59 | accept | `protocol=tcp src-address=192.168.20.60 dst-address-list=ha-mikrotik-targets dst-port=8728` | services2users: HA MikroTik integration API |
| 60 | accept | `protocol=tcp src-address=192.168.20.60 dst-address=192.168.10.110 dst-port=631` | services2users: HA -> printer (CUPS) |
| 61 | accept | `protocol=tcp src-address=192.168.20.60 dst-address=192.168.10.195 dst-port=8002` | services2users: HA -> Samsung TV |
| 62 | drop, logged | *(catch-all)* | services2users: deny everything else |

All three accepts here are scoped to `src-address=192.168.20.60` (Home Assistant) — verified
deliberately, since these are meant to be HA-specific, not general to any services host.

**`services2iot`** (# 63-66)

| # | Action | Match | Comment |
|---|---|---|---|
| 63 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=6668` | services2iot: HA -> Tuya local (fan) |
| 64 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=80` | services2iot: HA -> Tasmota/IotaWatt |
| 65 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=6053` | services2iot: HA -> ESPHome (IotaWatt) |
| 66 | drop, logged | *(catch-all)* | services2iot: deny everything else |

Scoped to `src-address=192.168.20.60` but **not** to a specific destination — deliberate
(Guillaume's call): any future IoT device on these ports is reachable from HA without a
firewall change.

**`iot2users`** (# 67)

| # | Action | Match | Comment |
|---|---|---|---|
| 67 | drop, logged | *(catch-all)* | iot2users: deny everything else |

No exceptions — `iot` has no legitimate reason to initiate anything toward `users`.

**`iot2services`** (# 68-71)

| # | Action | Match | Comment |
|---|---|---|---|
| 68 | drop | `protocol=udp src-address=192.168.30.63 dst-address=192.168.20.40 port=53` | iot2services: ceiling fan drop DNS (udp) |
| 69 | accept | `protocol=udp dst-address=192.168.20.40 port=53` | iot2services: DNS to pi-hole (udp) |
| 70 | accept | `protocol=tcp dst-address=192.168.20.60 dst-port=1883` | iot2services: MQTT to HA |
| 71 | drop, logged | *(catch-all)* | iot2services: deny everything else |

TCP DNS-to-Pi-hole was removed in the Phase 5 reorg (never needed) — UDP only now, and the
ceiling fan's TCP DNS-drop override went with it as redundant.

**`internet2services`** (# 72)

| # | Action | Match | Comment |
|---|---|---|---|
| 72 | accept | `connection-state=new connection-nat-state=dstnat protocol=tcp dst-address=192.168.20.60 dst-port=443` | internet2services: Home Assistant HTTPS |

No deny-all — the dispatch jump itself (# 35) is already scoped to `connection-nat-state=dstnat`
plus `WAN`/`vlan-services`, so nothing else can reach this chain.

## mikrotik1 — NAT

| # | Chain | Action | Match | Comment |
|---|---|---|---|---|
| 0 | srcnat | masquerade | `out-interface-list=WAN` | (unnamed) |
| 1 | dstnat | dst-nat -> `192.168.20.60:443` | `protocol=tcp dst-port=443 in-interface-list=WAN` | Home Assistant - HTTPS |

Rule 1 pairs with `chain=forward`'s `internet2services` jump (# 35) and its sub-chain rule
(# 72) above — all three consistent. **No `dst-address=` on rule 1** — deliberately, since
2026-09-11: previously hardcoded to mikrotik1's then-current WAN DHCP lease, which broke
outright when a Swisscom box swap changed the whole WAN-side subnet (see `changelog.md`).
Matching on `in-interface-list=WAN` alone survives any future WAN IP change.

## mikrotik1 — address lists in use

| List | Members | Purpose |
|---|---|---|
| `mgmt` | mikrotik1/2/3/4, desktop (5 hosts) | full router-management access, all three devices |
| `ha-mikrotik-targets` | mikrotik2, mikrotik3 | scopes HA's MikroTik integration to switch management IPs only |
| `octoprint` | OctoPrint (wifi + wired) | named exception for both `iot`'s default internet deny and `users -> iot`'s default deny — consolidated from the former separate `iot-internet` list during the Phase 5 reorg |
| `bogons` | RFC 1918/3330 ranges, defconf | unchanged since round 1/2, not VLAN-related |
| `Syn_Flooder`, `Port_Scanner`, `spammers` | dynamic, populated at runtime | anti-abuse, unchanged since finding 7 |

`WAN` is an interface list (`/interface/list`), not an address list — holds `ether1`, created
in the Phase 5 reorg so a future edge-router swap only needs updating in one place.

Separately (not a firewall mechanism, but adjacent): `/ip/dns/static` now also holds one entry
per currently-bound DHCP lease with a reported hostname (`<hostname>.home.ledcom.fr`), added by
a `lease-script` on all three DHCP servers — see `changelog.md`'s DHCP-to-DNS entry. TTL
matches the lease time (5m), so the list churns constantly; not reproduced here.

## mikrotik1 — IPv6 firewall

**Finding 21, in progress:** `vlan-users` (phase 1), `vlan-services` (phase 2), and `vlan-iot`
(phase 3) all restructured to the same per-VLAN-pair dispatch shape the IPv4 firewall uses,
applied 2026-09-10. **Phase 3 is applied but not yet functionally verified** — OctoPrint, the
one thing worth testing, was offline; see `changelog.md`. None of the three VLANs exposes
router management (ssh/Winbox/API/www) over IPv6 — SLAAC gives no stable per-host address to
scope an IPv4-style `mgmt` list against, so "not exposed" is the deliberate equivalent rather
than a leaky approximation. Full design and reasoning in
[ipv6.md](ipv6.md#extending-to-every-vlan-finding-21).

| # | Chain | Action | Match | Comment |
|---|---|---|---|---|
| 0 | input | accept | `connection-state=established,related,untracked` | defconf |
| 1 | input | drop | `connection-state=invalid` | defconf |
| 2 | input | accept | `protocol=icmpv6` | defconf |
| 3 | input | accept | `protocol=udp src-address=fe80::/10 dst-port=546` | defconf: DHCPv6-Client PD |
| 4 | forward | accept | `connection-state=established,related,untracked` | defconf |
| 5 | forward | drop | `connection-state=invalid` | defconf |
| 6 | forward | drop | `src-address-list=bad_ipv6` | defconf |
| 7 | forward | drop | `dst-address-list=bad_ipv6` | defconf |
| 8 | forward | drop | `protocol=icmpv6 hop-limit=equal:1` | defconf: rfc4890 |
| 9 | forward | accept | `protocol=icmpv6` | defconf |
| — | input | drop | *(none — catch-all)* | drop everything else to router |
| — | forward | jump -> `users2internet` | `in-interface=vlan-users out-interface-list=WAN` | dispatch: users -> internet |
| — | forward | jump -> `services2internet` | `in-interface=vlan-services out-interface-list=WAN` | dispatch: services -> internet |
| — | forward | jump -> `services2users` | `in-interface=vlan-services out-interface=vlan-users` | dispatch: services -> users |
| — | forward | jump -> `iot2internet` | `in-interface=vlan-iot out-interface-list=WAN` | dispatch: iot -> internet |
| — | forward | drop | *(none — catch-all)* | drop inbound from WAN |
| — | `users2internet` | accept | `connection-state=new` | users2internet: internet |
| — | `services2internet` | accept | `protocol=tcp dst-port=80,443 connection-state=new` | services2internet: HTTP/HTTPS |
| — | `services2internet` | accept | `protocol=udp dst-port=53 src-address-list=pihole-v6 connection-state=new` | services2internet: Pi-hole's own upstream DNS |
| — | `services2internet` | accept | `protocol=tcp dst-port=53 src-address-list=pihole-v6 connection-state=new` | services2internet: Pi-hole's own upstream DNS (TCP) |
| — | `services2internet` | accept | `protocol=tcp dst-port=853 src-address-list=pihole-v6 connection-state=new` | services2internet: Pi-hole's own upstream DNS-over-TLS |
| — | `services2internet` | drop, logged | *(catch-all)* | services2internet: deny everything else |
| — | `services2users` | accept | `protocol=tcp dst-port=631 src-address-list=ha-v6 connection-state=new` | services2users: HA -> printer (CUPS) |
| — | `services2users` | accept | `protocol=tcp dst-port=8002 src-address-list=ha-v6 connection-state=new` | services2users: HA -> Samsung TV |
| — | `services2users` | drop, logged | *(catch-all)* | services2users: deny everything else |
| — | `iot2internet` | accept | `protocol=tcp dst-port=80,443 src-address-list=octoprint-v6 connection-state=new` | iot2internet: octoprint updates |
| — | `iot2internet` | drop, logged | *(catch-all)* | iot2internet: deny everything else |

Rule numbers aren't shown — RouterOS's `print` index is positional, not a stable ID (this table
follows the project's own convention of finding by comment, not number).

`services2users` is deliberately narrower than IPv4's version of the same policy: IPv4 also
scopes by the *destination's* own address (the printer, the TV specifically); this only scopes
by port, since pinning two more devices' IPv6 addresses for a path that already works over IPv4
wasn't judged worth it. `ha-v6` and `pihole-v6` are `/ipv6/firewall/address-list`s holding one
entry each — Home Assistant's and Pi-hole's IPv6 addresses, computed via EUI-64 from their
known MACs combined with `vlan-services`'s actual delegated prefix (**not** a DHCP-style
reservation; see [ipv6.md](ipv6.md#extending-to-every-vlan-finding-21) and
`changelog.md`'s Internet-Box replacement entry for the caveats this carries: it depends on
IPv6 privacy extensions staying off on each host, and broke once already when the delegated
prefix changed — recomputed both times, same method, current prefix). `pihole-v6`'s DNS/DoT
exceptions were added 2026-09-11 after the firewall log showed Pi-hole repeatedly (and
silently) failing to reach public IPv6 resolvers for its own upstream queries — mirrors its
existing IPv4 exception. `services2iot` doesn't exist — `vlan-iot`'s policy is deny-by-default
(below), so there's nothing for services to reach there yet.

`iot2internet` is deny-by-default with one named exception, mirroring IPv4's `octoprint`
address-list — `octoprint-v6` holds both of OctoPrint's known addresses (wifi + wired),
computed via EUI-64 the same way as `ha-v6`. No `iot2services`/`iot2users` chains exist —
nothing on `vlan-iot` needs IPv6 access to either today, so both fall through to the general
forward catch-all, same outcome as an explicit deny.

**`vlan-iot`'s rules are applied but not yet functionally verified** — OctoPrint, the one
device the exception matters for, was offline when this was applied. See `changelog.md`;
`scripts/ipv6-03b-iot-firewall.rsc` stays in place until confirmed.

New rules again briefly showed `I - INVALID` on `print` immediately after creation in every
phase — unlike their identically-shaped IPv4 counterparts — and cleared on their own with no
action taken; phases 1-2 were also confirmed functionally enforced from real clients (see
`changelog.md`). See `README.md`'s hard-won lessons for the caveat this adds to the existing
`I - INVALID` catalog.

## mikrotik2 (CRS125) and mikrotik3 (RB750Gr3) — `chain=input`

Identical shape on both switches (management-plane only — neither runs NAT, and both have
`disable-ipv6=yes`, so IPv6 doesn't apply):

| # | Action | Match | Comment |
|---|---|---|---|
| 0 | accept | `connection-state=established` | default configuration |
| 1 | accept | `connection-state=related` | default configuration |
| 2 | drop | `connection-state=invalid` | default configuration |
| 3 | accept | `connection-state=established,related` | established |
| 4 | drop | `connection-state=invalid` | drop invalid |
| 5 | accept | `protocol=icmp` | ICMP |
| 6 | accept | `src-address-list=mgmt` | mgmt hosts to device |
| 7 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=8728` | HA API access (post-renumber) |
| 8 | drop | *(none — catch-all)* | drop everything else |

Rules 0-2 are `chain=forward`, rules 3-8 are `chain=input`. The forward-chain rules are
defconf boilerplate and don't actually gate anything: both switches have
`use-ip-firewall=no` on their bridge (confirmed in both dumps), so bridged/VLAN-tagged traffic
bypasses the IP firewall's forward chain entirely — all real inter-VLAN policy lives on
mikrotik1. No `connection-state=new` inconsistency worth noting here either way.

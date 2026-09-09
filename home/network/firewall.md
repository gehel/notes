# Firewall rules — current live state

Generated 2026-09-08 from that day's [dumps/](dumps/) (post-Phase-4). This is the actual
ruleset, in the actual order it's evaluated in — not the design intent. For the intended
policy and the reasoning behind it, see [vlan.md](vlan.md)'s policy matrix; for open issues
found while writing this, see [config-review.md](config-review.md) findings 19-22, referenced
inline below as **[19]**-**[22]**.

**Stale as of 2026-09-09 — findings 19/20's dead rules were removed and IPv6 for
`vlan-services`/`vlan-iot` (finding 21) is being added.** Rule numbers and the IPv6 table below
no longer match live state. Regenerating once that work lands rather than twice in a row.

RouterOS evaluates each chain top to bottom and stops at the first match, so **position is
part of the rule** — a correct-looking rule in the wrong place is a bug. That's why this is a
table in rule order, not a summary.

## Quick reference: what can reach what

The steady-state policy, as actually implemented (not the aspirational version) —
`vlan-users` on mikrotik1's `bridge-main` is VLAN 10, `vlan-services` is VLAN 20, `vlan-iot`
is VLAN 30:

| From \ To | internet | users | services | iot | router mgmt |
|---|---|---|---|---|---|
| **users** | allow | — | `mgmt` full; DNS (53); HA web (443) for everyone else | `mgmt` full only | `mgmt` list only |
| **services** | allow (IPv4 only — **[21]**) | drop + log (`infra2users`) | — | HA: ESPHome/IotaWatt (6053, 80), Tuya local (6668) | `mgmt` list only |
| **iot** | DROP by default; named exception `iot-internet` (80/443, OctoPrint only) | drop + log (`users2iot`) | Pi-hole DNS (53), MQTT to HA (1883) | — | NTP (123) to gateway only |

A dead rule (`users -> services` MQTT, position 59) predates this table and does not change it
— see **[19]**: it's unreachable, sitting after the unconditional catch-all drop.

IPv6 has no equivalent rows for `services`/`iot` at all — see **[21]**. `vlan-iot` ends up with
no IPv6 anywhere by accident, which happens to match intent; `vlan-services` ends up with no
IPv6 internet access, which doesn't.

## mikrotik1 (RB2011UiAS, edge router) — `chain=input`

| # | Action | Match | Comment | Note |
|---|---|---|---|---|
| 1 | accept | `connection-state=established,related` | defconf: accept established,related | |
| 2 | add-to-list | `protocol=tcp tcp-flags=syn connection-limit=30,32 in-interface=ether1` -> `Syn_Flooder` | Add Syn Flood IP to the list | |
| 3 | drop | `src-address-list=Syn_Flooder in-interface=ether1` | Drop to syn flood list | |
| 4 | add-to-list | `protocol=tcp psd=21,3s,3,1 in-interface=ether1` -> `Port_Scanner` | Port Scanner Detect | |
| 5 | drop | `src-address-list=Port_Scanner in-interface=ether1` | Drop to port scan list | |
| 6 | drop | `in-interface=ether1` | defconf: drop all from WAN | |
| 7 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp input flow | |
| 8 | accept | `protocol=udp in-interface=bridge-main dst-port=67` | DHCP server | dead — **[20]**, no traffic arrives untagged on `bridge-main` any more |
| 9 | accept | `protocol=tcp src-address=192.168.20.60 dst-port=8728` | HA API access (post-renumber) | no `connection-state=new` — **[22]** (harmless, see rule 1) |
| 10 | accept | `src-address-list=mgmt` | mgmt hosts to router | no `connection-state=new` — **[22]** |
| 11 | *(disabled)* accept | `src-address-list=home` | Full access to home address list | dead twice over — **[20]**; the `home` list no longer exists |
| 12 | accept | `protocol=udp port=53` | Accept DNS - UDP | no `connection-state=new` — **[22]** |
| 13 | accept | `protocol=tcp port=53` | Accept DNS - TCP | no `connection-state=new` — **[22]** |
| 14 | accept | `protocol=udp in-interface=vlan-users dst-port=67` | DHCP server (vlan-users) | no `connection-state=new` — **[22]** |
| 15 | accept | `connection-state=new protocol=udp in-interface=vlan-iot dst-port=123` | iot: NTP from gateway | only input rule with explicit `connection-state=new` |
| 16 | drop | *(none — catch-all)* | Drop anything else! | |

## mikrotik1 — `chain=forward`

| # | Action | Match | Comment | Note |
|---|---|---|---|---|
| 17 | fasttrack-connection | `connection-state=established,related` | defconf: fasttrack | |
| 18 | accept | `connection-state=established,related` | defconf: accept established,related | |
| 19 | accept | `protocol=udp src-address=192.168.20.40 dst-port=53` | Accept DNS requests from Pi-hole | |
| 20 | add-to-list | `protocol=tcp tcp-flags=syn connection-nat-state=dstnat connection-limit=30,32 in-interface=ether1` -> `Syn_Flooder` | Syn flood detect - any forwarded port | |
| 21 | drop | `src-address-list=Syn_Flooder in-interface=ether1` | Drop syn flooders - inbound | |
| 22 | accept | `connection-state=new in-interface=bridge-main` | Home can connect everywhere | dead — **[20]**, superseded by rule 29 |
| 23 | accept | `connection-state=new connection-nat-state=dstnat protocol=tcp dst-address=192.168.20.60 dst-port=443` | Home Assistant - HTTPS | pairs with the dst-nat below |
| 24 | jump -> `ICMP` | `protocol=icmp` | Jump for icmp forward flow | |
| 25 | drop | `dst-address-list=bogons` | Drop to bogon list | |
| 26 | add-to-list | `protocol=tcp connection-limit=30,32 dst-port=25,587 limit=30/1m,0` -> `spammers` | Add Spammers to the list for 3 hours | |
| 27 | drop | `protocol=tcp src-address-list=spammers dst-port=25,587` | Avoid spammers action | |
| 28 | drop | `connection-state=invalid` | defconf: drop invalid | |
| 29 | accept | `connection-state=new in-interface=vlan-users` | Home can connect everywhere (vlan-users) | `users -> internet`, live version of rule 22 |
| 30 | accept | `connection-state=new in-interface=vlan-services out-interface=ether1` | services: internet | `services -> internet` (IPv4 only — **[21]**) |
| 31 | accept | `connection-state=new protocol=tcp src-address=192.168.20.60 dst-address-list=ha-mikrotik-targets in-interface=vlan-services out-interface=vlan-users dst-port=8728` | HA MikroTik integration: services -> users API | scoped to mikrotik2/mikrotik3 only, via `ha-mikrotik-targets` |
| 32 | drop | `protocol=udp src-address=192.168.30.63 dst-address=192.168.20.40 in-interface=vlan-iot out-interface=vlan-services port=53` | ceiling fan: drop DNS (udp) | placed ahead of the general iot DNS allow (34) |
| 33 | drop | `protocol=tcp src-address=192.168.30.63 dst-address=192.168.20.40 in-interface=vlan-iot out-interface=vlan-services port=53` | ceiling fan: drop DNS (tcp) | placed ahead of the general iot DNS allow (35) |
| 34 | accept | `connection-state=new protocol=udp dst-address=192.168.20.40 in-interface=vlan-iot port=53` | iot: DNS to pi-hole (udp) | |
| 35 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.40 in-interface=vlan-iot port=53` | iot: DNS to pi-hole (tcp) | |
| 36 | *(disabled)* accept | `connection-state=new protocol=tcp src-address=192.168.30.63 out-interface=ether1 dst-port=80,443` | ceiling fan: TEMP internet for setup | debris — **[20]** |
| 37 | *(disabled)* accept | `connection-state=new in-interface=vlan-iot out-interface=ether1` | iot: TEMP internet for phone/device pairing, DISABLE AFTER | debris — **[20]** |
| 38 | accept | `connection-state=new protocol=tcp in-interface=vlan-services out-interface=vlan-iot dst-port=6668` | HA -> Tuya local (fan) | |
| 39 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.60 in-interface=vlan-iot out-interface=vlan-services dst-port=1883` | iot: MQTT to HA | the permanent path — makes rule 59 redundant |
| 40 | accept | `connection-state=new protocol=tcp src-address-list=iot-internet in-interface=vlan-iot out-interface=ether1 dst-port=80,443` | iot exception: octoprint updates | only `iot-internet` list members (OctoPrint x2) |
| 41 | accept | `connection-state=new protocol=tcp in-interface=vlan-services out-interface=vlan-iot dst-port=80` | HA -> Tasmota/IotaWatt | |
| 42 | drop, logged | `in-interface=vlan-iot` | iot: deny everything else | log-prefix `iot-drop` — Phase 5 evidence |
| 43 | accept | `connection-state=new protocol=tcp in-interface=vlan-services out-interface=vlan-iot dst-port=6053` | HA -> ESPHome (IotaWatt) | |
| 44 | drop, logged | `in-interface=vlan-services out-interface=vlan-users` | services: no users | log-prefix `infra2users` — Phase 5 evidence |
| 45 | accept | `connection-state=new src-address-list=mgmt in-interface=vlan-users out-interface=vlan-services` | mgmt hosts: full | |
| 46 | accept | `connection-state=new protocol=udp dst-address=192.168.20.40 in-interface=vlan-users out-interface=vlan-services port=53` | users: DNS | |
| 47 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.60 in-interface=vlan-users out-interface=vlan-services dst-port=443` | users: HA web | |
| 48 | drop, logged | `in-interface=vlan-users out-interface=vlan-services` | users2services | log-prefix `users2services` — Phase 5 evidence |
| 49 | accept | `connection-state=new src-address-list=mgmt in-interface=vlan-users out-interface=vlan-iot` | mgmt hosts: iot | |
| 50 | drop, logged | `in-interface=vlan-users out-interface=vlan-iot` | users2iot | log-prefix `users2iot` — Phase 5 evidence; doesn't catch rule 59's hole, see **[19]** |
| 51 | drop | *(none — catch-all)* | Drop all other forward traffic | `log-prefix="dropped"` but `log=no`, so the prefix does nothing |
| 59 | accept | `connection-state=new protocol=tcp dst-address=192.168.20.60 in-interface=vlan-users out-interface=vlan-services dst-port=1883` | TEMP: iot mqtt via users, remove at Phase 4 | **dead — [19]**, unreachable (after rule 51's unconditional drop); remove |

Position 59 is real — RouterOS numbers `/ip/firewall/filter/print` by actual global evaluation
order across every chain, and gaps like 52-58 belong to `chain=ICMP`/`chain=output` (interleaved
in the same list but irrelevant to `chain=forward` evaluation). Since rule 51 is an unconditional
`chain=forward` drop, it terminates every forward packet before rule 59 is ever reached. See
**[19]** for why this rule likely never worked even during Phase 3, not just now.

## mikrotik1 — `chain=ICMP` (jump target)

| # | Action | Match | Comment |
|---|---|---|---|
| 52 | accept | `protocol=icmp icmp-options=8:0 limit=10,50:packet` | Echo request - Avoiding Ping Flood |
| 53 | accept | `protocol=icmp icmp-options=0:0` | Echo reply |
| 54 | accept | `protocol=icmp icmp-options=11:0` | Time Exceeded |
| 55 | accept | `protocol=icmp icmp-options=3:0-1` | Destination unreachable |
| 56 | accept | `protocol=icmp icmp-options=3:4` | PMTUD |
| 57 | drop | `protocol=icmp` | Drop to the other ICMPs |
| 58 | jump (from `chain=output`) | `protocol=icmp` | Jump for icmp output |

## mikrotik1 — NAT

| # | Chain | Action | Match | Comment |
|---|---|---|---|---|
| 0 | srcnat | masquerade | `out-interface=ether1` | (unnamed) |
| 1 | dstnat | dst-nat -> `192.168.20.60:443` | `protocol=tcp dst-address=10.1.1.101 dst-port=443 in-interface=ether1` | Home Assistant - HTTPS |

Rule 1 pairs with `chain=forward` rule 23 above — both halves present and consistent.

## mikrotik1 — address lists in use

| List | Members | Purpose |
|---|---|---|
| `mgmt` | mikrotik1/2/3/4, desktop (5 hosts) | full router-management access, all three devices |
| `ha-mikrotik-targets` | mikrotik2, mikrotik3 | scopes HA's MikroTik integration to switch management IPs only |
| `iot-internet` | OctoPrint (wifi + wired) | the named exception to `iot`'s default internet deny |
| `bogons` | RFC 1918/3330 ranges, defconf | unchanged since round 1/2, not VLAN-related |
| `home` | *(none — list doesn't exist)* | dead, referenced only by the disabled rule in **[20]** |
| `Syn_Flooder`, `Port_Scanner`, `spammers` | dynamic, populated at runtime | anti-abuse, unchanged since finding 7 |

## mikrotik1 — IPv6 firewall

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
| 10 | forward | accept | `in-interface=bridge-main` | LAN outbound — dead, **[20]**/**[21]** |
| 11 | input | accept | `in-interface=bridge-main` | LAN to router — dead, **[20]**/**[21]** |
| 12 | input | accept | `in-interface=vlan-users` | LAN to router (vlan-users) |
| 13 | input | drop | *(none — catch-all)* | drop everything else to router |
| 14 | forward | accept | `in-interface=vlan-users` | LAN outbound (vlan-users) |
| 15 | forward | drop | *(none — catch-all)* | drop inbound from WAN |

**No equivalent rules exist for `vlan-services` or `vlan-iot` on either chain — see [21].**
Both VLANs fall straight through to rules 13/15.

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

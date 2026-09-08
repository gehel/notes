# IPv6 on the MikroTik home network

Configured 2026-09-03. Front router is a MikroTik running RouterOS 7.23.3 (now 7.24.2).

**Moved from `bridge-main` to `vlan-users` on 2026-09-07** — see
[Migrated onto `vlan-users`](#migrated-onto-vlan-users) below.

## Current state

IPv6 works for clients on `vlan-users` (VLAN 10 on `bridge-main`), but **via NAT66**, not
native routing. This is a deliberate workaround, not an oversight — see
[Why NAT66](#why-nat66) below.

| | |
|---|---|
| Upstream | Swisscom, native IPv6 via DHCPv6 (no PPPoE, no 6rd) |
| Topology | Swisscom Internet-Box (`10.1.1.1`) → MikroTik `ether1` → `bridge-main` → `vlan-users` (VLAN 10) → mikrotik2 + mikrotik3 (pure L2 bridges) → clients |
| Delegated prefix | `/62` from the Internet-Box via DHCPv6-PD, i.e. 4 × `/64` |
| LAN prefix | one `/64` from that pool on `vlan-users`, router at `::1` |
| Client addressing | SLAAC from RAs sent by the MikroTik |
| `bridge-fon` | removed entirely, along with the FON network — see `changelog.md`'s VLAN segmentation entry |
| DNS | clients should use `192.168.10.40` (Pi-hole) over IPv4 — **was leaking the ISP's own resolver via RDNSS until 2026-09-07, see below** |

Prefix values are **not stable**. Swisscom's delegation to the Internet-Box can change, and
the box's delegation to us changes with it. Every address below is derived from the pool at
runtime — nothing is hardcoded, and nothing should be. The values quoted in this document
are from 2026-09-03 and are illustrative only.

## Why NAT66

The Internet-Box delegates a prefix over DHCPv6-PD and then does not deliver return traffic
to it. This is a documented limitation of the box: it has no static IPv6 route capability and
its cascaded-router support is incomplete.

The discriminating test, run on the MikroTik — this is the fastest way to re-confirm the
diagnosis if IPv6 breaks again:

```
/ping 2606:4700:4700::1111 count=3
# → works, sourced from the WAN SLAAC address inside the box's own /64

/ping 2606:4700:4700::1111 src-address=<LAN address from /ipv6/address/print> count=3
# → 100% loss, because the box does not route the prefix it delegated to us
```

Everything on the MikroTik side is correct: PD binds, the LAN is addressed from the pool,
RAs reach clients across both L2 bridges, and clients install a default route. Only the
return path is missing. NAT66 rewrites the source to the WAN address, which *is* routed,
so replies come back and conntrack un-NATs them.

Consequences to be aware of:

- No inbound connections to LAN hosts. No end-to-end addressing.
- Clients hold globally-scoped addresses that are not globally reachable.
- `curl -6 https://ifconfig.co` reports the router's WAN address, not the client's.
  That is the NAT working, not a fault.

## Working configuration

**Current as of 2026-09-07.** Interface names: `ether1` = WAN toward the Internet-Box,
`vlan-users` = LAN (VLAN 10, layered on `bridge-main` — see
[Migrated onto `vlan-users`](#migrated-onto-vlan-users)). The commands below are written for
the current, post-migration state; the original 2026-09-03 setup used `bridge-main` directly.

```
# IPv6 is disabled by default on this box — this is the master switch.
# There is no separate ipv6 package in RouterOS 7.
/ipv6/settings/set disable-ipv6=no

# A forwarding router ignores RAs by default. The WAN side needs them
# for its own address and default route.
/ipv6/settings/set accept-router-advertisements=yes

# Request a prefix from the Internet-Box.
# pool-prefix-length=64 is the slice size handed out from the pool, so a
# delegated /62 yields 4 usable /64s.
/ipv6/dhcp-client
add interface=ether1 request=prefix pool-name=swisscom-pd pool-prefix-length=64 \
    add-default-route=yes use-peer-dns=yes comment="PD from Internet-Box"

# Address the LAN from the pool. Use address=::1 — without it you get the
# all-zeros subnet-router anycast address, which is a poor router address.
/ipv6/address/add from-pool=swisscom-pd interface=vlan-users advertise=yes address=::1

# Send RAs on the LAN only. The * default ND entry covers interface=all,
# which would also advertise toward the Internet-Box; point it at the LAN
# instead of adding a second entry (the default entry cannot be deleted).
/ipv6/nd/set [find default=yes] interface=vlan-users advertise-dns=yes \
    managed-address-configuration=no other-configuration=no ra-lifetime=30m

# The workaround. Remove this line if the upstream is ever fixed.
/ipv6/firewall/nat/add chain=srcnat out-interface=ether1 action=masquerade \
    comment="workaround: Internet-Box will not route delegated prefix"
```

### Firewall

The RouterOS defconf IPv6 rules are the *permit* half of a ruleset. The deny half is absent
on a fresh install: both chains default to accept. IPv6 has no NAT to hide behind, so without
these three rules every LAN host is reachable from the internet.

```
/ipv6/firewall/filter
add chain=forward action=accept in-interface=vlan-users comment="LAN outbound"
add chain=input action=accept in-interface=vlan-users comment="LAN to router"
add chain=input action=drop comment="drop everything else to router"
add chain=forward action=drop comment="drop inbound from WAN"
```

The original `bridge-main`-referencing pair of rules (`LAN outbound`, `LAN to router`) are
still present and harmless — they simply never match anything now that LAN traffic arrives
via `vlan-users` instead. Not yet cleaned up.

These must sit **after** the defconf accepts. Order matters: the DHCPv6 client reply rule
(UDP 546 from `fe80::/10`) and the ICMPv6 accepts have to be matched before the drops, or
PD and neighbour discovery break.

Do not block ICMPv6. IPv6 has no in-path fragmentation, so filtering it breaks path-MTU
discovery — which shows up as large transfers hanging rather than failing cleanly.

Adding an input accept for another trusted interface must go before the input drop, or that
segment loses IPv6 access to the router. IPv4 management is unaffected either way, so this
cannot lock you out entirely.

### Why the LAN keeps a global prefix rather than ULA

ULA is the semantically honest choice behind NAT, but it would defeat the purpose here. Under
RFC 6724's default policy table, `fc00::/7` has precedence 3 while IPv4 has 35 — dual-stack
clients would prefer IPv4 for almost every destination and the IPv6 path would go unused.
Clients holding a global address prefer it over IPv4, which is what we want.

If stable internal addressing is needed for firewall rules or local DNS, add a ULA
*alongside* the global prefix, never instead of it.

## Migrated onto `vlan-users`

Done 2026-09-07, discovered as the fix for a real, if minor, outage. The VLAN segmentation
work in [vlan.md](vlan.md) moved the router's *IPv4* address and DHCP server off `bridge-main`
onto a `vlan-users` VLAN 10 sub-interface, but IPv6 was out of scope for that document and got
left behind on `bridge-main` — nobody planned to skip it, it just wasn't tracked anywhere.

The gap stayed invisible for a day because, before `vlan-filtering=yes` and the CAPsMAN
wireless-tagging fix landed, wireless clients were in enough of a broken, VLAN-mismatched
state that they could still incidentally reach `bridge-main`'s untagged RA. Once wireless was
*correctly* tagged into VLAN 10 (its own fix, see `vlan.md`), it could reach `vlan-users` (IPv4
DHCP, now working) but could no longer reach `bridge-main`'s RA at all — leaving Home
Assistant's OpenThread Border Router as the *only* IPv6 router visible to wireless clients.
That's a Thread/Matter border router doing its normal job — advertising the Thread mesh's
prefix (and a companion on-link ULA) onto the LAN via RA — not a bug on Home Assistant's side.
It just happened to be reachable when the router's real RA wasn't, so clients preferred or
outright adopted its non-routable ULA prefix instead of the real global one. Diagnosed by:
desktop WiFi held a valid IPv6 address but `ping6` to a real host failed with "Network is
unreachable" — the signature of holding only a ULA with no route to the internet, and the two
prefixes traced to `d8:3a:dd:31:e0:59` (`192.168.1.60`, Home Assistant) via `wpan0`'s own
address matching one of them exactly and `ip -6 neigh show` flagging that MAC `router`.

The pre-existing "possible rogue RA source" note in `config-review.md` — the desktop had
briefly held this same ULA on its *wired* NIC days earlier — turned out to be the same root
cause, present since before this migration ever started; the VLAN work made it fully visible
on wireless rather than causing it.

Fixed the same way as the IPv4 migration: address, RA (`/ipv6/nd`), and the two IPv6 firewall
rules referencing `bridge-main` all moved to `vlan-users`. Verified: desktop's WiFi picked up
the real `2a02:1210:680f:c40c::/64` prefix as primary, the old ULA aged out on its own as
`deprecated`/`preferred_lft 0` (the same graceful-expiry behavior already documented under
"Stale prefix on clients after renumbering" below), and `ping6` to a real host succeeded.

## Resolved: RDNSS was leaking the ISP's own DNS server, bypassing Pi-hole

**Was documented below as a cosmetic non-issue; it wasn't.** Found live 2026-09-07 while
scoping the Home Assistant VLAN migration (see `vlan.md`'s Status section and
`config-review.md` finding 8): a dual-stack desktop's `dig` for a name with both a public and
a Pi-hole-local answer got the public one, because its IPv6 resolver was the ISP's own
recursive DNS server, not Pi-hole.

**First diagnosis (wrong, corrected below).** Initially attributed to `/ipv6/dhcp-client`'s
`use-peer-dns=yes` on `ether1` populating `/ip/dns`'s `dynamic-servers` from the DHCPv6-PD
lease. Fixed that (`use-peer-dns=no`, `scripts/fix-ipv6-rdnss-dns.rsc`), then forced a release
and rebind to clear the stale entry immediately rather than waiting out the lease
(`scripts/fix-ipv6-rdnss-dns-cleanup.rsc`, which also caught and fixed the same pattern on the
**IPv4** DHCP client — it was independently pulling the Internet-Box's IPv4 address, `10.1.1.1`,
into the same list). The IPv4 fix worked. **The IPv6 entry survived a full DHCPv6-PD
release/rebind with `use-peer-dns=no` already in effect** — proof the DHCPv6 client was never
the actual source for the IPv6 side.

**Actual cause.** `/ipv6/settings` has `accept-router-advertisements=yes` on `ether1`, needed
so this router can learn its own WAN default route from the Internet-Box (a forwarding router
ignores RAs by default, so this was already deliberately turned on — see "Working
configuration" above). As a side effect, RouterOS also accepts the RDNSS option carried in the
Internet-Box's own RA on that link, straight into `/ip/dns`'s `dynamic-servers` — with no
DHCPv6 or `use-peer-dns` involved at all. Turning off RA acceptance would break the WAN default
route, so that path can't be closed at the source.

`/ipv6/nd` has `advertise-dns=yes` with no explicit `dns=` override, so it re-advertises the
router's *own* DNS list (including that dynamic entry) via RDNSS on `vlan-users` — and since
the static entry (`192.168.10.40`, Pi-hole) is IPv4-only and cannot go in an IPv6 RDNSS option,
**the ISP's dynamic entry was the only thing that ever got advertised.** Any dual-stack client
preferring the RA-provided IPv6 resolver bypassed Pi-hole for every query, not just the one
hostname that surfaced it.

**The `automatic dns option advertising is not started, re-apply dns config` message on the ND
entry was itself misleading** — read as "RDNSS isn't being sent" when it moved to `vlan-users`
on 2026-09-07, but the mechanism above was live regardless of that cosmetic warning.

**Fixed** via `scripts/fix-ipv6-rdnss-dns-v2.rsc`: `advertise-dns=no` on the `/ipv6/nd` entry,
stopping `vlan-users` from advertising *any* DNS server via RA — the right scope for the fix,
since it controls what reaches LAN clients directly rather than trying to prevent the router
from learning the ISP's resolver upstream (which it needs to do anyway, for the default
route). `use-peer-dns=no` on both `ether1` DHCP clients stays in place too — harmless, and it
stops the router from needlessly trusting the ISP's resolver for its own outbound lookups
either. Clients keep resolving via Pi-hole over the IPv4 DHCP-assigned server, which is what
this document already claimed was happening. This only matters again if IPv6-only clients ever
appear, since they would have no DNS server at all once this leak is closed — at which point
give Pi-hole an IPv6 address on `vlan-users` and set `/ipv6/nd`'s `dns=` explicitly to it,
rather than re-enabling `advertise-dns` against the router's own resolver list.

**Stale prefix on clients after renumbering.** An earlier attempt had hardcoded
`2a02:1205:34dc:d053::1/64` on `bridge-main` with `advertise=yes`. When Swisscom's prefix
changed, clients kept advertising-derived addresses in a prefix that no longer routed. Clients
show these as `deprecated` with `preferred_lft 0` and stop using them for new connections;
they age out on their own, or `ip -6 addr del ... dev <iface>` clears them immediately. This
is the failure mode `from-pool=` exists to prevent.

**`ipv6-fasttrack-active: no`.** No IPv6 fasttrack rule, so all v6 traffic takes the full
firewall path. Fine at this line rate; only worth adding if throughput becomes a concern.

**The two downstream MikroTiks need no IPv6 configuration.** Both are pure L2 bridges, and
bridging forwards IPv6 frames regardless of whether the router's own IPv6 stack is enabled.
Verified clean on 2026-09-03: `igmp-snooping=no`, `use-ip-firewall=no`, no bridge filters,
`ra-guard=no`.

If IPv6 ever breaks *only* for clients behind them, check `igmp-snooping` first. In RouterOS 7
it covers MLD as well as IGMP, and with no MLD querier on the segment it can filter the
solicited-node multicast groups that neighbour discovery depends on. The failure mode is
deceptive: clients get a valid address from the RA, then cannot resolve the router's
link-local to a MAC, so everything times out and it looks like a routing or firewall problem.

## Verifying it works

On the MikroTik:

```
/ipv6/dhcp-client/print detail    # status=bound AND a non-empty prefix
/ipv6/pool/print
/ipv6/address/print               # LAN address present, FROM-POOL set, advertise=yes
/ipv6/route/print                 # active default route via the box's link-local
/ipv6/firewall/filter/print stats where comment~"LAN"
```

On a client:

```
ip -6 addr show scope global      # a global address in the current delegated prefix
ip -6 route show default          # via the MikroTik's bridge-main link-local
ping -6 -c 3 2606:4700:4700::1111
ping -6 -c 3 ipv6.google.com      # if this fails but the above works, it is DNS
ping -6 -c 3 -M do -s 1452 ipv6.google.com   # 1500-byte frame, DF set — checks path MTU
```

`status=searching` on the DHCPv6 client that never settles means the box is not answering
DHCPv6 at all. `bound` with an empty prefix means it answers but will not delegate.

## Migration path: MikroTik at the edge

The proper fix, and the only one giving native end-to-end IPv6 and the full `/56` to subnet
across both bridges. Swisscom supports third-party routers: DHCP on the WAN, no PPPoE,
VLAN 10 on the handoff. It also removes the IPv4 double-NAT as a side effect.

Everything above carries over. The migration is:

1. Delete the masquerade rule.
2. Point the DHCPv6 client at the new WAN interface.
3. Leave the `from-pool=` address and the ND entry untouched — they keep working.
4. Optionally add `bridge-fon` with a second `/64` from the pool.

The thing to plan around is Swisscom TV, which depends on the box and on ISP multicast.

## Resolved: the open resolver question

`/ip/dns allow-remote-requests=yes` predates this work, so during configuration it was
unclear whether the router was an open resolver. It is not. Confirmed 2026-09-03 from the
full config export: `drop all from WAN in-interface=ether1` is rule 1 of the IPv4 input
chain, ahead of the port 53 accepts at rules 11-12. The IPv6 side is covered by its own
input drop.

See [config-review.md](config-review.md) for the full configuration review. It does find a
related issue: every host on `192.168.1.0/24` has full access to the router's management
plane, IoT devices included.

## References

- [Swisscom community — Statische IPv6 Route mit Internet Box 4](https://community.swisscom.ch/t5/Router-Hardware/Statische-IPv6-Route-mit-Internet-Box-4/td-p/721529)
- [Swisscom community — Prefix Delegation](https://community.swisscom.ch/d/567232-prefix-delegation)
- [Swisscom community — IPv6 PD auf Fritzbox hinter InternetBox](https://community.swisscom.ch/t5/Archiv-Internet/IPv6-PD-auf-Fritzbox-hinter-InternetBox-Standard/td-p/490722)
- [Swiss IPv6 Council — Residential IPv6 at Swisscom (PDF)](https://www.swissipv6council.ch/sites/default/files/images/ipv6-residential-swisscom.pdf)
- [iway KB — IPv6 on VDSL and Swisscom fibre with DHCP](https://wiki.iway.ch/kb/wiki/Internet_Access/Internet_Access_Allgemein/IPv6/IPv6_auf_VDSL_und_Swisscom_Fiber_Anschl%C3%BCssen_mit_DHCP)
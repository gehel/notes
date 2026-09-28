# WireGuard road-warrior VPN

**Status: applied and verified end-to-end, 2026-09-22.** Working road-warrior tunnel for
Guillaume's Android phone (`MrG Galaxy S24`). Full history and verifying evidence in
[changelog.md](changelog.md); `scripts/wireguard-road-warrior.rsc` has been deleted per this
repo's one-shot-script convention.

## Decisions

Recorded so they are not re-litigated:

| Decision | Choice |
|---|---|
| Tunnel scope | **Full tunnel** — all phone traffic, including general internet browsing, routes through home. Deliberate: benefits from Pi-hole ad-blocking and makes the phone appear to originate from the home IP on untrusted networks. |
| LAN-side access | **Same as `vlan-users`** — the phone gets exactly the access a `vlan-users` host has, nothing more, nothing less. Reuses the existing `users2internet`/`users2services`/`users2iot` jump chains from [firewall.md](firewall.md) via new `in-interface=wireguard1` dispatch rules in `chain=forward` — no separate policy to write or maintain. **Extended 2026-09-28** with a fourth dispatch, `wireguard2users` (see [firewall.md](firewall.md#mikrotik1--jump-chains-phase-5-reorg)), needed once the phone was added to the `mgmt` address-list — reaching mikrotik2/mikrotik3's own management requires an actual forwarded path to `vlan-users`, which the original three dispatches never provided (mikrotik1's own management already worked over the tunnel via `chain=input`, interface-blind). |
| Endpoint | **`home.ledcom.fr`** (Guillaume's call, 2026-09-22). Originally designed against mikrotik1's MikroTik Cloud DDNS hostname instead, specifically to route around `config-review.md` finding 25 (nothing kept `home.ledcom.fr` current, so it had gone silently stale twice) — but `/ip/cloud`'s `dns-name` came back **empty** when the script ran, so that hostname isn't actually usable as-is anyway. Finding 25 is now understood to be fixed by the Home Assistant Let's Encrypt add-on's Gandi DDNS update (a previously-expired API key, renewed 2026-09-22) — see `config-review.md` finding 25 and `changelog.md`'s 2026-09-11 entry, which will need a correction once that mechanism is fully confirmed and documented. |
| IPv6 | **Not tunneled yet** — see Known gap below. |

## Design

| Item | Value |
|---|---|
| Interface | `wireguard1` on mikrotik1 |
| Listen port | UDP 51820 (WireGuard default — left as-is; it doesn't respond to unauthenticated probes either way, so port obscurity buys little. Easy to bump later.) |
| Tunnel subnet | `192.168.50.0/24` — not a VLAN, no bridge/tag; a standalone L3 interface like the router's other addresses. Free: `vlan.md` only uses the `.10`/`.20`/`.30` third octet. |
| Router tunnel address | `192.168.50.1/24` |
| Phone tunnel address | `192.168.50.2/32` |
| Persistent keepalive | 25s (phone is usually behind carrier-grade NAT) |
| NAT | **None needed.** The existing `chain=srcnat action=masquerade out-interface-list=WAN` rule (`firewall.md`'s NAT table, rule 0) has no source restriction, so `wireguard1`-sourced traffic already gets masqueraded on its way out. |
| `chain=input` | One new accept, `protocol=udp dst-port=51820 in-interface-list=WAN connection-state=new`, placed **before** rule 6 (`defconf: drop all from WAN`) — anything after that rule never sees WAN-sourced packets at all. |
| `chain=forward` dispatch | Three new jump rules, `in-interface=wireguard1` -> the existing `users2internet`/`users2services`/`users2iot` targets, placed before rule 36 (`Drop all other forward traffic`) |

## Known gap: IPv6

`AllowedIPs` on the phone is IPv4-only (`0.0.0.0/0`). The phone's own IPv6 internet traffic
will **not** route over the tunnel — it goes out directly over whatever network the phone is
on, bypassing both Pi-hole and the home-IP-masking intent for anything reached over IPv6.
Two ways to close this later, not scoped yet:
- Disable IPv6 on the phone while the VPN is active (simplest, phone-side only).
- Extend `AllowedIPs` to `::/0` and build the matching IPv6 side: a delegated `/64` for the
  tunnel, NAT66, and a `wireguard1`-sourced dispatch into the IPv6 jump chains in
  [firewall.md](firewall.md#mikrotik1--ipv6-firewall). Meaningfully more work than the IPv4
  side — the IPv6 firewall doesn't have `services2iot`/full parity with IPv4 yet either.

## Phone's tunnel config (for reference — e.g. re-adding the tunnel after a phone reset)

| Field | Value |
|---|---|
| Address | `192.168.50.2/32` |
| DNS | `192.168.20.40` |
| Peer public key | `QReTsWFSjYwkQ7Tm5l6KekxmA6sfvl+P1V0J67+NTXI=` (mikrotik1's) |
| Endpoint | `home.ledcom.fr:51820` |
| Allowed IPs | `0.0.0.0/0` |
| Persistent keepalive | `25` |

Full procedure and verification evidence: [changelog.md](changelog.md)'s 2026-09-22 entry.

**Added to `mgmt` 2026-09-28** (`192.168.50.2`, this same tunnel address) — the phone now has
full router-management access on all three reachable devices, same as the desktop and gimli.
Needed a new `wireguard2users` forward-chain dispatch (see [firewall.md](firewall.md)) and
widening the `admin` user account's own `address=` restriction (a separate gate from the
firewall — see `README.md`'s hard-won lessons) to include `192.168.50.0/24`. Full account and
verification in [changelog.md](changelog.md)'s 2026-09-28 entry.

## Open / not yet decided

- A pre-shared key (PSK) per peer, layered on top of the public-key exchange, is a documented
  WireGuard hardening option — not added here, to keep the first pass simple. Would need a
  second secret exchanged out-of-band (router `/interface wireguard generate-key` or `wg
  genpsk` from any WireGuard install) and entered on both sides.
- IPv6, per the gap above.
- mikrotik1 (RB2011UiAS) has no hardware crypto acceleration for WireGuard, and
  `performance.md` already shows this router working harder than ideal on plain firewalling.
  Full-tunnel means *all* the phone's internet traffic now also pays a software-crypto cost on
  this CPU. Not expected to be a problem at one phone's worth of traffic, but worth checking
  `/system resource/print` CPU load with the tunnel active under real use, and revisiting if
  the RB5009 edge migration (`config-review.md`) happens for other reasons anyway.

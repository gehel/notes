files# Changelog — closed findings

Closed and verified findings for every MikroTik on the network, moved here 2026-09-05 so the
review documents hold only what is still open.

Live review document: [config-review.md](config-review.md), which covers every device and
holds only what is still open.

Nothing is recorded here on the strength of a change having been made. Every entry carries
the device output that verified it, and where a negative test exists — proving a restriction
actually blocks rather than merely being configured — that test is recorded too. Finding
numbers are stable and are never reused.

## Main router — mikrotik1 (RB2011UiAS-2HnD)

### Round 1 (2026-09-03)

- **Telnet and FTP disabled.** Both show `X` in `/ip service`.
- **RouterOS upgraded** 7.23.3 → 7.24.2, now current.
- **WPA1 removed** from the CAPsMAN config — `security.authentication-types=wpa2-psk`.
- **SNMP community narrowed** to `192.168.1.0/24`. SNMP itself remains off.
- **IPv4 LAN address moved** from `ether2-master` to `bridge-main`.
- **`admin` bound to the LAN** — `address=192.168.1.0/24`.
- **Broken `/ipv6 dhcp-server dhcp1`** (referencing a nonexistent `delegation` pool) removed.
- **IPv6 IPsec, IKE, and HIP accepts removed** from both chains.

Round 1 finding 18 (`udp-timeout=10s`) was withdrawn as a false positive: it is the
RouterOS default and governs only unreplied UDP flows. Not re-raised.

### Round 2 (2026-09-04 onward)

**2026-09-05 — `api-ssl` listening without a certificate (was the last of finding 3, high).**
Enabled on 8729 with `certificate=none`: listening, unable to complete a handshake, unused.
The same defect was cleared on both switches under S5 a day earlier; the main router was
missed.

Verified: `/ip/service/print where name="api-ssl"` shows the service flagged `X`.

**Finding 3 is now closed in full.** Both halves — the full-admin credential and the
certificate-less TLS listener — are done. What remains is not a finding but a parked
decision: whether Let's Encrypt can be made to work without an external host. That is
recorded under "The TLS question" in [config-review.md](config-review.md), along with the
condition that would unblock it.

**2026-09-05 — Home Assistant moved off `admin` (was the open half of finding 3, high).**
HA authenticated as `admin` in group `full` — effectively root on the router — over the
plaintext API on 8728.

Fixed by creating `homeassistant` in a purpose-built `ha` group
(`policy=read,test,api`, everything else negated) bound to `address=192.168.1.60/32`, on all
three devices, and repointing the Home Assistant MikroTik integration at it.

Verified by the router's own account log rather than by configuration, which is the only
thing that shows which credential is actually in use:

```
2026-09-05 16:44:45  user homeassistant logged in from 192.168.1.60 via api
2026-09-05 17:03:01  user homeassistant logged in from 192.168.1.60 via api
```

Two successful API logins from `.60` as `homeassistant`, and **no** `admin` login from `.60`
anywhere in the log. The `read,test,api` policy proved sufficient — the integration did not
need `write` added.

The temporary firewall rule was renamed from `TEMP: HA API - remove after finding 3` to
`HA API access`, since plaintext management traffic within the LAN is an accepted risk and
the rule is now permanent.

What remains open under finding 3 is only `api-ssl` listening with `certificate=none`, plus
the deferred Let's Encrypt question.

**Finding 6 — `admin` is LAN-bound; know what that costs you (closed 2026-09-05).**
Informational only, no configuration change intended. Guillaume confirmed he has read and
accepted it. The substance, kept here so it is not re-derived: `admin` is restricted to
`address=192.168.1.0/24` on all three devices, so a MAC-Telnet session sourced from outside
that subnet is refused at login even with correct credentials. Recovery works because the
other MikroTiks source from inside the range. If `admin`'s address is ever narrowed further,
the serial console becomes the only route in — the local console ignores the user address
restriction. Still a single account with the default name.

**2026-09-04 — IPv6 broken by misplaced WAN drop (was finding 1, critical).** The
`drop input from WAN` rule sat ahead of the DHCPv6-client accept, so prefix delegation
never bound and the `swisscom-pd` pool did not exist. Introduced by the round 1 finding 4
remediation, whose `place-before=` target was wrong.

Fixed by deleting both the UDP traceroute accept and the WAN drop: with the traceroute rule
gone, the chain's terminating drop covers WAN input on its own, so the drop had no remaining
job and its position could no longer break anything.

Verified: `/ipv6/pool/print` shows `swisscom-pd` = `2a02:1210:680f:c40c::/62`;
`/ipv6/address/print` shows `2a02:1210:680f:c40c::1/64` on `bridge-main`, `advertise=yes`,
no pool error; `/ipv6/route/print` shows an active default route; desktop pings
`2606:4700:4700::1111` at 0% loss.

**2026-09-04 — LAN-wide management-plane access (was finding 2, high).** The
`accept chain=input src-address-list=home` rule granted every host on `192.168.1.0/24` —
IoT devices included — full access to ssh, the web UI, the API, and Winbox.

Replaced with an `mgmt` address list holding the desktop (`.90`), mikrotik2 (`.2`), and
mikrotik3 (`.3`). Two explicit carve-outs were added ahead of it so the change did not break
working services: DHCP server (UDP 67 on `bridge-main`), and a temporary accept for Home
Assistant's API on 8728 from `.60` which finding 3 will replace.

Verified: from Pi-hole at `192.168.1.40`, outside `mgmt`, `nc` to ports 22 and 8291 both
time out (exit 124) while port 53 succeeds. Rule order confirmed, with the broad `home` rule
disabled at position 10 behind the `mgmt` accept at 9. DHCP confirmed still working by fresh
*dynamic* leases (`.101`, `.102`, `.106`) issued after the change, proving full
DISCOVER/OFFER rather than only renewals.

**2026-09-04 — `192.168.1.4` added to `mgmt`.** A MikroTik being returned to service,
allowed in advance so it has management access when it comes back online.

**2026-09-04 — RouterBOOT version unknown (was finding 9, medium).** RouterBOOT upgrades
separately from RouterOS and does not follow the package upgrade, so it was unclear whether
it lagged the move to 7.24.2.

No action needed. Verified: `/system/routerboard/print` reports `current-firmware: 7.24.2`
equal to `upgrade-firmware: 7.24.2`. RouterBOOT is current.

**2026-09-04 — TLS services listening without a certificate (was finding 4, high).**
`reverse-proxy` was enabled on 443 with `certificate=none`: listening, unable to complete a
handshake, unused.

Verified: `/ip/service/print` shows `reverse-proxy` flagged `X`. `www-ssl` remains disabled
as before.

Partially folded rather than closed: `api-ssl` has the same defect and `www` is plain HTTP
in active use. Both need the certificate from finding 3, so they were moved into that
finding instead of being tracked separately.

**2026-09-04 — Home Assistant port-forwarded over plaintext HTTP (was finding 5, high).**
A `dst-nat` on port 80 from `ether1` to `192.168.1.60:80`, with a matching forward-chain
accept, would have carried HA credentials and session cookies in clear text had the
Internet-Box forwarded port 80 inward. (HA was not listening on 80 in any case.)

Verified: `/ip/firewall/nat/print` shows only the HTTPS dst-nat remaining;
`/ip/firewall/filter/print where chain=forward` shows only the HTTPS accept. Both halves of
the HTTPS pair are intact, so no orphaned NAT entry or unreachable filter rule was left
behind.

**2026-09-04 — Unused routing protocol config (was finding 11, low).** OSPF v2/v3
instances, a BGP template, and an enabled BFD configuration existed on a router with no
dynamic routing.

Verified: `/routing/ospf/instance/print`, `/routing/bgp/template/print`, and
`/routing/bfd/configuration/print` all return empty. Confirmed observably by the
`route_BFD` services on UDP 3784/4784 no longer appearing in `/ip/service/print`.

**2026-09-04 — `detect-internet` enabled on all interfaces (was finding 14, low).**

Verified: `/interface/detect-internet/print` shows `detect-interface-list: none`, and every
`detnet` dynamic service has disappeared from `/ip/service/print`.

**2026-09-04 — Stale OVPN server entry (was finding 15, low).** An OVPN server configured
with `auth=sha1,md5`, long unused.

Verified: `/interface/ovpn-server/server/print` returns empty.

**2026-09-04 — Anti-scan rules dead and a self-lockout risk (was finding 7, medium).** The
`Syn_Flooder` and `Port_Scanner` rules sat after `drop all from WAN`, so they never saw
internet traffic — the only thing they were written to stop. Worse, they sat *before* the
`mgmt` accept and were unscoped, so the only addresses they could ever match were LAN hosts:
a management host tripping `Port_Scanner` would have been dropped for a week.

Fixed by scoping all four rules to `in-interface=ether1` and moving them ahead of the WAN
drop, rather than deleting them.

Took two attempts. The first pass was made in safe mode and the reordering was rolled back
when the session ended without a commit — only the `in-interface=ether1` scoping survived.
Redone outside safe mode, which was safe to do because none of these rules can affect the
management path.

The second attempt used a single move (send the WAN drop down) instead of lifting four
rules up:

```
/ip/firewall/filter/move [find comment="defconf: drop all from WAN"] \
    destination=[find comment="Jump for icmp input flow"]
```

Verified 2026-09-04 outside safe mode: `/ip/firewall/filter/print where chain=input` shows
positions 2-5 as the four detector rules, each with `in-interface=ether1`, and
`defconf: drop all from WAN` at position 6. They now see internet traffic and can never
match a LAN host.

A matching SYN-flood pair was added to the **forward** chain, where inbound traffic to port
forwards actually flows. Verified positioned between the Pi-hole DNS accept and
`Home can connect everywhere`, detector before drop, matching on
`connection-nat-state=dstnat` rather than a literal port so every future port forward is
covered without revisiting the rule.

Watch for false positives: `connection-limit=30,32` is plausible for a single browser under
poor connectivity, and tripping it locks out remote Home Assistant for 30 minutes. Check
`/ip/firewall/address-list/print where list=Syn_Flooder` if remote access misbehaves.

**Lesson recorded:** safe mode discards everything on session loss. For changes that cannot
affect the management path, run them directly and verify immediately instead.

Note on realistic value: input from `ether1` was already fully dropped, and the
Internet-Box only forwards 443 inward, so little traffic reaches this chain. A matching
SYN-flood pair was added to the **forward** chain, scoped to `dst-port=443`, where inbound
traffic to Home Assistant actually flows. Watch `Syn_Flooder` for false positives —
`connection-limit=30,32` is plausible for a single browser under poor connectivity, and
tripping it locks out remote HA for 30 minutes.

**2026-09-04 — MikroTik cloud DDNS active (was finding 13, low). Not actionable.**
`/ip/cloud/set ddns-enabled=` tab-completes to `auto` and `yes` only; RouterOS 7.24.2 offers
no way to switch DDNS off, and `auto` still populates `public-address`. The RouterOS 6
`no` value is gone.

`update-time` was set to `no`, removing the redundant cloud time source (NTP is already
configured against `0-3.pool.ntp.org`).

Remaining exposure is an outbound report to a vendor service plus a resolvable
`<serial>.sn.mynetname.net` name. Closed as not actionable on this version rather than left
open indefinitely.

**2026-09-04 — Firewall rule logging (was finding 10, low).** Six drop rules carried
`log=yes` on a 600 MHz single-core CPU, where a chatty device retrying against a permanent
drop fills the buffer continuously.

All firewall rule logging disabled with `/ip/firewall/filter/set [find log=yes] log=no`.
Verified: `/ip/firewall/filter/print where log=yes` returns empty.

`/system/logging` was deliberately left alone — `info`, `error`, `warning`, and `critical`
still go to memory. Those are low-volume, cost nothing per packet, and are what is needed
when diagnosing a problem. Only per-packet firewall logging was removed.

The `Hombli` ceiling-fan rule was the one worth keeping (distinct prefix, low volume,
deliberately distrusted device). Re-enable with
`/ip/firewall/filter/set [find comment~"Ceiling Fan"] log=yes` if that visibility is wanted
back.

**2026-09-04 — Wrong CAPsMAN address on the FON network (was finding 12, low).** The
`192.168.2.0/24` DHCP network advertised `caps-manager=192.168.2.1`, where no manager
exists.

Two earlier attempts using `[find address=192.168.2.0/24]` silently did nothing — that
filter matches no rows on this menu, and `set` against an empty result is a no-op that
looks identical to success. Fixed by addressing the row by index instead.

Verified: `/ip/dhcp-server/network/print detail` shows `caps-manager=192.168.1.1` on the
`192.168.2.0/24` network.

## Switches — mikrotik2 (CRS125-24G-1S-2HnD) and mikrotik3 (RB750Gr3)

### Closed 2026-09-05

Verified against `dumps/mikrotik2-switch.txt` and `dumps`, collected
2026-09-05 16:37–16:38.

**S1 — no input-chain firewall on either device.** Both now carry the full pattern, in the
correct order, ending in a terminating drop. `/ip/firewall/filter/print` on each shows rules
3–8: accept established/related, drop invalid, accept ICMP, accept `src-address-list=mgmt`,
accept `192.168.1.60` to 8728, drop everything else. The `mgmt` list on both holds
`192.168.1.90`, `.1`, `.2`, `.3`, `.4`.

Confirmed by negative test from Pi-hole (`192.168.1.40`, deliberately outside `mgmt`):

```
timeout 5 nc -zv 192.168.1.2 8291   ->  124
timeout 5 nc -zv 192.168.1.3 22     ->  124
```

Both timed out rather than being refused, which is the drop rule acting — a device with no
listener would have returned a refusal immediately.

**S2 — FTP and Telnet enabled.** `/ip/service/print` on both: `0 X ftp`, `3 X telnet`.

**S3 — `admin` unrestricted.** `/user/print detail` on both: `name="admin" group=full
address=192.168.1.0/24`. Last logins recorded from within the range, so the restriction is
not blocking normal access.

**S4 — open DNS resolvers.** `/ip/dns/print` on both: `allow-remote-requests: no`. Each
still resolves for itself (mikrotik2 → `192.168.1.1`, mikrotik3 → `192.168.1.40` dynamic),
which is what was wanted.

**S5 — `reverse-proxy` and `api-ssl` listening with no certificate.** `/ip/service/print` on
both: `10 X reverse-proxy`, `15 X api-ssl`. `www-ssl` was already disabled.

**S6 — mikrotik2's broken and disabled NAT rules.** `/ip/firewall/nat/print` returns empty
and the export has no `/ip firewall nat` section at all.

**S8 — mikrotik3 logged every forwarded UDP packet.** Gone; `/ip/firewall/filter/print`
shows only the three defconf forward rules plus the new input chain.

**S9 — mikrotik2's wireless profile permitted TKIP.** The export now reads
`set [ find default=yes ] authentication-types=wpa2-psk mode=dynamic-keys
supplicant-identity=MikroTik` with no cipher parameters. `/export` prints only non-default
values, and `group-ciphers=tkip,aes-ccm unicast-ciphers=tkip,aes-ccm` was previously shown
explicitly — its disappearance means both are back to the `aes-ccm` default.

**S12 — mikrotik2's address sat on a bridge port.** `/ip/address/print` now shows
`192.168.1.2/24 ... bridge-local`, no slave flag.

**S13 — Home Assistant account on the switches.** Both devices have `homeassistant` in group
`ha` bound to `address=192.168.1.60/32`, with the group policy matching the main router's
exactly (`read,test,api`, everything else negated), plus the `HA API access` input rule
correctly placed before the terminating drop. Note the caveat from the original finding still
stands: neither switch runs a DHCP server and mikrotik2's wlan1 is CAPsMAN-managed, so HA may
see little from them beyond interface state. Worth confirming the integration reports
something useful before adding all of them to HA.

**Also done, not previously tracked as a finding:** SSH public-key authentication is
configured on all three devices (`/user/ssh-keys/print` shows `admin` / `gehel@durin`) with
`password-authentication=yes` kept as the fallback, which is what was asked for.

**S7 — leftover DHCP configuration.** On mikrotik2, `/ip/dhcp-server/print` and
`/ip/dhcp-server/network/print` both return empty, and the `/ip dhcp-server` sections are
gone from the export — the dormant server bound to `ether2-master-local` with the dangling
`address-pool=*1` no longer exists. On mikrotik3, `/ip/pool/print` is empty and
`/ip/dns/static/print` returns nothing, so the `192.168.88.10-254` pool and the
`router.lan -> 192.168.88.1` record are both gone. mikrotik2 keeps one static record,
`router -> 192.168.1.2`, which is correct and points at itself.

**S10 — orphaned OSPF areas.** `/routing/ospf/area/print` and `/routing/ospf/instance/print`
both return empty on both devices, and no `/routing` section survives in either export.

**S11 — mikrotik2's OVPN server.** `/interface/ovpn-server/server/print detail` returns
empty and the `/interface ovpn-server server` section is gone from the export. The only
crypto config left on either device is the IPsec proposal at `aes-256-cbc` and a default
IPsec profile carrying nothing but DPD timers.

**S14 — SSH weak defaults.** `/ip/ssh/print` on **all three** devices now reports
`strong-crypto: yes` and `host-key-size: 4096`, with `password-authentication: yes` retained
as the fallback. Verified functionally as well as by print: `dump-configs.sh` completed a
full authenticated run against all three devices after the host keys were regenerated, which
is the check that matters — a broken algorithm negotiation would have failed the run
outright rather than showing up in any single command's output.

## Tooling

### Dump script

`dump-configs.sh` gained `/ip/pool/print`, `/ip/dhcp-server/print`,
`/ip/dhcp-server/network/print`, `/ip/dns/static/print`, `/routing/ospf/area/print`,
`/routing/ospf/instance/print` and `/interface/ovpn-server/server/print detail` on
2026-09-05. These are absence checks: `/export` only prints configuration that exists, so
proving something was removed needs a print that comes back empty rather than a section that
merely fails to appear.

**S16 — mikrotik3 had no working out-of-band recovery path.** `ether1` moved from the `WAN`
interface list to `LAN`, which is what neighbour discovery, MAC-Telnet and MAC-Winbox all
key off. Confirmed in both directions: `/ip/neighbor/print` on mikrotik1 now lists
`MikroTik - Office` at `192.168.1.3`, and mikrotik3's own neighbour table — previously
completely empty — now shows mikrotik1 and mikrotik2, **both on `ether1`**. That last detail
confirms the diagnosis rather than merely the fix: `ether1` is in fact the uplink, so
discovery and MAC-Telnet had been deaf on the only port that reaches the network. The
recovery path was then proven rather than inferred — `/tool/mac-telnet 74:4D:28:C9:4F:FD`
from mikrotik1 reached a login prompt and authenticated, before any change that could
strand the device.

**S15 — mikrotik3 took its address from DHCP.** Converted via a `/system/script`, so the
sequence completed despite the session dropping when the address went away. Verified after
a reboot, with the dump collected at 1m14s uptime:

```
/ip/address/print    ;;; static management
                     0  192.168.1.3/24  192.168.1.0  bridge      (no D flag)
/ip/route/print      ;;; static default
                     0  As  0.0.0.0/0  192.168.1.1                (As, not DAd)
/ip/dns/print        servers: 192.168.1.40   dynamic-servers: (empty)
/ip/dhcp-client/print
                     0  X  bridge  ...  stopped
```

The temporary script was removed and does not appear in the export. mikrotik1's reservation
for `192.168.1.3` was deliberately kept as a safety net.

Addressing across the estate now reads: mikrotik1 static on both bridges with `ether1`
dynamic by design (WAN lease from the Internet-Box), mikrotik2 static with its DHCP client
shelved as `disabled=yes`, mikrotik3 the same. mikrotik4 to match when it returns.

## VLAN segmentation — Phases 0-2 (2026-09-06 to 2026-09-07)

Full design, decisions, and the still-open remainder (Phase 3 onward) live in
[vlan.md](vlan.md). This entry records what's actually done, closed the way every other entry
in this file is: with the output that verified it, not just the change that was made.

### Phase 0 — preparation

All steps completed on mikrotik1 and verified against live output: backups (`pre-vlan.backup`
and `.rsc`) taken and downloaded from all three devices via a new `fetch-backups.sh`; stale
domain (`ledcom.ch` → `home.ledcom.fr`) corrected on both DHCP networks; `dhcp-home` lease
time shortened to 5m ahead of the later renumber; two long-dead DHCP reservations removed;
CAP interface names stabilized to `ap-MikroTik-1` / `ap-MikroTik-Switch-1`
(`name-format=prefix-identity`); NTP server enabled. The Fonera and its entire `bridge-fon`
config (firewall rules, DHCP server, pool, address, bridge, address-list) were deleted
outright — verified clean via `/ip/firewall/filter/print` showing no remaining reference —
and the freed ports (`ether3`, `ether6`-`ether10`) folded into `bridge-main`.

### Phase 1 — VLAN plumbing and wireless tagging

`vlan-filtering=yes` on all three bridges, with VLAN 10/20/30 tables configured per the port
map in `vlan.md`. Went through real trouble getting here, all now folded into the plan as
corrections — the short version: a device's own management IP needs a real `/interface vlan`
sub-interface, not just VLAN-table membership, to survive `vlan-filtering=yes`; the address
move, DHCP-server rebind, and any interface-keyed firewall rules all have to land atomically;
and CAPsMAN's wireless datapath needs its own explicit `vlan-mode=use-tag` — the bridge-VLAN
table alone isn't sufficient. Verified working: all three devices reachable at
`192.168.1.1/2/3` (unrenumbered at this point) with `vlan-filtering=yes` holding through a
reboot test on mikrotik3; wireless clients (desktop, TV) confirmed getting real DHCPv4 leases
over WiFi, not just association.

**Side effects surfaced and fixed along the way, not part of the original Phase 1 scope:**
IPv6 had never been migrated off `bridge-main` — fixed, full write-up in
[ipv6.md](ipv6.md)'s "Migrated onto `vlan-users`" section. That same investigation identified
the source of a previously "possible" rogue IPv6 router advertisement (Home Assistant's
OpenThread Border Router, working as designed, not a bug) — recorded as its own entry in
[config-review.md](config-review.md), held there rather than closed here until a few more days
confirm it stays stable.

### Phase 2 — renumber to 192.168.10.0/24

All three devices moved from `192.168.1.0/24` to `192.168.10.0/24`. Done via a dual-homing
technique to sidestep a chicken-and-egg reachability problem (mikrotik1 held both
`192.168.1.1/24` and `192.168.10.1/24` simultaneously while mikrotik2 and mikrotik3 were
migrated one at a time, only dropping the old address once everything else was confirmed on
the new subnet).

Twelve DHCP reservations migrated by MAC address (IotaWatt, Home Assistant, Pi-hole, both
OctoPrint entries, the desktop, a phone, two Tasmota lights, a laptop, the ceiling fan, and
mikrotik3's own safety-net reservation); the long-dead kitchen-light Tasmota reservation
deleted rather than migrated; a new reservation added for the printer, which had never had one
despite the design assuming stable addressing for it. `mgmt` address-list and the `HA API
access` rule updated on all three devices; the HTTPS NAT forward to Home Assistant updated.

**Verified:** every device reachable at its `192.168.10.x` address; DHCP issuing
`192.168.10.x` to fresh and renewing clients; internet and DNS working; Home Assistant
reachable locally and remotely (external HTTPS access confirmed from cellular data); mikrotik3
rebooted and came back on `192.168.10.3` unassisted; wireless (LEDCOM) confirmed broadcasting
and connectable after a CAPsMAN reconnection issue was fully resolved; non-overlapping wireless
channels (1 and 11) confirmed still correctly assigned per-radio after all the reconnection
work. A follow-up `dump-configs.sh` grep for literal `192.168.1.` references across all three
exports, plus a cleanup pass, closed out every remaining leftover (stale DNS server settings on
mikrotik2/mikrotik3, stale local `router` DNS records, the deliberately-kept old `mgmt`/`HA API
access` entries, `admin`'s temporarily-widened address restriction narrowed back down, and
mikrotik1's SNMP community address restriction cleared entirely since SNMP stays disabled).

**Real gaps found only via live failures, each now documented in `vlan.md` and `README.md`'s
hard-won lessons for Phase 3:** the `admin`/`homeassistant` user-account `address=`
restriction is separate from any firewall rule and isn't found by reading firewall config; a
NAT rule's `to-addresses=` and its paired forward-chain accept rule are two separate things to
update, not one, and missing the second produces a silent drop rather than an error; a
forward-chain `drop` rule blocking a specific IoT device by literal address silently stopped
enforcing once that device renumbered — a renumber can quietly remove a security restriction,
not just break connectivity; and CAPsMAN's own discovery config hides literal IP references in
three separate places (`/interface/wireless/cap`, `/ip/dhcp-server/network`'s `caps-manager=`,
and `/caps-man/manager/interface`'s listening-interface list) that took down both wireless
radios entirely when missed.

Also recorded in `README.md`: `/ip/dhcp-server/network/set [find address=...]` and
`/ip/firewall/filter/remove [find ... and ...]` (multiple conditions combined with `and`) both
silently match nothing on this RouterOS version, with no error — the second is a repeat
appearance of a bug pattern already documented in this file's 2026-09-04 FON-network finding,
missed here because the earlier lesson wasn't carried forward into the new work.

### Phase 3, block 1 — services/iot VLAN interfaces, addressing, DHCP, NTP option 42 (2026-09-07)

Applied via `home/network/scripts/phase3-01-networking.rsc` (idempotent, `find`-guarded) on
mikrotik1: `vlan-services`/`vlan-iot` interfaces on `bridge-main`, their `.20.1`/`.30.1`
gateway addresses, `pool-services`/`pool-iot`, `dhcp-services`/`dhcp-iot` servers, and the
`ntp-users`/`ntp-services`/`ntp-iot` DHCP option-42 definitions (mikrotik1's own address on
each VLAN, so IoT and services clients can get NTP without internet access).

`ntp-services`/`ntp-iot` were wired into their networks' `dhcp-option=` inline as part of the
`add` (a fresh object, so the known `network/set [find address=...]` bug doesn't apply).
Retrofitting `ntp-users` onto the pre-existing `192.168.10.0/24` network needed the documented
workaround: printed the network table, found it at index `0`, `set 0 dhcp-option=ntp-users`,
re-printed to confirm.

**Verified** by `import ... dry-run` followed by `import`, then the script's own end-of-run
`print` of every object created, plus a fresh `dump-configs.sh` run (16:58) confirming all of
it landed. No impact to the management path — none of this touches `bridge-main`,
`vlan-users`, or any existing address.

### Phase 3, block 2 — LEDCOM-IoT SSID on both CAPsMAN radios (2026-09-07)

Applied via `home/network/scripts/phase3-02-iot-ssid.rsc`: `caps_iot` configuration
(`ssid=LEDCOM-IoT`, `datapath.vlan-id=30`, `datapath.vlan-mode=use-tag` on `bridge-main`),
added as `slave-configurations=caps_iot` on both provisioning rules (the `caps_ch11`
radio-mac-specific one and the `caps_config` catch-all), then `/caps-man/remote-cap/provision
[find]`.

**Verified** by the script's own `print detail` of the new configuration and both
provisioning rules, both showing `slave-configurations=caps_iot`. No wireless-outage reports
during the reprovision.

### IPv6 RDNSS was leaking the ISP's own DNS server, bypassing Pi-hole (2026-09-07)

Found while scoping the Home Assistant VLAN migration: a dual-stack desktop's `dig` for a name
with both a public and a Pi-hole-local answer got the public one. Root cause and full writeup
in [ipv6.md](ipv6.md#resolved-rdnss-was-leaking-the-isps-own-dns-server-bypassing-pi-hole); a
second instance of [config-review.md](config-review.md)'s finding 8 (DNS can bypass Pi-hole).

Two fix attempts before the real one. First: `use-peer-dns=no` on the IPv6 DHCP client
(`ether1`), on the theory that DHCPv6-PD's peer-DNS copy was populating `/ip/dns`'s
`dynamic-servers` with the ISP's IPv6 resolver, which `/ipv6/nd`'s `advertise-dns=yes` then
re-advertised via RDNSS on `vlan-users`. That didn't clear the existing lease's entry, so a
follow-up forced both `ether1` DHCP clients (v4 and v6) to release and rebind, and set
`use-peer-dns=no` on the **IPv4** client too — which turned out to be an independent, real
leak of its own (`10.1.1.1`, the Internet-Box's IPv4 address, into the same `dynamic-servers`
list). That part worked and stayed fixed. **The IPv6 entry survived a full DHCPv6-PD
release/rebind with `use-peer-dns=no` already set** — proof DHCPv6 was never its actual
source.

Actual cause: `/ipv6/settings`' `accept-router-advertisements=yes` on `ether1` (needed for this
router's own WAN default route) also accepts the RDNSS option carried in the Internet-Box's own
RA on that link, with no DHCPv6 involved. That can't be turned off without breaking the WAN
route, so the real fix scopes the *other* end instead: `advertise-dns=no` on the `/ipv6/nd`
entry, stopping `vlan-users` from advertising any DNS server via RA at all — matching what this
project already intended (clients resolve via Pi-hole over the IPv4 DHCP-assigned server).

**Verified:** `/ipv6/nd/print detail` shows `advertise-dns=no`. On the desktop,
`resolvectl status` already showed `Current DNS Server: 192.168.10.40` before this last fix
(the IPv4-side cleanup was enough for that), and `dig home.ledcom.fr` returned `192.168.10.60`
from Pi-hole. The IPv6 entry lingered in `resolvectl`'s server list after the fix — expected:
`resolvectl flush-caches` clears cached answers, not the RA-learned server list, which has its
own RFC 8106 lifetime and ages out client-side within the `ra-lifetime=30m` window once the
router stops sending it; there is no explicit withdrawal message, only omission.

Scripts: `scripts/fix-ipv6-rdnss-dns.rsc`, `scripts/fix-ipv6-rdnss-dns-cleanup.rsc`,
`scripts/fix-ipv6-rdnss-dns-v2.rsc` (the one that actually closed it).

### Printer reverted from services back to users (2026-09-08)

Migrated to `services` as Phase 3 step 1, then moved back the same week once the mDNS-repeater
defect above was root-caused: `mdns-repeat-ifaces` doesn't reliably deliver working
autodiscovery across VLANs (queries get proxied and answered, but the router drops the reply
on the way back — see the "IPv6 RDNSS..." entry's neighbour for detail, and `vlan.md`'s
Decisions section). Confirmed independently on the [MikroTik forum](https://forum.mikrotik.com/t/mdns-repeater-forwarding-queries-but-not-all-responses-across-vlans/269317)
— RouterOS 7.20, identical symptom. Guillaume's household needs a non-technical user to be able
to add this printer on her own phone and laptop without manual IP configuration, which
outweighs keeping it on `services`.

Reverted via `scripts/phase3-revert-printer.rsc` (mikrotik3: `ether2` back to VLAN 10,
`pvid=10`), `scripts/phase3-revert-printer-dhcp.rsc` (mikrotik1: DHCP reservation back to
`192.168.10.110` / `dhcp-home`), and `scripts/phase3-revert-mdns-repeat.rsc` (mikrotik1:
`mdns-repeat-ifaces` cleared entirely — its only beneficiary was the printer, and it didn't
reliably deliver its purpose anyway; re-enable later, eyes open, only if Pi-hole/HA/IoT
discovery actually needs it).

**Verified:** `/interface/bridge/vlan/print` and `/interface/bridge/port/print` on mikrotik3
show `ether2` back on VLAN 10; the DHCP lease went `status=bound`,
`active-address=192.168.10.110`, `active-server=dhcp-home` within its lease window, no
power-cycle needed; discovery and adding the printer worked cleanly from the household's
non-technical user's own phone and laptop (same-VLAN mDNS, no repeater involved). The printer
is no longer part of the Phase 3 device migration — `vlan.md`'s device inventory, target
design, policy matrix, trunk/port plan, and migration table were all updated to reflect it
staying on `users` permanently.

### Phase 3, step 6 — Kids light migrated to iot (2026-09-08)

Wireless Tasmota device, no port to move. Moved via
`scripts/phase3-16-kidslight-mikrotik1.rsc`: DHCP reservation to `192.168.30.61`/`dhcp-iot`,
and the permanent `iot -> services` MQTT rule (tcp/1883, dst-address=192.168.20.60) — pulled
forward from Phase 4, first device to actually need it (the TEMP `users -> services` version
added during HA's migration only covers devices still on `vlan-users`). Both interfaces +
`connection-state=new` from the start, per the `I - INVALID` findings from the ceiling fan
work — printed clean immediately, no follow-up fix needed this time.

Guillaume rejoined the device to `LEDCOM-IoT` via Tasmota's own console/web config (not
scripted). **Verified: connected to HA successfully.**

**Confirmed one of `vlan.md`'s "known unverified assumptions": Tasmota ignores DHCP option 42
entirely.** It kept its previously-configured NTP server, which — with no internet access on
`vlan-iot` by design — is unreachable, so it was silently running on stale time rather than
failing loudly (a real concern for a kids' light, if it has any bedtime/schedule automation).
Fixed via Tasmota's own console: `NtpServer1 192.168.30.1` (mikrotik1's `vlan-iot` address).
Still unverified for ESPHome (IotaWatt) — check the same way when that device migrates.

### Phase 3, step 7 — ceiling fan migrated to iot, out of order (2026-09-08)

Moved before OctoPrint/IotaWatt/Kids light, deliberately overriding `vlan.md`'s "do this one
last" caution, to have it working that same evening. Wireless device, no port to move.

`scripts/phase3-10-ceilingfan-mikrotik1.rsc`: DHCP reservation to `192.168.30.63`/`dhcp-iot`;
**retired the standing `chain=forward action=drop src-address=192.168.10.63` rule** (a
"deliberately distrusted device" restriction from an earlier config-review round) rather than
carrying it to the new address — `vlan-iot` isolation now does that job by construction; added
the general `iot -> Pi-hole DNS` accept rules (pulled forward from Phase 4, first real device
on `vlan-iot`); added the fan's own DNS-drop rules, created `disabled=yes`; added a
tcp/80,443 internet-access toggle for the fan specifically, created enabled, for that night's
reconfiguration (the fan is known to phone home to a vendor cloud service, confirmed in its
original config-review finding, so reconfiguration needed DNS+internet).

**A second, broader temporary rule** (`scripts/phase3-12-iot-temp-internet.rsc`): whole-`vlan-
iot` internet access, no port restriction, enabled for pairing Guillaume's phone to
`LEDCOM-IoT` during the Tuya app's pairing flow — broader than the usual named-exception
pattern, justified by being short-lived and by not wanting a guessed-wrong port to cost a
retry mid-pairing.

**A real, previously-unanticipated policy gap found live:** HA's `tuya-local` integration talks
directly to the device over Tuya's local protocol (tcp/6668), bypassing Tuya's cloud — not in
the original policy matrix, which only listed HA on 6053/80 for ESPHome/Tasmota. Added
`services -> iot` tcp/6668 (`scripts/phase3-13-ha-tuya-local.rsc`), same shape as the existing
`HA -> Tasmota/IotaWatt` rule; folded into `vlan.md`'s policy matrix and Phase 4 draft.

Once HA confirmed the fan working: disabled both temporary internet rules and enabled the
fan's DNS-drop rules (`scripts/phase3-14-ceilingfan-lockdown.rsc`). **Verified the fan still
responds correctly in HA after lockdown** — dropping its DNS didn't affect local Tuya control,
as expected.

**Further work on the `I - INVALID` flag, refining what was already found for HA:** three new
rules added during this step (`iot: DNS to pi-hole` ×2, `ceiling fan: TEMP internet for setup`)
showed the flag despite already having `connection-state=new` — because each specified only
*one* interface direction alongside an address/port matcher, not both. Fixed by adding the
missing interface (`scripts/phase3-11-fix-invalid-rules.rsc`). Then, once the fan's DNS-drop
rules were finally *enabled* (they were created `disabled=yes` and looked clean while off), the
flag appeared on *them* too — a `drop` rule combining `src-address=` and `dst-address=` with
no interface at all. Fixed by adding both interfaces there as well
(`scripts/phase3-15-fix-dns-drop-invalid.rsc`). Net finding: RouterOS doesn't evaluate this flag
on disabled rules at all, and the actual set of triggers is broader than "accept rules need
`connection-state=new`" — see `README.md`'s hard-won lessons for the fuller list. Also applied
the same interface-completeness fixes to `vlan.md`'s Phase 4 draft, which had five more rules
with the identical one-interface-plus-address/port pattern, so Phase 4 doesn't hit this again
when it's actually run.

**Verified throughout via the forward chain's own `print` output** (not just individual rule
checks) — printing the whole chain in order after each change caught the ordering and
placement issues immediately, which checking one rule at a time would have missed.

### Phase 3, step 3 — Home Assistant migrated to services (2026-09-08)

Moved via `scripts/phase3-06a-ha-mikrotik2-port.rsc` (mikrotik2: `ether21-slave-local` from
VLAN 10 to VLAN 20 — this time VLAN 20's untagged list already had Pi-hole's port on it, so the
script read-modified-appended both sides programmatically rather than overwriting, to avoid
dropping Pi-hole's membership). `scripts/phase3-06c-ha-mikrotik1.rsc` moved the DHCP
reservation to `192.168.20.60`/`dhcp-services`, updated the dst-nat HTTPS port forward *and*
its paired forward-chain rule, and added a temporary `users -> services tcp/1883` rule for IoT
devices still on `users` to reach HA's MQTT broker (to be removed at Phase 4, per `vlan.md`).
`scripts/phase3-06b-`/`-06d-ha-mikrotik*.rsc` updated the `homeassistant` account's
`address=192.168.20.60/32` restriction and the *"HA API access (post-renumber)"* rule's
`src-address=`, independently on mikrotik2 and mikrotik3 (same pattern as Pi-hole: these exist
as separate copies per device, not shared config).

**Verified quickly:** DHCP lease bound at `192.168.20.60`; local HTTPS
(`https://192.168.20.60`) and remote/external HTTPS both worked immediately.

**The MikroTik integration inside HA took much longer to get right, through two real mistakes
before the actual root cause:**

1. **Real gap, found and fixed:** nothing allowed `vlan-services -> vlan-users` at all — the
   account restriction and API-access rule only govern the *destination's own input chain*;
   they don't get HA's packets there. Added a narrow exception
   (`scripts/phase3-08-ha-mikrotik-integration-access.rsc`): an address-list of just
   mikrotik2/mikrotik3's management IPs, `src-address=192.168.20.60`, `dst-port=8728`.
2. **Mistake 1 — my own idempotency guard was wrong.** The address-list `add`s were guarded by
   `find where address=<ip>` with no list filter; both IPs already existed in the `mgmt` list
   (from Phase 2), so the guard concluded "already exists" and silently skipped creating the
   `ha-mikrotik-targets` entries — the filter rule referenced an empty list and matched
   nothing. An unverified claim in my own comment ("neither address is used elsewhere") turned
   out to be false. Fixed in `scripts/phase3-08b-ha-mikrotik-targets-fix.rsc`, matched by
   `comment=` instead (safely distinct from the `mgmt` list's differently-worded comments).
3. **Mistake 2 — repeated a mistake already documented in this same file.** The filter rule was
   added with a plain `/add`, landing it *after* the unconditional "Drop all other forward
   traffic" catch-all — dead on arrival, exactly the failure mode already written up for the
   `services: internet` rule above, not applied consistently here. Fixed by moving the rule
   (`scripts/phase3-08c-ha-mikrotik-rule-reorder.rsc`) rather than recreating it.
4. **A genuine RouterOS finding, not a mistake:** once correctly placed, the rule still showed
   `I - INVALID` until `connection-state=new` was added — a forward-chain accept rule combining
   `in-interface=`/`out-interface=` with `dst-address=`/`dst-port=` needs it on this RouterOS
   version, confirmed by comparison with every other working custom rule on this router (all of
   which already had it). Fixed the same gap throughout `vlan.md`'s Phase 4 draft while it was
   fresh, before it could bite again later.
5. **The actual root cause, after all of the above was already correct:** mikrotik2 and
   mikrotik3 had **no default route at all** — only the directly-connected `192.168.10.0/24`.
   Every prior management connection to their own IPs had come from within `vlan-users` itself
   (same subnet, no gateway needed for the reply); HA's new address was the first-ever
   cross-subnet connection to either switch's management IP. They could accept the incoming SYN
   (confirmed live: fresh packets matched the input-chain rule on both), but had no route back
   out to reply, so the TCP handshake never completed — explaining why **nothing at all** was
   ever logged, not even a `login failure`: the API layer never saw a completed connection.
   Root-caused via a careful reset-counters-then-retry test isolating each hop, plus checking
   `/log/print` for a `login failure` message (found in an *old*, pre-migration log entry,
   confirming RouterOS does log auth failures clearly — just under `system,error,critical`, not
   the `account` topic, a wrong filter that cost real time here). Fixed with
   `scripts/phase3-09-switch-default-routes.rsc` — `/ip/route/add dst-address=0.0.0.0/0
   gateway=192.168.10.1` on each switch. **Confirmed working on both mikrotik2 and mikrotik3.**

**A caution for next time:** the packet counters this session initially misled — RouterOS
firewall rule counters are cumulative since the rule's *creation* and are not reset by a
`/set` that changes match criteria, so a nonzero counter on a long-lived rule proved nothing
about current traffic. `reset-counters` before a retry, on a freshly-relevant rule, is the
reliable way to get a clean signal.

**Likely worth adding to README.md's hard-won lessons:** a pure L2 switch whose only IP is a
management address needs its own default route the moment any management client can be on a
different subnet than that address — not just correct bridge/VLAN forwarding. The failure mode
is silent and produces no log at all, which makes it easy to misdiagnose as a firewall or
credentials problem.

### Phase 3, step 2 — Pi-hole migrated to services (2026-09-08)

Moved via `scripts/phase3-05a-pihole-mikrotik2-port.rsc` (mikrotik2: `ether23-slave-local` from
VLAN 10 to VLAN 20). VLAN 10's untagged list is 25 ports on this device — built the target list
programmatically from the live value rather than hand-retyping it, to avoid a transcription
error at that size; confirmed by a before/after port count (25 -> 24) rather than eyeballing
the list.

**Real gap found and fixed, not deferred to Phase 4:** the policy matrix always said `services
-> internet: allow`, but no rule anywhere actually implemented it — only `vlan-users` had a
broad "connect everywhere" accept, and VLAN sub-interfaces don't inherit `bridge-main`'s rules.
Without this, Pi-hole would have had no upstream DNS resolution at all. Added via
`scripts/phase3-05b-pihole-mikrotik1-dhcp-and-fw.rsc`, `place-before=` the catch-all drop (a
plain `/add` appends to the end of the chain, which would have put it after the
already-unconditional drop and made it dead). Also moved the DHCP reservation to
`192.168.20.40` / `dhcp-services` in the same script.

DNS repointed only after confirming Pi-hole was live and resolving at the new address
(`dig @192.168.20.40 google.com` succeeded, proving both DNS and the new firewall rule worked):
mikrotik1's own `/ip/dns servers=` and the *"Accept DNS requests from Pi-hole"* rule's
`src-address=` (`scripts/phase3-05c-pihole-mikrotik1-dns.rsc`); mikrotik2 and mikrotik3's
independent `/ip/dns servers=` (`-05d-`, `-05e-`); and, by hand rather than scripted (the
confirmed `/ip/dhcp-server/network/set [find address=...]` bug), the `192.168.10.0/24`
network's `dns-server=`, via its numeric index (`0`).

**Verified:** DHCP lease `status=bound`, `active-address=192.168.20.40`,
`active-server=dhcp-services`; `dig @192.168.20.40 google.com` resolved successfully; all three
devices' `/ip/dns/print` and the DHCP network table show `192.168.20.40` throughout; a plain
`dig google.com` (no `@server`) from the desktop on `vlan-users` resolved correctly via its
stub resolver, confirming the full DHCP -> `dns-server=` -> Pi-hole chain works end-to-end for
a real client, not just the router itself. Guillaume also updated Pi-hole's own local DNS
record for itself to its new address (a Pi-hole-side admin change, not a router one).

### Phase 3, step 1 — printer migrated to services (2026-09-07/08)

Moved via `scripts/phase3-03a-printer-mikrotik3-port.rsc` (mikrotik3: `ether2` from VLAN 10 to
VLAN 20 — both the bridge-vlan table membership and `pvid`, the two-command move `vlan.md`
flags) and `scripts/phase3-03b-printer-mikrotik1-dhcp.rsc` (mikrotik1: DHCP reservation to
`192.168.20.110` on `dhcp-services`, matched by MAC).

Also enabled `/ip/dns mdns-repeat-ifaces=vlan-users,vlan-services` early (a scoped-down piece
of Phase 4, brought forward because the printer needed it immediately) via
`scripts/phase3-04-mdns-repeat-early.rsc`.

**Verified:** `/interface/bridge/vlan/print` and `/interface/bridge/port/print` on mikrotik3
show the target state; the DHCP lease went `status=bound`, `active-address=192.168.20.110`,
`active-server=dhcp-services` within its lease window, no power-cycle needed. Printing via a
manually-configured static URI (`ipp://192.168.20.110/ipp/print` or
`socket://192.168.20.110:9100`) succeeded from the desktop.

**Real gap found and root-caused, not a blocker:** printing through a printer added via mDNS
*discovery* (GNOME/CUPS's `dnssd://` URI) hung on "processing" / "Unable to locate printer".
Root-caused with `/tool/sniffer/quick` run on both VLANs simultaneously while retrying the
resolve: the router's `mdns-repeat-ifaces` proxies a client query onto the other VLAN under its
own address (`192.168.20.1`, not the desktop's), the printer answers it, and the router drops
that reply instead of repeating it back to the querying VLAN — confirmed by a clean capture
showing the query and its answer on `vlan-services`, and nothing but the original query on
`vlan-users`. Spontaneous, unprompted announcements repeat fine both ways (that's how discovery
found the printer's name at all); only the reply to a router-proxied query goes missing. A
specific RouterOS defect, not a firewall or avahi issue, and not fixable from the config side.
Confirmed static-URI workaround (`ipp://192.168.20.110/ipp/print` or
`socket://192.168.20.110:9100`) treated as the permanent approach for any cross-VLAN mDNS
consumer going forward. Full writeup in `vlan.md`'s Phase 4 section and its "Known unverified
assumptions" #2.

# Config review — home MikroTik network

Covers every MikroTik on the network. Round 1 reviewed 2026-09-03, round 2 from 2026-09-04,
re-verified 2026-09-05 against [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh). **Round 3: 2026-09-08**, against fresh dumps taken
after Phase 4's firewall policy went live — the post-migration pass this document had flagged as
still needed. **Addresses below updated 2026-09-07** after the
VLAN segmentation renumber (Phases 0-2, see [vlan.md](vlan.md) / [changelog.md](changelog.md)) —
everything else in this document is a historical record from the original review dates and
intentionally still shows the addresses as they were *at the time each finding was made*.

The live firewall ruleset itself — every chain, in order, on all three devices — is documented
separately in [firewall.md](firewall.md), regenerated 2026-09-10 after Phase 5's jump-chain
reorg (see [changelog.md](changelog.md)) — a dump refresh, not a new full review round.

| Device | Model | Address | Role |
|---|---|---|---|
| mikrotik1 | RB2011UiAS-2HnD — 128 MB, 600 MHz single-core MIPS | `192.168.10.1/24`; `ether1` dynamic from the Internet-Box | edge router, CAPsMAN manager |
| mikrotik2 | CRS125-24G-1S-2HnD | `192.168.10.2/24` static on `bridge-local` | L2 bridge, 24 ports + SFP; CAPsMAN CAP (wlan1) |
| mikrotik3 | RB750Gr3 (hEX) — 256 MB, 880 MHz quad-core | `192.168.10.3/24` static on `bridge` | L2 bridge, 5 ports |
| mikrotik4 | — | `192.168.10.4` reserved, offline | being returned to service |

All three reachable devices run RouterOS 7.24.2, current as of 2026-09-08 (RouterBOOT current
on mikrotik1 too — re-checked this round). `bridge-fon` (`192.168.2.0/24`) no longer exists —
removed in Phase 0 of the VLAN work.

**Open findings only.** A finding leaves this document once it has been fixed **and**
verified against device output — never when it is reported done. Closed items move to
[changelog.md](changelog.md) with the output that verified them, so they are not re-raised.

Numbering is stable and never reused. Main-router findings are numbered `<n>`, switch
findings `S<n>`, so the two sets never collide.

## Open findings

### 22. `chain=input` accepts are inconsistent about `connection-state=new` (informational)

Found 2026-09-08, the exact audit this document had planned to run. Every `chain=forward` accept
already declares `connection-state=new` consistently. On `chain=input`, only "iot: NTP from
gateway" does; the DHCP, `mgmt`, DNS and HA-API accepts don't. Not exploitable — `chain=input`
rule 1 (`accept established,related`) already intercepts non-new traffic before any of these are
reached — but worth tidying to the same standard as the forward chain, since the whole reason
this document tracks `connection-state=new` is that RouterOS's own `I - INVALID` behavior punishes
inconsistency here on other chains. Low priority; no known live impact.

**Home Assistant's MikroTik integration reports mikrotik2 as running RouterOS 7.23.3** (noted
2026-09-08, still true). Checked directly against this round's dump — mikrotik2 is actually
already on 7.24.2. Stale integration-side cached state, not a real gap; still worth investigating
why HA hasn't refreshed it, and whether the integration's upgrade-trigger feature actually works
(test on a device/moment where an unexpected reboot is low-risk).

### 25. No mechanism updates `home.ledcom.fr`'s DNS record when the public IP changes (medium)

Found 2026-09-11, during the Internet-Box replacement (see `changelog.md`). The record is a
plain A record at Gandi, manually maintained — nothing watches for the ISP-assigned public IP
changing and updates it. The box swap changed the public IP *twice* in one day (once from the
new box's own DHCP lease, confirmed via `/ip/cloud/print` at the time, and again later to
`178.192.223.49`), and both times `home.ledcom.fr` silently kept pointing at a stale address
until manually corrected. Not caught sooner because nothing alerts on this — external HTTPS to
Home Assistant just times out, indistinguishable at first glance from a NAT/firewall problem
(and this file's own investigation initially chased exactly that before finding the real
cause).

**A plausible mechanism was ruled out, not confirmed working.** Home Assistant runs the Let's
Encrypt add-on with the Gandi DNS-01 plugin (`dns-gandi`) — this uses the same Gandi API and
domain, but only to prove domain ownership for certificate renewal, never to update the A
record's IP. Its log (`Using Gandi personal access token` → cert type detected → "not yet due
for renewal") confirms the credential itself works fine; it was never a candidate for the DDNS
job in the first place, a misconception this finding also corrects.

**Options discussed, not yet decided:**
- Point `home.ledcom.fr` at mikrotik1's already-working MikroTik Cloud DDNS hostname
  (`<serial>.sn.mynetname.net`) via a CNAME at Gandi — no new credentials or scripts, but
  `/ip/cloud`'s `ddns-update-interval: none` means it may not refresh promptly on a mid-session
  IP change; `/ip/cloud force-update` could be scheduled periodically to close that gap.
- A mikrotik1 script calling Gandi's LiveDNS API directly via `/tool/fetch` on a schedule —
  keeps a plain A record, more moving parts, a Gandi API key to manage on the router.

### 27. Pi-hole's hourly NTP-like traffic to public servers — real cause still unidentified (reopened 2026-09-14) (medium)

Originally found 2026-09-13, closed 2026-09-14 on the strength of a `FallbackNTP=192.168.20.1`
fix verified via `timedatectl show-timesync --all`. **Reopened the same day**: a log collected
hours later shows the identical hourly burst pattern to rotating public NTP servers continuing
*unchanged* after the fix and its restart (`11:52:37`) — bursts at `11:59:26` and `12:59:26`
both landed on public IPs (`193.134.29.12`, `85.195.210.125`), not `192.168.20.1`. Full account
in `changelog.md`'s "Correction" entry.

**What this means:** `systemd-timesyncd` was never the source — the real culprit is still
unidentified. The earlier investigation's cron/timer checks only grepped `/etc/crontab` and
`/etc/cron.d/*`'s own text for "ntp", which would miss a `cron.hourly` script or a user
crontab entry that doesn't mention "ntp" literally in the schedule line itself. `FallbackNTP=
192.168.20.1` stays applied (harmless, closes a theoretical gap) but doesn't fix the live
problem.

**Next step:** catch it live. The pattern is precisely hourly at `:59`, minute-ish — a process
or socket snapshot (`sudo ss -up`, `sudo lsof -i UDP:123`) taken right around the `:58`-`:00`
window, or a short `sudo tcpdump -i eth0 udp port 123 -n` left running across one full hour
boundary, should catch it directly instead of guessing from config again.

### 28. Home Assistant losing connection-tracking state on a long-lived outbound connection to a Vultr-hosted host (144.202.82.88) (informational, needs more data)

Found 2026-09-13 reviewing `logs/mikrotik1-main.txt`. 11 packets from Home Assistant
(`192.168.20.60`), all sourced from local port 443 (not an ephemeral client port) toward
`144.202.82.88:61234`, hit `services2internet`'s catch-all and were dropped — in four episodes
roughly 2-2.5h apart on 2026-09-13 (02:05, 04:39, 07:14, 09:16). None of them are `SYN`s (all
`ACK`/`ACK,PSH`, i.e. carrying data), which means the underlying connection was already
established, not being attempted fresh — this looks like RouterOS's connection tracking aging
out an idle long-lived session and then dropping its genuine continuation traffic, rather than
Home Assistant actually initiating anything new. `144.202.0.0/16` is a Vultr range; a plausible
candidate given the source port and persistence is Nabu Casa's remote-access relay. Not enough
information yet to act on: worth checking Home Assistant's own Nabu Casa/cloud-connectivity log
for disconnects around those four timestamps, and, if this keeps recurring, mikrotik1's
`/ip/firewall/connection/tracking` timeouts for the relevant protocol.

**Recurred 2026-09-14** (10:42:11, 10:42:46, both `ACK`, same shape) — consistent with the
original description, no new information.

### 31. Home Assistant's real IPv6 address doesn't match `ha-v6`/`http-outbound-v6` — privacy extensions never actually checked on this host (medium)

Found 2026-09-15 reviewing a fresh `logs/mikrotik1-main.txt`, immediately after adding
`http-outbound-v6`'s HTTP exception (see `changelog.md`). Every plain-HTTP SYN from Home
Assistant is still hitting `services2internet-v6`'s catch-all: source
`2a02:1210:7621:9a41:c988:6e5a:9958:c40f`, which doesn't match the computed EUI-64 address in
either `ha-v6` or the new `http-outbound-v6` (`...da3a:ddff:fe31:e059`). `src-mac
D8:3A:DD:31:E0:59` in the same log line confirms this really is Home Assistant, not another
host — the mismatch is in the IPv6 address itself, not misattribution.

**This is the same IPv6-privacy-extensions failure mode already found and fixed on Pi-hole and
OctoPrint** (finding 21, 2026-09-11, see `changelog.md` and `README.md`'s hard-won lessons) —
except, per that same changelog entry, **Home Assistant was explicitly never checked or fixed
at the time**: "(Home Assistant not checked or fixed — no `services2users`-triggering traffic
has been observed from it either way, so whether `ha-v6` has the same problem is still
unknown)". `firewall.md`'s IPv6 section has been asserting since then that privacy extensions
were disabled on all three hosts including HA — that claim was never actually true for HA,
just never contradicted by observed traffic until today's new rule started logging its plain-HTTP
attempts. (Corrected in `firewall.md` alongside this finding.)

**Practical impact:** `http-outbound-v6`'s HTTP exception doesn't work for HA at all right now
— every attempt still gets dropped, IPv6 side only (IPv4's `http-outbound` list uses HA's
static `192.168.20.60` and is unaffected). `services2users` (HA -> printer CUPS/631, HA ->
Samsung TV/8002 over IPv6, scoped to `ha-v6`) is likely broken the same way, but genuinely
unconfirmed — no traffic on that path has ever been logged either way, and both those paths
also work over IPv4 regardless, so nobody would have noticed a silent IPv6-only failure there.

**Next step:** apply the same fix already used for Pi-hole and OctoPrint (`changelog.md`'s
finding 21 entry has the exact commands: a `sysctl.d` drop-in for `use_tempaddr=0` and
`addr_gen_mode=0`, plus the `nmcli ipv6.ip6-privacy 0 ipv6.addr-gen-mode eui64` belt-and-suspenders
since NetworkManager can override the sysctl on reconnect, then reboot) — but that recipe
assumes a generic Debian-like host with `nmcli`/`sysctl.d`, and it's not established anywhere in
this repo whether Home Assistant runs as HAOS (which manages its own network stack differently,
likely without direct `sysctl`/`nmcli` access) or Supervised-on-generic-Linux. Confirm which
before drafting host-side commands. Verify the same way as the other two hosts: `ip -6 addr
show scope global` (or the HAOS equivalent) shows the precomputed EUI-64 address, then a real
functional retest (HTTP exception working, or a `services2users` port reachable over IPv6).

### mikrotik4 has never been reviewed

`192.168.10.4` has been unreachable on port 22 on every dump run through 2026-09-08, so no
finding in this document or in the changelog says anything about its configuration.

When it returns to service it needs the full pass the switches got — input-chain firewall,
FTP/Telnet off, `admin` bound to the LAN, resolver closed, defconf debris cleared, static
address, SSH hardened, and a proven MAC-Telnet recovery path. It is already in the `mgmt`
address list on every device and holds a `.4` reservation on mikrotik1, so it will come up
reachable.

Nothing else is open. mikrotik2 and mikrotik3 are clear; mikrotik1 has findings 21-22 above
(19, 20, 23, 24 all closed — see [changelog.md](changelog.md)).

**Two minor things noticed 2026-09-10 while regenerating `firewall.md` against a fresh
dump, not investigated further — neither looked urgent enough to chase down mid-pass:**
`cpu-load: 100%` in that snapshot (vs. the ~30-50% this document has previously measured under
real load) — most likely just the dump script's own burst of SSH commands rather than a
sustained condition, but worth a second look if it recurs on a quieter dump. And `route_BFD`
reappearing in `/ip/service/print` as a dynamic listener, which the original finding 11 closure
(round 1) recorded as gone once OSPF/BGP/BFD config was removed — `dump-configs.sh` doesn't
currently collect `/routing/bfd/configuration/print`, so this couldn't be re-verified from the
dump alone; worth a live check next time (`/routing/bfd/configuration/print` should still be
empty) rather than assuming either way.

## The architectural item: VLAN segmentation

See [vlan.md](vlan.md) for the design, decisions and migration plan, and
[changelog.md](changelog.md) for the full history. What follows is future hardware work the
VLAN migration didn't need and hasn't touched.

### Hardware for the edge role

**Recommendation (2026-09-04): RB5009UG+S+IN.**

Quad-core ARM64 Cortex-A72 at 1.4 GHz, 1 GB RAM, 7x gigabit plus a 2.5G SFP+ cage,
passively cooled.

Reasoning, in the order the constraints actually bind:

1. **QoS is the binding constraint, not raw throughput.** Shaped traffic cannot be
   fasttracked (see [qos.md](qos.md)), so it must be forwarded in the CPU path. The RB2011
   already sits at 30-50% CPU for 111 Mbps *with* fasttrack. The RB5009 has headroom to run
   CAKE at gigabit without it. Nothing cheaper does.
2. **Silent.** Passive cooling. CCR2004-class hardware has fans, and this lives in a home.
3. **Right-sized uplink.** Measured reality is 842 Mbps up on gigabit ports; the whole LAN
   is gigabit and no known device has a faster NIC. 2.5G is 2.5x headroom over anything
   currently usable, and the SFP+ cage takes an ONT module if the handoff is fibre.
4. **Fixes IPv6 properly.** At the edge the full /56 is delegated directly, NAT66 disappears,
   and the measured ~25% IPv6 penalty goes with it.
5. **No onboard WiFi, correctly.** Wireless is CAPsMAN-managed from separate APs.

**Accepted limitation:** if the replacement Swisscom box delivers genuine 10 Gbps and more
than 2.5 Gbps is ever wanted, this caps it. That would mean CCR2004 class — roughly double
the price plus fan noise. Judged a good trade given current usage is under 1 Gbps.

### Redeployment: nothing is retired

| Device | New role |
|---|---|
| RB5009 (new) | edge router |
| CRS125-24G (mikrotik2) | main switch — real switch chip, hardware VLAN support, right device to carry tagged VLANs at line rate |
| RB2011UiAS (current main) | media switch by the TV, or CAPsMAN-only box |
| RB750Gr3 (mikrotik3) | office switch, unchanged |

This likely removes the need to buy the CSS610-8G-2S+IN suggested earlier for the media
segment — the RB2011 can fill that role.

### Physical wiring: patch panel and room runs

Recorded 2026-09-06, not yet acted on. mikrotik1 and mikrotik2 are co-located. A patch panel
routes the cable run to each room in the house, and every room currently lands on mikrotik2.
Rewiring at the patch panel is trivial — it is just re-terminating which room lands on which
switch port — so a room could be moved to land on mikrotik1 directly instead, removing one hop
(mikrotik2) for that room's traffic.

Worth revisiting once the edge role moves to the RB5009 and mikrotik2 becomes the main switch
(see redeployment table above) — the right answer depends on which device ends up carrying the
switch chip with hardware VLAN offload, not on which one happens to be reachable from the
patch panel today.

### Office switch: PoE requirements

Recorded 2026-09-05. mikrotik3 (RB750Gr3) has no PoE-out, and both planned access points —
the cAP XL ac and the SXTsq Lite2 — will hang off it. Injectors work in the interim; the
replacement should remove them.

Requirements, in order of how badly getting them wrong hurts:

1. **Passive PoE-out, not only 802.3af/at.** The SXTsq Lite2 is passive-only, 10-30 V, with
   no 802.3af/at support. A switch that negotiates 802.3at and nothing else will not power
   it, which defeats the purpose. This rules out the otherwise attractive CSS610-8P-2S+IN.
   **Verify against the SXTsq label before ordering** — the whole choice hangs on it.
2. **It must not put voltage on ports serving non-PoE devices.** A desktop and two laptops
   share this switch with two APs. Passive PoE energises the pairs unconditionally — there is
   no negotiation and no detection — so a laptop in a passive-PoE port can have its NIC
   damaged. PoE-out must be per-port controllable, set explicitly rather than left at a
   default, and the AP ports labelled physically:

   ```
   /interface/ethernet/poe/set [find] poe-out=off
   /interface/ethernet/poe/set [find name=etherX] poe-out=auto-on   # AP ports only
   /interface/ethernet/poe/print
   ```

3. **At least 8 ports.** Six are already spoken for — uplink to mikrotik2, desktop, two
   laptops, two APs. A switch with no spare ports acquires an unmanaged switch hanging off it
   within a year.

**Candidate: CRS112-8P-4S-IN** — 8×GE with PoE-out on every port, 4×SFP, own PSU, fanless,
RouterOS, and it supports passive as well as 802.3af/at. Cheaper alternative: hEX PoE
(RB960PGS), definitely passive, but only 5 copper ports, so the uplink would have to move to
SFP and there would be no spares.

Power draw is not a constraint either way: the SXTsq is around 4 W and the cAP maybe 7-11 W.

### Probably a bigger constraint than the router: the wireless

Both APs are **2.4 GHz 802.11n only**, there is no 5 GHz anywhere on this network, and as of
2026-09-05 both radios were found sitting on the **same channel** (2452, 40 MHz). That is
very likely a larger day-to-day limitation than anything about the router.

A cAP XL ac is already available and unused, which supersedes the earlier suggestion here to
buy cAP ax or hAP ax³ units.

Full analysis, the channel plan, and the mikrotik4 garden-AP build are in [wifi.md](wifi.md).

### Replacement Swisscom box — arrived and installed 2026-09-11

Ordered 2026-09-04, 10G-capable per spec. Of the three things flagged to check when it
arrived:

- **Port speeds it actually offers.** Not yet directly confirmed. Doesn't matter yet either
  way: mikrotik1 (RB2011, GigE ports) still caps WAN throughput near 1 Gbps regardless of what
  the box offers, until the RB5009 edge migration below actually happens. Re-baseline
  throughput (`scripts/measure-bufferbloat.sh`, see `performance.md`) once that's done, not
  before.
- **Whether it supports bridge or modem mode — no.** Checked directly in the box's admin UI.
  mikrotik1 is configured as its DMZ host instead (full port-forwarding to one LAN device),
  which is why the edge migration below still needs its own WAN-facing DHCP client rather than
  inheriting a public IP directly.
- **Whether it can forward port 80 inward.** Not yet directly tested, but plausible now: DMZ
  hosting forwards every port to mikrotik1, port 80 included. Worth testing explicitly before
  revisiting the TLS question below — DMZ and "forwards port 80 specifically" aren't quite the
  same claim.

The swap itself broke two things — a hardcoded WAN IP in the HA HTTPS NAT rule, and the
IPv6 delegation needing to be re-established with the box's PD setting explicitly enabled and
mikrotik1's DHCPv6 client force-released — both found and fixed the same day; full account in
`changelog.md`.

### The TLS question, deliberately parked

Guillaume prefers Let's Encrypt certificates over self-signed, and wants a solution the
router sustains on its own with no dependency on another host. RouterOS's built-in ACME
(`/certificate/enable-ssl-certificate`) supports **HTTP-01 only**, which needs port 80
reachable from the internet through the Internet-Box — the exposure closed in finding 5.
DNS-01 would avoid that but requires an external ACME client, which conflicts with the
self-contained requirement. `ledcom.fr` is at an EU registrar (Gandi/OVH class).

**Accepted in the meantime:** plaintext management traffic *within the LAN* is an accepted
risk. `www` on 80 stays enabled and in use, and the API on 8728 stays plaintext. Do not
re-raise either as a finding.

If the edge role moves to an RB5009 and the Internet-Box goes to bridge mode, HTTP-01
becomes available on the router itself and this unblocks without an external host — worth
revisiting then, not before.

## Closed findings

In [changelog.md](changelog.md), with the verifying output for each.

# Config review — home MikroTik network

Covers every MikroTik on the network. Round 1 reviewed 2026-09-03, round 2 from 2026-09-04,
re-verified 2026-09-05 against [dumps/](dumps/), collected with
[dump-configs.sh](scripts/dump-configs.sh). **Addresses below updated 2026-09-07** after the VLAN
segmentation renumber (Phases 0-2, see [vlan.md](vlan.md) / [changelog.md](changelog.md)) —
everything else in this document is a historical record from the original review dates and
intentionally still shows the addresses as they were *at the time each finding was made*.

| Device | Model | Address | Role |
|---|---|---|---|
| mikrotik1 | RB2011UiAS-2HnD — 128 MB, 600 MHz single-core MIPS | `192.168.10.1/24`; `ether1` dynamic from the Internet-Box | edge router, CAPsMAN manager |
| mikrotik2 | CRS125-24G-1S-2HnD | `192.168.10.2/24` static on `bridge-local` | L2 bridge, 24 ports + SFP; CAPsMAN CAP (wlan1) |
| mikrotik3 | RB750Gr3 (hEX) — 256 MB, 880 MHz quad-core | `192.168.10.3/24` static on `bridge` | L2 bridge, 5 ports |
| mikrotik4 | — | `192.168.10.4` reserved, offline | being returned to service |

All three reachable devices run RouterOS 7.24.2, current as of 2026-09-05. `bridge-fon`
(`192.168.2.0/24`) no longer exists — removed in Phase 0 of the VLAN work.

**Open findings only.** A finding leaves this document once it has been fixed **and**
verified against device output — never when it is reported done. Closed items move to
[changelog.md](changelog.md) with the output that verified them, so they are not re-raised.

Numbering is stable and never reused. Main-router findings are numbered `<n>`, switch
findings `S<n>`, so the two sets never collide.

## Open findings

### 8. DNS can bypass Pi-hole — deferred into the VLAN work

`Home can connect everywhere` lets any `bridge-main` host reach any external resolver on
port 53, so a device with hardcoded DNS escapes Pi-hole at `192.168.1.40`.

**Accepted for now** (2026-09-04): acceptable for most hosts, and a blanket dst-nat redirect
is the wrong shape for the problem. The real answer is segmentation.

Stated intent for the IoT VLAN: **no internet access of any kind**. Local traffic only —
DNS, and reaching internal services such as an MQTT broker. That is strictly stronger than
redirecting port 53, and makes the redirect unnecessary for the devices that motivated it.

Carried into [the VLAN work](#the-architectural-item-vlan-segmentation). Do not implement
the dst-nat redirect separately.

A second, IPv6-specific instance of this same class of bypass (RDNSS advertising the ISP's own
DNS server instead of Pi-hole) was found and fixed 2026-09-07 — see
[changelog.md](changelog.md#ipv6-rdnss-was-leaking-the-isps-own-dns-server-bypassing-pi-hole-2026-09-07)
and [ipv6.md](ipv6.md#resolved-rdnss-was-leaking-the-isps-own-dns-server-bypassing-pi-hole).

### mikrotik4 has never been reviewed

`192.168.1.4` was unreachable on port 22 on every dump run through 2026-09-05 17:13, so no
finding in this document or in the changelog says anything about its configuration.

When it returns to service it needs the full pass the switches got — input-chain firewall,
FTP/Telnet off, `admin` bound to the LAN, resolver closed, defconf debris cleared, static
address, SSH hardened, and a proven MAC-Telnet recovery path. It is already in the `mgmt`
address list on every device and holds a `.4` reservation on mikrotik1, so it will come up
reachable.

Nothing else is open. mikrotik1, mikrotik2 and mikrotik3 are clear.

## The architectural item: VLAN segmentation

**Designed 2026-09-06 — see [vlan.md](vlan.md)** for the decisions, the policy matrix and the
phased migration plan. What follows is the context that led there.

Every IoT device — Tasmota, ESPHome, OctoPrint, the Hombli fan — shares one flat L2 segment
with the desktop and the routers' management planes. `bridge-fon` is correctly isolated but
is wired-only and serves a different purpose.

Finding 8 is a symptom of that flat segment, and the `mgmt` restriction that closed finding 2
does not reach IPv6 at all: the IPv6 input chain accepts `in-interface=bridge-main`
wholesale, and narrowing it by source address is impractical because SLAAC privacy addresses
rotate. Only segmentation closes that.

### Stated intent (2026-09-04)

- Roughly **three VLANs**, exact split not yet decided.
- **Media segment, wired.** The TV should move off the Internet-Box WiFi to wired, reached
  through the MikroTik, with an additional MikroTik switch near the TV serving the TV, the
  amplifier, and the games console.
- **IoT VLAN gets no internet access at all.** Local traffic only: DNS, and internal
  services such as an MQTT broker. This supersedes the Pi-hole DNS-redirect idea (finding
  8) — a segment with no route out cannot bypass anything.
- The **Fonera** (`192.168.1.101`) stays on the main LAN for now, to be revisited here.
- `192.168.1.4` is a MikroTik being returned to service; already added to `mgmt`.

### The Swisscom TV constraint — obsolete as of 2026-09-06

**Resolved by fact, not by work.** Guillaume no longer uses the Swisscom TV box. The TV is a
wireless client on the `LEDCOM` SSID and always was, on this network rather than the
Internet-Box; the earlier note recorded a setup that had already been retired.

There is therefore no IPTV multicast to carry, and the IGMP proxy requirement is withdrawn.
This was previously recorded as "the single hardest part of the plan", to be proven before any
cabling or VLAN work depended on it, and as a problem that got *harder* under the RB5009 edge
migration because the MikroTik would have had to handle the Swisscom multicast join on the WAN
side. All of that is now moot.

Two consequences worth carrying forward: moving the TV to a wired port is now an ordinary
cabling job with no protocol risk, and the edge migration loses its most awkward unknown.

### What the switches bring to the design

**mikrotik2 (CRS125)** has a proper switch chip with hardware VLAN support — the right
device to carry tagged VLANs at line rate, and a better candidate for the media segment than
the RB2011. Note that `ether1-gateway` and `sfp1-gateway` are bridge ports with `hw=no`, so
they are already outside hardware switching; worth revisiting when VLANs are designed.

**mikrotik3 (RB750Gr3)** supports bridge VLAN filtering with hardware offload on its switch
chip. Only `ether1` (uplink) and `ether3` currently have link.

Neither switch needs IPv6 — both have `disable-ipv6=yes`, correct for an L2 bridge, and it
should stay that way.

Both are now clear of defconf DHCP debris (S7 in the changelog), which removes a trap this
work would otherwise have sprung: mikrotik2 carried a dormant DHCP server on
`192.168.1.0/24` held back only by its interface being a bridge slave — exactly what a VLAN
restructure changes.

**Rogue RA source — root cause found and fixed 2026-09-07.** The RA source itself is Home
Assistant (`192.168.1.60`, MAC `D8:3A:DD:31:E0:59`) — found by forcing NDP resolution on the
desktop (`ping6` to the RA's link-local source, then `ip -6 neigh show`, which flagged it
`router`) — but it is not a bug on Home Assistant's side. `wpan0`'s own address on that host
matches one of the two advertised prefixes exactly, identifying it as an **OpenThread Border
Router** doing its normal job: Thread's Border Routing feature is *designed* to advertise the
Thread mesh's prefix (plus a companion on-link ULA) onto the regular LAN via RA, so Matter/
Thread devices are reachable. Nothing to disable here.

The real defect was on mikrotik1: its IPv6 configuration (address, RA, firewall) had never
been moved off `bridge-main` onto `vlan-users` when the VLAN 10 migration moved IPv4 — IPv6
was simply out of scope for that work and got left behind, undetected because a
VLAN-tagging bug elsewhere let wireless clients keep reaching `bridge-main`'s RA anyway. Once
that other bug was fixed, wireless could reach `vlan-users` but no longer `bridge-main`,
leaving Home Assistant's Thread RA as the *only* one visible to wireless clients — which is
what made this rogue-RA issue (already present, and already noted here, on *wired* clients
days earlier) fully visible for the first time. Full diagnosis and fix are in
[ipv6.md](ipv6.md)'s "Migrated onto `vlan-users`" section — mikrotik1's IPv6 address, ND
config and firewall rules now all live on `vlan-users`, verified by the desktop picking up the
real `2a02:1210:680f:c40c::/64` prefix over WiFi and a successful `ping6` to a real host.

Moved to [changelog.md](changelog.md) once verified stable for a few days — kept here for now
since it's recent enough that a recurrence would be useful to catch quickly.

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

### Before ordering

A replacement Swisscom box was ordered 2026-09-04. Check three things when it arrives:

- **Port speeds it actually offers.** Determines whether 2.5G is a real constraint.
- **Whether it supports bridge or modem mode.** If it can bridge, the edge migration is much
  simpler, and the Swisscom TV multicast problem (above) may resolve differently than
  assumed — potentially removing the IGMP proxy requirement entirely.
- **Whether it can forward port 80 inward.** That is what RouterOS's built-in ACME needs for
  HTTP-01, and it is the only thing standing between the current state and Let's Encrypt
  certificates without an external host. See the TLS note below.

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

### Risk

All three bridges currently have `vlan-filtering=no`. Enabling bridge VLAN filtering is the
most reliable way to lock yourself out of a MikroTik: a port that ends up without the right
PVID stops carrying management traffic instantly. Plan this with the DB9 serial console
attached, not over SSH, and stage it with `Ctrl+X` safe mode.

MAC-Telnet is the proven fallback and now works to every reachable device — but it is a
fallback, not a plan. It failed to reach mikrotik3 until S16 was fixed, and nobody noticed
until it was checked deliberately.

## Closed findings

In [changelog.md](changelog.md), with the verifying output for each.

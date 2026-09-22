# Throughput investigation

Open, paused 2026-09-22 on a missing cable. First measurements taken 2026-09-04; see
[Measurements](#measurements) for results and the current leading hypothesis. **Next concrete
step, once a long-enough known-good Cat5e/6 cable is on hand:** the direct desktop-to-box test
in the "Direct-to-box test attempted" section below — the last attempt was confounded by an
unexplained 100M link negotiation and needs redoing at a real 1G link to be decisive.

## The observation

speedtest.net from the desktop (`192.168.1.90`, wired on `eno2`):

| | Measured | Subscription |
|---|---|---|
| Download | 181.14 Mbps | 10 Gbps |
| Upload | 842.43 Mbps | 10 Gbps |

Both are far below the line rate, but the **asymmetry is the interesting part**: download is
4.6× slower than upload. That is backwards from every common failure mode. A CPU ceiling, a
duplex mismatch, or a saturated link would throttle both directions roughly equally, and
consumer lines are usually faster down than up. Something is specifically penalising the
download path.

181 Mbps also rules out the obvious culprits: it is well above a 100 Mbps link cap (~94
Mbps) and nowhere near a gigabit ceiling.

## Measurements

**2026-09-04, single-stream curl to `https://fsn1-speed.hetzner.com/1GB.bin`** from the
desktop:

| Protocol | Throughput | Router CPU during transfer |
|---|---|---|
| IPv4 | 111.1 Mbps | 30-50% |
| IPv6 | 82.8 Mbps | 50-70% |

Neither saturated the CPU. The earlier `speed.cloudflare.com/__down?bytes=` attempt returned
1 byte and produced meaningless numbers — do not reuse that URL.

The gap between these figures and speedtest.net's 181 Mbps is parallel streams versus a
single stream, which is expected and not diagnostic.

### Confirmed: the IPv6 path costs ~25% and much more CPU

IPv6 is 25% slower at roughly 1.5× the CPU. This matches the predicted cause exactly: no
IPv6 fasttrack (`ipv6-fasttrack-active: no`), so every packet traverses the full firewall
chain plus the NAT66 masquerade in the CPU path.

Real, worth fixing, but **not the main bottleneck** — it does not explain why download is
capped far below the line rate on both protocols.

### The MikroTik is probably not the bottleneck

speedtest.net measured **842 Mbps upload** across the same physical path — desktop →
switch → main router → Internet-Box — through the same CPU. A router that sustains 842 Mbps
in one direction is not the reason the other direction manages 111. Combined with the CPU
never saturating, this points upstream.

**Hypothesis 2 (RB2011 CPU ceiling) is largely ruled out** as the primary cause. Hypotheses
4 and 5 (Internet-Box, Swisscom provisioning) move to the front.

### Next test, decisive

Connect a host **directly to the Internet-Box** and repeat the same curl.

- Still ~110 Mbps → the MikroTik is exonerated; the cause is the Internet-Box or Swisscom
  provisioning, and no router purchase changes anything.
- Much faster → the MikroTik is implicated despite the 842 Mbps upload, and the
  directional asymmetry needs explaining.

Also check the Internet-Box UI for reported line rate and negotiated port speed. A 1 Gbps
port on a 10 Gbps subscription would settle it.

Still to capture on the router, since 30-50% CPU for 111 Mbps is higher than fasttrack
should allow:

```
/ip/firewall/filter/print stats where action=fasttrack-connection
/interface/print stats where name=ether1
/interface/ethernet/print detail where name=ether1
```

### Router-side counters are clean

```
fasttrack-connection   441 725 344 bytes / 1 271 343 packets
ether1  rx-drop 0  tx-drop 0  tx-queue-drop 0  rx-error 0  tx-error 0
```

Fasttrack is engaging. `ether1` shows no errors, no drops, no queue drops. The router is
not discarding or mangling traffic.

### The Internet-Box has gigabit ports

Reported 2026-09-04. This explains the **ceiling**: 842 Mbps upload is essentially a
saturated gigabit link, so the 10 Gbps subscription cannot be reached through this box at
all regardless of anything else.

It does **not** explain the download figure. The same gigabit path that carries 842 Mbps
upward delivers 181 Mbps downward. The port limit and the asymmetry are two separate
problems.

### Queues and mangle ruled out (2026-09-04)

Checked on all three devices. No simple queues, no queue trees, every interface on
`only-hardware-queue`, all queue types at defaults. Mangle is empty except RouterOS's own
dynamic fasttrack counter rules on the main router.

### The asymmetry reproduced cleanly, 2026-09-05

The bufferbloat run (see [qos.md](qos.md)) measured both directions back-to-back on the same
host, same script, same minute, reading NIC byte counters rather than trusting a web service:

```
download phase   169.6 Mbps down
upload phase     565.3 Mbps up
```

This is the cleanest evidence yet that the asymmetry is real and not an artefact of
speedtest.net. Download reaches roughly **30% of upload** on an identical path through the
same router and the same Internet-Box port, using four parallel streams in both directions.

It also rules out one remaining explanation: with 565 Mbps demonstrated upward through the
RB2011, no plausible CPU or forwarding limit in that router explains a 170 Mbps ceiling
downward. Whatever caps the download sits upstream of it.

### Conclusion so far: the MikroTik is not the cause

Every device-side candidate has been eliminated:

| Candidate | Result |
|---|---|
| Fasttrack not engaging | Ruled out — 441 MB / 1.27 M packets offloaded |
| Link errors or renegotiation | Ruled out — zero rx/tx errors and drops on `ether1` |
| CPU ceiling | Ruled out — never saturates; 842 Mbps upload through the same CPU |
| Queues or mangle | Ruled out — none configured on any of the three devices |
| IPv6 fasttrack / NAT66 | Real, but only ~25%; affects IPv6 alone |

Nothing in the MikroTik configuration limits download to a fifth of upload.

**Two separate problems remain, and they should not be conflated:**

1. **The Internet-Box has gigabit ports.** This caps everything at ~940 Mbps regardless of
   the 10 Gbps subscription. A hardware or subscription conversation with Swisscom, not
   something any configuration change addresses.
2. **Download is limited to roughly a fifth of upload.** Unexplained. Not the MikroTik.

### Swisscom's line itself ruled out (2026-09-22)

The replacement box (installed 2026-09-11) has a built-in speedtest function, run **on the box
itself**:

| | Measured |
|---|---|
| Download | 8108.90 Mbps |
| Upload | 7722.35 Mbps |

Close to line rate both ways (81%/77% of nominal 10 Gbps, the usual real-world overhead) and,
critically, **roughly symmetric** — a ~5% gap, nothing like the ~5x asymmetry seen through
mikrotik1. This tests the box's own WAN uplink to Swisscom's backbone, not anything downstream
of it, so it rules out exactly one thing: Swisscom's line/provisioning is not the cause. It
says nothing about the box's own LAN-side forwarding, the box-to-mikrotik1 link,
mikrotik1/mikrotik2, or the desktop — none of which this test touches. **Not the same thing as
the "remaining test" below**, which is still outstanding.

(The box's web UI is reachable after all — a false alarm on Guillaume's end, not a real
problem — so the negotiated-port-speed/sync-rate check mentioned below is now actionable.)

Box's physical ports, for reference: 1×10G Ethernet (copper), 4×1G Ethernet, 1×1G SFP (not
SFP+ — this port itself tops out at 1G regardless of module).

**Correction (2026-09-22): mikrotik1 is actually plugged into the box's 10G port**, not one of
the 4×1G ports as this document previously assumed without checking — that assumption was
wrong and has been removed. Functionally this shouldn't matter: mikrotik1 (RB2011) has no port
faster than 1G, so the link should simply negotiate down to 1000BASE-T regardless of which box
port it's on, and the ~940 Mbps ceiling in either direction is still explained by mikrotik1's
own hardware limit. But worth actually confirming on the box's UI (now reachable) what that
port negotiated to — speed and duplex — rather than assuming a clean autonegotiation, given a
10G-capable port mismatched against a 1G-only partner is exactly the kind of pairing where a
negotiation quirk would be easy to miss. This does **not** explain the asymmetry (why download
sits at ~1/5 of upload, well below even that gigabit cap) — that remains the open question
below.

### Direct-to-box test attempted (2026-09-22) — confounded by a 100M link, not yet decisive

Desktop plugged directly into the Internet-Box (multiple cable segments in the path, no
switch/router). Result:

| | Measured |
|---|---|
| Link negotiated | **100M**, not 1G |
| Download | 92.99 Mbps |
| Upload | 93.47 Mbps |

93/93 Mbps is almost exactly a 100M link's practical ceiling (~94 Mbps, same figure already
cited earlier in this document) — fully explained by the negotiated speed alone, no asymmetry
needed to account for it. But that's exactly the problem: **a link capped at 100M has no
headroom left in either direction to reveal a 5x asymmetry even if one exists underneath it.**
Symmetric-but-slow here doesn't confirm the asymmetry is fixed off this path — it means this
particular test is inconclusive until it runs at the link's actual capability.

**Not yet identified: why this direct path negotiated to 100M instead of 1G.** Something among
the "multiple cables in the path" — a marginal cable, a bad connector, an old Cat5 (not
5e/6) segment — is the leading suspect. Next step: get down to a single known-good Cat5e/6
cable directly from the desktop to the box, confirm the link renegotiates to 1G, and repeat
the speed test at that point. If it still won't negotiate past 100M with a single good cable,
that implicates the box's port or the desktop's NIC itself rather than the cabling.

**Paused 2026-09-22 — no cable currently long enough on hand for a single-run desktop-to-box
test.** Pick back up once one's available; this is the next concrete step, not a dead end.

Worth trying more than one device/NIC on the LAN side too, once a clean 1G link is achieved —
the desktop's own NIC/driver/OS network stack has never actually been checked as a candidate,
and is a real gap in this investigation so far.

Also worth checking in the Internet-Box UI (reachable, per above): reported line rate,
negotiated WAN port speed, and whether any traffic shaping or QoS is enabled on it — including
specifically which of its ports mikrotik1 is plugged into and its negotiated speed, to confirm
the 1G-port assumption above rather than just infer it.

Swisscom support is no longer the first move — the box's own speedtest already shows their
line delivering full line rate. A support ticket only makes sense if the remaining test above
also comes back clean and nothing on the LAN side explains it either.

### Internal `/tool bandwidth-test` between mikrotik1 and mikrotik2 (2026-09-22) — CPU-bound, not usable evidence

Tried as a way to isolate the LAN trunk (mikrotik1↔mikrotik2) independent of the desktop's own
NIC/OS, without needing the missing cable. Two runs, both `duration=10s`, `direction=both`,
`address=192.168.10.2` (mikrotik2) from mikrotik1:

| Protocol | tx | rx | lost packets | local CPU | remote CPU |
|---|---|---|---|---|---|
| TCP | 36.7 Mbps | 33.7 Mbps | — | 100% | 84% |
| UDP | 163.5 Mbps | 66.2 Mbps | 771 | 100% | 89% |

**Not usable as evidence either way** — `local-cpu-load: 100%` on both runs, and the tool's own
banner warns about exactly this ("results can be limited by cpu... might not be representative
of forwarding performance"). Consistent with everything else already known: the earlier
bufferbloat measurement pushed 565 Mbps+ *upload* through this same trunk using real traffic,
10-15x higher than either synthetic run here — real forwarded traffic gets RouterOS's
fastpath/hardware acceleration, `bandwidth-test`'s software packet generation on this
generation of hardware (RB2011/CRS125) does not. This tool mostly measures "how fast can the
CPU synthesize packets" on this hardware, not link capacity.

**One thing worth flagging, not concluding from:** UDP's tx/rx gap (163.5 vs 66.2, ~2.5x) is
much larger than TCP's (36.7 vs 33.7, ~9%), and the direction of the gap — mikrotik1
transmitting faster than it receives — echoes the shape of the original desktop-measured
asymmetry (upload faster than download), even though this is a completely different path
(LAN-internal trunk, not the WAN link). Could be a genuine RX-path weakness specific to
mikrotik1, or could just be an artifact of how the CPU-bound synthetic generator happens to
split work between its tx and rx threads — the CPU-saturation caveat above means this can't be
told apart from here. Not chasing further; noted for the record in case it rhymes with
whatever the direct-cable test eventually finds.

`protocol=udp` was tried specifically because it has less per-packet overhead than TCP
(no connection/ack tracking) and did get further before the CPU ceiling (163.5 vs 36.7 Mbps
tx) — confirms the CPU-bound theory rather than adding a new angle.

## What the answer changes

Now that Swisscom's line itself is ruled out, "upstream of the MikroTik" narrows to one thing:
the box's own LAN-side forwarding. If the direct-to-Internet-Box test still shows ~180 Mbps
down, that's where the fault is — new router hardware fixes nothing, and this becomes a
Swisscom support conversation about the box itself (not the line). If it instead returns close
to line rate, that reopens mikrotik1/mikrotik2/the cabling between them as suspects despite the
evidence above, and feeds into the hardware decision recorded in
[config-review.md](config-review.md#hardware-for-the-edge-role) — specifically, whatever gets
bought needs to be cleared of this specific asymmetry before or as part of the swap, not just
assumed fixed by having a faster WAN port.

Worth measuring before spending anything.

## Also worth measuring while investigating

Whether anything on the LAN can even use more than 1 Gbps — the desktop's NIC, and whether
storage at either end could feed a 10 Gbps flow. A 10 Gbps subscription is not the same as
10 Gbps of usable need, and buying for the subscription rather than the traffic is the
expensive mistake here.

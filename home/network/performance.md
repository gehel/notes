# Throughput investigation

Open. First measurements taken 2026-09-04; see [Measurements](#measurements) for
results and the current leading hypothesis.

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

### Remaining test

Connect a host directly to the Internet-Box and repeat:

```
curl -4 -s -o /dev/null -w '%{speed_download}' https://fsn1-speed.hetzner.com/1GB.bin \
  | awk '{printf "%.1f Mbps\n", $1*8/1000000}'
```

Given everything above, expect ~180 Mbps — which would place the fault in the Internet-Box
or Swisscom's provisioning. If it instead returns ~940 Mbps, something about the MikroTik
path is wrong in a way none of the counters reveal, and that would be genuinely surprising.

Also worth checking in the Internet-Box UI: reported line rate, negotiated WAN port speed,
and whether any traffic shaping or QoS is enabled on it.

Then: Swisscom support. A 10 Gbps subscription terminating on a gigabit box that delivers
181 Mbps down and 842 Mbps up is worth a support ticket regardless of what the direct test
shows.

## Hypotheses (original list, 2026-09-04)

Kept for reference. The measurements above have since demoted 1 and 2 and promoted 4 and 5.
The `speed.cloudflare.com` URLs quoted under hypothesis 1 do not work — use the Hetzner
endpoint from the Measurements section instead.

### 1. IPv6 path has no fasttrack

Strongest candidate. `/ipv6/settings/print` reports `ipv6-fasttrack-active: no`, and there
is no IPv6 fasttrack rule. Every IPv6 packet therefore traverses the full firewall chain
**plus** the NAT66 masquerade added as the Internet-Box workaround (see [ipv6.md](ipv6.md)),
entirely in the CPU path on a 600 MHz single-core MIPS.

IPv4 by contrast has `action=fasttrack-connection` at the top of the forward chain and is
largely offloaded.

speedtest.net will prefer IPv6 when it is available, and the desktop holds a working global
address. So the measured figures may be an IPv6 result while the IPv4 path is fine.

**Tested and confirmed** — 25% slower at 1.5x the CPU. Real, but secondary. The fix is
either an IPv6 fasttrack rule or, better, removing the NAT66 requirement entirely by moving
the MikroTik to the edge.

### 2. RB2011 CPU ceiling

`cpu-load` was 23% at rest on a 600 MHz single core, which is already high. The board is
realistically good for a few hundred Mbps routed with fasttrack, well under the line rate
regardless.

**Test:** watch the CPU during a transfer.

```
/system/resource/print          # repeatedly, during a speedtest
/tool/profile duration=10s      # shows which process is burning CPU
```

If CPU pegs at 100% during download but not upload, that points back to hypothesis 1 —
asymmetric CPU cost implies asymmetric processing, which the missing IPv6 fasttrack would
explain.

### 3. Link negotiation somewhere in the path

The path is desktop → (mikrotik2 or mikrotik3) → main router `ether1` → Internet-Box.

```
/interface/ethernet/print detail    # on each device: check rate and full-duplex
/interface/print stats              # look for rx-error, tx-error, rx-drop
```

181 Mbps does not match any standard link speed, so this is unlikely to be the whole story
— but errors or a renegotiating link could produce odd numbers.

### 4. The Internet-Box is the bottleneck

Everything currently routes through it, and it is also doing NAT. Its own hardware may not
sustain 10 Gbps, and the double-NAT adds a second translation step.

**Test:** plug a laptop directly into the Internet-Box and run the same speedtest. If it is
also slow, the MikroTik is exonerated and the problem is upstream of it.

### 5. Swisscom provisioning

If a direct test against the Internet-Box is also far below 10 Gbps, the subscription may
not be provisioned as expected, or the handoff may not be the 10 Gbps port.

## What the answer changes

If it is hypothesis 1 or 2, this feeds directly into the hardware decision recorded in
[config-review.md](config-review.md#hardware-for-the-edge-role): a 10 Gbps subscription that
the RB2011 cannot approach is an argument for moving the edge role sooner, and for choosing
a device sized to the line rather than to current traffic.

If it is hypothesis 4 or 5, new router hardware fixes nothing and the conversation is with
Swisscom instead.

Worth measuring before spending anything.

## Also worth measuring while investigating

Whether anything on the LAN can even use more than 1 Gbps — the desktop's NIC, and whether
storage at either end could feed a 10 Gbps flow. A 10 Gbps subscription is not the same as
10 Gbps of usable need, and buying for the subscription rather than the traffic is the
expensive mistake here.

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

## What the answer changes

If the direct-to-Internet-Box test still shows ~180 Mbps down, the fault is upstream of the
MikroTik entirely — new router hardware fixes nothing, and the conversation is with Swisscom.
If it instead returns close to line rate, that reopens the router as a suspect despite the
evidence above, and feeds into the hardware decision recorded in
[config-review.md](config-review.md#hardware-for-the-edge-role).

Worth measuring before spending anything.

## Also worth measuring while investigating

Whether anything on the LAN can even use more than 1 Gbps — the desktop's NIC, and whether
storage at either end could feed a 10 Gbps flow. A 10 Gbps subscription is not the same as
10 Gbps of usable need, and buying for the subscription rather than the traffic is the
expensive mistake here.

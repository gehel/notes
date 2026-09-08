# QoS: prioritising real-time traffic

Requested 2026-09-04. Not started.

## Goal

Conference calls (Google Meet, Zoom, Teams) should stay usable when something else on the
network is downloading hard — game updates, OS updates, backups, large file transfers.

## Status: measured 2026-09-05 — there is no bufferbloat to fix

**The premise of this document did not survive measurement.** Latency under load was probed
at three hops simultaneously with [measure-bufferbloat.sh](scripts/measure-bufferbloat.sh), and the
buffers are fine.

Two runs, 2026-09-05. The second recorded achieved throughput and reached 169.6 Mbps down /
565.3 Mbps up, confirming the link was actually full.

| Target | idle avg | download avg | upload avg |
|---|---|---|---|
| mikrotik1 (`192.168.1.1`) | 0.48 ms | 0.47 ms | 0.87 ms |
| Internet-Box (`10.1.1.1`) | 1.68 ms | 1.34 ms | 2.16 ms |
| internet (`1.1.1.1`) | 7.89 ms | 5.78 ms | 6.94 ms |

Figures from the second, throughput-verified run; the first run agreed to within a few
tenths of a millisecond.

**Download saturation produced no latency increase at any hop** — the figures are lower
under load than at idle. Upload added between 0.2 ms and 0.7 ms on average, with worst-case
spikes around 10 ms.

For scale: bufferbloat worth fixing shows up as **hundreds of milliseconds**, often more
than a second. A 0.7 ms rise is not a queue filling; it is the noise floor. On the Waveform
scale this is an A or A+.

### Therefore: do not build QoS

CAKE or FQ-CoDel exist to drain oversized buffers. There is no oversized buffer here, so
shaping would cost throughput and CPU and return nothing. **This document should stay
parked, and not merely until the Swisscom box arrives — it should stay parked until there is
evidence of a problem that queueing actually solves.**

If conference calls do degrade when something else is downloading, the measurement says the
cause is elsewhere. The strongest candidate by far is the wireless: 2.4 GHz only, no 5 GHz
anywhere, and until 2026-09-05 both access points sat on the same channel at 40 MHz width.
See [wifi.md](wifi.md). Fix that before revisiting this.

### What the measurement also showed: CPU, not queueing

Router CPU sampled during the run went from 16-22% idle to peaks of **81%** under load, on a
600 MHz single-core MIPS.

The one place latency did degrade meaningfully was **to the router itself** during upload —
avg 0.88 ms but max 9.8 ms with 2% packet loss, while the hop *beyond* it stayed clean at
1.96 ms. That shape is diagnostic: a router whose own ICMP replies are delayed while transit
traffic passes cleanly is CPU-starved in its control plane, not congested in its buffers.
Router-originated ICMP is the first thing to suffer when the CPU saturates.

This is consistent with everything in [performance.md](performance.md) and is an argument
for the hardware move — but it is an argument about CPU headroom, not about QoS.

### Caveats on the measurement, worth resolving before treating it as final

- ~~**The first run did not record throughput.**~~ **Resolved 2026-09-05 by a second run.**
  The script now reads NIC byte counters either side of each probe window. Achieved rates:

  ```
  idle       down     0.0 Mbps    up     0.0 Mbps
  download   down   169.6 Mbps    up     1.4 Mbps
  upload     down     7.2 Mbps    up   565.3 Mbps
  ```

  169.6 Mbps down matches the ~181 Mbps parallel-stream figure in
  [performance.md](performance.md), so the download path was at its ceiling. Upload reached
  565 Mbps against a measured maximum around 842 Mbps — not fully saturated, but far more
  load than a household call competes with, and it moved average latency by 0.5 ms. The small
  reciprocal figures (1.4 Mbps up during download, 7.2 Mbps down during upload) are ACK
  traffic, which is what a working test looks like.

  **The conclusion is now falsifiable and it holds.** The link was full and the buffers did
  not fill.

- **The idle baseline was noisier than the loaded phases** — 45.8 ms max to `1.1.1.1` and
  15.5 ms to the Internet-Box at idle, against 12.2 ms and 3.7 ms under download load. Something
  was disturbing the quiet measurement. Not important for the conclusion, which rests on
  averages, but it means the idle column should not be quoted precisely.
- ~~**The firewall rate-limits ICMP.**~~ **Ruled out 2026-09-05.**
  `/ip/firewall/filter/print stats where chain=ICMP` after the run:

  ```
  0  ICMP accept  ;;; Echo request - Avoiding Ping Flood      266 packets
  1  ICMP accept  ;;; Echo reply                          206 312 packets
  5  ICMP drop    ;;; Drop to the other ICMPs                   77 packets
  ```

  The rate-limited echo-request rule has seen **266 packets in ~45 hours of uptime**, against
  a limit of 10 per second, and the terminating drop has caught 77 — a trickle of other ICMP
  types over two days, not the hundreds of echo requests the test would have contributed had
  it been throttled. The measurement was not distorted.

  The reason the counters are so low is worth understanding, because it also explains the
  206 312 echo *replies* against 266 *requests*. Connection tracking groups an entire `ping`
  run into one ICMP connection: only its first packet reaches the ICMP chain, and every
  packet after it matches `accept established,related` at the top of the input chain. Pings
  *through* the router never reach the ICMP jump at all — `fasttrack`, `accept
  established,related` and `Home can connect everywhere` all sit ahead of it in the forward
  chain. The replies counter is high because the router's own replies leave via the output
  chain, which does jump to ICMP.

  Side observation, not raised as a finding: this means the "Avoiding Ping Flood" limit is
  largely decorative. It sees one packet per ICMP connection, and WAN input is already
  dropped at position 6 before the ICMP jump at position 7, so the only traffic it can ever
  rate-limit originates on the trusted LAN. Harmless, just not load-bearing.

  This also strengthens the CPU reading above: the 2% loss to `192.168.1.1` during upload was
  **not** the limiter, so it was the router failing to answer its own pings under load.

## The fasttrack problem

This is the constraint that shapes everything else.

**Fasttracked connections bypass queueing.** The main router currently offloads the bulk of
its traffic via `action=fasttrack-connection`, which is exactly why a 600 MHz single-core
MIPS box can forward near-gigabit at all. Traffic you want to shape must *not* be
fasttracked — so meaningful QoS means disabling fasttrack for that traffic, pushing it into
the CPU path.

On the RB2011 that is a bad trade: fasttrack is what makes the throughput possible, and
without it the router becomes the bottleneck. The measured numbers already show 30-50% CPU
at only 111 Mbps *with* fasttrack working.

On an RB5009 (quad-core ARM64, see the hardware note in
[config-review.md](config-review.md)) there is enough headroom to shape without fasttrack
and still exceed the line rate. **This is a strong argument for doing the hardware move
before attempting QoS**, not after.

## Recommended approach, in order

Kept for reference. Step 1 has been done and returned a negative result, which makes steps
2 and 3 unnecessary for now.

### 1. Measure bufferbloat first — done 2026-09-05, no bufferbloat found

Calls degrade under load far more often from **bufferbloat** than from lack of
prioritisation. When a bulk download fills an oversized buffer somewhere in the path, every
other flow's latency rises from milliseconds to hundreds of milliseconds, and real-time
audio falls apart. No amount of prioritisation on your side fixes a buffer upstream of you.

Measure before designing anything:

- <https://www.waveform.com/tools/bufferbloat> — run idle, then again during a large
  download, and compare the latency grades.
- Or `flent` for a proper RRUL test if you want real numbers.

If latency under load is the issue, the fix is queue management, not classification — which
is item 2 and much simpler than item 3.

### 2. CAKE or FQ-CoDel — likely sufficient on its own

RouterOS 7 supports both. Either gives per-flow fairness automatically: a bulk download
cannot starve a call, because each flow gets its share without anyone having to identify
which is which.

The key requirement is that the queue must be **the bottleneck**, so set its bandwidth
slightly below the real line rate (typically 90-95%) — otherwise the upstream buffer fills
first and the queue never engages.

```
/queue/type/add name=cake-up kind=cake cake-bandwidth=<~92% of upload>
/queue/type/add name=cake-down kind=cake cake-bandwidth=<~92% of download>
```

Applied via a simple queue or queue tree on the WAN interface. Exact shape depends on the
hardware and line rate at the time — do not write it until both are settled.

CAKE also honours DSCP when configured with `cake-diffserv`, which pairs well with item 3.

**Download shaping is inherently weaker than upload shaping.** You control what leaves your
network; you can only influence what arrives by dropping or delaying it to make senders
back off. Expect upload QoS to work well and download QoS to be approximate.

### 3. Explicit classification, only if 1 and 2 are not enough

Two ways to identify call traffic, best first.

**Trust DSCP.** Meet, Zoom, and Teams generally mark real-time media EF (46) or CS5. Honour
the marking rather than reconstructing it:

```
/ip/firewall/mangle/add chain=prerouting action=mark-packet \
    dscp=46 new-packet-mark=realtime passthrough=no
```

Caveat: DSCP is often stripped or rewritten by ISPs, and any device on your LAN can set it.
On a home network with no untrusted senders that is acceptable — but revisit it once IoT
devices are segmented.

**Classify bulk instead of real-time.** Often more robust: rather than identifying calls,
identify what is *not* a call. Any connection that has moved more than ~10 MB is bulk by
definition, and interactive flows never reach that:

```
/ip/firewall/mangle/add chain=forward action=mark-connection \
    connection-bytes=10000000-0 protocol=tcp new-connection-mark=bulk passthrough=yes
```

This needs no knowledge of Zoom or Google port ranges, does not break when they change, and
catches game downloads and OS updates automatically. Deprioritise `bulk` and leave
everything else at normal priority.

**Port-based matching is the fallback and the worst option** — Zoom uses UDP 8801-8810,
Meet uses UDP 19302-19309 plus STUN on 3478 — but both fall back to TCP 443 when UDP is
blocked, at which point ports tell you nothing.

## What to decide when picking this up

- Is the new Swisscom box's throughput actually fixed? QoS design depends on knowing the
  real line rate.
- Has the edge role moved to new hardware? If not, expect to trade throughput for
  prioritisation.
- Did bufferbloat measurement show a problem? If not, CAKE alone may be unnecessary.
- Should the IoT VLAN (see the VLAN plan in [config-review.md](config-review.md)) be
  deprioritised wholesale? Easier and more robust than per-flow classification, and it
  composes well with the "IoT gets no internet" policy already recorded.

# Network diagrams

Two diagrams, because they answer different questions and neither tool does both well.

| Diagram | Question it answers | Source | Tool |
|---|---|---|---|
| [network.svg](network.svg) | what is plugged into what | [network.dot](network.dot) | Graphviz |
| [network-addressing.svg](network-addressing.svg) | which device is on which subnet | [network-addressing.nwdiag](network-addressing.nwdiag) | nwdiag |

```
dot -Tsvg network.dot -o network.svg
dot -Tpng -Gdpi=140 network.dot -o network.png

scripts/render-nwdiag.py -T svg network-addressing.nwdiag -o network-addressing.svg
scripts/render-nwdiag.py -T png network-addressing.nwdiag -o network-addressing.png
```

Regenerate after any change and commit the sources alongside the output — the `.dot` and
`.nwdiag` files are the things worth diffing.

## Why `render-nwdiag.py` and not `nwdiag3`

nwdiag 2.0.0 aborts on this diagram with

```
TypeError: '<' not supported between instances of 'Network' and 'Network'
```

The cause is upstream, in `nwdiag/metrics.py:162`:

```python
networks = group.nodes[0].networks[:]
networks.sort(key=lambda a: a.xy.y)
network = min(networks)
```

The list is already sorted by vertical position, so the intent is "take the topmost network"
— `networks[0]`. The `min()` is redundant, `Network` defines no ordering, and on Python 3 it
raises. It survives unnoticed because `min()` on a one-element list never invokes `__lt__`:
the bug only appears once a node belongs to **two** networks, which is exactly what a router
does.

[render-nwdiag.py](scripts/render-nwdiag.py) defines `__lt__` on the same key the sort already uses,
so `min()` agrees with the sort rather than papering over it, then calls the normal CLI. It
takes the same arguments as `nwdiag3`. Nothing is patched on the system, so a package upgrade
cannot silently undo it — and if upstream ever fixes this, the shim becomes a harmless no-op.

Note the shebang is `/usr/bin/python3`: `nwdiag` is installed in the system
`dist-packages`, which the default `python3` on this machine does not see.

## Reading it

Edge style carries meaning, because a diagram that mixes what is true with what is planned
is worse than no diagram:

| Style | Meaning |
|---|---|
| **solid** | verified from device output — neighbour tables, link flags, the dumps |
| **dashed** | inferred; consistent with the evidence but not directly confirmed |
| **dotted** | planned, not yet cabled |
| **green** | CAPsMAN control relationship, not a cable |

Node fill: blue = MikroTik infrastructure, green = radios, purple = hosts, orange = the flat
IoT segment, yellow = a known constraint, red = the current bottleneck, grey dashed = planned.

**What is verified.** `mikrotik1 -> mikrotik2` and `mikrotik2 -> mikrotik3` come from the
neighbour tables on both ends. `mikrotik3 -> desktop` on `ether3` is inferred: `ether3` is
one of only two ports with link on that device, the other faces upstream, and the desktop is
in the office. Host attachment for Pi-hole, Home Assistant and the IoT devices is **not**
recorded anywhere in the dumps — those edges say "somewhere on this L2 segment", not "in
this port".

## Why these two tools

**Graphviz** was already installed (`dot - graphviz version 2.43.0`), which settled it. Beyond that:
the source is plain text and diffs cleanly in git, rendering is a single offline command with
no runtime, and DOT is stable enough that this file will still render in ten years.

The alternatives, all text-based and all capable of local SVG output:

| Tool | Renders via | Worth choosing when |
|---|---|---|
| **Graphviz** (`dot`) | native C binary | general topology; already present; smallest dependency |
| **D2** | single Go binary | nicer default output, containers and nesting; better looking with less fiddling |
| **nwdiag** | Python (blockdiag) | the diagram is *subnet*-centric — it draws networks as horizontal buses with hosts hanging off them, which is exactly the VLAN picture |
| **PlantUML** | Java | you also want sequence and deployment diagrams in the same syntax |
| **Mermaid** | Node + headless Chromium | the diagram should render inline on GitHub or in a markdown viewer without a build step |
| **Diagrams** (mingrammer) | Python + Graphviz | you want vendor icon sets; oriented at cloud architecture rather than home LAN |

Mermaid is the one to reach for if inline rendering matters more than fidelity — but its CLI
pulls in Chromium, which is a heavy dependency for a diagram. D2 is the strongest upgrade
path if this ever needs to look polished.

**nwdiag** turned out to be worth having alongside rather than instead. It draws each subnet
as a horizontal bus with hosts hanging off it, which makes address-plan questions obvious —
who is static, who is in `mgmt`, which devices are destined for the IoT VLAN — and makes
physical questions impossible, since it has no notion of a cable. Graphviz is the reverse.

It is now the right tool for a VLAN diagram: the port map is fully collected (see
[vlan.md](vlan.md)'s trunk/port plan), so the groups can become `vlan-users`, `vlan-services`
and `vlan-iot` directly. Not yet drawn — the two diagrams below predate the VLAN migration and
have not been regenerated since.

## What the diagram records

**Predates the VLAN migration — not yet regenerated.** Facts as of when it was drawn:

- The **Internet-Box has gigabit ports**, capping a 10 Gbps subscription at ~940 Mbps, and
  separately delivers only ~170 Mbps down against ~565 Mbps up (see
  [performance.md](performance.md)).
- **mikrotik3 has no PoE-out**, so both planned access points need injectors until the office
  switch is replaced.
- **IoT shared one flat L2 segment** with the desktop and the management plane — since fixed
  by the VLAN work (see [vlan.md](vlan.md)).
- **cap6 and cap7 are 2.4 GHz only.** The cAP XL ac is the only planned 5 GHz radio.

## Corrected while drawing this

Two errors surfaced only because the diagram forced every device to be placed somewhere
specific. Both had been stated in earlier notes and are now fixed:

- **The Fonera is at `192.168.1.101` on the main LAN**, not on `bridge-fon`. It had been
  recorded as being on the FON network on the strength of the name.
- **`bridge-fon` is entirely unused.** `ether6` through `ether10` all show `S` with no `R` in
  `/interface/print detail` — no link on any port — and its `.100-.200` pool is idle.

The second one matters beyond tidiness: **`ether10`, the port with PoE-out, is a `bridge-fon`
member.** Powering the cAP XL ac from it would have placed the access point on an isolated,
unrouted network rather than the LAN. The suggestion was already withdrawn for a different
reason — it is at the wrong end of the house — but it was wrong twice over, and only drawing
the picture made that visible.

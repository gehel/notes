# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

This is a personal notes repository for Wikimedia Foundation Data Platform Engineering (DPE) SRE work owned by Guillaume Lederrey. It contains operational notes, architecture diagrams, and project planning artifacts — not application source code. Most "work" here is editing text/markdown notes, PlantUML diagrams, and TaskJuggler planning files.

## Repository layout

- `planning/` — TaskJuggler project plans (`.tjp` top-level projects, `.tji` includes). Quarterly/fiscal-year DPE SRE planning, with shared `resources.tji` (team roster) and `reports.tji` (report definitions) imported by most `.tjp` files. Naming convention: `FY<YYYY>-<YYYY>-q<N>-<area>.tjp` for fiscal-year quarters, `q<N>-<area>.tji` for calendar-quarter slices.
- `plantuml/` — Architecture diagrams (`.puml`) grouped by system (elasticsearch, maps, rcstream). Additional `.puml` files live alongside topic dirs (`growthbook/`, `wdqs/`, `hiring/`, etc.) and at the repo root.
- Topic dirs (`elasticsearch/`, `wdqs/`, `maps/`, `mediawiki/`, `growthbook/`, `experimentation-platform/`, `hiring/`, `home/`) — free-form `.txt`/`.md` notes plus the occasional helper shell script (e.g. `elasticsearch/restart-elasticsearch.bash`, `wdqs/rolling-restart.sh`). Scripts are operational runbooks, not part of a build.
- Root `.txt`/`.md` files — single-topic notes (`wdqs.txt`, `varnish-ban.txt`, `todo.md`, etc.).
- `.remember/` — local memory buffer from the `remember` skill; ignored by git (`.remember/.gitignore` is `*`).
- `.idea/` — JetBrains IDE config; mostly gitignored.

## Working with the planning files

The planning files are processed by [TaskJuggler](https://taskjuggler.org/) (`tj3` CLI, installed as the `tj3` apt package per `home/install.md`).

- Render a project: `tj3 -o output/<project> planning/<project>.tjp` (from the `planning/` directory). Output goes under `planning/output/` which is gitignored.
- Live-rebuild + publish loop: `planning/generate.sh` watches the tree with `inotifywait` and on each change rebuilds the projects listed in its `projects=` variable, then `rsync`s `output/*` to `people2004.codfw.wmnet:~/public_html/planning`. Update the `projects=` line when adding a new top-level `.tjp` you want auto-published.
- `.tjp` files are top-level projects (have a `project ... { }` block); `.tji` files are includes (resources, reports, task fragments). When editing, follow the existing pattern: top-level `.tjp` files `include "resources.tji"` and `include "reports.tji"` and pull in per-initiative `.tji` files.
- `planning/.taskjugglerrc` configures the optional `tj3d` daemon (auth key + port 8899); it is not needed for normal one-shot rendering.

## Working with PlantUML

`.puml` files are rendered with the `plantuml` CLI (not installed via the apt list in `home/install.md` — install separately if needed). There is no build script; render ad-hoc, e.g. `plantuml path/to/diagram.puml`. Multiple `@startuml`/`@enduml` blocks in one file (see `maven-ci.puml`) produce multiple output images.

## Working with `home/`

`home/` holds Guillaume's personal home-infrastructure notes, split into two independent,
self-contained areas — each with its own `README.md`; **read that first** before touching
anything in its directory, since it names the currently active work and links every other
document in the area:

- `home/network/` — a MikroTik-based home network (VLANs, firewall, wifi, IPv6, QoS).
- `home/home-assistant/` — review and maintenance of a Home Assistant instance.

These documents exist so work can resume from the files alone, with no memory of prior
sessions, which drives their conventions:

- **A finding leaves an area's open-findings doc (`config-review.md`) only when fixed *and*
  verified** against real output/device state — never when merely reported done. Closed items
  move to that area's `changelog.md` with the verifying evidence attached. Finding numbers are
  stable and never reused (`<n>` for `home/network`'s main router, `S<n>` for its switches).
- **Every change, in any session, gets logged to the area's `changelog.md` as it happens**, not
  batched at the end. For `home/network`, RouterOS's own logs can't distinguish one session
  from another (both show up as the same `admin@<ip>/terminal` client), so the changelog is the
  only record that survives a session boundary.
- Each area's README ends with a running list of hard-won lessons/gotchas specific to that
  system — check it before debugging something that looks like a known quirk.

Both areas pull live device/config state for review and gitignore the raw copy, keeping only
the derived, reviewed markdown in git: `home/network/dumps/`, `home/network/backups/`,
`home/network/logs/` (via `scripts/dump-configs.sh`, `scripts/dump-logs.sh`,
`scripts/fetch-backups.sh`), and `home/home-assistant/config/` (via `scripts/sync.sh`, rsync
over SSH — see that area's README for the required HA add-on and env vars). Regenerate before
any review; these are snapshots, not sources of truth, and none of it belongs in git (secrets,
tokens, location history).

`home/network/diagrams/` has two complementary diagrams, regenerated after any change to the
trunk/port plan or device inventory, sources committed alongside rendered output:

```
cd home/network/diagrams
dot -Tsvg network.dot -o network.svg              # physical topology (Graphviz)
./render-nwdiag.py -T svg network-addressing.nwdiag -o network-addressing.svg   # VLAN/address plan
```

Use `render-nwdiag.py`, not plain `nwdiag3` — it works around an upstream nwdiag crash on any
node belonging to two networks (which a router always does); see `network.md`. Edge/fill style
in these diagrams is meaningful (solid=verified, dashed=inferred, dotted=planned) — see
`network.md`'s "Reading it" section before editing `network.dot`.

In `home/network/scripts/`, one-shot `.rsc` scripts (used for a single migration step) are
deleted once run and verified — the changelog entry is the durable record, not the file. For
RouterOS `.rsc` scripting itself (idempotency, safe-mode pitfalls, `find`/`print where`
reliability quirks), use the `mikrotik-routeros-rsc` skill and `home/network/README.md`'s
"Hard-won lessons" rather than re-deriving these from scratch.

## Conventions

- Notes are intentionally informal and often link to Phabricator tickets (`https://phabricator.wikimedia.org/T...`). Preserve those links when editing.
- Shell scripts in topic dirs are operational helpers run by a human against production hosts — assume they require credentials/SSH access and do not attempt to execute them from this repo.
- The team roster in `planning/resources.tji` is the source of truth for resource identifiers used in `.tji` task allocations (`responsible <id>`, `allocate <id>`).

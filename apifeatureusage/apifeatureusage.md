# APIFeatureUsage — decommissioning candidate

*Prepared for Jerry, as input to the "what can we decommission?" exercise.*

## TL;DR

APIFeatureUsage is a low-usage, low-maintenance MediaWiki feature that lets API
consumers (mostly bot operators) check whether they are still using a deprecated
API feature. Its usage is normally near zero, but it is the only external-facing
tool that serves this purpose, and its usefulness spikes during API deprecation
campaigns. Two decisions are worth separating: our **operational cost** can be
removed cheaply without touching the feature (there are existing proposals to
drop the OpenSearch dependency), whereas actually **decommissioning** is a
product decision we can't make alone — there is no product owner, and it would
involve WMCS and a MediaWiki team. This doc presents the trade-off without a
recommendation.

## What it is

When MediaWiki deprecates or discourages an API feature (e.g. an old parameter
of an `action=` module), every use of that feature is logged. APIFeatureUsage
exposes that data back to the outside world through:

- **`Special:APIFeatureUsage`** — a page where anyone can look up usage of a
  given feature by user-agent.
  ([live UI](https://en.wikipedia.org/wiki/Special:ApiFeatureUsage))
- **`action=featureusage`** — the equivalent API module.

Technical documentation:
[Extension:ApiFeatureUsage](https://www.mediawiki.org/wiki/Extension:ApiFeatureUsage).

The typical user is a **bot operator**: when a deprecation is announced, they use
it to check whether *their* bot is hitting the feature that's going away, so they
can fix their code before it breaks. There is **no known product owner** for it
on our side, and we don't have a clear picture of who the users actually are.
(The **WMCS team** likely has better visibility, since they support many of the
bot/tool operators who would use this.)

## How it works (infrastructure)

The moving parts, so the impact of keeping vs. removing it is clear:

- **The extension** — provides the special page and API module (query path only).
- **Log ingestion** — a **dedicated Logstash instance** consumes the
  apifeatureusage log stream and writes it into OpenSearch. This is a separate
  piece of infrastructure that exists solely for this feature.
- **Storage / query backend** — the data lives in **OpenSearch indices**
  (we migrated from Elasticsearch to OpenSearch some time ago). Today those
  indices are **co-located on the same OpenSearch cluster as our general Search
  indices**, which is the main operational annoyance: it couples an otherwise
  unrelated, low-value workload to our primary search infrastructure and
  complicates operations and upgrades.
- **Planned change** — we intend to move these indices onto our **new OpenSearch
  on Kubernetes**, into an isolated cluster, which removes the coupling problem.
  At this point that migration is **cheap and we're doing it anyway** — so it is
  *not* a cost that argues for decommissioning. (The only scenario where we'd
  skip it is a very fast decision to remove the feature outright.)

The maintenance cost overall is **not high** — it's more of a paper-cut /
annoyance than a real burden.

## Usage

Usage is **very low**. Traffic to `Special:APIFeatureUsage` works out to roughly
a **few hundred hits per day** ([Turnilo](https://w.wiki/SEUm)). That figure is
extrapolated from heavily sampled data (1/128), so the underlying sampled signal
is small enough to be statistically noisy — which is itself an indication of how
little the feature is used.

Importantly, low usage is **expected by design**: between deprecation campaigns
nobody has a reason to use the tool. When we *do* actively deprecate an API
feature, it briefly becomes genuinely useful to the community.

## The trade-off

**Reasons to decommission:**

- Usage is normally near zero and hard to even measure reliably.
- No product owner; nobody is actively invested in it.
- It couples a low-value workload to our primary Search infrastructure. (The
  planned k8s migration fixes this cheaply, so it's a minor point — but it's
  still ongoing infrastructure carried for a barely-used feature.)

**Reasons to keep it:**

- It is the **only external-facing tool** offering this capability. If removed,
  bot operators can still read their own code, but they lose the ability to
  confirm from the outside whether they hit a deprecated feature.
- Internally we have log-parsing tools that can answer similar questions, but
  those are **not available to external API users**.
- Its value is **spiky, not flat**: low usage most of the time, but potentially
  important during a deprecation campaign. Low average usage understates its
  worst-case usefulness.

## A third option: simplify instead of remove

Decommissioning is not the only way to get rid of the operational annoyance.
There is prior discussion about keeping the feature but **dropping the
OpenSearch / Logstash dependency entirely**, re-implementing the storage on a
plain MariaDB table:

- **[T313731](https://phabricator.wikimedia.org/T313731)** — *Long term plan for
  reducing maintenance workload on the Search Platform team of supporting
  ApiFeatureUsage.* Proposes sampling-based counting backed by a SQL table on
  MariaDB (x1), removing the search-infrastructure dependency. Motivated by the
  same pain points we have (curator failures, ES version compatibility, Logstash
  pipeline stalls).
- **[T148484](https://phabricator.wikimedia.org/T148484)** — *Make
  ApiFeatureUsage extension easier to set up.* Proposes a database-backed
  alternative to the ES/Logstash infrastructure via a hook in
  `ApiBase::logFeatureUsage()`.

This is worth noting because it decouples the two decisions: the **operational
cost on our team can be removed without a product decision** by moving to a
DB-backed implementation. Decommissioning is only necessary if the feature has
no value at all — which is a separate, product-level judgment.

## Why this is hard to action

Even if we decide the feature isn't worth keeping, actually removing it is not
purely an SRE task:

- **It's a product decision.** With no product owner, it's unclear who is
  entitled to make the call, and how we would communicate the change to users —
  especially since we don't have a clear picture of who those users are.
- **WMCS should likely be involved.** They support many of the bot/tool
  operators who are the real audience, so they're both a stakeholder and our best
  channel for reaching users.
- **MediaWiki-side work is required.** Undeploying the extension is work on the
  MediaWiki side, by a team still to be identified — not something our team can
  do unilaterally.

## Summary of the decision

- Keeping it running costs us little, and the one real annoyance (coupling to our
  Search OpenSearch cluster) can be resolved cheaply — either by the planned k8s
  migration, or more thoroughly by the MariaDB re-implementation discussed above.
- The genuine open question is **product-level**: is the occasional
  deprecation-campaign value worth keeping the feature at all? Answering that
  needs an owner we don't currently have, and any removal would need WMCS and a
  MediaWiki team involved.

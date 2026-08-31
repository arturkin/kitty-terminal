---
name: devops-review
description: Use when reviewing code or pull requests, or when planning/reviewing devops and infrastructure changes (Helm, K8s, Istio, Pulumi, GCP, Fastly, CI/CD, observability, caching, cron jobs, DB queries) in Travelshift repositories, to hold the work to the review standards and institutional knowledge the team inherited from its former senior SRE.
---

# DevOps Review: Preserved Review Standards & Institutional Knowledge

This skill preserves the review standards and hard-won operational knowledge of Yurii Serhiichuk (GitHub `xSAVIKx`), Travelshift's platform/SRE engineer 2021–2026 (1,553 authored PRs, 2,368 reviewed org-wide), distilled from his commit, PR, and review history across `monorepo`, `guide`, `infrastructure-resources`, and a dozen smaller company repos. Quotes were verified against GitHub in Aug 2026; recorded review history covers May 2023–Aug 2026 (GitHub holds no earlier review data for these repos).

**What this is:** a checklist of standards and a knowledge base, with attributed quotes from company review history as evidence of each rule's origin.
**What this is not:** a persona. Reviews produced with this skill are your own (or Claude's, stated as such) — never sign, present, or imply that output was written by Yurii.

## Review principles (team practices he established)

1. **Hunt silent failures first.** The recurring theme of his review history: configurations that look healthy while doing nothing — an audit sink with a wrong filter ("nothing errors"), a sidecar that silently doesn't render, a mock bypass that "reads exactly like" real data, a regex alert condition against an INT64 field that never matches. For every change ask: *if this were subtly wrong, would anything error?* If not, require loud failure or an explicit verification step.
2. **Scope the verdict.** Approve only what was actually evaluated and name what wasn't — his standard closing was "ops-wise LGTM. code-wise — left some comments, up to you to address/postpone or disregard." A review that rubber-stamps outside its competence is worth less than a scoped one.
3. **Separate blocking from taste, in words.** One review names "the only really critical thing" and explicitly marks the rest "not a blocker" / "team's call". A stated preference that the author rebuts with real reasoning converts to approval — don't re-litigate.
4. **Ask before directing — with genuine curiosity.** Frame debatable points as questions ("are these values somehow justified or just random?", "do we need GTE queues as well?"), and ask to *understand*, not to gatekeep ("just trying to understand if this was a deliberate choice"). Reserve imperatives for the non-negotiables below. Concede immediately when given a real technical reason.
5. **Evidence over authority.** Positions are backed by doc links, measured numbers, prod telemetry, or a dry-run — never by rank. Bot findings (CodeRabbit etc.) are data to verify: accept with a fix, or rebut with evidence.
6. **Numbers before knob-turning.** Resource limits, HPA thresholds, sampling rates, batch sizes, cron cadences need a cited measurement or documented rationale. ("This change increases products 500→750 — that's 50% more iterations, memory… I'd highly recommend documenting this.")
7. **State what wasn't verified.** He checked the repo's "I'm cowboy 🤠 (it's bad)" testing checkbox honestly rather than claim coverage, and wrote "treat this as uniform coverage, not a proven mitigation." Reviews and PRs must state plainly what is untested, not deployed, or inferred.

## Review flow

Work through in order; reference files hold the per-area rules.

1. **Digestibility** — a PR mixing tooling setup + specs + generated implementation, or too big to review honestly, gets a split request ("we'd better split such things into digestible parts"), not a skim-approve.
2. **Parity sweep** — staging AND prod values? GTI AND other marketplaces? Drift between `stage-values.yaml`/`prod-values.yaml`? This was his most-repeated question in `guide`.
3. **Deploy-risk** — migration ordering, backfill cursors, table-swap timing, cross-repo merge order (state it explicitly: "Do not merge before X"), rollback path, and the distinction "safe to merge" vs "safe to run".
4. **Silent-failure hunt** — principle 1; also: does a removed fallback break before its replacement exists?
5. **Data layer** — index for every new/changed query; reads on `replica` where that convention holds; retries need jitter and idempotency; no redundant inserts.
6. **Observability** — every span closed on every return path including error branches; a tracing failure must never fail the request; per-failure-mode logs carrying entity details; no unlogged throw or empty catch.
7. **Infra checklist** — see [devops-knowledge.md](references/devops-knowledge.md): probes (dependency checks never gate liveness), PDBs, spot pods + affinity + sensible replicas for new prod workloads, pinned versions, Pulumi provider wiring, Helm chart genericity, GitHub Actions contracts.
8. **Cost** — cron cadence skepticism (weekly-or-slower + manual trigger unless justified), resource requests justified, runner sizing proportional to the job.
9. **Code quality (non-blocking lane)** — reduce nesting via early returns/extract-method, magic numbers into config with documented rationale, fix types at the source not at call sites, naming precision ("if we decide to go with another one is it going to be `new_new`? …go with `_v2`"), and basic file hygiene (trailing newlines, stray formatting) — small, but he flagged it nearly every time.

## Hard blocks (he never let these slide)

- Missing index on a new or changed DB query.
- Magic number/constant without documented rationale.
- Swallowed exception or error path without logging.
- Dependency check (Redis etc.) wired into a **liveness** probe.
- Floating/wildcard dependency versions in **any** manifest — npm `^`/`~` ranges in package.json, composer.json wildcards, Pulumi/NuGet ranges — and unpinned (`:latest`) or years-stale container images. He pinned exact versions even where a lockfile exists ("Please don't use wildcard versions", "I personally prefer fixed versions over wildcards").
- Disabling a test or check without a linked tracking task.
- Config duplication where a template/shared value would do — including forking a chart to add one flag.
- New prod workload without spot pods, node affinity, sensible replicas/PDB.
- Tracing span that can orphan on an early return or redirect.
- A "generic"-named tool that isn't generic; an undocumented/untyped script ("no docs, no requirements, no readme, no typings").

## Explicitly non-blocking

Style/taste once stated; micro-optimizations on tiny data ("I'd not spend any more time on this"); clearly-marked WIP/debug gated to non-prod; documented deliberate trade-offs (defer even legitimate hardening to a dedicated cross-cutting PR rather than block an unrelated change); decisions owned by another team — tag the owner and defer.

## When authoring PRs and changes (not just reviewing)

The same standards applied from the author's side:

- **Structure the PR body as `## Why` → `## What` → `## Verification`**, with measured before/after numbers and literal command output (test counts, `pulumi preview` diffs, `git diff --ignore-all-space` for mechanical changes). Link the Asana task.
- **State cross-repo merge order explicitly**: "⚠️ Do not merge before X merges to main."
- **Separate "safe to merge" from "safe to run"**: a merged-but-not-deployed change says so in the body ("Not deployed", "Not yet applied to a cluster").
- **Staging cutover and prod cutover are separate PRs** for risky infra changes; ship-observe-revert is legitimate for reversible flips.
- **Declare what's out of scope and what's unverified** — check the "cowboy 🤠" testing box honestly rather than imply coverage; "treat this as uniform coverage, not a proven mitigation."
- **Design docs before code for risky work**, reviewed while changing course is still free: "Argue with the design, not the code — there is no code yet."
- Full rollout/verification protocol: [devops-knowledge.md](references/devops-knowledge.md) § Rollout & verification discipline.

## Verdict format

End every review with a scoped verdict and the blocking/non-blocking split:

> Ops-wise this looks good; on the code side I've left comments you can address or postpone.
> The only blocking item is the cron schedule — the rest is the team's call.

## References

- [devops-knowledge.md](references/devops-knowledge.md) — house rules and gotchas: Helm/K8s/Istio, Pulumi/IaC, GCP, Fastly/CDN, GitHub Actions, observability, caching/Valkey.
- [domain-gotchas.md](references/domain-gotchas.md) — Travelshift-specific: guide/Kohana monolith, marketplace headers/parity, DB conventions, LLM integrations, AI-workflow risks.
- [offboarding-map.md](references/offboarding-map.md) — index into his offboarding knowledge base (`infrastructure-resources` `docs/offboarding/`): the 26 landmines, per-system gotchas, reusable audit tooling, and where to look before touching any infra system.
- [design-decisions.md](references/design-decisions.md) — index of his `docs/superpowers/specs/` design docs across guide/infrastructure-resources/monorepo, with each doc's rejected alternatives and key constraint; open the doc before reworking anything it covers.

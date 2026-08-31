# Design-Decision Trail (docs/superpowers/specs)

His spec-first workflow left design docs in three repos — the highest-fidelity record of *how he decided*, including rejected alternatives. Open the doc before reworking anything it covers. One-line index + the durable gotcha each one carries.

## guide (`docs/superpowers/specs/`, branch `development`)

- **2026-06-15-sentry-logging-design** — cause-based error fingerprinting. Gotcha: MySQLi puts errno in exception *code*, not message (dual PDO/MySQLi parsing); error reporting is try/catch-wrapped so it can never itself throw.
- **2026-06-11-draftable-hotels-design** (+plan) — extends the draft framework to hotels. Rule: fields driving business logic (ES indexing, geocoding, pricing, provider sync) are *structurally excluded* from draft maps; draft saves never call `Model_Hotel::save()`.
- **2026-06-30-istio-retries-staging-design** — explicit gateway/mesh retry config. Gotchas: `enabled:false` does NOT remove Envoy default retries (must zero `attempts`); `retryOn` ending in a bare `retriable-status-codes` token silently loses 503 retries; prod connection-pool limits were sized from SigNoz/KEDA telemetry via Little's Law, not guessed.
- **2026-07-06-cms-global-change-log-design** — one generic `cms_change_log` + single chokepoint. Rejected per-table `updated_by` (60+ ALTERs; "side table over widening"). Gotcha: `cms` and `users` are separate schemas — no FK; actor is int + denormalized label; audit writes are best-effort and must never break the mutation.
- **2026-07-06-insurance-bundle-mapping-design** (+plan) — shared `BundleWriter` service behind both admin flows; single-transaction category grid.
- **2026-07-16-hotel-searchcategory-content-draft-design** — draft trio pattern. Gotcha: draft-mode POST must `isset`-guard business fields or it clobbers live values with empties.
- **2026-07-28-cms-soft-delete-and-async-export-design** (+plans) — opt-in `softDeleteColumn()` hook filtered at one `applyRowGuards()` chokepoint; async export via keyset pagination + incremental deflate (full payload never in memory). `is_disabled` deliberately not exposed via GraphQL.
- **2026-08-05-wiremock-mock-variants-design** (+plan) — **only on PR #38661's branch, unmerged.** Header-based variant selection; rejected pod affinity, admin fan-out, shared Deployment, PHP self-PUT (each with stated reasons). Accepted trade-off: static `MockVariantContext` vs the anti-static rule, because a missed injection site would *silently* drop the variant.

## infrastructure-resources (`docs/superpowers/specs/`, branch `main`)

- **2026-04-23-helm-version-bump-script-design** (+plan) — git-diff-based chart-version cascade; unmatched version string counts as "modified" (bias toward safety).
- **2026-06-11-split-workload-utilization-alerts-design** (+plan) — split combined alert policies because GCP dashboards render single-condition only; kept old resource IDs so 0.9.x stacks update in place (breaking 0.10.0 otherwise).
- **2026-06-29-helm-chart-render-testing-design** (+plan) — two-tier: helm-unittest+kubeconform smoke across all components; behavioral + byte-identical no-op snapshots for the Istio controls. Istio 1.19 CRD schemas vendored manually.
- **2026-06-29-istio-traffic-controls-design** (+plans incl. istio-gateway-mesh-scopes) — the gateway/mesh scope split. Gotchas: several natural-looking fields (`connectionPool.tcp.idleTimeout`, `maxConcurrentStreams`, LB `warmup`, `httpCookie.attributes`) are Istio 1.20+ and don't exist on pinned ASM 1.19 — keep out of values.yaml. Helm/Go template landmine: `range` rebinds `.` — capture `$base := .base` before entering the range.
- **2026-07-02-pr-chart-prerelease-versioning-design** (+plan) — `BASE-pr.<n>.g<sha>` at publish time only. Rejected `+` build metadata (Helm rewrites `+`→`_` in OCI tags; ignored for precedence). Draft PRs validate but skip publish; `ready_for_review` must be in trigger `types`.

## monorepo (`docs/superpowers/specs/`, branch `master`)

- **2026-06-16-doppler-operator-helm-kustomize-design** (+plan) — adopt via `--post-renderer`+Kustomize. Rejected `kustomize --enable-helm` and template-then-apply: both lose the Helm release object (history/rollback). Gotchas: upstream chart's values.yaml is completely empty (why post-renderer is the only path); exclude the Namespace from Helm or `helm uninstall` cascade-deletes every DopplerSecret.
- **2026-06-30-shared-valkey-cache-consolidation-design** — one logical DB per service. Gotcha: plain `host:port` strings have no DB-index field — consumers need `redis://host:port/N` or client default-DB, verified per-consumer before migrating.
- **2026-08-07-web-content-length-design** (+plan) — the authoritative root-cause writeup of the Next 12 `NEXT_BUILTIN_DOCUMENT`/`supportsDynamicHTML` issue and why the response-wrapper approach (PR #41219) emitted broken HTTP (also captured in root CLAUDE.md learnings).
- *(2026-08-04-nl-borderline-band-design exists — Northern Lights scoring; product-specific, see the doc itself if touching NL verdicts.)*

# DevOps & Infrastructure House Rules

Rules and gotchas established by Yurii Serhiichuk (xSAVIKx) across Travelshift infrastructure, with source PRs for provenance. Repos: `infrastructure-resources` (IR), `.github-workflows` (GW), `monorepo` (M), `guide` (G), `monolith-service` (MS), `bookings-overview-micro-service` (BO).

## Kubernetes / GKE

- **Dependency checks never gate liveness.** "redis check must not be used for liveness. it can be OK to use it for readiness if redis presence is absolute must, but killing a pod because redis is not accessible is wrong." (M#43339)
- **Probe semantics contract:** startup check fails until startup completes; liveness OK throughout; readiness fails before startup completes, OK after. (M#36903)
- **Every new prod workload:** ~2 replicas, PDB that still permits node drains, spot pods, node anti-affinity ("Please downscale this service to 2 replicas, configure spot pods and affinity to run on different nodes", M#30796). Cosmo router: 2 pods + PDB=1 "to ensure we're not gonna end up with no pods at all" (M#43214).
- **PDB permissiveness matters:** an unpermissive staging PDB (`minAvailable` too high) blocked GKE node auto-updates across 40+ services (M#43222/#43224). `minAvailable: 0` during voluntary disruption doesn't take the service down — pods just move.
- **GKE Autopilot:** DOES support `limits > requests` (pod bursting) with prerequisites; node-autoscaling config is forbidden on Autopilot and flips on IAM/SA creation (M#43745). Autopilot resource floor is 50m CPU — recommenders suggesting below that cause eviction loops (CAST AI, M#43745, "not ready to roll out to prod"). GKE fleet ≠ GKE Enterprise: Istio via fleets doesn't need the Enterprise tier (M#33890).
- **Don't stack redundant pod hardening:** upstream charts often already set runAsNonRoot/drop NET_RAW; `readOnlyRootFilesystem: true` is risky (controllers write /tmp); Autopilot enforces baseline Pod Security (M#43331).
- **Helm chart adoption gotcha:** strategic-merge patches don't drop containers absent from the new chart — an explicit `kubectl patch ... "delete"` prune is needed before the rollout wait (Doppler operator migration, M#43331).
- **Zone pinning** (europe-west2-b/c) is a deliberate latency/cost-vs-capacity tradeoff: "That's a tradeoff we did in AWS and we are doing it now in GCP as well." (G#38270)

## Helm

- **Charts stay generic; app-specifics go to values.** Never fork a chart to add one flag: "Why do we need a whole new chart when the only difference is this capability...? Let's instead modify existing charts and just make creation of SA configurable." (M#27073) Logic belongs near the code: "I'd rather create a script near the dockerfile and use it as a CMD. If you keep it here this is gonna be a nightmare to support." (M#27073)
- **Template context explicitly:** pass `$root` and `$current` rather than relying on ambient `.` context (M#30831). No commented-out blocks as feature toggles — use arrays + enable flags (M#30831).
- **New config surface needs a fully-configured example** (in `devops-test` setup): "how people would know that these values are required?" (M#30831)
- **`serviceAccount` is a long-deprecated alias** — don't reference it (IR#104). `nginx` is a reserved sidecar name rendered directly by deployment/statefulset — the generic propagation path silently produces nothing for it (IR).
- **Sidecars for Job-backed pods:** native k8s sidecars via `restartPolicy: Always` init containers (k8s 1.29+) so Jobs can complete (IR#152). Chart-version skew is a silent failure: "a values file opting into a sidecar against an older published chart renders a worker with no sidecar — silently, not as an error." (IR#152)
- **Render-test charts:** helm-unittest + kubeconform with vendored CRD schemas; prove validation is non-hollow by injecting a bogus enum and confirming rejection (IR#147). When refactoring templates, compare **parsed manifests, not text** (IR#152).
- **Chart prerelease flow:** `BASE-pr.<n>.g<sha>` to stage-only on PR, plain `BASE` on merge; smoke-test CI changes on a throwaway PR first (IR#149/#150).

## Istio

- **Gateway-scoped vs mesh-scoped VirtualServices are different things.** Route policies on a gateway-scoped VS never reach the in-mesh service→service hop — the cause of a real retry-amplification incident; the chart exposes `istio:` blocks scoped separately for `gateway` and `mesh` (IR#146).
- **Unconfigured = Envoy invisible defaults** for retries/timeout/outlier/connection-pool — set them explicitly (IR#146).
- **Envoy access-log format operators:** `upstream_service_time` needs `%RESP(...)%` not `%REQ(...)%` — it was empty for years because of this (M#43757). Verify operators against the substitution-formatter reference for the actual proxy version.
- **Two VirtualServices per release (gateway+mesh) share instance labels** — tooling must classify VS type; derive release URLs from the primary gateway VS (GW#66).

## Pulumi / IaC

- **Explicit `{provider}` on every resource creation AND every `get`-style call.** "none of our infra setup will let you spin it up while providers are always required... it's a bit annoying but it pays off eventually." (IR#30/#80) Dedicated `gcp.Provider`/k8s provider — controls default labels and update behavior.
- **Never rely on GCP defaults:** default VPC, default service account, default oauth scopes propagate to nodes and can't be revoked without recreating the cluster (IR#30). Separate node-pool creation from cluster creation so pool changes don't recreate the cluster.
- **Backward compatibility is a hard requirement in shared components:** renames force resource re-creation → outages. Use `aliases` (URN) to migrate existing infra without downtime — worked example in IR#42. "It is always possible to import existing infra, but doing imports into IaaC is a pain." (IR#40)
- **`keepers` on generated secrets/randoms** so they don't regenerate on unrelated diffs.
- **Importing a live service (e.g. Fastly) into Pulumi — the protocol:** `pulumi import` against the active version → verify the no-op version is behavior-neutral → `pulumi refresh --preview-only` AND `pulumi preview --refresh` both "unchanged" → independent manual count of domains/backends/conditions vs live (IR#46, #154, #155).
- **Reuse existing modules:** "we already have `cart` module. Why haven't we put this infra there?" (M#36408). Conditional exports: populate a temp object inside `if`, export once.
- **Pulumi TS is pinned to yarn 1 deliberately** (yarn 2/3/4 issues) — known accepted rough edge.
- **Pin dependency versions.** "I personally prefer fixed versions over wildcards. Especially when we have more than 90 versions of Pulumi 3.x." (M#24792)

## GCP monitoring / logging / alerting

- **GCP Monitoring API constraints:** Istio `response_code` is INT64 — `monitoring.regex.full_match` silently never matches; use numeric comparisons (IR#142/#143). Dashboard alert charts only render **single-condition** policies — split combined mean+per-pod policies (IR#144). `alignmentPeriod` caps at 25h — daily windows, not weekly (M#43784).
- **Log-volume cost alerting:** use `logging.googleapis.com/byte_count` (post-exclusion, billable); don't use Snoozes for suppression (time-bounded, silently expire) (M#43784).
- **Audit-log sinks:** separate bucket with `deletionPolicy: PREVENT`; leave `_Default` untouched; a wrong filter "produces a healthy-looking bucket and sink with an empty audit trail — nothing errors" — verify with a real event (M#43744).
- **GCP Error Reporting for PHP** needs the exact case-sensitive prefix `"PHP (Notice|Parse error|Fatal error|Warning): "` on log messages to auto-detect stack traces (G#37898/#37514).
- **Cloud NAT port exhaustion** at pod scale is a known gotcha (prior real incident) (M#33890).

## Fastly / CDN

- **`origin.*` domains bypass all caches unconditionally** — purging them does nothing (M#42087).
- **Cache-bypass set:** `admin.`/`origin.` subdomains and login/logout/review/user routes (session-cookie pages); staging and prod bypass rules must stay in parity (IR#156).
- **Multi-line VCL lives in `src/*.vcl` files** pulled via `localFileContent` — inline strings silently drop `$` regex anchors (IR#46).
- **Service chaining is an architectural boundary:** CMS backend routing via a separate chained CDN service, not embedded logic — "I'd rather avoid having this logic in Fastly unless absolutely required."
- **The booking image proxy caches images indefinitely** — undermines any "re-check every N weeks" logic downstream (M#42726).

## GitHub Actions / CI

- **Reusable-workflow secrets contract:** declared on the workflow, passed with `secrets: inherit` — redeclaring at the caller breaks the contract (GW#51).
- **`skipped` propagates transitively** to all dependents-of-dependents: "you absolutely have to use `always` in order to make sure a job even just tries to evaluate its own condition." (G#38146)
- **Runner sizing:** custom/large runners only for heavy jobs (GW#65). Actions reuse the caller's runner; workflows don't.
- **hardened-checkout everywhere**, with honest framing: "Treat this as uniform coverage + a single place to retune the threshold, not a proven mitigation." (IR#151)
- **Cross-repo changes state merge order in the PR body:** "⚠️ Do not merge before .github-workflows#66 merges to main — revert these refs back to @main afterwards." (G#38606)
- **Mechanical-change PRs prove themselves:** `git diff --ignore-all-space` identical to plain diff; exact file/line counts stated (M#43714).
- **GitHub doesn't auto-close PRs when a squashed branch is pushed** — why the toolbox squash-push policy was reverted (toolbox#55).
- **Keep PRs under CodeRabbit's 150-file limit** — a 348-file cache-behavior PR "got no automated review at all"; that is itself the argument for small PRs (BO#64).

## Observability / OTel / Sentry

- **Span discipline:** every span closed on every return path including error branches — the single most repeated review comment in `guide`. A tracing failure must never fail the request: "catch it, log it, send Sentry error, whatever, but not fail the whole request." (G#36772)
- **OTEL load-balancing exporter** routes spans by trace ID so the tail sampler sees whole traces — forward immediately, don't batch at the LB layer (M#41352). Tail sampling took monolith spans ~950k → ~250k per 15 min (MS#23).
- **Per-failure-mode logging:** separate logs for pull/process/delete steps of a queue consumer, each carrying message details (M#29107).
- **Sentry error grouping:** cause-based fingerprinting (SQLSTATE + errno + normalized statement), traceparent correlation, lazy context capture behind cheap filters; injectable service over static helper with hardcoded DSN (G#38440 — triggered by "~377 ungrouped error types in 7 days").
- **Debuggability is a review criterion:** prefer code where "I'd be able to inspect the `result` and have a single breakpoint." (M#32366)

## Caching / Valkey

- **Shared Valkey:** one instance, 32 logical DBs, one per service, same DB index across environments (M#43502+).
- **Behavioral contract on backend swap:** memcached silently misses on outage; redis/valkey **throws** — wrap access so a cache outage degrades instead of 500s: "A cache outage used to degrade this service; it would now have broken it." (BO#63, currency-exchange M#43522)
- **Migration rollout pattern:** driver support + staging cutover in one PR; prod cutover deferred until the shared prod instance exists; dump/upload/verify tooling with per-env interactive confirmation and restartability.

## Runbooks he left in Slite (private DevOps channel)

He owns 49 Slite notes — none formally triaged since departure. Highest-value (search by title in the DevOps channel): AWS RDS→Cloud SQL DMS migration; marketplace prod→staging DB sync; single-table MySQL restore; KEDA async processors; Istio traffic mirroring; SignalSciences bot blocking; Known Fastly hiccups; Elastic "out of shards" fix; gcloud configurations; the "🛠️ Tools and Accounts 🔐" collection (~30 per-tool docs: admins + credential locations). Durable gotchas from them:

- **Fastly request collapsing:** rule action `Pass` does NOT trigger collapsing; `Force miss`+`Do nothing` does — `Pass` avoids collapsing stalls but forfeits post-cache processing (compression).
- **SignalSciences blocking:** reverse-DNS (`host <ip>`) before blocking — never block Googlebot ranges; check per-IP volume in the Fastly access-log Metabase questions first.
- **KEDA:** Scaled Job only for rare/bounded tasks; Scaled Workloads have no liveness/readiness safety net — an unhealthy one becomes a zombie that never drains its queue. No GKE UI for scaling them — CLI/Actions only.
- **PubSub `ackDeadlineSeconds` caps at 600s** — longer processing needs explicit lease extension, not a bigger config value.
- **DMS MySQL migration:** Limited LOB mode sized from an actual max-length scan; cascade constraints, auto-increment attrs, and geometry columns are NOT migrated — reapply manually. CDC `LoopbackPreventionSettings` must be edited via the JSON editor or wizard-set fields get wiped.
- **Elasticsearch (single-node):** hard 1000-shard ceiling; degrades silently before failing. Diagnose `_cat/shards` UNASSIGNED → `_cluster/allocation/explain`; usual fix is `number_of_replicas: 0` (orphaned replicas, not data loss).
- **Prod→staging DB sync:** disable RDS backups during the data sync (backups enable binlog; the sync floods it). Restore single tables via a temp VM + scoped `mysqldump --no-create-info` — never sed a raw dump.
- **Istio traffic mirroring** appends `-shadow` to the mirrored host header — that's the GCS folder name for replay data.
- **gcloud:** named configurations exist per project (prod-ts/stage-ts/infra/…) — switch with `gcloud config configurations activate` or you operate on the wrong cluster.

## Incident-derived rules (from Asana postmortems)

- **Domain expiry is a single point of failure across systems:** a Namecheap renewal failure took down the Client API Fastly proxy, Metabase, and the VPN simultaneously; the fix was dual-domain redundancy (`traveldev.services` alias) for all three. Keep registrar billing + renewal-notification routing owned.
- **SignalSciences legacy NGWAF engine drops Brotli** — the agreed path was Fastly's newer engine (loses VCL `director`/mTLS, both unused). Post-Cosmo decision: disable Fastly-side compression entirely, let Cosmo's gzip/brotli handle it; Fastly caches on `Vary`.
- **Cost-anomaly spikes are the abuse detector:** a Stays Maps API consumption spike is what exposed public client-api GraphQL abuse; Places API keys were traced by name ("RZyw" = Client API prod, "QDtE" = GTI server key).

## Rollout & verification discipline

- Staging always precedes prod; prod cutover is its own PR.
- "Safe to merge" ≠ "safe to run": merged-but-not-deployed is stated explicitly in the PR.
- Measure before changing values; quote `pulumi preview`/test output verbatim in the PR; cross-check tool output against an independent manual count.
- Validate functional round-trips after migrations (e.g. add+delete a secret, confirm propagation both directions, measure the lag).
- Ship-observe-revert is a legitimate strategy for reversible flips — revert fast and without drama when prod data disagrees.
- Design docs before code for risky work, reviewed while changing course is still free: "Argue with the design, not the code — there is no code yet." (G#38661)

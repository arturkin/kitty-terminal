# Offboarding Map — Index to docs/offboarding/ (infrastructure-resources)

Compact index into Yurii's offboarding knowledge base (`infrastructure-resources` PR #153, branch `infra-docs`, landing in `docs/offboarding/` on main once merged). **This file is a map, not the content** — open the referenced file in the repo when touching that system. His own instruction: do not read it front to back.

**Read order** (per its README): `narrative/org.md` → `narrative/landmines.md` → `STATE.md` → `ACTIONS.md` (154 items, un-triaged — not a starting point) → `map/<system>.md` only when you touch that system (index: `map/README.md`).

## The 26 landmines (narrative/landmines.md) — one line each

1. **CIDR reuse** — prod-ts Cloud SQL /16 already contains stage-ts Redis /24 over a live peering (+2 more overlaps); allocate only from the generated register (`reference/generate-cidr-register.sh`), never from memory.
2. **stage-ts-gke-v2 is not a restore path** — never integrated; no DR plan exists; treat cluster loss as unrecoverable.
3. **Pulumi drift is deletions, not duplicates** — 11 resources managed-but-undeclared (incl. 8 log exclusions); `pulumi up` deletes them; always preview and read the deletes.
4. **ClickHouse staging ≠ prod** — staging in-cluster Helm, prod a separate managed provider; never infer prod behavior from staging.
5. **bookings-overview-service DB** — one AWS instance split by schema across envs; any change is a prod change.
6. **bungalow** — web+app+DB on one unmanaged Linode box, code drifted from repo, no runbook possible; preserve SSH (A2).
7. **Networking is hand-built** — configured manually by an unknown person, no IaC, no fallback; every change is high blast radius.
8. **Observability is split six ways** — except tracing: SigNoz is deliberately authoritative for traces only.
9. **Missing trace ≠ broken instrumentation** — tail sampling drops traces for cost; confirm via logs/metrics first.
10. **Incident routing** — multiple undocumented paths incl. a 5-hop chain through 3 SaaS automation tools, none in any repo.
11. **AWS is not legacy** — DynamoDB is source of truth for ALL sessions; session issues are AWS investigations.
12. **Load-bearing state outside repos** — Helm chart versions in GitHub env-level vars (`OCI_CHART_CONFIG`), CIDR register in a Google Sheet.
13. **Merging to main deploys staging AND prod** — one workflow, no gate; any merge is a prod deploy.
14. **db-sync can destroy prod** — it overwrites the same AWS instance that holds prod (shared schema); wrong target/schema/Doppler value = prod data loss (A22).
15. **db-sync is the only backup-restorability proof** — don't retire it without a replacement.
16. **Fastly origin add is a two-step op** — needs a separate manual Signal Sciences dynamic-VCL re-trigger (local CLI, two keys), no CI (A26).
17. **Automation authenticating as Yurii personally** — PagerDuty Pulumi stack + WAF updater; WAF updater fails silently (only stops adding new entries); symptoms surface months later (A3/A24/A30).
18. **Blacksmith kill-switch is build-only** — 4 build workflows honor it; `deployment-gke.yaml` (154 refs) does not (A31).
19. **Out-of-repo config is systemic** — CIDR sheet, SimpleBackups schedule, Stitch config, WAF VCL, ~81 Make + 52 Zapier + 5 n8n workflows; assume the repo is incomplete.
20. **WireMock sidecar in prod succeeds silently** — returns fake data with no error; staging/branch-only.
21. **Traffic mirroring needs a configured receiver first** — else it silently drops; receiver → switch → verify.
22. **~30 legacy Pulumi stacks live in `monorepo/infrastructure/pulumi/infra/js|yaml`** — an unfinished move; default is relocating to the infra repo, not building on them in place.
23. **Offboarding doesn't remove cloud access** — audit per platform; Yurii held bindings under TWO corporate identities (@travelshift.com + @guidetoiceland.is) (A75/A88).
24. *(duplicate emphasis of 18.)*
25. **siggi's personal accounts are deliberate shared logins** — Zapier, Fastly, Cloudflare, Signal Sciences, n8n, Altinity, 15+ GCP projects, AWS; Artur is custodian; don't revoke — the real gaps are audit trail + the 2016 static AWS key.
26. **"Legacy" is load-bearing** — `guide` still builds/tests on CircleCI; Apollo gateway still carries ~5% of GraphQL traffic; verify usage before deleting anything labeled legacy (A157/A158).

## His own recorded error patterns (README §4 — apply when reading the rest)

Access findings run over-severe (APIs can't distinguish shared-custody from stale access); "absence of evidence" claims failed 3× from checking the wrong scope; one AWS enumeration covered 1 of 3 accounts and wrongly declared live VPCs dead; recalled magnitudes survived but recalled *directions* inverted; "superseded" got misrecorded as "dead" (CircleCI, Apollo).

## System map lookup (82 entries, map/<name>.md)

- **edge (7):** akamai-linode, booking-proxy, bungalow, cloudflare, fastly-cdn, fastly-object-store, signal-sciences-waf
- **aws (2):** aws-networking, dns-route53
- **data (13):** aws-dynamodb-sessions, aws-rds, aws-s3-static, aws-sqs, backups-simplebackups, cosmo-clickhouse, db-read-replicas, db-sync, elasticsearch, gcp-cloudsql, influxdb, mongodb-atlas, redis-valkey
- **k8s (11):** bookings-overview-service, comentario, cosmo, gke-cluster-operators, glitchtip, helm-capabilities, infra-ts-gke, prod-ts-gke, squidex, stage-ts-gke, unleash
- **gcp (11):** bigquery, gcp-cloud-dns, gcp-iam, gcp-networking, gcp-projects, gcp-secret-manager, maps-api-keys, pritunl-vpn, sound-vault-671, travel-plan-production, waf-updater
- **ci (11):** aws-cloud9, blacksmith-runners, bungalo-v3-repo, coderabbit, github-workflows, gti-bot, guide-repo, monorepo, pulumi-components, repo-inventory, tasks-automaton
- **saas (27):** asana-incidents, bulksignature, business-central, cloudwatch, doit-finops, domain-registrars, doppler, gcp-observability, google-workspace, grafana-cloud, healthchecks-io, hellobar, intercom, lastpass, make-com, metabase, n8n, otel-collectors, pagerduty, robocorp, sendgrid, sentry, signoz, snowflake, stitch, usersnap, zapier

## Highest-value per-system gotchas (from the entries read in full)

- **fastly-cdn** — 13 of 15 live services are unmanaged/drifted from repo; console edits never sync back → console is source of truth except the 2 Cosmo proxies; two IaC branches unmerged and at risk (A139).
- **signal-sciences-waf** — both operational credentials are Yurii's personal tokens (no expiry, no IP allowlist); 31-rule ruleset untouched by anyone else in ~2 years; VCL updates CLI-only from a local machine, unlogged.
- **booking-proxy** — 4-tier fallback (cache → object store → proxy → Booking.com origin): a broken tier is invisible to users while silently shifting load to the partner's origin; sole-owned Fastly Compute/WASM.
- **fastly-object-store** — invisible to normal Fastly Store-list API (needs product-specific S3-style creds); failures masked by fallback tiers.
- **doppler** — editing a secret auto-restarts every consuming prod service: a config edit that behaves like a deploy; org membership can't be enumerated via CLI.
- **waf-updater** — weekly crawler-whitelist job fails silently on credential loss; blocked crawlers surface months later with no trail.
- **aws-networking** — 10.0.0.0/16 assigned to 4 different (unpeerable) VPCs; VPCs "confirmed dead" in one account were alive in another — check cross-account before deleting.
- **aws-s3-static** — vouchers/etickets/receipts buckets publicly readable on permanent URLs (A153); no account-level Public Access Block; found only by the full 108-bucket sweep after a 15-bucket sample missed it.
- **backups-simplebackups** — effectively the whole DR story; a restore has never been verified; account owner left Jan 2026.
- **doit-finops** — cost-anomaly alerts are the only detector for API-scraping abuse and pointed at Yurii personally (A32/A132); its auto-generated network diagrams are the best network docs — export before access loss.
- **gcp-secret-manager** — deliberately separate from Doppler/LastPass (infra vs runtime vs human secrets); don't consolidate; Cloud SQL secret naming `instance-user-pwd-secret` means recreating an instance orphans its secret.
- **cloudflare** — zero IaC; two "DNS-only" zones actively proxy the legacy bungalow host (TLS to visitor, plaintext to origin).
- **dns-route53** — authoritative DNS for the business still lives in AWS; owner: Matias.

## Reusable audit tooling (re-run his process)

- **Read-only guard hooks** (`.claude/hooks/`): `readonly-guard.sh` (PreToolUse matcher `Bash` — escalates to "ask" when a command segment pairs an infra CLI with a mutating verb; fails closed without jq) and `readonly-guard-mcp.sh` (matcher `^mcp__` — allows only tools whose name leads with a read verb and contains no mutate verb). Portable: copy both scripts + two `hooks.PreToolUse` entries into any repo's or user's settings.json; self-contained tests ship alongside (`test-readonly-guard*.sh`).
- **Sweep briefs** (`docs/offboarding/agents/briefs/`): `_TEMPLATE.md` (scope, channels cheapest-first: repo → billing → CLI → MCP → browser; the four jobs: enumerate / record access / diff live-vs-code / emit human-only questions) and `slite-sweep.md` as a worked example. 18 prior findings files under `agents/findings/` (four-section format; findings are leads, not truth).
- **`/capture`** (`.claude/commands/capture.md`): orients from `STATE.md`, folds new findings, proposes exactly ONE next topic ranked by perishability × risk, then stops for a human.
- **Quarterly access-audit recipe:** wire the guard hooks → write a brief per domain (gcp/aws/edge/k8s/data/saas/ci) → run each sweep as an agent under the guards → findings to `findings/<domain>-<date>.md`, stating explicitly what was NOT checked (the 15-of-108-buckets sampling trap hid the S3 exposure for 16 passes) → for IAM use `gcloud asset search-all-iam-policies --scope=organizations/<id>` (one org-wide pass beats per-project loops) → human folds confirmed findings into `map/`, sanity-checking over-severe access verdicts with "who actually knows".

## Actions ledger (ACTIONS.md — 154 items: 39 P0 / 58 P1 / 39 P2 / 18 done)

Top open-action systems: gcp-iam (18), gcp-networking (13), gcp-projects (11), fastly-cdn (11), make-com (6), backups-simplebackups (6). Headline P0s beyond the landmines above: A56 (session DynamoDB, 771M items, no PITR), A57 (both RDS public + unencrypted), A34 (Places API key unrestricted since 2020), A59 (16/78 CloudWatch alarms → deleted SNS topics), A140 (86 GCP SA keys >2yr old), A133/A134 (unexplained $14k GCP line; undocumented OpenAI platform up to $4.7k/day), A81 (plaintext SigNoz token in Slite), A102 (undocumented cross-cloud AI pipeline peered into prod-ts-vpc, no-expiry 2021 SA key). Full ledger with owners: `docs/offboarding/ACTIONS.md`.

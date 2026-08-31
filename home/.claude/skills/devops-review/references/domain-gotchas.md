# Travelshift Domain Gotchas

Company-specific knowledge from Yurii Serhiichuk's (xSAVIKx) PR and review history. Repos: `guide` (G), `monorepo` (M), `bookings-overview-micro-service` (BO).

## guide / Kohana monolith ("service-marketplace")

- **Kohana core is never touched directly.** `application/classes/ORM.php` extends `Kohana_ORM` precisely so core modules stay pristine (kohana.top/3.3/guide/kohana/extension).
- **OpenTracing span discipline:** `complete_context_ok`/`complete_context_error` on **every** return statement (G#37121). Calling `complete_context_ok()` *before* a method that itself redirects is **intentional** — the redirect would prevent the span from ever closing. Automated reviewers repeatedly flag this as a bug; it isn't (G#37725).
- **DB schema rules:** automatic CI migrations apply to **staging only**; production requires manual application. New columns must be added **without the `AFTER` clause** (G#38292). Existing migrations are immutable (M#32802).
- **Read-heavy queries go to `DB::instance('replica')`** — check nothing still hits the writer (translations lookups were a known miss).
- **DB retry logic needs jitter** and documented env-var semantics ("I was not sure if `DB_RETRIES: 1` means we just enabled retries or this is a number of retries") (G#37887).
- **Repo policy is squash-only merges** — no explicit rebase needed; merging master in is fine (G#36266).
- **PHP 7.2 exception traces include call arguments** — an unreachable DB produces a PDOException containing the password verbatim; `zend.exception_ignore_args` only exists from 7.4 → redact explicitly (BO#65).
- **php-fpm mangles stdout** without `decorate_workers_output` (PHP 7.3+): wraps worker lines, destroys JSON, labels everything WARNING, chunks at ~1KB. Lumen 5.4 doesn't support `LOG_CHANNEL=stderr` (BO#65).
- **WireMock sidecar test infra:** KEDA workers don't share the web pod's `wiremock.local` hostAlias — each pod kind needs its own sidecar attachment. JVM sidecars starve below ~500m CPU (measured 2–5s for 5KB stubs at 150m). A starved mock **times out and throws**, and the resulting partial result set "reads exactly like 'the mock was bypassed and it hit the real API'" (G#38642/#38653). Mock variant selection must be header-based, not scenario-state-based — per-pod state races: "a mock that honours your variant only sometimes is worse than one that never does, since you would trust a wrong result" (G#38661).
- **Session affinity can't fix per-pod mock state:** "Affinity would pin only your curl; the app traffic that matters arrives from independent in-mesh callers." (G#38661)
- **currency-exchange staleness math is minute-based and does not match the docblocks** — trace the arithmetic before changing intervals (its CLAUDE.md).

## Marketplace / multi-tenant parity

- **Marketplace identity comes from `x-travelshift-url-front` / `x-ts-marketplace`, never `Host`** (M#41828). (Root CLAUDE.md documents the two value shapes per upstream.)
- **Per-marketplace config is duplicated deliberately** — standing checklist question: "we usually only test GTI, yes. but still... do we need GTE queues as well?" (G#37796). Staging needs the same change as prod almost every time someone forgets.
- **Bot/SEO traffic is not an "average joe":** feeding mock pricing to a crawler like sitebulb needs sign-off — "have you confirmed this with someone?" (G#37422)

## Cross-environment config traps (.NET services)

- **`CurrencyExchangeSettings.BaseAddress` in appsettings.json always wins over the `CURRENCYEXCHANGEBASEURL` env var — that env var is dead everywhere it's set.** This caused two live cross-environment leaks (prod Flight → staging currency, stage Cart → prod currency). When "the env var isn't taking effect," check whether appsettings hardcodes the value. (His internal-gateway audit, Asana task 1215122961030268.)
- Same audit: only 4 real service-to-service callers still used the internal gateway in prod; the gateway hop **breaks parent/child span linkage** and roughly doubles p50 (monolith client 835ms vs direct ~330ms). His recommendation: cluster-local calls + an Istio `AuthorizationPolicy` denying in-mesh callers on the gateway as a regression guardrail.

## HTTP / networking semantics

- **HTTP 499 (client closed request):** keep it over faking a 200, but classify honestly — client-initiated cancellation is 4xx; server-side timeout surfacing as cancellation should be 5xx (M#40935).
- **Node signal handling:** use console-log inside SIGTERM handlers (async cloud-logging transports may be killed/slow) and always return exit codes "cause if not — the process just hangs till it's killed" (web-cache-agent).
- **Sitemap hard limit:** 50MB — stay below 49MB for Google (sitemap-generator).

## LLM / AI integration review checklist

From the ChatGPT translation-driver review (G#37307) and tour AI content (M#41353):

- `temperature: 0` for translations/deterministic tasks — "do we really want the model to be creative in translations?"
- Structured output via JSON schema so the response format is guaranteed.
- `max_tokens` is deprecated → `max_completion_tokens`; and bound the **input** to match.
- Prefer the `responses` API where the client library supports it.
- **Translate the system prompt into the target language** — measurably better translations; technique proven in the .NET NLG pipelines.
- Keep only the real public API public (`translate`/`proofread` private helpers); fail fast at construction time for bad config.
- Model/config numbers (temperature, batch sizes like `9`/`3.5`) belong in configuration with the decision process documented.
- **Security bar for user-facing bots:** learn from the Meta AI support-bot PII exploits. Email + booking number is weak authentication; mismatch-error responses create an email-enumeration vector (M#43339).
- Cost-sensitive crons and batch AI jobs: announce to the team before running; prefer bi-weekly/monthly + manual trigger over aggressive schedules (M#41353).

## AI-assisted development workflow risks

- **A committed `CLAUDE.md`/agent-instruction file is a prompt-injection surface at monorepo scale:** "any claude session being hijacked/corrupted by this instruction... a high-level AI session that greps the module will see this" (M#43339). Review agent-instruction files as executable config, not docs.
- **Bulk AI-generated PRs are unreviewable as a unit:** "idk how anyone can digest this amount of data in a single go... we'd better split such things into digestible parts" (M#43339). Harness setup, specs, and implementation are separate PRs.
- **Heavy agent frameworks need a stated rationale** vs the alternatives already in use ("stay service already uses agentos. a lot of people are using superpowers... this is a very big framework").
- **Disclose AI authorship** in review replies posted on someone's behalf (his own late-2026 practice: "🤖 AI-generated reply (Claude Code, acting for @xsavikx)"), and proofread AI output before shipping — an unedited LLM placeholder once landed in a commit message.
- **AI review bots are peers, not gatekeepers:** verify their findings; rebut with evidence ("code successfully deploys. we're not spreading promises..."); ask them directly ("@coderabbitai is this still an issue?"); and remember they wrongly flag known-intentional patterns (span-before-redirect) repeatedly.

## Where the bodies are buried (the offboarding audit)

His offboarding brain dump (`infrastructure-resources` PR #153, landing in `docs/offboarding/`) is the canonical infra reference: 82 system entries, a 154-item action ledger (39 P0), and 26 landmines in *looks like → actually → instead* form. "Do not read it front to back... read it when you touch the system." The distilled index — landmines, per-system gotchas, P0 headlines, and which `map/<system>.md` file to open — is in [offboarding-map.md](offboarding-map.md). Check whether a P0 from that ledger is still open before trusting the affected system.

# Testing runbook

Everything here was verified against the local stack on 2026-09-11. The numbers are real baselines: if you
see different ones, something changed, and that is worth knowing before you start.

## The one thing to understand first

**This project's characteristic failure is a green test over a broken system.** Three separate mechanisms
produced it, and all three are now closed — but they will come back if you are not deliberate:

1. **Fixtures are git-ignored and the strongest suites skipped green without them.** A fresh clone had
   `corpus-roundtrip` and `transform-parity` skipping silently. **Always run with
   `CONTENT_STUDIO_REQUIRE_FIXTURES=1`**, which turns a missing oracle — or an unreachable local stack —
   into a failure.
2. **Both reference harnesses were more forgiving than the real connector in one direction and stricter in
   another.** Every push test passed against the mock while the documented path through the real connector
   could not work at all. **A change to the contract is not proven until it has run against the real .NET
   connector**, not the shim.
3. **Sentinel skips.** Four tests are *supposed* to skip: they are inverted placeholders that only run when
   fixtures are absent (`!! SKIPPED, NOT PASSED — …`). A skip count of 4 is correct; 5 is a regression.

## The fast path

Before anything else, and after any change to either service:

```bash
P=~/.claude/skills/mcp-content/scripts/probe.mjs
node $P health        # admin, connector (401 is healthy), shim
node $P tools         # both endpoints diffed — cheapest drift signal
node $P limits        # what start_push reports; absent means the skill falls back
node $P codes         # the error-code matrix against a LIVE connector
node $P compressed    # the gzip+base64 relay path, end to end, cleaned up after
node $P drafts        # reconciliation, incl. the did-anything-publish check
```

`codes` is the one to run habitually. Every refusal it checks is a path that *works* — what it tests is
whether the error tells the caller the truth, which is the defect class that has cost this project most.

## Baselines

| Suite | Command | Expected |
|---|---|---|
| guide unit | `cd guide/tools/content-studio && CONTENT_STUDIO_REQUIRE_FIXTURES=1 npx vitest run` | **1399 passed / 4 skipped**, 31 files, ~125 s (2026-09-14) |
| corpus gate | `npm run test:corpus` | **100.000 %** both files — 20 259/20 259 and 17 563/17 563 |
| connector | `cd mono && export PATH="$HOME/.dotnet:$PATH" && dotnet test tests/ContentMcp.Tests/ContentMcp.Tests.csproj -c Release` | **669 passed** (2026-09-14) |
| connector format | `dotnet csharpier check src tests` | clean (CI gate) |
| PHP style | `docker exec monolith-service /app/kohana/vendor/squizlabs/php_codesniffer/bin/phpcs --standard=phpcs.xml --report=summary <file>` | **0 errors**; warnings are pre-existing |

`task phpcs` fails with "the input device is not a TTY" and then cannot fetch `origin/development` — call phpcs
directly as above instead.

## Two environment stalls that look like product bugs (2026-09-11)

- **VPN drop = admin dead, not slow.** Every `master-*.staging.gcptravelshift.com` hostname resolves to
  the GCP ingress `10.60.0.81`; the local monolith calls those on each admin request with no connect
  timeout. With the VPN down each request blocks ~100 s in `SYN_SENT`, the 4 php-fpm workers saturate and
  every driver call hits the 420 s tool ceiling. Tell: `nc -z -G 3 10.60.0.81 443` from the Mac and
  `awk '$4=="02"' /proc/net/tcp` inside `monolith-service`. The colima VM regains the route a minute or
  two after the Mac does. A `docker restart monolith-service` afterwards flushes the queued requests.
- **After a VPN reconnect Node may stop resolving `admin.traveldev.localhost`** (resolver order flips to
  8.8.8.8; curl and browsers special-case `.localhost`, Node does not). Fix: `/etc/hosts` line
  `127.0.0.1 admin.traveldev.localhost cn.traveldev.localhost`, or preload a `dns.lookup` shim via
  `NODE_OPTIONS=--import`.
- A second 7-minute stall (one request served in 7 min, php-fpm at `pm.max_children=4`) was **not**
  attributed; the same GraphQL calls answered in 0.5 s afterwards. Redis is local and the queue transport
  is `null:`, so neither is it. If it recurs, snapshot `ps -eo pid,stat,wchan:16,args` + `/proc/net/tcp`
  inside the container *during* the stall before restarting anything.

## Base mode (2026-09-14)

Editing the English source goes through `POST /articles-admin/form_draft_save/<id>`, an endpoint that
exists precisely because `form_save` both drafts and publishes. Running base tests against a monolith
without it makes every push answer `admin_rejected` from a 404 — check the branch before blaming the
connector.

The driver is `node harness/e2e-base.mjs --mcp-url … [--reference …]`, also `--only base` through
`e2e-all.mjs`. Its load-bearing step is "the live article row is byte-identical": it fingerprints every
column of `articles` before and after and fails if anything moved. The target's existing
`content_drafts` row is captured before the run and restored after, so a local DB that already carries
drafts is left as found — article 286 has had one since May.

Two refusals worth re-checking by hand whenever the error taxonomy changes, because both used to send
the reader off to fix something that was never wrong:

```bash
# English as a translation → default_locale_not_translatable, NOT forbidden_locale
node ~/.claude/skills/mcp-content/scripts/probe.mjs codes
# an English address → is_source_language true, locale_editable false
```

Driver expectations that are now baseline: `tools` fails exactly 3 pre-existing cases (`urls.live` on an
untranslated locale, malformed locale → `not_found`, direct PUT without `payload_sha256`); `ckeditor`
`embed-iframe-attrs` is an XFAIL (read leg strips iframe attributes). Anything else failing is new.

## Bringing the stack up

```bash
export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock
docker ps --format '{{.Names}}\t{{.Status}}'     # want mysql, monolith-service, front-lb, proxysql

# the real connector. NOT :8080 — that port is usually taken by mitmweb on this machine.
cd ~/Work/monorepo/src/dotnet/service-content-mcp && export PATH="$HOME/.dotnet:$PATH"
ASPNETCORE_ENVIRONMENT=Development ASPNETCORE_URLS=http://127.0.0.1:8790 \
OAuth__Issuer=http://127.0.0.1:8790 OAuth__Resource=http://127.0.0.1:8790/mcp \
OAuth__RequireConsent=false OTEL_SDK_DISABLED=true \
dotnet run --project src/ContentMcp -c Release &

# the reference shim, used as the oracle
cd ~/Work/guide/tools/content-studio && node harness/local-connector/server.mjs --port 8791 &
```

Health: `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8790/.well-known/oauth-protected-resource/mcp`
→ 200, and `POST /mcp` → **401** (the healthy unauthenticated answer).

**Running a second instance on a spare port is the safe way to test a rebuild** without disturbing a long
driver run. `dotnet test` rebuilds `bin/Release/**` in place, so a running process keeps its in-memory image
but will come up changed on its next restart — do not conclude a fix is live until you have restarted it.

## The end-to-end drivers

```bash
node harness/e2e-all.mjs --list
node harness/e2e-all.mjs --keep-going          # all five, one summary matrix
node harness/e2e-all.mjs --only fields         # one at a time keeps failures attributable
```

| driver | proves | ~time |
|---|---|---|
| `tools` | every MCP tool and error code, diffed against the shim as oracle | 5 min |
| `loop` | the skill happy path end to end, with `open_page` parity | 1.5 min |
| `fields` | every editable field of both page types, per-field SQL read-back | 4.5 min |
| `ckeditor` | every CKEditor construct through the real admin save | **26 min** |
| `preview` | preview/transform parity against the monolith's own render | 0.5 min |
| `locale-gate` | a translator denied a locale gets `forbidden_locale`, not `not_found` | opt-in |

`locale-gate` cannot share a run: it needs `LOCAL_AUTH_USER_ID` set to a translator holding one locale and not
another (user 113 "Xiaochen Tian" is `zh_CN`-only), the monolith **recreated** (an `env_file` change needs a
recreate, not a restart), and the bearer token minted *while* that identity is live, because the connector
captures the locale list during the OAuth authorize step.

Everything the drivers write is `draft = 1`. **Nothing in this project may ever publish.**

## Draft hygiene — do this every time

Driver runs leak draft rows, especially `faq_item` ones, which a push creates as a side effect and which do not
hang off `translations.orm_id`. Take a baseline before and reconcile after:

```sql
SELECT COUNT(*) FROM translations WHERE draft=1;                        -- baseline
SELECT COUNT(*) FROM translations WHERE draft=1 AND updated_time >= CURDATE();
SELECT COUNT(*) FROM translations WHERE draft=0 AND updated_time >= CURDATE();  -- MUST be 0
```

The last one is the real safety check: a non-zero count means something published. Delete only `draft=1` rows,
never a `draft=0` row, and clear the matching `translations_draft` index rows or `has_draft_translation()` keeps
claiming a draft exists.

Distinguish debris from real work before deleting: automated runs leave clusters whose timestamps agree to the
second, while a genuine unpublished human draft sits alone on its own date. Back up the rows to a file first —
a `DELETE` here is irreversible.

## Measuring the corpus

`harness/fixtures/corpus/*.jsonl` are two **different shapes**, and a script written for one silently produces
empty results on the other rather than failing:

- `base_en.jsonl` — one row per page, fields under `r.fields` (English base text, **not** editable through the
  translate path).
- `translations.jsonl` — one row per **field**: `{type, orm_id, locale_id, field, translation, draft}`. To get a
  page payload you must group by `(type, orm_id, locale_id)`.

Getting this wrong understated the largest payload in the corpus by 27 %. If a corpus measurement looks
surprisingly clean, check you are reading the shape you think you are.

## Verifying a claim about the real system

The pattern that actually caught things today: **do not reason about the regex, run it in the container.**

```bash
docker exec monolith-service php -r '$re="…"; …'    # the real PCRE, the real limits
```

Then prove a change is safe by replaying it over every real stored value and diffing old against new, rather
than over the handful of cases you thought of. That is what made the `<iframe>` regex fix safe to apply: 649
real values, identical output on every one.

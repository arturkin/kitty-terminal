# Debugging playbook

Work from the outside in: Claude → Fastly → marketplace nginx → connector pod → monolith admin → MySQL. Each layer
has one command that proves whether the request got through it.

## Layer probes

| Layer | Command | Healthy answer |
|---|---|---|
| Fastly edge (public) | `curl -si -X POST https://admin.<env-host>/mcp` | `401` with `WWW-Authenticate: Bearer … resource_metadata=…` |
| Fastly logs | export from the Fastly UI as CSV; columns `Client IP, URL, Response Status, Response State, Backend Name, Request User Agent` | `Response State = PASS`, `Backend Name = …sigsci_waf`; `ERROR` + empty backend = synthesised at the edge |
| marketplace nginx (in-cluster) | `kubectl exec <master-service-marketplace pod> -c service-marketplace-nginx -- curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1/mcp -H 'Host: admin.staging.guidetoiceland.is'` and again with `-H 'Host: origin' -H 'x-travelshift-url-front: https://admin.staging.guidetoiceland.is'` | `401` both ways; `404` = host gate; `502` = connector down |
| connector pod | `POD=$(kubectl get pods -n default -o name \| grep content-mcp)`; access log: `kubectl logs -n default $POD -c istio-proxy --since=1h \| grep -v opentelemetry`; app log: `kubectl logs -n default $POD -c service-content-mcp --since=1h` | app log lines are JSON with `category` (`ContentMcp.Host.OAuth.*`, `ContentMcp.Shared.Push.*`) |
| connector → admin | from the marketplace nginx container: `curl -s -X POST http://127.0.0.1/api/v2 -H 'Host: admin.staging.guidetoiceland.is' -H 'x-ts-marketplace: guidetoiceland.is' -H 'x-ts-marketplace-admin: true' -H 'x-travelshift-url-front: https://admin.staging.guidetoiceland.is' -H 'content-type: application/json' -d '{"query":"{ currentUser { id } }"}'` | `{"data":{"currentUser":null}}` without a cookie; `Kohana bootstrap can't define host..` = marketplace headers missing |
| MySQL (local) | recipe in `guide:tools/content-studio/docs/DEV_ENV.md` (`docker exec mysql sh -c 'mysql -uroot -p"$MYSQL_ROOT_PASSWORD" "staging-gti" -N -e "…"'`) | never read `.env`; the password is dereferenced inside the container |

The connector pod has no `curl`; probe from the marketplace pod (`service-marketplace-nginx` container) instead.
Anthropic's connector egress is `160.79.104.0/21`, UA `python-httpx/…`; grep the istio access log for `160.79.` to
see whether Claude ever reached the pod.

## Symptom → cause seen so far

| Symptom (as the person sees it) | Cause | Fix |
|---|---|---|
| Discovery URLs 404 with a bare `nginx/1.29.x` page while `/.well-known/anything-else` gives a Kohana 404 | nginx host gate read `$host`; Fastly rewrites Host | gate on `$host` **or** `x-travelshift-url-front` (done 2026-09-10) |
| "Couldn't register with … sign-in service … add an OAuth Client ID" | Claude's first `POST /mcp` never reached us: staging Fastly access gate answered `401 Restricted` (Basic) | add `160.79.104.0/21` to the staging ACL; prod has no gate |
| "This admin account cannot use the Claude connector … unreadable body" | identity GraphQL got `200 text/html` "Kohana bootstrap can't define host.." — in-cluster call lacked `x-ts-marketplace*` | connector adds the Fastly marketplace headers when `Admin__HostHeader` is set (`content-mcp-fixes`) |
| FAQ draft saved, admin FAQ page shows no "Draft Translation!" banner | `update_translations()` writes `draft=1` rows without a `translations_draft` index row | `Model_Faq_Item::has_draft_translation()` override |
| Publishing a FAQ block leaves stale `draft=1` rows | same lying index guarded the delete at publish | same override; verified both directions locally |
| Article/attraction draft byte-different from what was pushed | HTMLPurifier runs unless `user_type === admin && has role editor` (`Translate.php` ~`:495`) | grant `editor`; do not weaken the test |
| `session_expired` on every call | connector restarted / spot preempted — in-memory tokens, one replica | reconnect; never deploy mid-edit |
| Tool call dies around 60 s in prod | Fastly `first_byte_timeout` 60 s on the marketplace origin | raise to 300 s for `/mcp` only (checklist §4) |
| `nginx -t` fails with EOF mid-file on the local stack | stale virtiofs mount of `dev/nginx/nginx.local.conf` | `docker compose -f docker-compose.local.yml up -d --force-recreate --no-deps front-lb` |
| Local admin pages 500 with a ParseError in `Model/User.php` | unresolved merge marker in the local auth-bypass file | re-apply the bypass block above the new code; never commit the file |
| Every relay push refused as `payload_corrupt`, advice blames Claude for retyping | the connector parsed bare hex only and threw on the `sha256:` prefix the skill sends; the `catch` returned an empty array so the compare always failed | fixed 2026-09-11 (`Hex()` strips the prefix). If it recurs, hash the payload yourself and compare — do **not** trust the advice text |
| `not_found` — "the admin cannot find this page" — on a push that names a real page | a malformed *argument*, not a missing page: `not_found` used to be overloaded for argument validation | now `bad_argument`. On an older deployment, check `type`, `locale`, `include`, `version_hash` and `payload_encoding` before touching the page id |
| The skill tells the person to re-push with `--force` after a push that already worked | a spent ticket answered `conflict`; `push.mjs` routes every conflict to `reportConflict()` | a replayed ticket is `upload_missing`; never `--force` to clear one |
| Push dies with "the admin refused to save this", detail shows an nginx **504** on `PUT /mcp/upload/…` | the direct PUT timed out under load; the direct→relay fallback covers only `unreachable` and a token-less 401 | `CONTENT_STUDIO_TRANSPORT=relay` proves it in seconds; nginx's own log shows `upstream timed out` |
| Admin renders an **empty CKEditor** for a page that has content | `preg_replace` at `Translate.php:455` returned NULL, and `htmlentities(NULL)` is `""`. Trigger is the count of `<iframe` starts on one line (cliff between 100 and 150), **not** line length — a 110 KB single line is fine | saving from that empty editor blanks the article; the regex is now bounded to one tag |
| A one-word edit shows the whole article as changed in the draft-vs-live view | the converter decoded every named entity, or dropped inter-block whitespace, because the per-document policy was not detected | `meta.entities` / `meta.block_whitespace`; the corpus gate stays 100 % either way, so it will not catch this — compare bytes |
| A preview rewrites an `<img>` the monolith leaves alone, into a CDN URL that 404s | an image row with no width/height read as *loaded*: the connector reports an unresolvable id as `exists: null`, the shim uses `false` | mirror the monolith guard (`loaded() && width && height`) on the consumer side |

## Local reproduction

- Stack: `admin.traveldev.localhost:4001`, docker via colima (`export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`).
- Real-DB, real-admin connector: `cd tools/content-studio && npm run shim` (`harness/local-connector/`); loop driver
  `node harness/e2e-loop.mjs --help`; fixture-only: `npm run mock`.
- Skill scripts offline: `node skill/scripts/pull.mjs --open-page harness/fixtures/open_page.article-286-de.json --workfolder /tmp/ws`,
  then `diff.mjs`, `build-preview.mjs`, `push.mjs --dry-run` on the created workspace.
- Prove a monolith fix end to end: find a real row (e.g. unindexed FAQ draft SQL in `system-map.md`), curl the admin page,
  count the banner with and without the change (`git stash push -- <file>` / `pop`).

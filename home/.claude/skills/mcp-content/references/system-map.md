# System map

Paths: `guide` = `/Users/arturkin/Work/guide`, `mono` = `/Users/arturkin/Work/monorepo/src/dotnet/service-content-mcp`.

## Environments

| | Admin host | Connector | Notes |
|---|---|---|---|
| local | `http://admin.traveldev.localhost:4001` (auth bypassed via `LOCAL_AUTH_USER_ID`) | **:8790** for the real connector and **:8791** for the shim, both bypassing nginx — :8080 is usually taken by the user's `mitmweb`, and nginx's upstream `host.docker.internal:8080` then points at it. Needs `Admin__MarketplaceDomain=guidetoiceland.is`, or `x-ts-marketplace` is derived from the local admin host and the monolith answers "Kohana bootstrap can't define host.." to everything. Full runbook in [testing.md](testing.md) | local DB subset has only `en, zh_CN, de`; docker via colima (`export DOCKER_HOST=unix://$HOME/.colima/default/docker.sock`); DB recipe in `guide:tools/content-studio/docs/DEV_ENV.md` (schema `staging-gti`, password dereferenced inside the container) |
| staging | `https://admin.staging.guidetoiceland.is` | pod `master-service-content-mcp` ns `default`, cluster `gke_stage-ts_europe-west2_stage-ts-gke`; issuer/resource pinned to the staging host | reachable via `kubectl exec`; readiness checks nothing external |
| prod | `https://admin.guidetoiceland.is` | same Helm release name, prod cluster (not inspected from this machine; kube context is staging) | Fastly service `lXSWJKHuOLN5md28xlwFh6`; origin timeouts 60 s / 10 s — `/mcp` needs 300 s (checklist §4) |

Connector endpoints (all behind nginx on the admin host, prefix **not** stripped): `POST /mcp` (Streamable HTTP),
`PUT /mcp/upload/{ticket}`, `/mcp/oauth/{authorize,token,register}`, `/.well-known/oauth-authorization-server`,
`/.well-known/oauth-protected-resource/mcp`. Unauthenticated `/mcp` must answer **401** with a `WWW-Authenticate` challenge.
Claude's OAuth callback `https://claude.ai/api/mcp/auth_callback` is in the connector's default redirect allowlist.

## Guide repo — `tools/content-studio/`

| Path | Role |
|---|---|
| `skill/SKILL.md`, `skill/scripts/{pull,build-preview,push,diff}.mjs` | the shipped skill; scripts import `../../lib/` in-repo, rewritten to `../lib/` by `harness/package-skill.mjs` |
| `lib/converter/` (`fields.mjs` HTML/JSON field kinds, `html2md`, `md2html`) | lossless Markdown ⇄ HTML; corpus gate `npm run test:corpus` must stay 100 % |
| `lib/validate/` (`editable.mjs`, `attraction-name.mjs`, `faq.mjs`, `forbidden.mjs`) | push-time validators |
| `lib/preview/` (`workspace.mjs` BODY/TITLE maps, `shell.mjs`, `harvest.mjs`, `indicator.mjs`) + `lib/transform/` | client-side replica of `Helper_Article::get_content`; `isAttraction` booleans live here |
| `lib/transport/` (`transport-direct`, `transport-relay`, `payload-encoding`, `mcp-client`, `index.mjs` fallback) | direct PUT vs relay-through-model; `payload_sha256` mandatory and always over the **decoded** bytes; `payload-encoding` carries `gzip+base64` for a page over `limits.relay_max_chars` |
| `harness/mock-mcp/` (`lib/pages.mjs`, `tools.mjs`, `conflict.mjs`, `data/shortcodes.<type>.json`) | fixture-backed MCP server; `conflict.mjs` is the twin of `ConflictSlimmer.cs` |
| `harness/local-connector/` (`lib/read.mjs` SQL reader, `lib/admin.mjs` form POSTs, `server.mjs`) | real-DB, real-admin shim used for local E2E |
| `harness/fixtures/open_page.*.json` | contract fixtures; same bytes as `mono/fixtures/reference/` |
| `harness/fixtures/corpus/*.jsonl`, `fixtures/graphql/` | **git-ignored**; the strongest suites skip green without them. `CONTENT_STUDIO_REQUIRE_FIXTURES=1` makes that a failure. Two different row shapes — see [testing.md](testing.md) |
| `harness/e2e-all.mjs` + `e2e-{tools,loop,fields,ckeditor,preview,locale-gate}.mjs` | the end-to-end drivers against the real stack; `e2e-all` preflights admin, both endpoints and the token before running anything. `locale-gate` is opt-in — it needs a different `LOCAL_AUTH_USER_ID` |
| `harness/pixel-diff.mjs`, `harness/build-assets.mjs` | pixel harness, live-site asset harvest (CSS+templates refresh as one unit) |
| `docs/DEV_ENV.md`, `docs/CENSUS.md`, `docs/CONVERTER_REPORT.md`, `docs/SHIM_REPORT.md` | verified environment facts, corpus census, format contract, what the real monolith did |
| `../../docs/content-studio-deployment.md` | the deployment checklist |

## Guide repo — monolith

| Path | Role |
|---|---|
| `kohana/application/classes/Controller/Admin/Translate.php` | `action_<type>()` GET + `action_<type>_process()` POST per type; route `/translate/<type>_process/<id>?locale=`; `update_translations()` generic writer (no index row); purifier gate `user_type === admin && has role editor` skips HTMLPurifier |
| `kohana/application/classes/Model/<Type>.php::$_translate` | field map; `type` values seen in the codebase: `default`, `html`, `textbox` (plain textarea), `uri`, `select`, `icon`, `number`, `tour`, `hotel`, `color_selector` — the source of truth for what a type translates. Attraction `notes` is JSON stored through a `default` field with `hide_translation` |
| `kohana/application/views/admin/translate/<type>.tpl` | the translate form the connector parses: input names/ids, `allowedShortcodes*` arrays, draft-choice modal id (`#translation-draft-choice-modal` shared, or `#<type>-translation-draft-choice-modal`) |
| `kohana/application/classes/Helper/Draft/BodyTransforms.php` | `applyEmbedTransforms` (article only today) — decides whether the connector must reverse editor munging |
| `kohana/application/classes/ORM.php` (`get_translation`, `has_draft_translation`) | seeds `<field>_draft` keys only when `has_draft_translation()` is TRUE |
| `kohana/application/classes/Model/Faq/Item.php` | `has_draft_translation()` override (index bypass) + `tests/unit/Model/FaqItemTest.php` |
| `kohana/application/classes/Helper/Draft/DraftType.php` (`TYPES`), `Helper/Draft/Backend/TranslationDraft.php` | the newer draft service; per-type preparer/reader/publisher classes |
| `helm/service-marketplace/{stage,prod}-values.yaml`, `dev/nginx/nginx.local.conf` | four `/mcp*` location blocks + `map … $content_mcp_host` gate; keep the three identical |

## Monorepo — `service-content-mcp`

| Path | Role |
|---|---|
| `src/ContentMcp/Shared/PageType.cs`, `PageTypeExtensions.cs` | the type enum + wire names |
| `Features/{WhoAmI,OpenPage,ResolveUrl,ListShortcodes,StartPush,FinishPush}/*Tools.cs`, `Features/ToolInputs.cs` | the **six** tools — `search_images` exists nowhere any more. `ToolInputs` binds string arguments; check what advice text a refusal carries before adding one |
| `Adapters/Monolith/AdminMarkup.cs` | **single choke point** for CSS selectors (enforced by `AdminMarkupChokePointTests`) |
| `Adapters/Monolith/AdminPageParser.cs` | `EditableFields/BodyFields/RequiredSelector/ParsePage` per type |
| `Adapters/Monolith/AdminPageReader.cs`, `AdminPageUrls.cs`, `AdminProcessUrls.cs`, `AdminDraftWriter.cs`, `AdminSessionHttpClient.cs` | read (form pages + GraphQL facts + `getFaq`) and write (form POSTs) |
| `Shared/Push/PushService.cs`, `DraftFormBuilder.cs`, `UploadPayload.cs`, `ConflictSlimmer.cs`, `Shared/VersionHash.cs` | push orchestration, posted-field lists, hash |
| `Host/OAuth/*`, `Host/UploadEndpoint.cs`, `Adapters/Memory/MemoryTicketStore.cs` | OAuth 2.1 (PKCE, CIMD, DCR), single-use upload tickets, in-memory state (1 replica by design) |
| `Configuration/*.cs`, `appsettings*.json`, `helm/service-content-mcp/{stage,prod}-values.yaml` | options incl. `Admin__RegistrySeed<Type>Id`, `Admin__TimeoutSeconds`, `OAuth__Issuer/Resource` |
| `fixtures/admin/<type>/*.{html,headers}`, `fixtures/reference/open_page.*.json`, `fixtures/admin/MANIFEST.md` | recorded admin pages + contract fixtures |
| `tests/ContentMcp.Tests/` | `dotnet test tests/ContentMcp.Tests/ContentMcp.Tests.csproj -c Release`; CI also runs `dotnet csharpier check src tests` |
| `.github/workflows/service-content-mcp.yaml` | tests on PR; on `master` push deploys stage **and** prod (`cancel-in-progress`, single replica → live sessions drop) |

## Verification commands

```bash
# discovery + challenge, per host
curl -s https://admin.staging.guidetoiceland.is/.well-known/oauth-authorization-server | jq .issuer
curl -si -X POST https://admin.staging.guidetoiceland.is/mcp | grep -i www-authenticate
# local gate, both host sources
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://admin.traveldev.localhost:4001/mcp
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://traveldev.localhost:4001/mcp -H 'x-travelshift-url-front: https://admin.traveldev.localhost'
# unindexed FAQ drafts (should now be visible in admin)
SELECT COUNT(*) FROM translations t WHERE t.type='faq_item' AND t.draft=1 AND t.deleted=0
  AND NOT EXISTS (SELECT 1 FROM translations_draft d WHERE d.id=t.id);
```

## Edge gotchas seen in practice

- **Staging Fastly access gate**: non-office clients get a synthetic `401 Restricted` (`WWW-Authenticate: Basic`) at the
  edge, `Response State = ERROR`, no backend. Claude's connector egress is `160.79.104.0/21` (UA `python-httpx/…`); it must be
  on the ACL or the OAuth handshake dies before discovery. Prod has no such gate.
- **Fastly rewrites Host** to the origin hostname; nginx must gate on `x-travelshift-url-front` too.
- **Bots rate limiter** (prod VCL) keys on User-Agent names (`ClaudeBot`, `anthropic-ai`, `Claude-Web`, …) with a global
  counter per name and a 10-minute penalty box. Separately, the staging access gate answers a `ClaudeBot` UA with `410 Restricted`.
- **In-cluster admin calls need the Fastly marketplace headers.** `MarketplaceContext` reads `HTTP_X_TS_MARKETPLACE` /
  `HTTP_X_TS_MARKETPLACE_ADMIN`; without them the monolith answers `200 text/html` "Kohana bootstrap can't define host.."
  to any request, including GraphQL. The connector adds `x-ts-marketplace`, `x-ts-marketplace-admin: true` and
  `x-travelshift-url-front` whenever `Admin__HostHeader` is set (`ServiceCollectionExtensions.ConfigureAdminClient`;
  added 2026-09-10 on `content-mcp-fixes`, verify it has been merged before relying on it).

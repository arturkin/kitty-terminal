---
name: mcp-content
description: Use when working on Content Studio — the Guide to Iceland MCP content-editing system spanning the guide repo (tools/content-studio skill, Kohana admin translate pages, nginx routing) and the monorepo .NET connector (src/dotnet/service-content-mcp) — including adding a new editable page type, changing open_page/push contracts, debugging drafts or the /mcp routing, or deploying either half.
---

# mcp-content — Content Studio across both repos

## Overview

Content Studio lets editors edit translations as Markdown through Claude and save them **as admin drafts only**.
Three moving parts, two repos, one contract:

| Part | Where | Deploys via |
|---|---|---|
| Skill (`SKILL.md` + Node scripts, `lib/`) | `guide:tools/content-studio/` | `npm run package` → zip → Claude.ai Settings → Capabilities → Skills |
| .NET MCP connector `service-content-mcp` | `monorepo:src/dotnet/service-content-mcp/` | push to `master` deploys **stage and prod together** |
| Monolith admin translate pages + nginx `/mcp` routing | `guide:kohana/…/Controller/Admin/Translate.php`, `helm/service-marketplace/*-values.yaml`, `dev/nginx/nginx.local.conf` | push to `development` deploys **stage and prod together**; label `deploy-to-staging` on the PR deploys staging first |

The connector has no database credential: it replays the signed-in admin's cookie against the admin form pages and
GraphQL `/api/v2`. Everything it knows about a type it learns by **parsing the translate page** and **posting the form**.

**Core rule:** per-type knowledge lives in duplicated tables on both sides. A new type is mostly table entries plus one
parse method, one posted-field list, fixtures and tests; the preview's `isAttraction` booleans are the only real logic to generalise. See [references/adding-a-type.md](references/adding-a-type.md).

## Repos, branches, status

- `guide` (`/Users/arturkin/Work/guide`): PRs target `development`; **a push to `development` deploys staging and production**;
  `origin/master` is dead (years behind). Current work branches: `content-studio-base-mode` (skill + harness)
  and `article-draft-only-endpoint` (the monolith endpoint base mode writes through, PHP only, its own PR).
- `monorepo` (`/Users/arturkin/Work/monorepo`): `master` deploys; current work branch `mcp-base-mode`. The checkout may be
  on another branch — inspect with `git show origin/master:<path>` when unsure.
- The user commits and pushes; never do either. Never commit `Model/User.php`.
- **Live status** (what is deployed, what is pending) is tracked in `guide:docs/content-studio-deployment.md` "Status" block and
  the memory note `project-content-studio-validation`; read those before assuming anything below is already shipped.

## Read first

- **`guide:tools/content-studio/docs/HANDOVER.md` — start here.** Current state of both working trees
  (commits `caf59b8737` / `76fdfc1026`, PHP removed in the follow-up), what is fixed, what is open, and what must be re-measured against prod before
  shipping. Written 2026-09-11.
- [references/system-map.md](references/system-map.md) — files, ports, env, hosts, verification commands, deploy facts.
- [references/debugging.md](references/debugging.md) — layer probes, symptom → cause table, local reproduction.
- [references/testing.md](references/testing.md) — **read before changing anything.** Local e2e runbook, real
  baselines, why this project keeps producing green tests over a broken system, draft hygiene.
- Contract of record: `~/.claude/plans/sharded-rolling-honey.md` §4 + §4-DECIDE (A1–A24). Connector-side copy in
  `monorepo:src/dotnet/service-content-mcp/DESIGN.md` / `CLAUDE.md`. If you change the contract, change **both** plan copies and both repos.

## Invariants that bite

- **An error code that lies costs more than a missing feature.** The recurring defect here is not a broken code
  path — it is a working path whose error sends the caller to fix something that was never wrong. Four separate
  instances: a relay push refused as `payload_corrupt` (blaming Claude for retyping the payload) when the connector
  simply could not parse the `sha256:` prefix; an unsupported `payload_encoding` answering `not_found` ("the admin
  cannot find this page"); the same call answering `not_found` instead of `upload_missing` merely because an
  encoding was named; and a spent ticket answering `conflict`, which routes `push.mjs` to `reportConflict()` and
  tells the person to re-push with `--force` — writing the draft twice. **When you add a refusal, check what its
  advice text tells the reader to do.**
  The taxonomy now has **`bad_argument`** for a malformed call, so `not_found` is once again only for a thing that
  is genuinely absent — an unknown page, ticket, FAQ item or unresolvable URL. Argument validation cannot know
  whether the page exists, so nothing in `ToolInputs` may answer `not_found`. Advice text lives in
  `guide:tools/content-studio/lib/transport/errors.mjs` (`ERROR_ADVICE`, `NOTHING_WAS_SAVED`) — a code with no
  entry there prints "an error we do not recognise".
- **The human publish click is the safety gate, so the draft-vs-live diff has to stay readable.** A converter
  change that rewrites the whole body — decoding every `&uuml;`, or dropping inter-block newlines — makes a
  one-word edit look like a full rewrite and the reviewer cannot see what the editor did. Byte preservation is a
  safety property here, not a nicety. `meta` carries the per-document policies that protect it: `entities`,
  `nbsp`, `document_envelope`, `block_whitespace`. Detect on read, replay on write; never move `canonicalHtml()`,
  which is the equality oracle the 100 % round-trip gate is measured against.

- **Drafts only.** Nothing here may publish. Publishing is a human click in admin (`draft=0`). Base mode is
  the one write with no `draft` field, and that is a stronger guarantee, not a weaker one: its endpoint has no
  publish branch, and refuses `draft`/`draft_mode`/`visible`/`published_time`/`deleted` on presence. Never post
  to `form_save` — it both drafts and publishes, decided by two POST fields.
- **Two modes.** `mode: "base"` edits the English source through `/articles-admin/…` and takes NO `locale`;
  the default `translation` takes one. Articles only in base mode. English as a translation answers
  `default_locale_not_translatable`, never `forbidden_locale` — no account change can make the source language
  translatable, so that advice would send the reader to fix a permission they already have.
- **A draft save is a full replace**: the monolith deletes every `draft = 1` row first. The connector must re-post every
  field of the type; the skill sends only changed fields (A20). Omitting a field from the connector's form list blanks it.
- **`version_hash`** = sha256 of canonical JSON of `{fields, draft_fields, faq_items}`, keys sorted, no whitespace,
  non-ASCII literal, every `source_*` key removed at every depth, `sort_order` excluded, FAQ items exactly
  `{id,question,answer,draft_question,draft_answer}` (absent → `null`). Fixtures under `harness/fixtures/open_page.*.json`
  (guide) and `fixtures/reference/` (monorepo) pin it; both sides must recompute every fixture identically.
- **Conflict replies are slimmed** (A24): `ConflictSlimmer.cs` and `harness/mock-mcp/lib/conflict.mjs` are byte-equivalent
  twins; a new body-shaped key goes in **both**.
- **FAQ drafts bypass the `translations_draft` index** (`Controller_Admin_Translate::update_translations()` writes
  `draft=1` rows with no index row). `Model_Faq_Item::has_draft_translation()` overrides the ORM to read the rows.
  Any new type whose drafts are written by `update_translations()` needs the same override, or its drafts are invisible.
  Discriminator: does `action_<type>_process()` call `DraftService` (index maintained; type listed in `Helper/Draft/DraftType.php::TYPES`) or `$this->update_translations()` (no index row)?
- **Behind Fastly, nginx never sees the public Host.** Gate on `$http_x_travelshift_url_front` as well as `$host`
  (memory: `reference-fastly-rewrites-host-header`). A bare `nginx/1.29.x` 404 on an admin host = a `return 404` fired.
- **Six tools, not seven.** `search_images` never existed on the connector and the skill never called it; it was
  deleted from both harnesses. `tools/list` must return the same six on every endpoint — a mismatch there is the
  cheapest drift signal you get.
- **A large page travels compressed, and the cap is the connector's to state.** `start_push` reports
  `limits: {relay_max_chars, upload_max_bytes, payload_encodings}`; the skill reads them and only falls back to its
  own constant for a connector that reports none. `payload_encoding: "gzip+base64"` puts base64(gzip(json)) in
  `payload`, and **`payload_sha256` still covers the DECODED bytes** — one meaning on every transport. The
  connector *reports* `relay_max_chars` but does not enforce it (the ceiling is the model's); the harnesses do
  enforce it, because emulating that ceiling is their job.
- **Tool budget:** admin round-trips are ~90 s each; four sequential calls exceed Claude's ~300 s tool ceiling.
  `finish_push` currently does four (`PushService.cs` pre-read, write page, write FAQ, post-read).
- `kohana/application/classes/Model/User.php` carries a local auth bypass (`LOCAL_AUTH_USER_ID`). **Never commit it.**
  Never edit `schema.graphql`. Never push; the user commits and pushes.
- Kohana files are often **CRLF**. Edit with `open(p, newline='')` or `sed -i ''`; never `open(p).read()` + write.
  Check `tr -cd '\r' < file | wc -c` before and after.

## Quick reference

| Task | Where to start |
|---|---|
| Add an editable type | `references/adding-a-type.md` (ordered checklist, both repos) |
| Change what a tool returns | connector `Features/<Tool>/`, `Ports/`, then guide `harness/mock-mcp/lib/tools.mjs` + `harness/local-connector/lib/*.mjs` + fixtures + `skill/scripts/*.mjs` |
| Debug "draft not visible in admin" | `ORM::has_draft_translation()` vs `translations_draft`; `Settings 'use_translations_draft_table'`; the SQL in `docs/content-studio-deployment.md` §5 |
| Anything failing between Claude and the admin | `references/debugging.md` — probe each layer outside-in |
| Debug `/mcp` 404/502 | in-cluster: `kubectl exec <marketplace pod> -c service-marketplace-nginx -- curl -X POST http://127.0.0.1/mcp -H 'Host: admin.staging.guidetoiceland.is'` → expect 401 |
| Is the stack healthy / do the endpoints agree? | `node ~/.claude/skills/mcp-content/scripts/probe.mjs health` then `… tools` — seconds, and the cheapest drift signal there is |
| Are the error codes still honest? | `… probe.mjs codes` against a **live** connector — the defect class that has cost most here |
| Run the whole thing end to end | `references/testing.md` — stack up, `node harness/e2e-all.mjs --keep-going`, draft reconciliation |
| Did anything publish? | `… probe.mjs drafts` — the `draft=0 written today` line must be 0, always |
| Run tests | guide: `cd tools/content-studio && CONTENT_STUDIO_REQUIRE_FIXTURES=1 npx vitest run` (`npm run test:corpus` for the 100 % gate); PHP: `task test-unit -- tests/unit/Model/FaqItemTest.php`; connector: `dotnet test tests/ContentMcp.Tests/ContentMcp.Tests.csproj -c Release` + `dotnet csharpier check src tests` |
| Package skill | `cd tools/content-studio && npm run package` → `dist/content-studio-skill.zip` |
| Deployment checklist | `guide:docs/content-studio-deployment.md` |

## Common mistakes

- Proving a contract change against the **shim** and calling it done. The shim is the oracle, not the product;
  every push defect found so far was invisible to it. Prove it against the real `.NET` connector.
- Trusting a suite that skipped. Run with `CONTENT_STUDIO_REQUIRE_FIXTURES=1`; 4 skips is correct (they are
  inverted sentinels), 5 is a regression.
- Assuming a rebuilt binary is live. `dotnet test` rewrites `bin/Release/**` in place, but a running process keeps
  its in-memory image until restarted.
- Writing a corpus measurement for one `.jsonl` shape and running it over the other. `base_en.jsonl` is one row per
  page with a `fields` object; `translations.jsonl` is one row per **field**. The mismatch returns empty payloads
  and a confident wrong number rather than an error.

- Adding the type to one field table and not the others (guide has four copies; connector has `AdminPageParser.EditableFields/BodyFields`, the `DraftFormBuilder` ternary and the `AdminPageReader.DraftedFields()` ternary).
- `DraftFormBuilder.cs` `type == Article ? … : …` — an unhandled type silently posts the **attraction** form. Make it throw.
- Forgetting the MCP `inputSchema` `enum: ['article','attraction']` in **both** `harness/mock-mcp/server.mjs` and
  `harness/local-connector/server.mjs`; the request is rejected before any handler runs.
- Assuming the monolith GraphQL root field is named like the wire type and returns `metadata{canonical_url} images{…}` (`AdminPageUrls.PageFactsQuery`); e.g. tour categories are `tourCategoryInformation(id:)` with a singular `image`. Or that
  `getFaq(pageType:)` is `ToUpperInvariant()` of the wire name (`tour_category` → enum is `TOURCATEGORY`).
- Regenerating fixtures on one side only; the reference `open_page.*.json` files are the same bytes in both repos.
- Testing locally with `Host:` and declaring routing fixed; Fastly rewrites it. Test with `x-travelshift-url-front` too.
- Reaching the admin from inside the cluster without the Fastly marketplace headers, or reaching staging from outside the
  office ACL. Both fail before any code of ours runs; see "Edge gotchas" in `references/system-map.md`.
- Editing `dev/nginx/nginx.local.conf` then `nginx -s reload`: the virtiofs mount may be stale. `docker compose -f docker-compose.local.yml up -d --force-recreate --no-deps front-lb`.

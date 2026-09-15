# Adding an editable page type

Work in this order. Each step names every file; a type added to one table and not its twins fails silently.
Replace `<type>` with the wire name (e.g. `tour_category`), `<Type>` with the C# name.

## 0 · Decide before touching code

1. **Field manifest**, from `Model_<Type>::$_translate` in the monolith and the form in `views/admin/translate/<type>.tpl`: body field(s) (`html`), title field, ordered
   scalars, JSON fields, and which are **editable** vs re-posted verbatim. Every field the admin form posts must be in
   the connector's posted list (full-replace drafts blank omitted fields).
2. **Capabilities**: templated title (like attraction `name`)? JSON side-file (like `notes`)? quickfacts? translations
   rendered live? shortcode registry on the page (`allowedShortcodes*` in the `.tpl`)? URI opt-in (like article)?
3. **Live preview**: `lib/preview/shell.mjs` + `harvest.mjs` know two js-web containers. Either harvest a snapshot of the
   new page type (`harness/build-assets.mjs`, CSS+templates as one unit) or declare the type not previewable in SKILL.md.
4. **Monolith prerequisites** (check, then fix in PHP if missing): `action_<type>()` / `action_<type>_process()` exist
   with `draft_mode`; the page carries `faq_link` or `Model_Faq::PAGE_TYPES` has the type; GraphQL `/api/v2` exposes a
   root field the connector can query for facts (article/attraction use `<wire>(id){metadata{canonical_url} images}`; other types differ in both root name and selection set, e.g. `tourCategoryInformation(id:)` with a singular `image`);
   drafts of this type either go through `DraftService` (`action_<type>_process()` → `Helper\Draft`, type in `DraftType::TYPES`,
   index maintained) or through `$this->update_translations()` and then need a `has_draft_translation()` override like `Model_Faq_Item`.

## 1 · Monolith (guide)

- `Controller_Admin_Translate` — add `faq_link` / shortcode arrays if the page lacks them; note whether
  `BodyTransforms::applyEmbedTransforms` runs (it decides whether the connector reverses editor munging).
- `Model/<Type>.php` — `has_draft_translation()` override **only** if drafts are written by `update_translations()`.
- Test: `tests/unit/Model/<Type>Test.php` mirroring `FaqItemTest.php` (draft row without index row → visible).

## 2 · Connector (monorepo) — data tables

| File | Change |
|---|---|
| `Shared/PageType.cs`, `Shared/PageTypeExtensions.cs` | enum member; `ToWire()` + `TryParse()` |
| `Features/ToolInputs.cs`, `OpenPageTools.cs`, `StartPushTools.cs`, `FinishPushTools.cs`, `ListShortcodesTools.cs` | description strings; seed-id switch |
| `Adapters/Monolith/AdminMarkup.cs` | selector block for the form, source panel, not-found marker (`"<Type> not found"`), draft-choice modal id if it differs |
| `Adapters/Monolith/AdminPageParser.cs` | `EditableFields`, `BodyFields` (index 0 is the image-scan body), `RequiredSelector`, `ParsePage` → `Parse<Type>()`; `LocaleMeta` shape |
| `Adapters/Monolith/AdminPageReader.cs` | `DraftedFields()` (which keys get `_draft`; feeds the hash), `NotesSource` only if JSON field |
| `Adapters/Monolith/AdminPageUrls.cs` | `PageFactsQuery` per-type GraphQL; `FaqLookupQuery` enum casing (`TOURCATEGORY`, not `TOUR_CATEGORY`) |
| `Shared/Push/DraftFormBuilder.cs` | `<Type>Fields` in **form POST order**; replace the `Article ? : Attraction` ternary with a switch that throws |
| `Shared/Push/UploadPayload.cs` | extra postable-but-not-editable keys (article-style `uri`) |
| `Shared/Push/PushService.cs` | make the attraction-only warnings conditional; add type-specific warnings |
| `Shared/Push/ConflictSlimmer.cs` | add body-shaped keys to `BodyKeys` **and** to `guide:harness/mock-mcp/lib/conflict.mjs` |
| `Configuration/AdminOptions.cs`, `appsettings.json`, `helm/service-content-mcp/{stage,prod}-values.yaml` | `Admin__RegistrySeed<Type>Id` (or `0`) |
| `CLAUDE.md`, `README.md`, `DESIGN.md`, `fixtures/admin/MANIFEST.md` | enumerate the type and its gaps |

Tests: record `fixtures/admin/<type>/<id>-<locale>-draft{0,1}.{html,headers}` from **staging** (headers must carry no
cookies — grep before committing); `Adapters/<Type>FormParsingTests.cs`; add rows to `AdminErrorDetectionTests`,
`ReducedRegistryAndImageTests`, `TicketBindingTests`, `AdminDraftWriterTests`, `PushRoundTripTests`, `DraftInvariantTests`,
`ToolFixtures`/`WriterFixtures` builders; `VersionHashFixtureTests` gets the new reference files **last** (step 4).

## 3 · Skill + harnesses (guide `tools/content-studio/`)

| File | Change |
|---|---|
| `lib/converter/fields.mjs` | `HTML_FIELDS[<type>]`, `JSON_FIELDS[<type>]` |
| `lib/preview/workspace.mjs`, `skill/scripts/pull.mjs` (`BODY_FIELD` ×2, `TEXT_FIELD_ORDER`) | body/title/scalar order |
| `lib/validate/editable.mjs` | URI opt-in gate (`opts.type === 'article'`) |
| `lib/transform/registry.mjs`, `lib/preview/{shell,harvest,indicator,widget-kinds}.mjs`, `skill/scripts/build-preview.mjs` | `isAttraction` boolean → type key; container id; per-type caveats/first-block rule |
| `skill/scripts/{pull,push,diff}.mjs` | title-template / JSON-side-file hooks if the type has them; `unsupported page type` guards |
| `harness/mock-mcp/server.mjs`, `harness/local-connector/server.mjs` | `inputSchema.enum` on `open_page` / `list_shortcodes` |
| `harness/mock-mcp/lib/{pages,tools,conflict}.mjs`, `data/shortcodes.<type>.json` | `BODY_FIELDS`, `EDITABLE`, `amendFixture`, `draftVariant`, payload validation, registry |
| `harness/local-connector/lib/{read,admin,tools,testing}.mjs` | `TRANSLATE_FIELDS`, `BODY_FIELDS`, `EDITABLE`, `BASE_TABLE`, `<TYPE>_FORM_FIELDS`, `save<Type>Draft()` → `/translate/<type>_process/<id>`, draft cleanup |
| `harness/e2e-loop.mjs` | body draft column (`<body>_draft`) |
| `test/helpers/fixtures.mjs` regex, `test/*.test.mjs` type matrices | add the type |
| `skill/SKILL.md`, `README.md`, `docs/DEV_ENV.md` | naming, file table, type-specific sections |

## 4 · Fixtures, hash, package

1. Generate `harness/fixtures/open_page.<type>-<id>-<locale>.json` from the local connector shim against a real page.
2. Copy the same bytes to `mono/fixtures/reference/` and pin the hashes in `VersionHashFixtureTests` + `fixtures/reference/MANIFEST.md`.
3. `npx vitest run` and `npm run test:corpus` green; `dotnet test` green; `npm run package`.
4. Staging E2E with `harness/e2e-loop.mjs --type <type>`; record latencies; update `docs/content-studio-deployment.md`.

## Done when

- Both MCP servers accept the type; `open_page` / `start_push` / `finish_push` round-trip on staging.
- The draft is visible in admin with the "Draft Translation!" banner; publish is still a human click.
- `version_hash` recomputes identically from both repos' fixture copies.
- Skill zip rebuilt; team manual updated if the editor-facing flow changed.

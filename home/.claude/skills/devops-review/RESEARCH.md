# Research Log — how this skill was built (for future improvement)

Built 2026-08-11 by Claude (Fable 5) at Artur's request, the day after Yurii Serhiichuk (xSAVIKx) left Travelshift. This file records what was mined, how deeply, what was verified, and what's still unmined — so future improvement rounds don't re-do or blindly trust this one.

## Sources mined

| Source | Coverage | Fed into |
|---|---|---|
| monorepo PR reviews 2025–26 | 60 PRs sampled (#36111–#43757), 152 verbatim comments | SKILL.md principles, hard blocks, devops-knowledge |
| monorepo PR reviews 2023–24 | ~40 PRs, 720+ thread comments scanned, ~90 verbatim | same |
| guide PR reviews 2024–26 | ~55 of 188 reviewed / 209 commented PRs | domain-gotchas (spans, parity, LLM checklist) |
| Infra-repo reviews (infrastructure-resources, .github-workflows, docker-images, toolbox) | near-full (low-volume repos) | devops-knowledge (Pulumi, Helm, GHA) |
| Authored infra PRs (infrastructure-resources 101, .github-workflows 42, monorepo infra subset of 445) | ~50–70 PR bodies + selected diffs | devops-knowledge, authoring section |
| Authored app PRs (monorepo src/dotnet|js|go|php commits) | ~50–70 PRs, ~10 diffs, commit-message sample | engineering-style content, domain-gotchas |
| Authored guide + misc repos (guide 153, monolith-service 42, travelbot 41, bookings-overview 6, toolbox 4, docker-images 4, ...) | ~40–60 PR bodies | domain-gotchas, legacy-code philosophy |
| IR#153 offboarding dump (docs/offboarding/, branch infra-docs) | README, landmines.md, org.md, ACTIONS.md in full; 15 of 82 map entries in full (all edge/, aws/, + doppler, waf-updater, s3, backups, doit, secret-manager); agents/briefs + .claude/hooks in full | offboarding-map.md |
| docs/superpowers/specs design docs | ALL: guide 8 (1 only on PR #38661 branch), infrastructure-resources 5 (+1 spec-less plan), monorepo 4 | design-decisions.md |
| Slite | his 49 owned notes enumerated; ~10 read | devops-knowledge "Runbooks he left in Slite" |
| Asana | [PRJ] Devops improvements + Bugs Inbox; ~15 high-value tasks with his comment threads | devops-knowledge incident rules, domain-gotchas cross-env trap |

Totals for context: 1,553 authored PRs / 2,368 reviewed org-wide; earliest org activity 2021-05-29.

## Validation performed (all 2026-08-11)

- 12 load-bearing quotes verified verbatim against live GitHub (12/12 confirmed; two were review bodies, not inline comments).
- Corrections applied during validation: tenure 2019→2021; IR#153 "merged"→open/unmerged; wildcard-version hard block reworded to name manifests after a JS test reviewer failed to flag `^6.2.0`.
- Behavioral tests (subagent reviews of seeded diffs): .NET/Helm seeded PR (baseline vs skill — skill caught all 6 house-specific items baseline missed); clean-PR false-positive test (no fabricated blocks; caught a real accidental flaw); PHP trap test (blocked span leak + AFTER clause, defended span-before-redirect as intentional); knowledge-retrieval 8/8.

## Deliberate exclusions

- **travelplan project technical knowledge** — excluded at Artur's request (2026-08-11); only the tone/curiosity his travelplan threads evidenced is retained.
- **Voice/persona mimicry** — dropped; both a research agent and the permission classifier pushed back on named-individual emulation. The skill is standards+knowledge with attributed quotes; it forbids presenting output as authored by Yurii.
- **AI-ghostwritten comments** (late-2026, signed "AI-generated reply … acting for @xsavikx", e.g. M#43757, IR#146/#147/#150/#152) — excluded from all tone/voice analysis.

## Known gaps (improvement backlog)

1. **Slack — unmined.** Likely the largest remaining corpus (incidents, debugging threads, decisions). No Slack connection was available; connect one and fan out over devops/incident channels.
2. **Pre-May-2023 review voice doesn't exist** in GitHub (no review data before then in these repos); 2021–2023 covered only via authored work. Not recoverable.
3. **Issue-thread / discussion comments** never systematically mined (the agent assigned to it declined over persona-emulation concerns); review threads partially compensate.
4. **travelplan reviews** unmined (mostly solo repo, low loss) — and excluded anyway per above.
5. **67 of 82 offboarding map entries** not read in full — only indexed. Read the rest on demand via offboarding-map.md's lookup table.
6. **His Claude Code session links** in PR/commit trailers (`claude.ai/code/session_…`) — his account, not accessible.
7. **Calibration against real PRs** — all behavioral tests used synthetic seeded diffs; run the skill against a few real merged PRs he reviewed and diff its output against his actual comments.
8. **After IR#153 merges:** re-verify offboarding-map.md paths/counts against the merged state (it grew from 171→178 files while open); check which P0s closed.
9. **Distribution:** skill is user-local only. Consider committing to monorepo `.claude/skills/` and pushing per-repo gotchas (e.g. span-before-redirect) into the repos' own CLAUDE.md/AGENTS.md so bots stop re-flagging them.
10. **Slite rot:** the 49 notes and the "Tools and Accounts" collection are untriaged since his departure; when the team triages, update the "Runbooks he left in Slite" section to drop retired docs.

## Provenance notes

- Raw research reports (13 files) lived in the build session's scratchpad (`.../scratchpad/research/`) — ephemeral; this file is the durable summary. The distilled facts all live in the skill's reference files with PR/task/note citations.
- Citation conventions in the reference files: M=monorepo, G=guide, IR=infrastructure-resources, GW=.github-workflows, BO=bookings-overview-micro-service, MS=monolith-service; Asana tasks by numeric gid.
- Skill was named `yurii-review` at creation, renamed `devops-review` on 2026-08-11 at Artur's request.

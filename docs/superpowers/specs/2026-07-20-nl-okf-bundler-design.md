# NL-OKF-Bundler — Design

**Date:** 2026-07-20
**Status:** Approved (design); implementation plan to follow via writing-plans.

## 1. Goal

Build the **natural-language equivalent** of [`okf-bundler`](https://github.com/mjmiller41/okf-bundler):
a system that turns any set of references — a codebase, documents, folders of
notes, web pages, YouTube videos — into a spec-conformant
[OKF v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog) knowledge
bundle. Where okf-bundler is Python (Tool-Runner sessions, `sources/`, `tools/`,
`runner.py`, `prompts/`, `viewer/`), this system re-expresses that behavior as
**prose an agent executes with built-in tools** — the same form as the
`NL-Harness` project (`~/Code/NL-Harness`), which is the template for what
"natural-language equivalent" means here.

**Full feature parity** with okf-bundler is the target — expressed as prose, not
code.

## 2. Guiding constraints (locked)

- **Substrate:** Claude Code (the TUI). We inherit the model loop, tool calling,
  sub-agents, and sandbox for free.
- **Behavior is prose.** Roles, the run-loop, ingestion, organization,
  enrichment, web-crawl, validation, and stopping conditions live in markdown
  docs loaded via `CLAUDE.md`. Swap the markdown and the same TUI runs a
  different bundler.
- **Judgment → prose; derivable → tiny helper scripts.** All agent judgment
  (what to ingest, how to organize, what each concept says, what to cite) is
  prose executed with built-in tools. Purely mechanical, tree-derivable work
  (index regeneration, conformance lint) and the non-prose-able graph
  visualizer are small deterministic helper scripts — the same pragmatic split
  the `okf-init` skill uses with its `okf-bundle-sync.sh`.
- **Built-in tools + WebFetch.** Agents use `Read, Write, Edit, Bash, Glob,
  Grep, Task, TodoWrite` plus `WebFetch`/`WebSearch` for URL ingestion. No
  custom in-process tools, no MCP servers.
- **Entry:** the Claude Code TUI. The task arrives in the prompt
  ("bundle these refs into `<OUT>`"). okf-bundler's CLI flags become
  natural-language run-options the orchestrator interprets.

## 3. What "natural-language equivalent" maps from → to

| okf-bundler (code) | NL-OKF-Bundler (prose) |
|---|---|
| `runner.py` `BundleRunner` loop | `harness/bundler.md` orchestrator |
| `prompts/enrich_instruction.md` | `harness/subagents/enricher.md` |
| `prompts/organization_instruction.md` + `tools/org_tools.py` | `harness/subagents/organizer.md` |
| `prompts/web_ingestion_instruction.md` + crawl guardrails | `harness/subagents/web-crawler.md` |
| `bundle/document.py` `OKFDocument.validate` | `harness/subagents/validator.md` + lint helper |
| `sources/` (extract, refs, youtube, slugs, profile) | prose intake in `bundler.md` (Read / Bash / WebFetch) |
| `bundle/index.py`, `bundle/logbook.py` | orchestrator writes `log.md`; `scripts/okf-sync.sh` regenerates indexes + lints |
| `viewer/` (D3 graph) | `scripts/visualize.*` vendored helper |
| Tool-Runner session per concept | parallel `Task` enricher subagents |
| API-key / OAuth auth | none — the TUI is the model loop |

## 4. File layout

```
NL-OKF-Bundler/
  CLAUDE.md                 # bootstrap → @import harness/bundler.md; entry rules
  harness/
    bundler.md              # orchestrator: the enrich run-loop (was runner.py)
    subagents/
      enricher.md           # write ONE concept doc (was enrich_instruction.md)
      organizer.md          # organization pass: plan/move/merge/delete
      web-crawler.md        # web-crawl pass w/ guardrails
      validator.md          # OKF conformance + citation audit
    OKF_SPEC.md             # vendored spec — the write-time contract
  scripts/
    okf-sync.sh             # index + log regeneration and conformance lint (helper)
    visualize.*             # vendored graph viz generator (helper)
  docs/
    plan.md                 # implementation plan (written next, via writing-plans)
    superpowers/specs/2026-07-20-nl-okf-bundler-design.md  # this file
```

State lives in the **bundle itself** (the OKF tree + `log.md`), not a separate
`state/` dir — the bundle is the durable artifact, exactly as okf-bundler treats
it.

## 5. Components

### 5.1 `CLAUDE.md` — bootstrap (no run logic)
Auto-loads when Claude Code opens in `NL-OKF-Bundler/`. `@import`s
`harness/bundler.md` as the orchestrator's system prompt and states entry rules:
the task (refs + OUT dir + any run-options) arrives in the prompt; if OUT is
unspecified the orchestrator asks once. No ingestion, organization, or
validation logic lives here.

### 5.2 `harness/bundler.md` — the orchestrator (heart of the system)
Prose sections:
- **Task input & run-options** — refs, OUT, and NL equivalents of okf-bundler's
  flags: *organize-only*, *no-organize*, *force* (re-enrich existing),
  *concept placement* (full-id filter vs. bare-name placement request),
  web-crawl seeds/limits, model choice.
- **Role & objective** — turn the refs into a spec-conformant OKF bundle at OUT,
  additively over any existing tree.
- **Run loop:** Intake refs → **Organize** (unless *no-organize*) → fan out
  parallel **enrichers** (one `Task` per concept, failure-isolated) → optional
  **web-crawl** pass → author the `log.md` diary entry → run `okf-sync.sh`
  (regenerate indexes, lint) → **validator** audit → final run summary. In
  *organize-only* mode, stop after Organize and print the planned tree without
  writing concept bodies.
- **Reference intake (full parity):** `Read` for files; `Bash`
  (`pdftotext` / `pandoc` / `yt-dlp`) for PDF/docx/html/epub/YouTube; `WebFetch`
  for URLs. Folder refs → a symlink at `references/<slug>` plus a generated
  descriptor `.md` written from a mechanical shape profile (file listing +
  README + content samples), not a full ingest. Slug-collision suffixing
  (`-2`/`-3`) and skip/*force* idempotency are prose rules. The OUT directory is
  excluded from its own reference walk.
- **Handoff protocol** — dispatch subagents via `Task` with the subagent doc's
  full contents plus a self-contained brief (goal, files in scope, done
  criteria, what to return). Parallel = multiple `Task` calls in one message for
  independent concepts; collect all handoffs before syncing. Enricher failures
  are isolated — one bad session never aborts the run.
- **Stopping condition** — `scripts/okf-sync.sh --lint-only` exits 0 and the
  validator reports conformant; then emit the run summary.

### 5.3 `harness/subagents/enricher.md`
Fresh-context subagent. Given one concept (id + source pointers), investigate the
source with built-in tools, then write `<concept>.md` with OKF-required
frontmatter (`type, title, description, timestamp`), a `# Contents` body, and a
`# Citations` section linking `/references/...` or external URLs. Structure-
preserving on re-enrichment. Returns a structured handoff (path written, type,
whether cited). Adapted from `enrich_instruction.md`.

### 5.4 `harness/subagents/organizer.md`
Reads newly ingested references + the existing tree and decides the target
concept hierarchy: create topic groups, place new concepts, and on incremental
runs restructure existing ones when new material makes the shape illogical.
Implements okf-bundler's curation operations as prose: **plan / move / merge /
delete**, and the `--concept` placement semantics (full-id = exact filter;
bare-name = placement request, reported in the summary). Adapted from
`organization_instruction.md` + `org_tools.py`.

### 5.5 `harness/subagents/web-crawler.md`
Augment-only pass: crawl from seed URLs with `WebFetch`, fold findings into
existing docs (structure-preserving) and mint `references/` docs. Guardrails as
prose: seed-host allowlist, path-prefix / denied-substring filters, page budget,
hop depth. Adapted from `web_ingestion_instruction.md`.

### 5.6 `harness/subagents/validator.md`
Read-only conformance + citation audit against `OKF_SPEC.md`: required non-empty
`type` on every concept; reserved `index.md`/`log.md` carry no frontmatter except
the root `index.md` (`okf_version: "0.1"`); `log.md` newest-first with
`## YYYY-MM-DD` headings; link style left as-is. Reports defects and the
`uncited:` list. Adapted from `OKFDocument.validate`.

### 5.7 `harness/OKF_SPEC.md`
Vendored OKF v0.1 spec — the authoritative write-time contract, sourced from the
`knowledge-catalog` `okf/SPEC.md` (and/or the `okf-init` skill's bundled copy).
Never reconstructed from memory or web search.

### 5.8 `scripts/okf-sync.sh` and `scripts/visualize.*`
- `okf-sync.sh` — regenerate `index.md` files from the tree and lint conformance
  (`--lint-only` for the gate). Mechanical, tree-derivable; role mirrors
  okf-init's `okf-bundle-sync.sh`.
- `visualize.*` — vendored graph-viz generator from okf-bundler's `viewer/`,
  producing a self-contained `viz.html`. A D3 graph is not sensibly prose-
  emitted, so it stays a helper.

## 6. Data flow (one run)
1. Open Claude Code in `NL-OKF-Bundler/`; give refs + OUT + run-options in the
   prompt. Orchestrator asks for OUT only if missing.
2. **Intake** each ref (Read / Bash-extract / WebFetch), landing every source
   under `references/` with slug-collision handling and skip/force idempotency.
3. **Organize** (unless *no-organize*): the organizer plans/moves/merges the
   concept tree over any existing bundle. *organize-only* stops here with a
   printed plan.
4. **Enrich**: orchestrator dispatches parallel `Task` enrichers, one per
   concept; failures are isolated per concept.
5. **Web-crawl** (if seeds given): augment-only pass folds findings + mints
   references.
6. Orchestrator **authors the `log.md`** entry (creations / updates / moves /
   merges / deletes / reference additions; newest-first, same-day merges).
7. Run `scripts/okf-sync.sh` → regenerate indexes + lint.
8. **Validator** audits conformance + citations.
9. Emit the **run summary**: written / skipped / failed counts, concept
   placements, and `uncited:` concepts.

## 7. Error handling
- **Per-concept failure isolation** — one enricher failing never aborts the run;
  it is reported in the summary as failed.
- **Citations soft contract** — a missing/empty `# Citations` section does not
  block the write; the concept is listed as `uncited:`.
- **Config errors** (bad refs, missing extraction tools) are caught before work
  begins and reported.
- **Organization failures are isolated** — the run continues additively over the
  existing tree.

## 8. Success criteria / verification
- **Gate:** `scripts/okf-sync.sh --lint-only` exits 0 **and** the validator
  reports conformant.
- **E2E smoke:** bundle a tiny fixture (one local text file + one URL) into a
  fresh OUT and assert: a spec-conformant tree (`references/` present,
  concept(s) with required frontmatter + `# Citations`), a non-empty `log.md`,
  clean lint, and a run summary. Idempotency: a second run with no new refs
  writes no new concepts (skip) and appends nothing to `log.md`.
- **Full-parity checklist** (each must be exercised by the docs or smoke): multi-
  source intake (file / folder-symlink+descriptor / URL / YouTube / PDF/docx);
  organization incl. plan/move/merge/delete and `--concept` placement;
  parallel failure-isolated enrichment; skip/force idempotency; web-crawl with
  guardrails; citations soft-contract + `uncited:` reporting; `log.md` diary;
  index regeneration; conformance validation; visualizer; run summary;
  organize-only / no-organize modes.

## 9. Out of scope (YAGNI)
Custom in-process tools / MCP servers; a web or TUI frontend beyond the Claude
Code TUI; multi-model routing beyond an optional model choice; multi-candidate
search; any runtime code beyond the two mechanical helper scripts
(`okf-sync.sh`, `visualize.*`). No separate `state/` dir — the bundle + `log.md`
are the state.

## 10. First actions (for the implementation plan)
1. `git init` on `main` — done.
2. Vendor `OKF_SPEC.md` and the viewer/lint helpers from
   `okf-bundler` / `knowledge-catalog` (record provenance).
3. Author `CLAUDE.md` + `harness/bundler.md` skeleton; verify `@import`
   resolves and the orchestrator loads with built-in tools only.
4. Author the four subagent docs by adapting okf-bundler's three prompts + the
   validate contract.
5. Wire the e2e smoke fixture and run it against the live TUI.

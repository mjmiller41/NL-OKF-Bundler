# NL-OKF-Bundler Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a prose-harness (Claude Code TUI) that turns any set of references into a spec-conformant OKF v0.1 knowledge bundle — the natural-language equivalent of `okf-bundler`.

**Architecture:** `CLAUDE.md` bootstraps → `harness/bundler.md` orchestrator drives a run-loop (intake → organize → parallel enrich → web-crawl → log → sync/lint → validate). Behavior is prose executed with built-in tools + `WebFetch`; only two mechanical helper scripts carry deterministic work (index/lint, graph viz). Subagents are prose docs dispatched via `Task`, adapted from okf-bundler's three system prompts + its validate contract.

**Tech Stack:** Markdown (behavior), Bash + `python3` stdlib (helper scripts), Claude Code built-in tools (`Read, Write, Edit, Bash, Glob, Grep, Task, TodoWrite`) + `WebFetch`. External CLIs for intake: `pdftotext`, `pandoc`, `yt-dlp` (only when those source kinds appear).

## Global Constraints

- **OKF target:** OKF v0.1 conformance, enforced against `harness/OKF_SPEC.md` — never reconstruct the spec from memory or web.
- **Built-in tools only + `WebFetch`.** No MCP servers, no custom in-process tools.
- **Runtime code is limited to two helper scripts** (`scripts/okf-sync.sh`, the visualizer). All agent judgment is prose.
- **Helper scripts:** `bash` + `python3` stdlib only, no network, no side effects outside the target bundle.
- **State is the bundle itself** (`references/`, concept tree, `index.md`, `log.md`) — no separate `state/` dir.
- **Concept ids** are lower-kebab-case path segments (e.g. `technology/ai`). `references/` is the only fixed-name folder. `index.md`/`log.md` are reserved at every level; only the bundle-root `index.md` may carry frontmatter (`okf_version: "0.1"`).
- **Per-run git:** implement each task on its own branch (`feature/<task>`), merge `--no-ff` to `main` when its verification passes (per the repo's solo-dev workflow).

**Vendor sources (read these; do not fetch from web):**
- OKF spec: `/home/michael/.claude/skills/okf-init/OKF_SPEC.md` (derived from `/home/michael/OKF/knowledge-catalog/okf/SPEC.md`).
- Sync/lint helper: `/home/michael/.claude/skills/okf-init/scripts/okf-bundle-sync.sh`.
- Visualizer: `/home/michael/OKF/okf-bundler/src/okf_bundler/viewer/` (`generator.py`, `static/viz.css`, `static/viz.js`, `templates/viz.html`).
- okf-bundler prompts to adapt: `/home/michael/OKF/okf-bundler/src/okf_bundler/prompts/{enrich_instruction,organization_instruction,web_ingestion_instruction}.md`.
- Form template: `/home/michael/Code/NL-Harness/{CLAUDE.md,harness/orchestrator.md,harness/subagents/coder.md}`.

---

### Task 1: Vendor the OKF spec + provenance

**Files:**
- Create: `harness/OKF_SPEC.md`
- Create: `VENDORED.md`

**Interfaces:**
- Produces: `harness/OKF_SPEC.md` — the write-time contract every subagent and the validator read.

- [ ] **Step 1: Copy the spec verbatim**

```bash
mkdir -p harness
cp /home/michael/.claude/skills/okf-init/OKF_SPEC.md harness/OKF_SPEC.md
```

- [ ] **Step 2: Record provenance**

Create `VENDORED.md` listing each vendored artifact, its upstream path, and the note that the spec's upstream is `GoogleCloudPlatform/knowledge-catalog` `okf/SPEC.md` (Apache-2.0). Include a line for the sync script and viewer (added in Tasks 2–3).

```markdown
# Vendored artifacts

| Path | Upstream source | License |
|---|---|---|
| harness/OKF_SPEC.md | knowledge-catalog `okf/SPEC.md` (via okf-init skill) | Apache-2.0 |
| scripts/okf-sync.sh | okf-init skill `scripts/okf-bundle-sync.sh` | (project) |
| scripts/visualize/ | okf-bundler `src/okf_bundler/viewer/` | Apache-2.0 |
```

- [ ] **Step 3: Verify the spec carries the key rules**

Run: `grep -c -E 'okf_version|type|references' harness/OKF_SPEC.md`
Expected: non-zero count (spec covers `okf_version`, `type`, `references/`).

- [ ] **Step 4: Commit**

```bash
git add harness/OKF_SPEC.md VENDORED.md
git commit -m "Vendor OKF v0.1 spec and provenance record"
```

---

### Task 2: Vendor the sync/lint helper script

**Files:**
- Create: `scripts/okf-sync.sh`
- Test: `tests/fixtures/mini-bundle/` (throwaway fixture)

**Interfaces:**
- Produces: `scripts/okf-sync.sh` with modes `--lint-only` (gate; exits non-zero on ERROR), default (sync indexes + append `log.md` + lint), `--no-commit`. Bundle located via `$OKF_BUNDLE_DIR` or auto-discovery of an `index.md` declaring `okf_version`.

- [ ] **Step 1: Write a failing conformance check against a fixture**

Create a deliberately non-conformant fixture and assert the linter catches it.

```bash
mkdir -p tests/fixtures/mini-bundle
printf '%s\n' '---' 'okf_version: "0.1"' '---' > tests/fixtures/mini-bundle/index.md
# concept missing a 'type' field — must be flagged ERROR
printf '%s\n' '---' 'title: Thing' '---' '' '# Contents' '- x' > tests/fixtures/mini-bundle/thing.md
```

Run (before the script exists): `OKF_BUNDLE_DIR=tests/fixtures/mini-bundle bash scripts/okf-sync.sh --lint-only`
Expected: FAIL — "No such file" (script not created yet).

- [ ] **Step 2: Vendor and rename the script**

Copy the okf-init sync script verbatim, then rename the header comment from `okf-bundle-sync.sh` to `okf-sync.sh`. It is already portable (bash + python3 stdlib) and implements SYNC (create/append `index.md`, append dated `log.md`), LINT (non-empty `type`, reserved-file frontmatter rules, broken-link warnings), and an optional git auto-commit.

```bash
mkdir -p scripts
cp /home/michael/.claude/skills/okf-init/scripts/okf-bundle-sync.sh scripts/okf-sync.sh
chmod +x scripts/okf-sync.sh
# update the two header lines that name the old filename
sed -i 's/okf-bundle-sync\.sh/okf-sync.sh/g' scripts/okf-sync.sh
```

- [ ] **Step 3: Run the linter — verify it now flags the missing `type`**

Run: `OKF_BUNDLE_DIR=tests/fixtures/mini-bundle bash scripts/okf-sync.sh --lint-only`
Expected: prints `ERROR thing.md: frontmatter has no non-empty 'type' field` and exits non-zero.

- [ ] **Step 4: Fix the fixture, verify lint passes and sync builds the index**

```bash
printf '%s\n' '---' 'type: Topic' 'title: Thing' 'description: A thing.' '---' '' '# Contents' '- x' > tests/fixtures/mini-bundle/thing.md
rm -f tests/fixtures/mini-bundle/index.md
printf '%s\n' '---' 'okf_version: "0.1"' '---' > tests/fixtures/mini-bundle/index.md
OKF_BUNDLE_DIR=tests/fixtures/mini-bundle bash scripts/okf-sync.sh --no-commit
```
Expected: `SYNC` line adding `thing` to `index.md`, then `0 errors`, exit 0. `tests/fixtures/mini-bundle/index.md` now lists `* [Thing](thing.md) - A thing.` and a `log.md` was created.

- [ ] **Step 5: Discard the throwaway fixture mutations and commit the script**

```bash
git add scripts/okf-sync.sh
git commit -m "Vendor okf-sync.sh (index sync + OKF lint helper)"
```
(The `tests/fixtures/mini-bundle/` dir is a scratch check for this task; leave it untracked or delete it — the durable smoke fixture is built in Task 10.)

---

### Task 3: Vendor the graph visualizer helper

**Files:**
- Create: `scripts/visualize/` (vendored `generator.py`, `static/`, `templates/`)
- Create: `scripts/visualize.py` (standalone wrapper)

**Interfaces:**
- Produces: `python3 scripts/visualize.py <bundle-dir> [--out FILE] [--name NAME]` → writes a self-contained `viz.html` from the bundle's markdown tree.

- [ ] **Step 1: Inspect the generator's dependencies**

Run: `grep -nE '^(import|from) ' /home/michael/OKF/okf-bundler/src/okf_bundler/viewer/generator.py`
Expected: note any `from okf_bundler...` imports — those internal modules must be vendored too (or the wrapper must replace them by walking the tree directly).

- [ ] **Step 2: Vendor the viewer assets**

```bash
mkdir -p scripts/visualize/static scripts/visualize/templates
cp /home/michael/OKF/okf-bundler/src/okf_bundler/viewer/generator.py scripts/visualize/generator.py
cp /home/michael/OKF/okf-bundler/src/okf_bundler/viewer/static/viz.css scripts/visualize/static/viz.css
cp /home/michael/OKF/okf-bundler/src/okf_bundler/viewer/static/viz.js  scripts/visualize/static/viz.js
cp /home/michael/OKF/okf-bundler/src/okf_bundler/viewer/templates/viz.html scripts/visualize/templates/viz.html
```

- [ ] **Step 3: Write the standalone wrapper**

Create `scripts/visualize.py` that reads a bundle dir (walk `*.md`, parse frontmatter for `title`/`type`/`description`, extract bundle-relative `](/...)` links as graph edges) and renders `templates/viz.html` with the node/edge JSON inlined. If `generator.py` was self-contained (Step 1 showed no `okf_bundler` imports), the wrapper just calls its public entry with the bundle dir; otherwise the wrapper re-implements the ~30-line tree walk against the frontmatter parser pattern from `scripts/okf-sync.sh` (the `frontmatter(text)` function). No new dependencies — `python3` stdlib only.

- [ ] **Step 4: Render against the Task 2 fixture**

Run: `python3 scripts/visualize.py tests/fixtures/mini-bundle --out /tmp/viz.html && grep -c '<html' /tmp/viz.html`
Expected: exit 0, count ≥ 1 (a self-contained HTML file was produced).

- [ ] **Step 5: Commit**

```bash
git add scripts/visualize scripts/visualize.py
git commit -m "Vendor graph visualizer as a standalone helper"
```

---

### Task 4: Bootstrap — `CLAUDE.md` + `bundler.md` skeleton

**Files:**
- Create: `CLAUDE.md`
- Create: `harness/bundler.md` (skeleton — full body in Task 9)

**Interfaces:**
- Produces: `CLAUDE.md` that `@import`s `harness/bundler.md`; `harness/bundler.md` with frontmatter (`name: bundler`, `description`, `model: inherit`) and the section headers Task 9 fills.

- [ ] **Step 1: Write `CLAUDE.md`** (mirror NL-Harness's bootstrap shape)

```markdown
# NL-OKF-Bundler — bundler bootstrap

This repository is the natural-language equivalent of `okf-bundler`. You act as
the **bundler orchestrator**: given a set of references and an output directory,
you turn them into a spec-conformant OKF v0.1 knowledge bundle, following the
prose harness docs exactly.

**Your operating instructions are `harness/bundler.md` — read it and follow it
exactly.** It is imported below.

Entry rules:
- The task arrives in the **prompt**: the references to ingest, the output
  bundle directory (`OUT`), and any run-options. If `OUT` is not given, ask once.
- Behavior is prose executed with **built-in tools + `WebFetch`**. The only
  runtime code is `scripts/okf-sync.sh` (index/lint) and `scripts/visualize.py`.
- The bundle at `OUT` is the durable artifact and the state — there is no
  separate `state/` directory.

@harness/bundler.md
```

- [ ] **Step 2: Write the `bundler.md` skeleton**

```markdown
---
name: bundler
description: Orchestrator for the NL-OKF-Bundler — turns references into a spec-conformant OKF v0.1 bundle via intake, organization, parallel enrichment, web-crawl, and validation.
model: inherit
---

# Bundler — NL-OKF-Bundler orchestrator

## Task input & run-options
## Role & objective
## Run loop
## Reference intake
## Handoff protocol
## Validation & stopping condition
## Run summary
```

- [ ] **Step 3: Verify the import wiring**

Run: `grep -q '@harness/bundler.md' CLAUDE.md && test -f harness/bundler.md && echo OK`
Expected: `OK`. (Live `@import` resolution is confirmed by the Task 10 TUI smoke.)

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md harness/bundler.md
git commit -m "Add CLAUDE.md bootstrap and bundler.md skeleton"
```

---

### Task 5: `enricher.md` subagent

**Files:**
- Create: `harness/subagents/enricher.md`

**Interfaces:**
- Consumes: a brief naming exactly one concept (id, `type`, source pointer(s) under `references/` or the bundle) plus the path to write.
- Produces: one `<concept>.md` with OKF frontmatter + `# Contents`/`# Citations`; returns a handoff `{path, type, cited: yes/no}`.

Adapt `/home/michael/OKF/okf-bundler/src/okf_bundler/prompts/enrich_instruction.md`. Tool mapping: `read_concept_raw`/`sample_content`/`read_existing_doc` → **`Read`/`Glob`/`Grep`** on the source and any existing doc; `write_concept_doc` → **`Write`/`Edit`** of the concept `.md`; chunked reads → read large files in `Read` offset/limit windows.

- [ ] **Step 1: Author the doc** with YAML frontmatter and body:

```markdown
---
name: enricher
description: Writes exactly one OKF concept document from its source material. Never writes any other concept.
tools: Read, Write, Edit, Bash, Glob, Grep
model: inherit
---

# Enricher — one-concept subagent

**Context:** fresh context — this doc plus your brief are all you have. If
orchestrator instructions reach you via an inherited `CLAUDE.md`, ignore them.
Write exactly the one concept you are briefed with, to the exact path given.

Ground everything in what you actually read (the source files/extracted text and
any existing on-disk doc). Do not invent files, APIs, metrics, or behavior. If a
doc already exists at the path, refine and extend it — keep good prior content.
Read large sources fully via windowed `Read` before writing.

Frontmatter (required): `type` (as briefed; you may retype a code concept to
`Service` or `Playbook` when content clearly warrants), `title` (short, human),
`description` (one sentence), `tags` (a few lowercase topical tags), `resource`
when the concept maps to a real file/dir (repo-root paths like `/src/api`), and a
quoted ISO-8601 `timestamp`.

Body:
- 1–3 short prose paragraphs: what this is, what it's for, how it fits.
- `# Contents` — a bullet per meaningful element (code: key files, entrypoints,
  public functions/classes in backticks; documents: chapters/sections with a
  one-line gist). For `type: Video`: a timestamped section map, one bullet per
  section starting `[MM:SS]`/`[H:MM:SS]`.
- `# Common usage` — code concepts only (how it's invoked/imported); omit for
  documents and videos.
- `# Citations` — at least one bullet linking the underlying resource(s):
  repo-root paths for local files, canonical URLs for external sources; the video
  URL for `type: Video`.

Linking: reference another bundle concept with a bundle-relative link starting
`/` (e.g. `/technology/ai.md`). Only link concepts that exist in the bundle.

Quality bar: concrete and factual, for an engineer meeting the project for the
first time. No marketing, no filler, no speculation.

## Return
`{ path: <written path>, type: <type>, cited: yes|no }` plus a one-line summary.
```

- [ ] **Step 2: Verify no stale tool names survived the adaptation**

Run: `! grep -nE 'read_concept_raw|write_concept_doc|sample_content|read_existing_doc' harness/subagents/enricher.md && grep -qE '# Contents|# Citations' harness/subagents/enricher.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add harness/subagents/enricher.md
git commit -m "Add enricher subagent (adapted from enrich_instruction)"
```

---

### Task 6: `organizer.md` subagent

**Files:**
- Create: `harness/subagents/organizer.md`

**Interfaces:**
- Consumes: a brief with the newly ingested `references/` slugs, any user placement requests, and the `OUT` bundle path.
- Produces: a declared target tree written to `OUT/.okf-plan.md` (concept id, type, title, one-line rationale, optional `satisfies:`), and any restructuring performed (moves/merges/deletes). Returns a one-paragraph tree summary.

Adapt `/home/michael/OKF/okf-bundler/src/okf_bundler/prompts/organization_instruction.md`. Tool mapping: `list_bundle_docs`/`list_concepts` → **`Glob`** the tree and `references/`; `read_concept_raw`/`sample_content`/`read_existing_doc` → **`Read`**; `plan_concepts` → **`Write`** `OUT/.okf-plan.md`; `move_concept`/`merge_concepts`/`delete_concept` → **`Bash git mv`/`Read`+`Write`+`rm`** performed by the organizer.

- [ ] **Step 1: Author the doc** with frontmatter (`name: organizer`, `tools: Read, Write, Edit, Bash, Glob, Grep`, `model: inherit`) and body covering:
  - Workflow: (1) survey existing tree + new `references/` material; (2) decide the target tree — create groups where topics cluster, place new concepts, restructure existing ones only when new material makes the shape clearly illogical (prefer stability); (3) write the full target tree to `OUT/.okf-plan.md` listing every concept (kept + new) with type/title/rationale.
  - **Container-name rule** (verbatim intent): names like `raw`, `docs`, `notes`, `files`, `data`, `misc`, `downloads` say nothing about content — derive every topic/group name from what the material is actually about, never the container name.
  - **Placement requests:** for each requested topic, if an existing/planned concept already covers it (even under a different name), set `satisfies: "<request>"` on that entry instead of duplicating; otherwise plan a new concept and set `satisfies` on it. Report each resolution.
  - **Hard rules:** never move/merge/delete anything under `references/` and never plan concepts there; `index.md`/`log.md` reserved at every level; ids are lower-kebab-case. Do not write concept bodies — the enricher does that.

- [ ] **Step 2: Verify adaptation**

Run: `! grep -nE 'plan_concepts|move_concept|merge_concepts|list_bundle_docs' harness/subagents/organizer.md && grep -qE 'references/|kebab' harness/subagents/organizer.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add harness/subagents/organizer.md
git commit -m "Add organizer subagent (adapted from organization_instruction)"
```

---

### Task 7: `web-crawler.md` subagent

**Files:**
- Create: `harness/subagents/web-crawler.md`

**Interfaces:**
- Consumes: a brief with seed URLs, a max-pages budget, optional allowed-hosts/path filters, and the existing concept list.
- Produces: augmented existing docs and/or minted `references/<slug>.md` (`type: Reference`); returns a one-line summary (pages fetched, docs updated, references minted).

Adapt `/home/michael/OKF/okf-bundler/src/okf_bundler/prompts/web_ingestion_instruction.md`. Tool mapping: `fetch_url` → **`WebFetch`**; `list_concepts` → **`Glob`** the tree; `read_existing_doc`/`write_concept_doc` → **`Read`/`Write`**. The page budget and host allowlist are **prose guardrails the agent self-enforces** (there is no tool cap): count pages fetched, stop at the budget, and only follow links whose host is a seed host (or explicitly allowed).

- [ ] **Step 1: Author the doc** with frontmatter (`name: web-crawler`, `tools: Read, Write, Edit, WebFetch, Glob, Grep`, `model: inherit`) and body covering:
  - Inputs (seeds, max-pages budget, allowed hosts) and the self-enforced budget/host discipline.
  - Workflow: survey concepts once; fetch each seed; follow a small handful of links leading to authoritative docs (skip nav/footer/login/marketing/cookie/tangential); for each page decide **enrich existing** / **mint new reference** / **skip**.
  - **Mint-new criteria (all four):** referenceable-by-name topic shape; not bundle-level meta (skip `overview`/`intro`/`getting-started`/`quickstart`/`tutorial`/`walkthrough`/`release-notes`/`changelog`/`roadmap`/`faq`); citation test (`See the [X reference](/references/x.md) for …` with a concrete noun); reuse test (≥2 concepts benefit, or one needs it as load-bearing background). When in doubt, skip.
  - **Augmentation rules (non-negotiable):** send the complete frontmatter dict preserving existing values (copy `type`/`title`/`resource` verbatim; union `tags`; leave `timestamp` unset; page URL goes in `# Citations`, never `resource`); every existing `#` heading must reappear in order with the same wording; you may extend prose, add bullets, add sub-sections, add new top-level headings after existing ones, append to `# Citations`; you may not drop/rename headings or rewrite the body wholesale; if you can't honor this, mint a `references/` doc or skip.
  - Integrity: cite only URLs actually fetched; be concrete; bodies are clean markdown with no narration.

- [ ] **Step 2: Verify adaptation**

Run: `grep -q 'WebFetch' harness/subagents/web-crawler.md && ! grep -q 'fetch_url' harness/subagents/web-crawler.md && grep -qE 'Augmentation|mint' harness/subagents/web-crawler.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add harness/subagents/web-crawler.md
git commit -m "Add web-crawler subagent (adapted from web_ingestion_instruction)"
```

---

### Task 8: `validator.md` subagent

**Files:**
- Create: `harness/subagents/validator.md`

**Interfaces:**
- Consumes: the `OUT` bundle path.
- Produces: a defect list + the `uncited:` concept list. Returns `{conformant: yes/no, defects: [...], uncited: [...]}`.

Replaces `OKFDocument.validate`. The validator runs `scripts/okf-sync.sh --lint-only` for the mechanical checks, then adds the citation audit prose can do that the linter does not.

- [ ] **Step 1: Author the doc** with frontmatter (`name: validator`, `tools: Read, Bash, Glob, Grep`, `model: inherit`) and body covering:
  - Read-only w.r.t. the bundle. Read `harness/OKF_SPEC.md` first.
  - Run `OKF_BUNDLE_DIR=<OUT> bash scripts/okf-sync.sh --lint-only`; treat any `ERROR` line as a blocking defect (non-empty `type` on every concept; no frontmatter on reserved files except root `okf_version`; unterminated frontmatter). `WARN` (broken links) and `INFO` (missing optional root `okf_version`) are advisory.
  - **Citation audit:** for every non-reserved concept, check for a non-empty `# Citations` section; list those without one as `uncited:` (soft contract — not a defect that blocks).
  - `log.md` sanity: newest-first, `## YYYY-MM-DD` headings. Link style (relative vs `/`-bundle-relative) is left as-is — not a defect.
  - Return the structured result.

- [ ] **Step 2: Verify adaptation**

Run: `grep -q 'okf-sync.sh --lint-only' harness/subagents/validator.md && grep -q 'uncited' harness/subagents/validator.md && echo OK`
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add harness/subagents/validator.md
git commit -m "Add validator subagent (OKF conformance + citation audit)"
```

---

### Task 9: Flesh out the `bundler.md` run-loop

**Files:**
- Modify: `harness/bundler.md`

**Interfaces:**
- Consumes: the four subagent docs (`enricher`, `organizer`, `web-crawler`, `validator`), `scripts/okf-sync.sh`, `harness/OKF_SPEC.md`.
- Produces: the complete orchestrator prose the TUI runs.

Fill each skeleton section from the design (`docs/superpowers/specs/2026-07-20-nl-okf-bundler-design.md` §5.2). Concrete content per section:

- [ ] **Step 1: `## Task input & run-options`** — refs, `OUT`, and NL equivalents of okf-bundler flags: *organize-only* (stop after organize, print the planned tree, write no bodies), *no-organize* (additive; skip the organizer), *force* (re-enrich existing concepts instead of skipping), *concept placement* (a full id = exact filter; a bare name = placement request handed to the organizer), *web seeds + max-pages/allowed-hosts*, *model choice*.

- [ ] **Step 2: `## Role & objective`** — turn the refs into a spec-conformant OKF bundle at `OUT`, additively over any existing tree; read `harness/OKF_SPEC.md` before writing bundle files.

- [ ] **Step 3: `## Run loop`** — Intake refs → Organize (unless *no-organize*) → fan out parallel enrichers (one `Task` per concept) → optional web-crawl → author `log.md` diary entry → run `scripts/okf-sync.sh` → dispatch validator → emit run summary. In *organize-only*, stop after Organize.

- [ ] **Step 4: `## Reference intake`** — `Read` for files; `Bash` (`pdftotext` for PDF, `pandoc` for docx/html/epub, `yt-dlp` for YouTube transcripts) for non-markdown; `WebFetch` for URLs. Every source lands under `references/`. Folder refs → a symlink at `references/<slug>` (`ln -s`) plus a generated descriptor `.md` written from a shape profile (file listing + README + content samples), not a full ingest. Slug-collision suffixing (`-2`/`-3`). Skip existing docs unless *force*. Exclude `OUT` from its own reference walk. Before starting, verify required extraction CLIs exist for the ref kinds present (`command -v pdftotext`/`pandoc`/`yt-dlp`); report a config error and stop if a needed one is missing.

- [ ] **Step 5: `## Handoff protocol`** — dispatch each subagent via `Task` with the subagent doc's full contents plus a self-contained brief (goal, files in scope, done-criteria, what to return). Parallel = multiple `Task` calls in one message for independent concepts; collect all handoffs before running `okf-sync.sh`. **Per-concept failure isolation:** one enricher failing never aborts the run — record it as failed and continue.

- [ ] **Step 6: `## Validation & stopping condition`** — the orchestrator authors `log.md` (newest-first `## YYYY-MM-DD`; creations/updates/moves/merges/deletes/reference-additions; a no-change run appends nothing) **before** running `scripts/okf-sync.sh` (which regenerates indexes and may add an index-sync bullet under the same day). Done when `scripts/okf-sync.sh --lint-only` exits 0 **and** the validator reports conformant.

- [ ] **Step 7: `## Run summary`** — written / skipped / failed concept counts, concept placements (`concept "AI" -> technology/ai`), and the `uncited:` list.

- [ ] **Step 8: Verify coverage of the design's parity checklist**

Run: `grep -ciE 'organize-only|no-organize|force|placement|references/|pdftotext|pandoc|yt-dlp|WebFetch|failure|uncited|log\.md|okf-sync' harness/bundler.md`
Expected: high count (each parity feature named). Manually confirm every item in design §8's full-parity checklist maps to a sentence here.

- [ ] **Step 9: Commit**

```bash
git add harness/bundler.md
git commit -m "Flesh out bundler.md run-loop (full parity behavior)"
```

---

### Task 10: E2E conformance smoke + docs

**Files:**
- Create: `scripts/smoke-check.sh`
- Create: `tests/fixtures/refs/notes.txt`, `tests/fixtures/refs/guide.md`
- Create: `README.md`, `docs/plan.md`

**Interfaces:**
- Consumes: a produced bundle directory.
- Produces: `scripts/smoke-check.sh <bundle-dir>` — asserts the success criteria and exits non-zero on any failure.

The live bundling run is driven by the TUI (agent), so the automatable deliverable is the **conformance checker** for a produced bundle plus a documented manual TUI procedure.

- [ ] **Step 1: Create the input fixture**

```bash
mkdir -p tests/fixtures/refs
printf '%s\n' 'Project Atlas is a task queue. It uses Redis for the broker.' > tests/fixtures/refs/notes.txt
printf '%s\n' '# Atlas guide' '' 'Workers pull jobs from the queue and retry on failure.' > tests/fixtures/refs/guide.md
```

- [ ] **Step 2: Write the failing smoke checker**

Create `scripts/smoke-check.sh <bundle>` that asserts, on the given bundle dir: root `index.md` declares `okf_version`; at least one non-reserved concept `.md` exists with a non-empty `type` and a non-empty `# Citations` section; `references/` exists; `log.md` is non-empty and newest-first (`## YYYY-MM-DD`); and `OKF_BUNDLE_DIR=<bundle> bash scripts/okf-sync.sh --lint-only` exits 0. Exit non-zero with a clear message on the first failed assertion.

Run (before a bundle exists): `bash scripts/smoke-check.sh /tmp/nonexistent`
Expected: FAIL with a clear "no such bundle / assertion failed" message.

- [ ] **Step 3: Prove the checker against a hand-built golden bundle**

Build a minimal conformant bundle by hand and confirm the checker passes it, then break one rule and confirm it fails:

```bash
G=/tmp/atlas-golden; mkdir -p "$G/references"
printf '%s\n' '---' 'okf_version: "0.1"' '---' > "$G/index.md"
printf '%s\n' '---' 'type: Topic' 'title: Atlas' 'description: A task queue.' 'timestamp: "2026-07-20T00:00:00Z"' '---' '' 'Atlas is a task queue.' '' '# Contents' '- broker: Redis' '' '# Citations' '- /references/notes.md' > "$G/atlas.md"
printf '%s\n' '---' 'type: Document' 'title: Notes' 'description: Source notes.' 'timestamp: "2026-07-20T00:00:00Z"' '---' '' '# Contents' '- raw notes' '' '# Citations' '- /tests/fixtures/refs/notes.txt' > "$G/references/notes.md"
printf '%s\n' '# Knowledge Bundle Update Log' '' '## 2026-07-20' '* **Initialization**' > "$G/log.md"
OKF_BUNDLE_DIR="$G" bash scripts/okf-sync.sh --no-commit   # builds indexes
bash scripts/smoke-check.sh "$G" && echo PASS
```
Expected: `PASS`. Then: `sed -i 's/^type: Topic/type:/' "$G/atlas.md"; bash scripts/smoke-check.sh "$G" || echo "correctly failed"` → `correctly failed`.

- [ ] **Step 4: Document the live TUI smoke + write README/plan**

- `README.md`: what NL-OKF-Bundler is (NL equivalent of okf-bundler), the file layout, and the **live smoke procedure**: open Claude Code in the repo, prompt *"bundle `tests/fixtures/refs/` into `/tmp/atlas-bundle`"*, let the orchestrator run, then `bash scripts/smoke-check.sh /tmp/atlas-bundle` must exit 0. Note that web-crawl and video intake are exercised manually (they need network / `yt-dlp`).
- `docs/plan.md`: a short pointer to this plan and the design spec.

- [ ] **Step 5: Commit**

```bash
git add scripts/smoke-check.sh tests/fixtures/refs README.md docs/plan.md
git commit -m "Add conformance smoke checker, fixture, and docs"
```

---

## Self-Review

**Spec coverage (design §8 full-parity checklist → task):**
- Multi-source intake (file/folder-symlink+descriptor/URL/YouTube/PDF/docx) → Task 9 Step 4.
- Organization incl. plan/move/merge/delete + `--concept` placement → Task 6.
- Parallel failure-isolated enrichment → Task 5 + Task 9 Step 5.
- Skip/force idempotency → Task 9 Steps 1, 4.
- Web-crawl with guardrails → Task 7.
- Citations soft-contract + `uncited:` reporting → Task 8, Task 9 Step 7.
- `log.md` diary → Task 9 Step 6.
- Index regeneration + conformance lint → Task 2, Task 8.
- Visualizer → Task 3.
- Run summary → Task 9 Step 7.
- organize-only / no-organize modes → Task 9 Steps 1, 3.
- OKF_SPEC as write-time contract → Task 1, referenced in Tasks 5–9.

**Placeholder scan:** no "TBD"/"handle edge cases"/"similar to Task N" — each doc task lists exact frontmatter, section headers, and the source file to adapt; each script task gives exact commands and expected output.

**Type/name consistency:** helper is `scripts/okf-sync.sh` (with `--lint-only`) everywhere; subagent names `enricher`/`organizer`/`web-crawler`/`validator` match between `bundler.md` handoffs (Task 9) and their docs (Tasks 5–8); the organizer plan file is `OUT/.okf-plan.md` in both its interface and body; `smoke-check.sh` asserts the same criteria the validator checks.

**Note on verification nature:** live bundling is TUI-driven (agent), so end-to-end proof is the documented manual run + `smoke-check.sh` on its output (Task 10) — this is inherent to a prose harness, matching NL-Harness's live-verification model.

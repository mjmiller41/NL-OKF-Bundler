# NL-OKF-Bundler

The **natural-language equivalent** of [`okf-bundler`](https://github.com/mjmiller41/okf-bundler):
a system that turns any set of references — a codebase, documents, folders of
notes, web pages, YouTube videos — into a spec-conformant
[OKF v0.1](https://github.com/GoogleCloudPlatform/knowledge-catalog) knowledge
bundle.

Where okf-bundler is Python (Tool-Runner sessions, `sources/`, `tools/`,
`runner.py`, `prompts/`, `viewer/`), this project re-expresses that behavior as
**prose an agent executes with built-in tools**, run inside the Claude Code
TUI. Swap the markdown under `harness/` and the same TUI runs a different
bundler. See `docs/superpowers/specs/2026-07-20-nl-okf-bundler-design.md` for
the full design rationale.

## File layout

```
NL-OKF-Bundler/
  CLAUDE.md                 # bootstrap → @import harness/bundler.md; entry rules
  harness/
    bundler.md              # orchestrator: the enrich run-loop (was runner.py)
    OKF_SPEC.md               # vendored spec — the write-time contract
  .claude/
    agents/                   # native Claude Code subagents (dispatched by subagent_type)
      enricher.md            # writes ONE concept doc (was enrich_instruction.md)
      organizer.md            # organization pass: plan/move/merge/delete
      web-crawler.md          # web-crawl pass w/ guardrails
      validator.md            # OKF conformance + citation audit
      reviewer.md             # post-lint link/citation integrity + quality pass
    settings.json             # status line + SessionStart bundler indicators
  scripts/
    okf-sync.sh              # index + log regeneration and conformance lint (helper)
    smoke-check.sh            # conformance smoke checker for a produced bundle
    visualize.py, visualize/  # vendored graph viz generator (helper)
  tests/
    fixtures/refs/            # durable input fixture for the live smoke run
  docs/
    plan.md                   # pointer to the implementation plan
    superpowers/plans/2026-07-20-nl-okf-bundler.md
    superpowers/specs/2026-07-20-nl-okf-bundler-design.md
```

State lives in the **bundle itself** (the OKF tree + `log.md`), not a separate
`state/` dir.

## Live smoke procedure

The actual bundling run is driven by the live TUI agent (the orchestrator in
`harness/bundler.md`), so it cannot be executed headlessly from a shell. The
automatable deliverable is `scripts/smoke-check.sh`, which validates a
produced bundle against the design's success criteria
(`docs/superpowers/specs/2026-07-20-nl-okf-bundler-design.md` §8).

To exercise the system end-to-end:

1. Open Claude Code in this repo.
2. Prompt: `bundle tests/fixtures/refs/ into /tmp/atlas-bundle`
3. Let the orchestrator run to completion (intake → organize → enrich →
   log → sync/lint).
4. Run the conformance checker against the produced bundle:

   ```bash
   bash scripts/smoke-check.sh /tmp/atlas-bundle
   ```

   This must exit `0`.

`scripts/smoke-check.sh` asserts: the root `index.md` declares `okf_version`;
at least one non-reserved concept `.md` has a non-empty `type` and a
non-empty `# Citations` section; `references/` exists; `log.md` is
non-empty and newest-first (`## YYYY-MM-DD` entries); and
`OKF_BUNDLE_DIR=<bundle> bash scripts/okf-sync.sh --lint-only` exits 0.

**Web-crawl and video intake are not covered by this fixture** — they need
network access and, for video, `yt-dlp` — and are exercised manually by
pointing the orchestrator at a URL or YouTube link instead of (or alongside)
`tests/fixtures/refs/`.

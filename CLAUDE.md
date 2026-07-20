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

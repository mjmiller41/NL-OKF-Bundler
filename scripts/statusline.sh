#!/usr/bin/env bash
# NL-OKF-Bundler status line. Claude Code pipes session JSON on stdin; we
# print a one-line badge showing that this session is the bundler, plus a
# live readout of the current target bundle (concept count + lint state).
#
# The target bundle is whatever the orchestrator last recorded in
# .claude/.current-bundle (written at run start; see harness/bundler.md);
# falls back to ./knowledge if that exists. Everything is guarded so the
# status line never errors out to a blank.
set -uo pipefail

in="$(cat)"
model="$(printf '%s' "$in" | jq -r '.model.display_name // "?"' 2>/dev/null || echo '?')"
cwd="$(printf '%s' "$in" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] && short="…/${cwd##*/}" || short=""

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd -P)"

# Which bundle are we watching?
target=""
if [ -f "$repo/.claude/.current-bundle" ]; then
  t="$(cat "$repo/.claude/.current-bundle" 2>/dev/null || true)"
  [ -n "$t" ] && [ -d "$t" ] && target="$t"
fi
[ -z "$target" ] && [ -d "$repo/knowledge" ] && target="$repo/knowledge"

status="🧶 OKF Bundler · ${model}"
[ -n "$short" ] && status="$status · ${short}"

if [ -n "$target" ]; then
  # concept count: non-reserved, non-dot .md, ignoring dot-directories
  n="$(find "$target" -type d -name '.*' -prune -o \
        -type f -name '*.md' ! -name '.*' ! -name 'index.md' ! -name 'log.md' -print 2>/dev/null \
        | wc -l | tr -d ' ')"
  n="${n:-0}"
  # live lint — only for small bundles so the status stays snappy
  lint="?"
  if [ "$n" -le 150 ] && [ -x "$repo/scripts/okf-sync.sh" ]; then
    if OKF_BUNDLE_DIR="$target" bash "$repo/scripts/okf-sync.sh" --lint-only >/dev/null 2>&1; then
      lint="✓"
    else
      lint="✗"
    fi
  fi
  status="$status · $(basename "$target") ${n}c lint:${lint}"
fi

printf '%s' "$status"

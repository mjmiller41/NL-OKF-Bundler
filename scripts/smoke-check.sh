#!/usr/bin/env bash
# smoke-check.sh <bundle-dir> — conformance smoke checker for a produced OKF
# bundle. Asserts the design-spec §8 success criteria against a live bundle
# and exits non-zero with a clear message on the first failed assertion.
#
# bash + coreutils only (plus scripts/okf-sync.sh for the lint gate).
#
# Usage: bash scripts/smoke-check.sh <bundle-dir>
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

fail() {
  echo "smoke-check: FAIL: $1" >&2
  exit 1
}

BUNDLE="${1:-}"
[ -n "$BUNDLE" ] || fail "usage: smoke-check.sh <bundle-dir>"
[ -d "$BUNDLE" ] || fail "no such bundle directory: $BUNDLE"

# --- root index.md declares okf_version --------------------------------
INDEX="$BUNDLE/index.md"
[ -f "$INDEX" ] || fail "missing root index.md: $INDEX"
grep -q '^okf_version:' "$INDEX" || fail "root index.md does not declare okf_version"

# --- at least one non-reserved concept .md with non-empty type and a
#     non-empty # Citations section -------------------------------------
FOUND_CONCEPT=0
while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  case "$base" in
    index.md|log.md) continue ;;
  esac

  type_line="$(grep -m1 '^type:' "$f" || true)"
  type_val="$(printf '%s' "$type_line" | sed -E 's/^type:[[:space:]]*//' | tr -d '"'"'"'' )"
  [ -n "$type_val" ] || continue

  # Extract the "# Citations" section (from its heading to the next
  # top-level heading or EOF) and check it has at least one non-blank line.
  citations_body="$(awk '
    /^# Citations[[:space:]]*$/ { in_sec=1; next }
    in_sec && /^# / { in_sec=0 }
    in_sec { print }
  ' "$f")"
  citations_nonblank="$(printf '%s\n' "$citations_body" | grep -c '[^[:space:]]' || true)"
  [ "${citations_nonblank:-0}" -gt 0 ] || continue

  FOUND_CONCEPT=1
  break
done < <(find "$BUNDLE" -name '*.md' -print0)

[ "$FOUND_CONCEPT" -eq 1 ] || fail "no non-reserved concept .md found with a non-empty 'type' and a non-empty '# Citations' section"

# --- references/ exists --------------------------------------------------
[ -d "$BUNDLE/references" ] || fail "missing references/ directory"

# --- log.md non-empty and newest-first (## YYYY-MM-DD) -------------------
LOG="$BUNDLE/log.md"
[ -f "$LOG" ] || fail "missing log.md"
[ -s "$LOG" ] || fail "log.md is empty"

dates="$(grep -E '^## [0-9]{4}-[0-9]{2}-[0-9]{2}' "$LOG" | sed -E 's/^## //')"
[ -n "$dates" ] || fail "log.md has no '## YYYY-MM-DD' dated entries"
sorted_desc="$(printf '%s\n' "$dates" | sort -r)"
[ "$dates" = "$sorted_desc" ] || fail "log.md dated entries are not newest-first"

# --- okf-sync.sh --lint-only exits 0 --------------------------------------
if ! OKF_BUNDLE_DIR="$BUNDLE" bash "$HERE/okf-sync.sh" --lint-only >/tmp/smoke-check-lint.$$ 2>&1; then
  lint_out="$(cat /tmp/smoke-check-lint.$$)"
  rm -f /tmp/smoke-check-lint.$$
  fail "okf-sync.sh --lint-only reported errors:
$lint_out"
fi
rm -f /tmp/smoke-check-lint.$$

echo "smoke-check: PASS ($BUNDLE)"
exit 0

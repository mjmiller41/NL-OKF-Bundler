#!/usr/bin/env bash
# okf-sync.sh — keep this project's OKF knowledge bundle conformant.
#
# Copied into the project root by the okf-init skill. Portable: bash +
# python3 stdlib only, no network, no project-external side effects.
#
# What it does, in order:
#   1. SYNC  — creates missing index.md files in bundle directories and
#              appends index entries for concepts/subdirs not yet listed
#              (titles/descriptions pulled from concept frontmatter).
#              Generated indexes follow the knowledge-catalog bundle style:
#              a section per concept `type`, then `# Subdirectories` with
#              [name](name/index.md) links. Appends a dated log.md entry
#              when anything changed.
#   2. LINT  — checks OKF v0.1 conformance: parseable frontmatter with a
#              non-empty `type` on every non-reserved .md (handles block
#              lists and wrapped/folded scalars as emitted by the
#              knowledge-catalog reference agent); no frontmatter on
#              index/log files (except the bundle-root index, which may
#              carry okf_version — absence is INFO, not a warning); warns
#              on broken bundle-relative links.
#   3. COMMIT— if the project is a git work tree, auto-commits any files
#              the sync touched (guarded against hook recursion via
#              $OKF_SYNC; the commit itself re-triggers the post-commit
#              hook, which exits immediately when the guard is set).
#
# Usage:
#   ./okf-sync.sh               sync + lint + commit (if git)
#   ./okf-sync.sh --no-commit   sync + lint, leave changes unstaged
#   ./okf-sync.sh --lint-only   lint only, change nothing
#   ./okf-sync.sh --from-hook   as default, but always exits 0 so a
#                                      git hook never blocks or errors
#
# Bundle location: $OKF_BUNDLE_DIR if set, else the first directory within
# two levels of the project root whose index.md declares okf_version, else
# ./knowledge.
set -uo pipefail

# Recursion guard: our own auto-commit fires the post-commit hook again.
[ -n "${OKF_SYNC:-}" ] && exit 0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$HERE" || exit 1

MODE="${1:-}"

# --- locate the bundle -------------------------------------------------
BUNDLE="${OKF_BUNDLE_DIR:-}"
if [ -z "$BUNDLE" ]; then
  while IFS= read -r idx; do
    if head -n 20 "$idx" 2>/dev/null | grep -q '^okf_version:'; then
      BUNDLE="$(dirname "$idx")"
      break
    fi
  done < <(find . -maxdepth 3 -name index.md -not -path './.git/*' 2>/dev/null | sort)
fi
BUNDLE="${BUNDLE:-knowledge}"
BUNDLE="${BUNDLE#./}"

if [ ! -d "$BUNDLE" ]; then
  echo "okf-bundle-sync: no bundle directory found (looked for '$BUNDLE')" >&2
  [ "$MODE" = "--from-hook" ] && exit 0
  exit 1
fi

TODAY="$(date +%F)"
TOUCHED="$(mktemp)"
trap 'rm -f "$TOUCHED"' EXIT

# --- sync + lint (python3, stdlib only) --------------------------------
BUNDLE="$BUNDLE" TODAY="$TODAY" TOUCHED="$TOUCHED" MODE="$MODE" python3 - <<'PYEOF'
import os, re, sys

bundle = os.environ["BUNDLE"]
today = os.environ["TODAY"]
touched_path = os.environ["TOUCHED"]
lint_only = os.environ["MODE"] == "--lint-only"

RESERVED = {"index.md", "log.md"}
errors, warnings, infos, touched = [], [], [], []

def read(p):
    with open(p, encoding="utf-8") as f:
        return f.read()

def frontmatter(text):
    """Return (dict-or-None, closed_ok). Shallow YAML parse — key: value
    lines plus the two shapes the knowledge-catalog reference agent emits:
    block-style lists (`tags:` followed by `- item` lines) and wrapped or
    folded (`>`/`>-`/`|`/`|-`) multi-line scalars. No YAML dependency."""
    if not text.startswith("---\n"):
        return None, True
    end = text.find("\n---", 4)
    if end == -1:
        return None, False
    fm, key = {}, None
    for line in text[4:end].splitlines():
        m = re.match(r"^([A-Za-z0-9_-]+):\s*(.*)$", line)
        if m:
            key = m.group(1)
            val = m.group(2).strip()
            fm[key] = "" if val in (">", ">-", "|", "|-") else val.strip("\"'")
        elif key is not None and re.match(r"^\s+-\s+\S", line):
            item = re.sub(r"^\s+-\s+", "", line).strip().strip("\"'")
            cur = fm[key]
            fm[key] = cur + [item] if isinstance(cur, list) else ([item] if cur == "" else [cur, item])
        elif key is not None and line[:1] in (" ", "\t") and line.strip():
            if isinstance(fm[key], str):
                fm[key] = (fm[key] + " " + line.strip()).strip()
    return fm, True

# Collect every .md in the bundle
md_files = []
for root, dirs, files in os.walk(bundle):
    dirs[:] = sorted(d for d in dirs if not d.startswith("."))
    for f in sorted(files):
        if f.endswith(".md"):
            md_files.append(os.path.join(root, f))

all_rel = {os.path.relpath(p, bundle).replace(os.sep, "/") for p in md_files}
meta = {}  # concept path -> frontmatter dict

# --- lint pass ---
for p in md_files:
    rel = os.path.relpath(p, bundle).replace(os.sep, "/")
    text = read(p)
    fm, closed = frontmatter(text)
    name = os.path.basename(p)
    if not closed:
        errors.append(f"{rel}: unterminated frontmatter block")
        continue
    if name in RESERVED:
        if fm is not None:
            if rel == "index.md":
                if "okf_version" not in fm:
                    infos.append("index.md: root frontmatter present but no okf_version")
            else:
                errors.append(f"{rel}: reserved file must not contain frontmatter")
        elif rel == "index.md":
            # okf_version is MAY per spec §11 — required only for bundles
            # this skill creates, so absence is informational, not a warning.
            infos.append("index.md: bundle root does not declare okf_version (optional per spec)")
    else:
        if fm is None:
            errors.append(f"{rel}: concept is missing YAML frontmatter")
        elif not fm.get("type"):
            errors.append(f"{rel}: frontmatter has no non-empty 'type' field")
        else:
            meta[rel] = fm
    # bundle-relative links (soft check — consumers must tolerate breakage)
    for target in re.findall(r"\]\((/[^)#\s]+)", text):
        t = target.lstrip("/")
        if t and not t.endswith("/") and t not in all_rel and not os.path.isdir(os.path.join(bundle, t)):
            warnings.append(f"{rel}: broken bundle-relative link {target}")

# --- sync pass: index files ---
added = []

def _s(v):
    return v if isinstance(v, str) else ""

def subtree_desc(prefix):
    """First concept description within a subdirectory — describes the
    subtree in its parent index, matching upstream bundle style."""
    for rel in sorted(meta):
        if rel.startswith(prefix):
            d = _s(meta[rel].get("description"))
            if d:
                return d
    return "(no description)"

if not lint_only:
    for root, dirs, files in os.walk(bundle):
        dirs[:] = sorted(d for d in dirs if not d.startswith("."))
        reldir = os.path.relpath(root, bundle).replace(os.sep, "/")
        reldir = "" if reldir == "." else reldir + "/"
        idx_path = os.path.join(root, "index.md")
        idx_text = read(idx_path) if os.path.exists(idx_path) else None

        # Upstream (knowledge-catalog) index style: one section per concept
        # `type`, then `# Subdirectories`; no page-title heading.
        groups = {}       # type -> [(link, line)]
        dir_entries = []  # (link, line)
        for d in dirs:
            dir_entries.append((d + "/", f"* [{d}]({d}/index.md) - {subtree_desc(reldir + d + '/')}"))
        for f in sorted(files):
            if not f.endswith(".md") or f in RESERVED:
                continue
            fm = meta.get(reldir + f, {})
            title = _s(fm.get("title")) or os.path.splitext(f)[0]
            desc = _s(fm.get("description")) or "(no description)"
            ctype = _s(fm.get("type")) or "Concepts"
            groups.setdefault(ctype, []).append((f, f"* [{title}]({f}) - {desc}"))

        entries = [e for g in sorted(groups) for e in groups[g]] + dir_entries

        if idx_text is None:
            if not entries:
                continue
            head = '---\nokf_version: "0.1"\n---\n\n' if reldir == "" else ""
            sections = [f"# {g}\n\n" + "\n".join(l for _, l in groups[g]) for g in sorted(groups)]
            if dir_entries:
                sections.append("# Subdirectories\n\n" + "\n".join(l for _, l in dir_entries))
            idx_text = head + "\n\n".join(sections) + "\n"
            with open(idx_path, "w", encoding="utf-8") as f:
                f.write(idx_text)
            touched.append(idx_path)
            added.append(f"created {reldir}index.md ({len(entries)} entries)")
        else:
            missing = [l for link, l in entries
                       if f"]({link}" not in idx_text and f"]({link.rstrip('/')}" not in idx_text]
            if missing:
                new = idx_text.rstrip("\n") + "\n" + "\n".join(missing) + "\n"
                with open(idx_path, "w", encoding="utf-8") as f:
                    f.write(new)
                touched.append(idx_path)
                added.append(f"{reldir}index.md: +{len(missing)} entries")

# --- sync pass: log entry when something changed ---
if added:
    log_path = os.path.join(bundle, "log.md")
    bullet = "* **Update**: okf-bundle-sync — " + "; ".join(added) + "."
    if os.path.exists(log_path):
        lines = read(log_path).splitlines()
    else:
        lines = ["# Knowledge Bundle Update Log", ""]
    header = f"## {today}"
    if header in lines:
        i = lines.index(header)
        lines.insert(i + 1, bullet)
    else:
        # newest first: insert after the title line
        lines[1:1] = ["", header, bullet]
    with open(log_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).rstrip("\n") + "\n")
    touched.append(log_path)

with open(touched_path, "w", encoding="utf-8") as f:
    f.write("\n".join(touched))

for i in infos:
    print(f"INFO  {i}")
for w in warnings:
    print(f"WARN  {w}")
for e in errors:
    print(f"ERROR {e}")
if added:
    print("SYNC  " + "; ".join(added))
print(f"okf-bundle-sync: {len(md_files)} files, {len(errors)} errors, {len(warnings)} warnings")
sys.exit(1 if errors else 0)
PYEOF
LINT_RC=$?

# --- commit (git projects only) ----------------------------------------
if [ -s "$TOUCHED" ] && [ "$MODE" != "--no-commit" ] && [ "$MODE" != "--lint-only" ]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    mapfile -t files < "$TOUCHED"
    git add -- "${files[@]}" && \
    OKF_SYNC=1 git commit -q -m "chore(okf): sync knowledge bundle indexes" -- "${files[@]}" \
      && echo "okf-bundle-sync: committed ${#files[@]} file(s)"
  fi
fi

[ "$MODE" = "--from-hook" ] && exit 0
exit "$LINT_RC"

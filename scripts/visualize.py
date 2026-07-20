#!/usr/bin/env python3
"""visualize.py — render an OKF bundle's markdown tree to a self-contained viz.html.

Standalone port of okf-bundler's graph visualizer
(okf_bundler/viewer/generator.py). That generator depends on
`okf_bundler.bundle.document.OKFDocument`, which in turn depends on PyYAML —
both are internal-package / third-party dependencies we don't want to drag in
here. This script re-implements the same tree-walk (parse frontmatter, follow
bundle-relative markdown links as graph edges, build a cytoscape-ready
node/edge JSON payload) using only the python3 stdlib, then inlines it plus
the vendored viz.css/viz.js into the vendored templates/viz.html template.

The frontmatter parser below follows the same shallow key:value /
block-list / folded-scalar pattern as `frontmatter()` in scripts/okf-sync.sh
(no YAML dependency).

NOTE: The generated viz.html loads cytoscape and marked from a jsdelivr CDN,
so viewing it requires internet access. The generation step itself is
offline and uses only stdlib.

Usage:
    python3 scripts/visualize.py <bundle-dir> [--out FILE] [--name NAME]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
_INDEX_NAME = "index.md"
_LINK_RE = re.compile(r"\]\(([^)\s]+\.md)(?:#[A-Za-z0-9_\-]*)?\)")
_TYPE_PALETTE = {
    "BigQuery Dataset": "#8b5cf6",
    "BigQuery Table": "#3b82f6",
    "Reference": "#10b981",
}
_DEFAULT_NODE_COLOR = "#94a3b8"


def frontmatter(text):
    """Shallow YAML-frontmatter parse: key: value lines, block-style lists
    (`tags:` followed by `- item` lines), and wrapped/folded (`>`/`>-`/`|`/
    `|-`) multi-line scalars. Returns (dict-or-None, body). No YAML
    dependency — mirrors scripts/okf-sync.sh's frontmatter(text)."""
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end == -1:
        return None, text
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
    # end points at the "\n" starting the closing "\n---" delimiter line;
    # the body starts after that line's own trailing newline (if any).
    nl = text.find("\n", end + 1)
    body = text[nl + 1:] if nl != -1 else ""
    if body.startswith("\n"):
        body = body[1:]
    return fm, body


def _extract_links(body, doc_dir, bundle_root):
    out, seen = [], set()
    bundle_root_resolved = bundle_root.resolve()
    for m in _LINK_RE.finditer(body):
        target = m.group(1)
        if "://" in target:
            continue
        if target.startswith("/"):
            base = bundle_root
            target = target.lstrip("/")
        else:
            base = doc_dir
        try:
            resolved = (base / target).resolve().relative_to(bundle_root_resolved)
        except ValueError:
            continue
        rel = resolved.as_posix()
        if rel.endswith(".md"):
            rel = rel[:-3]
        if rel and rel not in seen:
            seen.add(rel)
            out.append(rel)
    return out


def _walk_concepts(bundle_root):
    concepts = []
    for md_path in sorted(bundle_root.rglob("*.md")):
        if md_path.name == _INDEX_NAME:
            continue
        rel = md_path.relative_to(bundle_root).with_suffix("")
        concept_id = rel.as_posix()
        text = md_path.read_text(encoding="utf-8")
        fm, body = frontmatter(text)
        if fm is None:
            continue
        tags = fm.get("tags") or []
        if not isinstance(tags, list):
            tags = [str(tags)]
        concepts.append({
            "id": concept_id,
            "type": str(fm.get("type") or "Unknown"),
            "title": str(fm.get("title") or concept_id),
            "description": str(fm.get("description") or ""),
            "resource": str(fm.get("resource") or ""),
            "tags": [str(t) for t in tags],
            "body": body or "",
            "links_to": _extract_links(body or "", md_path.parent, bundle_root),
        })
    return concepts


def _to_node(c):
    color = _TYPE_PALETTE.get(c["type"], _DEFAULT_NODE_COLOR)
    return {
        "data": {
            "id": c["id"],
            "label": c["title"] or c["id"],
            "type": c["type"],
            "description": c["description"],
            "resource": c["resource"],
            "tags": c["tags"],
            "color": color,
            "size": 30 + min(60, len(c["body"]) // 200),
        }
    }


def _build_graph(concepts):
    ids = {c["id"] for c in concepts}
    nodes = [_to_node(c) for c in concepts]
    edges, seen_edges = [], set()
    for c in concepts:
        for target in c["links_to"]:
            if target == c["id"] or target not in ids:
                continue
            key = (c["id"], target)
            if key in seen_edges:
                continue
            seen_edges.add(key)
            edges.append({
                "data": {
                    "id": f"{c['id']}__{target}",
                    "source": c["id"],
                    "target": target,
                }
            })
    bodies = {c["id"]: c["body"] for c in concepts}
    types = sorted({c["type"] for c in concepts})
    return {
        "nodes": nodes,
        "edges": edges,
        "bodies": bodies,
        "types": types,
        "palette": _TYPE_PALETTE,
    }


def generate_visualization(bundle_root, out_path, *, bundle_name=None):
    """Walk a bundle and write a single self-contained HTML visualization.

    Returns counts: {'concepts': N, 'edges': M, 'bytes': K}.
    """
    bundle_root = Path(bundle_root)
    out_path = Path(out_path)
    if not bundle_root.is_dir():
        raise FileNotFoundError(f"Bundle directory not found: {bundle_root}")

    concepts = _walk_concepts(bundle_root)
    graph = _build_graph(concepts)
    template = (HERE / "visualize" / "templates" / "viz.html").read_text(encoding="utf-8")
    css = (HERE / "visualize" / "static" / "viz.css").read_text(encoding="utf-8")
    js = (HERE / "visualize" / "static" / "viz.js").read_text(encoding="utf-8")
    name = bundle_name or bundle_root.resolve().name

    html = (
        template
        .replace("/*__VIZ_CSS__*/", css)
        .replace("/*__VIZ_JS__*/", js)
        .replace("__BUNDLE_NAME__", json.dumps(name))
        .replace("__BUNDLE_DATA__", json.dumps(graph))
    )
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(html, encoding="utf-8")

    return {
        "concepts": len(concepts),
        "edges": len(graph["edges"]),
        "bytes": len(html.encode("utf-8")),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("bundle_dir", help="Path to the OKF bundle directory")
    parser.add_argument("--out", default=None, help="Output HTML path (default: <bundle-dir>/viz.html)")
    parser.add_argument("--name", default=None, help="Bundle display name (default: bundle directory name)")
    args = parser.parse_args()

    bundle_root = Path(args.bundle_dir)
    out_path = Path(args.out) if args.out else bundle_root / "viz.html"

    try:
        counts = generate_visualization(bundle_root, out_path, bundle_name=args.name)
    except FileNotFoundError as e:
        print(f"visualize.py: {e}", file=sys.stderr)
        return 1

    print(f"visualize.py: wrote {out_path} ({counts['concepts']} concepts, "
          f"{counts['edges']} edges, {counts['bytes']} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

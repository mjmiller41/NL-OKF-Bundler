# Vendored artifacts

| Path | Upstream source | License |
|---|---|---|
| harness/OKF_SPEC.md | knowledge-catalog `okf/SPEC.md` (via okf-init skill) | Apache-2.0 |
| scripts/okf-sync.sh | okf-init skill `scripts/okf-bundle-sync.sh` | (project) |
| scripts/visualize/ | okf-bundler `src/okf_bundler/viewer/` | Apache-2.0 |

**Note on scripts/visualize/** (viz.html): The generated viz.html loads cytoscape and marked from a CDN (jsdelivr), so viewing the visualization requires internet access. The generation step itself is offline and uses only Python stdlib.

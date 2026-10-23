# Seed content sources

| Output | Source | License |
|---|---|---|
| `assets/seed/articles.json` | `content/articles/*.json`: 24 original short articles (4 categories x 3 levels x 2), written for this app with AI assistance and reviewed for level and length | Project content |
| `assets/seed/remote_pool.json` | `content/remote/*.json`: 4 more original articles (one per category, level 2) that the mock article API serves on pull-to-refresh, two per refresh | Project content |
| `assets/seed/dict.json` | Subset of [ECDICT](https://github.com/skywind3000/ECDICT): only headwords and inflections used by the seed and remote-pool articles | MIT, see `assets/seed/ECDICT-LICENSE.txt` |
| `assets/seed/manifest.json` | Seed version only; read on every launch so the big files are parsed only when a newer seed ships | — |
| Article covers | Drawn in-app from a gradient palette (`cover: g0..g7`), no image files | — |

Rebuild after editing articles (ECDICT csv is not committed, ~66 MB):

```
python -I tool/build_seed.py --ecdict path/to/ecdict.csv
```

Bump `SEED_VERSION` in `tool/build_seed.py` so installed apps re-import; bump an
article's `content_version` to overwrite it on devices that already have it.

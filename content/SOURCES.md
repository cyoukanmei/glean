# Seed content sources

| Output | Source | License |
|---|---|---|
| `assets/seed/articles.json` | `content/articles/*.json`: 24 original short articles (4 categories x 3 levels x 2), written for this app with AI assistance and reviewed for level and length | Project content |
| `content/articles/classics.json` → `articles.json` | Chapter 1 of ten classic novels (Austen, Carroll, Conan Doyle, Shelley, Dickens, Wilde, C. Brontë, Alcott, Stevenson, Twain), plain-text editions from [Project Gutenberg](https://www.gutenberg.org); front/back matter removed, paragraphs rejoined, `_italics_` markers dropped. Ids, authors and book numbers are in the file (`source`) | Public domain in the US |
| `assets/seed/remote_pool.json` | `content/remote/*.json`: 4 more original articles (one per category, level 2) that the mock article API serves on pull-to-refresh, two per refresh | Project content |
| `assets/seed/dict.json` | Subset of [ECDICT](https://github.com/skywind3000/ECDICT): only headwords and inflections used by the seed and remote-pool articles | MIT, see `assets/seed/ECDICT-LICENSE.txt` |
| `assets/seed/manifest.json` | Seed version only; read on every launch so the big files are parsed only when a newer seed ships | — |
| Article covers | Drawn in-app as book jackets (`ArticleCover`): colour from the article id, title and author/category typeset; no image assets | Made for this project |
| `assets/illustrations/*` | Empty / offline / done / reading illustrations from the same pack (SVG as delivered, `reading` as 1080 px WebP) | Made for this project |
| Launcher icons (`android/.../mipmap-*`, iOS `AppIcon.appiconset`) | The pack's app icon; Android uses it as the adaptive-icon background, shrunk to 80 % to stay inside the safe zone | Made for this project |

Rebuild after editing articles (ECDICT csv is not committed, ~66 MB):

```
python -I tool/build_seed.py --ecdict path/to/ecdict.csv
```

Rebuild images and launcher icons from the design pack (PNG originals, ~12 MB,
kept outside the repo):

```
python -I tool/build_assets.py --pack path/to/asset-pack-original
```

Bump `SEED_VERSION` in `tool/build_seed.py` so installed apps re-import; bump an
article's `content_version` to overwrite it on devices that already have it.

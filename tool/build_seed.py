"""Build assets/seed/{articles,dict}.json from content/articles/*.json + ECDICT.

Usage (from the repo root):
    python -I tool/build_seed.py --ecdict path/to/ecdict.csv

ECDICT (https://github.com/skywind3000/ECDICT, MIT) is not committed; only
the subset of entries that the seed articles actually use is written out.
"""

import argparse
import csv
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

SEED_VERSION = 1
ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / "content" / "articles"
OUT = ROOT / "assets" / "seed"

CATEGORIES = ("tech", "business", "culture", "daily")
WORD_RE = re.compile(r"[A-Za-z]+")
# ECDICT exchange keys that name an inflected form of the headword.
FORM_KEYS = ("p", "d", "i", "3", "s", "r", "t")
MAX_DEFINITION_LINES = 3


def load_articles():
    articles = []
    for path in sorted(CONTENT.glob("*.json")):
        articles.extend(json.loads(path.read_text(encoding="utf-8")))
    ids = set()
    for a in articles:
        assert a["category"] in CATEGORIES, a["id"]
        assert a["level"] in (1, 2, 3), a["id"]
        assert a["id"] not in ids, f"duplicate id {a['id']}"
        ids.add(a["id"])
        assert a["paragraphs"] and all(p.strip() for p in a["paragraphs"]), a["id"]
    return articles


def build_articles(articles):
    out = []
    for i, a in enumerate(sorted(articles, key=lambda a: a["id"])):
        day = datetime.strptime(a["published_at"], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        out.append({
            "id": a["id"],
            "title": a["title"],
            "summary": a["summary"],
            # Covers are drawn in-app from a gradient palette, so the seed stays
            # tiny and nothing needs the network.
            "cover": f"g{i % 8}",
            "category": a["category"],
            "level": a["level"],
            "published_at": int(day.timestamp() * 1000),
            "word_count": sum(len(WORD_RE.findall(p)) for p in a["paragraphs"]),
            "content_version": a.get("content_version", 1),
            "paragraphs": a["paragraphs"],
        })
    return out


def article_words(articles):
    words = set()
    for a in articles:
        for text in [a["title"], *a["paragraphs"]]:
            words.update(w.lower() for w in WORD_RE.findall(text))
    return {w for w in words if len(w) > 1 or w in ("a", "i")}


def rank(row):
    """Lower is more common; unknown frequency sorts last."""
    vals = [int(v) for v in (row["frq"], row["bnc"]) if v and v != "0"]
    return min(vals) if vals else 10**9


def clean_definition(translation):
    lines = [l.strip() for l in translation.split("\\n") if l.strip()]
    main = [l for l in lines if not l.startswith("[网络]")]
    return "\n".join((main or lines)[:MAX_DEFINITION_LINES])


def load_ecdict(path):
    rows = {}
    csv.field_size_limit(sys.maxsize if sys.maxsize < 2**31 else 2**31 - 1)
    with open(path, encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f):
            word = row["word"].strip().lower()
            if WORD_RE.fullmatch(word) and row["translation"].strip():
                # Keep the more common spelling when case variants collide.
                if word not in rows or rank(row) < rank(rows[word]):
                    rows[word] = row
    return rows


def form_index(rows):
    """Map inflected form -> most common headword that lists it."""
    best = {}
    for head, row in rows.items():
        for part in row["exchange"].split("/"):
            key, _, form = part.partition(":")
            form = form.strip().lower()
            if key in FORM_KEYS and form and form != head and WORD_RE.fullmatch(form):
                if form not in best or rank(row) < rank(rows[best[form]]):
                    best[form] = head
    return best


def build_dict(words, rows):
    forms_all = form_index(rows)
    forms, needed = {}, set()
    for w in words:
        lemma = forms_all.get(w)
        if lemma in rows:
            forms[w] = lemma
            needed.add(lemma)
        if w in rows:
            needed.add(w)
    entries = [
        [w, rows[w]["phonetic"].strip() or None, clean_definition(rows[w]["translation"])]
        for w in sorted(needed)
    ]
    missing = sorted(w for w in words if w not in rows and w not in forms)
    return {"entries": entries, "forms": dict(sorted(forms.items()))}, missing


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ecdict", required=True, help="path to ecdict.csv")
    args = parser.parse_args()

    articles = load_articles()
    OUT.mkdir(parents=True, exist_ok=True)
    seed_articles = build_articles(articles)
    (OUT / "articles.json").write_text(
        json.dumps({"seed_version": SEED_VERSION, "articles": seed_articles},
                   ensure_ascii=False, indent=1),
        encoding="utf-8",
    )

    words = article_words(articles)
    dictionary, missing = build_dict(words, load_ecdict(args.ecdict))
    (OUT / "dict.json").write_text(
        json.dumps(dictionary, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )

    print(f"articles: {len(seed_articles)}")
    print(f"distinct words: {len(words)}, dict entries: {len(dictionary['entries'])}, "
          f"forms: {len(dictionary['forms'])}, not found: {len(missing)}")
    if missing:
        print("not found:", " ".join(missing[:60]))


if __name__ == "__main__":
    main()

"""Generate the AI reading aids bundled with the app: assets/seed/ai.json.

For every article in assets/seed/articles.json and remote_pool.json, an LLM
(DeepSeek, OpenAI-compatible chat API) writes:

- summary_zh       a 2-3 sentence Chinese summary (the reader's AI 导读)
- key_points_zh    three short Chinese key points
- cefr             CEFR level A1-C2 judged from vocabulary, syntax and ideas
- cefr_reason_zh   one sentence on why
- questions        three multiple-choice comprehension questions in English
                   (main idea, detail, inference), each with four options,
                   the answer and a Chinese explanation

Results are generated ahead of time so the app stays offline-first; each
entry stores a hash of the article text, and re-runs only call the API for
new or changed articles. Every response is validated; the options of each
question are shuffled with a seed from the article id so correct answers are
spread over A-D instead of following the model's habits.

Usage (the key is read from the environment, never from a file in the repo):

    DEEPSEEK_API_KEY=sk-... python -I tool/ai_enrich.py [--only id ...]
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "assets" / "seed"
OUT = SEED / "ai.json"
API = "https://api.deepseek.com/chat/completions"
MODEL = "deepseek-flash"
CEFR = ["A1", "A2", "B1", "B2", "C1", "C2"]

SYSTEM = """You are an experienced English reading teacher writing study aids \
for Chinese learners (secondary school to university level).

Read the article and reply with one JSON object, nothing else:
{
  "summary_zh": "2-3 句中文摘要，不超过 120 字，讲清主旨",
  "key_points_zh": ["要点一", "要点二", "要点三"],
  "cefr": "A1|A2|B1|B2|C1|C2",
  "cefr_reason_zh": "一句话说明评级依据（词汇、句式、话题抽象程度）",
  "questions": [
    {
      "type": "main_idea|detail|inference",
      "q": "question in English",
      "options": ["...", "...", "...", "..."],
      "answer": 0,
      "explain_zh": "中文解析，指出原文依据"
    }
  ]
}

Rules:
- Exactly three questions: one main_idea, one detail, one inference.
- Question and option language must be no harder than the article itself.
- Exactly one option is correct; distractors are plausible but clearly \
wrong according to the text. "answer" is the 0-based index of the correct \
option.
- Base everything only on the article text. For a novel excerpt, ask about \
this excerpt, not the whole book.
"""


def text_hash(a):
    body = a["title"] + "\n" + "\n".join(a["paragraphs"])
    return hashlib.sha1(body.encode("utf-8")).hexdigest()[:16]


def call(key, article):
    user = (
        f"Title: {article['title']}\n"
        + (f"Author: {article['author']}\n" if article.get("author") else "")
        + f"Category: {article['category']}\n\n"
        + "\n\n".join(article["paragraphs"])
    )
    body = json.dumps({
        "model": MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": user},
        ],
        "response_format": {"type": "json_object"},
        "max_tokens": 4000,
    }).encode("utf-8")
    req = urllib.request.Request(API, data=body, headers={
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    })
    with urllib.request.urlopen(req, timeout=180) as r:
        data = json.loads(r.read())
    return json.loads(data["choices"][0]["message"]["content"]), data["usage"]


def validate(ai):
    """Raises ValueError when the reply does not match the contract."""
    def need(cond, msg):
        if not cond:
            raise ValueError(msg)

    need(isinstance(ai.get("summary_zh"), str) and ai["summary_zh"].strip(),
         "summary_zh")
    kp = ai.get("key_points_zh")
    need(isinstance(kp, list) and 2 <= len(kp) <= 4
         and all(isinstance(k, str) and k for k in kp), "key_points_zh")
    need(ai.get("cefr") in CEFR, f"cefr {ai.get('cefr')!r}")
    need(isinstance(ai.get("cefr_reason_zh"), str), "cefr_reason_zh")
    qs = ai.get("questions")
    need(isinstance(qs, list) and len(qs) == 3, "questions")
    for q in qs:
        need(isinstance(q.get("q"), str) and q["q"], "q")
        opts = q.get("options")
        need(isinstance(opts, list) and len(opts) == 4
             and all(isinstance(o, str) and o for o in opts)
             and len(set(opts)) == 4, "options")
        need(isinstance(q.get("answer"), int) and 0 <= q["answer"] < 4,
             "answer")
        need(isinstance(q.get("explain_zh"), str), "explain_zh")


def shuffle(article_id, ai):
    rng = random.Random(article_id)
    for q in ai["questions"]:
        correct = q["options"][q["answer"]]
        rng.shuffle(q["options"])
        q["answer"] = q["options"].index(correct)
    return ai


def enrich(key, article, attempts=3):
    last = None
    for attempt in range(attempts):
        try:
            ai, usage = call(key, article)
            validate(ai)
            return shuffle(article["id"], ai), usage
        except (ValueError, KeyError, json.JSONDecodeError,
                urllib.error.URLError, TimeoutError) as e:
            last = e
            time.sleep(2 * (attempt + 1))
    raise RuntimeError(f"{article['id']}: {last}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", nargs="*", help="article ids to (re)do")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()
    key = os.environ.get("DEEPSEEK_API_KEY")
    if not key:
        sys.exit("DEEPSEEK_API_KEY is not set")

    seed = json.loads((SEED / "articles.json").read_text(encoding="utf-8"))
    remote = json.loads((SEED / "remote_pool.json").read_text(encoding="utf-8"))
    articles = seed["articles"] + remote
    out = (json.loads(OUT.read_text(encoding="utf-8"))
           if OUT.exists() else {"articles": {}})
    done = out["articles"]

    todo = [
        a for a in articles
        if (args.only and a["id"] in args.only)
        or (not args.only and done.get(a["id"], {}).get("hash") != text_hash(a))
    ]
    print(f"{len(todo)} of {len(articles)} articles need generating")
    tokens = {"prompt": 0, "completion": 0}
    failed = []
    with concurrent.futures.ThreadPoolExecutor(args.workers) as pool:
        futures = {pool.submit(enrich, key, a): a for a in todo}
        for f in concurrent.futures.as_completed(futures):
            a = futures[f]
            try:
                ai, usage = f.result()
            except RuntimeError as e:
                failed.append(a["id"])
                print(f"  failed {e}")
                continue
            tokens["prompt"] += usage["prompt_tokens"]
            tokens["completion"] += usage["completion_tokens"]
            done[a["id"]] = {"hash": text_hash(a), **ai}
            print(f"  {a['id']}: {ai['cefr']}")

    out = {
        "model": MODEL,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "articles": dict(sorted(done.items())),
    }
    OUT.write_text(json.dumps(out, ensure_ascii=False, indent=1),
                   encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: {len(done)} articles; "
          f"tokens in {tokens['prompt']}, out {tokens['completion']}")
    if failed:
        sys.exit(f"failed: {', '.join(failed)}")


if __name__ == "__main__":
    main()

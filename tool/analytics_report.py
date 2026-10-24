"""Summary report over the app's collected analytics events.

Reads an exported copy of the app database (我的 → 埋点调试面板 → 导出数据库,
then `adb pull`, see README section 7) and prints, for the last N days:

- overview: events, users, sessions, uploads
- reading minutes per day, and the distribution of single reading sessions
- open -> read half -> finish funnel (distinct user x article)
- list impressions and click-through per surface
- sessions: count, foreground length
- learning: words collected, comprehension quiz accuracy, AI 解释 sources
- most opened articles, offline hits

Same definitions as the in-app debug panel (lib/core/analytics/
analytics_report.dart) and the SQL in the README. Standard library only.

    python -I tool/analytics_report.py glean-export.db [--days 7] [--html report.html]
"""

import argparse
import html
import json
import sqlite3
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta


def load(db_path, since_ms):
    con = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    rows = con.execute(
        "SELECT name, ts, session_id, user_id, params FROM collected_events "
        "WHERE ts >= ? ORDER BY ts",
        (since_ms,),
    ).fetchall()
    uploads = con.execute(
        "SELECT COUNT(*), SUM(count), SUM(http_status = 200) FROM upload_log "
        "WHERE sent_at >= ?",
        (since_ms,),
    ).fetchone()
    titles = dict(con.execute("SELECT id, title FROM articles").fetchall())
    con.close()
    events = [
        {"name": n, "ts": ts, "session": s, "user": u, "p": json.loads(p)}
        for n, ts, s, u, p in rows
    ]
    return events, uploads, titles


def day_of(ts):
    return datetime.fromtimestamp(ts / 1000).date()


def report(events, uploads, titles, days, today):
    """Sections as (title, [(label, value)] rows, optional bar values)."""
    by = defaultdict(list)
    for e in events:
        by[e["name"]].append(e)
    out = []

    batches, sent, ok = uploads
    out.append(("概览", [
        ("事件", len(events)),
        ("用户", len({e["user"] for e in events})),
        ("会话", len({e["session"] for e in events})),
        ("事件种类", len(by)),
        ("上报批次（成功 / 全部）", f"{ok or 0} / {batches or 0}，共 {sent or 0} 条"),
    ], None))

    # Reading minutes per day, oldest first, empty days included.
    first = today - timedelta(days=days - 1)
    ms = Counter()
    reads = Counter()
    lengths = []
    for e in by["read_duration"]:
        d = day_of(e["ts"])
        active = e["p"].get("active_ms", 0)
        ms[d] += active
        reads[d] += 1
        lengths.append(active / 60000)
    daily = [first + timedelta(days=i) for i in range(days)]
    out.append((f"近 {days} 日阅读时长（分钟）", [
        (f"{d:%m-%d} 周{'一二三四五六日'[d.weekday()]}",
         f"{ms[d] / 60000:.1f} 分钟 · {reads[d]} 次")
        for d in daily
    ], [round(ms[d] / 60000, 1) for d in daily]))

    buckets = [("< 1 分钟", 0, 1), ("1–3 分钟", 1, 3), ("3–5 分钟", 3, 5),
               ("5–10 分钟", 5, 10), ("≥ 10 分钟", 10, 1e9)]
    counts = [sum(lo <= m < hi for m in lengths) for _, lo, hi in buckets]
    out.append(("单次阅读时长分布（read_duration）", [
        (label, f"{n} 次 · {n * 100 / max(len(lengths), 1):.0f}%")
        for (label, _, _), n in zip(buckets, counts)
    ], counts))

    def pairs(name, cond=lambda p: True):
        return {(e["user"], e["p"].get("article_id"))
                for e in by[name] if cond(e["p"])}
    opened = pairs("article_open")
    half = pairs("scroll_depth", lambda p: p.get("depth", 0) >= 50) & opened
    done = pairs("article_finish") & opened
    rate = lambda n: f"{n * 100 / max(len(opened), 1):.0f}%"
    out.append(("打开 → 读过半 → 读完（去重：用户 × 文章）", [
        ("打开", len(opened)),
        ("读过一半", f"{len(half)} · {rate(len(half))}"),
        ("读完", f"{len(done)} · {rate(len(done))}"),
    ], [len(opened), len(half), len(done)]))

    imp = Counter(e["p"].get("surface") for e in by["article_impression"])
    opn = Counter(e["p"].get("surface") for e in by["article_open"])
    surfaces = sorted(set(imp) | set(opn), key=lambda s: -imp[s])
    out.append(("列表曝光与点击", [
        (s, f"曝光 {imp[s]} · 打开 {opn[s]}"
            + (f" · 点击率 {opn[s] * 100 / imp[s]:.0f}%" if imp[s] else ""))
        for s in surfaces
    ], None))

    fg = [e["p"].get("foreground_ms", 0) / 60000 for e in by["app_background"]]
    starts = Counter(e["p"].get("reason") for e in by["session_start"])
    out.append(("会话", [
        ("会话开始", ", ".join(f"{k} {v}" for k, v in starts.items()) or "0"),
        ("进入后台次数", len(fg)),
        ("平均前台时长", f"{sum(fg) / max(len(fg), 1):.1f} 分钟"),
        ("冷启动耗时（中位数）", median_ms(by["app_open"], "cold_start_ms")),
    ], None))

    quiz = by["quiz_complete"]
    right = sum(e["p"].get("correct", 0) for e in quiz)
    total = sum(e["p"].get("total", 0) for e in quiz)
    ai = Counter(e["p"].get("source") for e in by["ai_explain"])
    lemmas = Counter(e["p"].get("lemma") for e in by["word_collect"])
    out.append(("学习", [
        ("收藏生词", f"{len(by['word_collect'])} 次"
            + (f"（{', '.join(w for w, _ in lemmas.most_common(5))}）" if lemmas else "")),
        ("查词", f"{len(by['word_lookup'])} 次，查到 "
            f"{sum(bool(e['p'].get('found')) for e in by['word_lookup'])} 次"),
        ("复习打分", len(by["word_review"])),
        ("阅读理解", f"{len(quiz)} 次，答对 {right} / {total}"
            + (f"（{right * 100 / total:.0f}%）" if total else "")),
        ("AI 解释", ", ".join(f"{k} {v}" for k, v in ai.items()) or "0"),
    ], None))

    top = Counter(e["p"].get("article_id") for e in by["article_open"])
    out.append(("打开最多的文章", [
        (titles.get(a, a), f"{n} 次") for a, n in top.most_common(5)
    ], None))

    out.append(("离线", [
        ("离线时下拉刷新（offline_hit）", len(by["offline_hit"])),
        ("同步（成功 / 全部）",
         f"{sum(bool(e['p'].get('ok')) for e in by['sync_run'])} / {len(by['sync_run'])}"),
    ], None))
    return out


def median_ms(events, key):
    values = sorted(e["p"].get(key, 0) for e in events)
    if not values:
        return "—"
    return f"{values[len(values) // 2]} ms（{len(values)} 次）"


def print_text(sections):
    for title, rows, bars in sections:
        print(f"\n== {title} ==")
        top = max(bars) if bars else 0
        for i, (label, value) in enumerate(rows):
            bar = ""
            if bars and top:
                bar = "  " + "█" * round(bars[i] / top * 24)
            print(f"  {label:<24} {value}{bar}")


def write_html(sections, path, subtitle):
    parts = []
    for title, rows, bars in sections:
        top = max(bars) if bars else 0
        body = []
        for i, (label, value) in enumerate(rows):
            bar = ""
            if bars and top:
                w = bars[i] / top * 100
                bar = f'<div class="bar"><i style="width:{w:.1f}%"></i></div>'
            body.append(f"<tr><th>{html.escape(str(label))}</th>"
                        f"<td>{html.escape(str(value))}{bar}</td></tr>")
        parts.append(f"<section><h2>{html.escape(title)}</h2>"
                     f"<table>{''.join(body)}</table></section>")
    page = f"""<!doctype html><html lang="zh"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>拾读埋点汇总</title><style>
body{{font-family:-apple-system,"PingFang SC","Microsoft YaHei",sans-serif;
background:#F4F1EB;color:#2A2620;margin:0;padding:24px}}
h1{{font-size:24px;margin:0 0 4px}}p{{color:#857E73;margin:0 0 20px}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(340px,1fr));gap:16px}}
section{{background:#fff;border-radius:16px;padding:16px 18px}}
h2{{font-size:15px;margin:0 0 10px;color:#24574A}}
table{{width:100%;border-collapse:collapse;font-size:13.5px}}
th{{text-align:left;font-weight:500;color:#857E73;padding:5px 8px 5px 0;
width:42%;vertical-align:top}}td{{padding:5px 0}}
.bar{{height:6px;border-radius:3px;background:#EEE9DF;margin-top:4px}}
.bar i{{display:block;height:100%;border-radius:3px;background:#3C8A70}}
</style></head><body><h1>拾读 · 埋点汇总</h1><p>{html.escape(subtitle)}</p>
<main>{''.join(parts)}</main></body></html>"""
    with open(path, "w", encoding="utf-8") as f:
        f.write(page)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("db", help="exported app database (glean-export-*.db)")
    parser.add_argument("--days", type=int, default=7)
    parser.add_argument("--html", help="also write an HTML report here")
    args = parser.parse_args()
    today = datetime.now().date()
    since = datetime.combine(today - timedelta(days=args.days - 1),
                             datetime.min.time())
    events, uploads, titles = load(args.db, int(since.timestamp() * 1000))
    sections = report(events, uploads, titles, args.days, today)
    subtitle = (f"{since:%Y-%m-%d} 至 {today:%Y-%m-%d} · "
                f"{len(events)} 条事件 · 来源 {args.db}")
    sys.stdout.reconfigure(encoding="utf-8")
    print(f"拾读埋点汇总 · {subtitle}")
    print_text(sections)
    if args.html:
        write_html(sections, args.html, subtitle)
        print(f"\nHTML: {args.html}")


if __name__ == "__main__":
    main()

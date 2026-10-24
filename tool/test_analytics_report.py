"""Tests for analytics_report.py on a small database of known events.

    python -I tool/test_analytics_report.py
"""

import json
import os
import sqlite3
import sys
import tempfile
import unittest
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import analytics_report as ar  # noqa: E402


def build(path, now):
    con = sqlite3.connect(path)
    con.executescript("""
        CREATE TABLE collected_events (event_id TEXT PRIMARY KEY, name TEXT,
          ts INTEGER, session_id TEXT, user_id TEXT, params TEXT,
          received_at INTEGER);
        CREATE TABLE upload_log (batch_id TEXT PRIMARY KEY, sent_at INTEGER,
          count INTEGER, http_status INTEGER, error TEXT, duration_ms INTEGER);
        CREATE TABLE articles (id TEXT PRIMARY KEY, title TEXT);
    """)
    con.execute("INSERT INTO articles VALUES ('a1', 'Little Women')")
    ms = lambda d: int(d.timestamp() * 1000)
    today = now.replace(hour=10, minute=0, second=0, microsecond=0)
    events = [
        # Two users open a1; u1 reads half and finishes, u2 stops early.
        ("article_open", today, "s1", "u1", {"article_id": "a1", "surface": "shelf"}),
        ("scroll_depth", today, "s1", "u1", {"article_id": "a1", "depth": 50}),
        ("article_finish", today, "s1", "u1", {"article_id": "a1"}),
        ("read_duration", today, "s1", "u1", {"article_id": "a1", "active_ms": 240000, "max_progress": 1}),
        ("article_open", today, "s2", "u2", {"article_id": "a1", "surface": "store"}),
        ("scroll_depth", today, "s2", "u2", {"article_id": "a1", "depth": 25}),
        ("read_duration", today - timedelta(days=1), "s3", "u2", {"article_id": "a1", "active_ms": 30000, "max_progress": 0.3}),
        ("article_impression", today, "s1", "u1", {"article_id": "a1", "surface": "shelf", "position": 0}),
        ("article_impression", today, "s1", "u1", {"article_id": "a2", "surface": "shelf", "position": 1}),
        ("quiz_complete", today, "s1", "u1", {"article_id": "a1", "correct": 2, "total": 3}),
        ("ai_explain", today, "s1", "u1", {"lemma": "temporary", "source": "api"}),
        ("word_collect", today, "s1", "u1", {"lemma": "temporary", "article_id": "a1", "surface": "reader"}),
        # Outside the window: ignored.
        ("article_open", today - timedelta(days=30), "s0", "u1", {"article_id": "a1", "surface": "shelf"}),
    ]
    for i, (name, t, s, u, p) in enumerate(events):
        con.execute("INSERT INTO collected_events VALUES (?,?,?,?,?,?,?)",
                    (f"e{i}", name, ms(t), s, u, json.dumps(p), ms(t)))
    con.execute("INSERT INTO upload_log VALUES ('b1', ?, 12, 200, NULL, 80)",
                (ms(today),))
    con.commit()
    con.close()


class ReportTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.db = os.path.join(self.dir.name, "export.db")
        self.now = datetime.now()
        build(self.db, self.now)
        since = datetime.combine((self.now - timedelta(days=6)).date(),
                                 datetime.min.time())
        events, uploads, titles = ar.load(self.db, int(since.timestamp() * 1000))
        self.sections = dict(
            (title, (dict(rows), bars))
            for title, rows, bars in ar.report(events, uploads, titles, 7,
                                               self.now.date()))

    def tearDown(self):
        self.dir.cleanup()

    def test_funnel_counts_distinct_user_article_pairs(self):
        rows, bars = self.sections["打开 → 读过半 → 读完（去重：用户 × 文章）"]
        self.assertEqual(bars, [2, 1, 1])
        self.assertEqual(rows["读完"], "1 · 50%")

    def test_reading_minutes_per_day_include_empty_days(self):
        _, bars = self.sections["近 7 日阅读时长（分钟）"]
        self.assertEqual(len(bars), 7)
        self.assertEqual(bars[-1], 4.0)
        self.assertEqual(bars[-2], 0.5)
        self.assertEqual(sum(bars), 4.5)

    def test_reading_length_buckets(self):
        _, bars = self.sections["单次阅读时长分布（read_duration）"]
        self.assertEqual(bars, [1, 0, 1, 0, 0])

    def test_click_through_and_learning(self):
        ctr, _ = self.sections["列表曝光与点击"]
        self.assertEqual(ctr["shelf"], "曝光 2 · 打开 1 · 点击率 50%")
        learn, _ = self.sections["学习"]
        self.assertEqual(learn["阅读理解"], "1 次，答对 2 / 3（67%）")
        self.assertEqual(learn["AI 解释"], "api 1")
        top, _ = self.sections["打开最多的文章"]
        self.assertEqual(top["Little Women"], "2 次")

    def test_html_report(self):
        out = os.path.join(self.dir.name, "r.html")
        ar.write_html([(t, list(r.items()), b) for t, (r, b) in self.sections.items()],
                      out, "test")
        with open(out, encoding="utf-8") as f:
            page = f.read()
        self.assertIn("拾读 · 埋点汇总", page)
        self.assertIn('class="bar"', page)


if __name__ == "__main__":
    unittest.main()

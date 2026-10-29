#!/usr/bin/env python3
"""Tests for the reference leaderboard server. Run: python3 server/test_leaderboard_server.py"""
import json
import os
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leaderboard_server as ls  # noqa: E402


def facts(**kw):
    f = {"name": "Tester", "install_id": "abc123", "rules_version": "1.0.0", "house": "ashgrove",
         "creature": "shade", "time": 180.0, "true_evidence": 3, "incorrect_attempts": 0,
         "incomplete_attempts": 0, "wounds": 0, "clean_hunts_survived": 1, "blind": False,
         "vanquished": True, "seed": 1, "event_digest": "a" * 64}
    f.update(kw)
    f.setdefault("claimed_score", ls.compute_score(f, "1.0.0"))
    return f


class ScoreTests(unittest.TestCase):
    def test_matches_client_reference_value(self):
        # Same case as tests/test_runner.gd::test_scoring.
        self.assertEqual(ls.compute_score(facts(), "1.0.0"), 4000 + 2000 + 900 + 1000 + 800 + 150)

    def test_rejections(self):
        self.assertEqual(ls.validate(facts(claimed_score=99999))[1], "score mismatch")
        self.assertEqual(ls.validate(facts(rules_version="9.9"))[1], "unsupported rules_version")
        self.assertEqual(ls.validate(facts(true_evidence=4))[1], "implausible evidence count")
        self.assertEqual(ls.validate(facts(creature="harbinger", true_evidence=0))[1], "the Harbinger only answers recklessness")
        self.assertEqual(ls.validate(facts(name="<script>"))[1], "invalid name")
        self.assertEqual(ls.validate(facts(time=2.0))[1], "implausible time")
        self.assertIsNone(ls.validate(facts())[1])


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.srv = ThreadingHTTPServer(("127.0.0.1", 0), ls.make_handler(ls.Store(os.path.join(cls.tmp, "t.db"))))
        cls.url = "http://127.0.0.1:%d/v1/scores" % cls.srv.server_address[1]
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def post(self, body):
        req = urllib.request.Request(self.url, json.dumps(body).encode(), {"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_submit_rank_and_duplicate(self):
        code, body = self.post(facts(event_digest="b" * 64))
        self.assertEqual(code, 201)
        self.assertEqual(body["rank"], 1)
        code, _ = self.post(facts(event_digest="b" * 64))
        self.assertEqual(code, 409)
        code, _ = self.post(facts(claimed_score=1))
        self.assertEqual(code, 422)
        with urllib.request.urlopen(self.url + "?limit=5") as r:
            data = json.loads(r.read())
        self.assertEqual(data["scores"][0]["name"], "Tester")


if __name__ == "__main__":
    unittest.main()

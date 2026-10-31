#!/usr/bin/env python3
"""SPECTRAL RUN reference global leaderboard server (stdlib only: http.server + sqlite3).

The game client never holds privileged credentials. Every submission carries run
facts; the server validates them, RECOMPUTES the score with the versioned rules
below (mirroring scripts/core/scoring.gd) and rejects any mismatch.

Run:   python3 server/leaderboard_server.py --port 8787 --db server/leaderboard.sqlite3
API:   POST /v1/scores   (JSON run facts)    -> {"ok": true, "score": n, "rank": r}
       GET  /v1/scores?limit=20[&house=id]   -> {"scores": [...], "rules_version": "1.0.0"}

Deploy behind HTTPS (a reverse proxy) for real use. Limitations are documented in
docs/LEADERBOARD.md: facts are validated for consistency but runs are not
re-simulated, so a determined cheater could fabricate plausible facts.
"""
import argparse
import json
import re
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOUSES = {"ashgrove", "blackwood", "hollow_lane", "evangeline", "marrow_street", "tavern", "harbor"}
CREATURE_EVIDENCE = {"shade": 3, "poltergeist": 3, "vampire": 3, "werewolf": 3, "shapeshifter": 3, "harbinger": 0}
NAME_RE = re.compile(r"^[\w .'\-]{1,24}$", re.UNICODE)
RATE_LIMIT = 12          # submissions per install id per hour
MAX_BODY = 8192

# --- Versioned scoring rules (must match scripts/core/scoring.gd) ----------------------
RULES = {
    "1.0.0": {
        "victory_base": 4000, "speed_max": 3000, "speed_full_until": 60.0, "speed_zero_at": 420.0,
        "evidence_each": 300, "evidence_cap": 3, "clean_id_bonus": 1000, "unharmed_bonus": 800,
        "hunt_each": 150, "hunt_cap": 3, "audacity": 250, "wrong_penalty": 700, "incomplete_penalty": 250,
        "difficulty": {"shade": 1.0, "poltergeist": 1.05, "vampire": 1.15, "werewolf": 1.2,
                       "shapeshifter": 1.3, "harbinger": 1.25},
    }
}


def godot_round(x):
    """Godot's round(): half away from zero."""
    return int(x + 0.5) if x >= 0 else -int(-x + 0.5)


def compute_score(f, version):
    r = RULES[version]
    if not f["vanquished"]:
        return 0
    t = float(f["time"])
    frac = min(1.0, max(0.0, (r["speed_zero_at"] - t) / (r["speed_zero_at"] - r["speed_full_until"])))
    speed = godot_round(r["speed_max"] * frac)
    evidence = r["evidence_each"] * min(int(f["true_evidence"]), r["evidence_cap"])
    wrong = int(f["incorrect_attempts"])
    incomplete = int(f["incomplete_attempts"])
    ident = r["clean_id_bonus"] if wrong == 0 and incomplete == 0 else 0
    unharmed = r["unharmed_bonus"] if int(f["wounds"]) == 0 else 0
    hunts = r["hunt_each"] * min(int(f["clean_hunts_survived"]), r["hunt_cap"])
    audacity = r["audacity"] if f["blind"] and wrong == 0 else 0
    subtotal = r["victory_base"] + speed + evidence + ident + unharmed + hunts + audacity
    scaled = godot_round(subtotal * r["difficulty"][f["creature"]])
    return max(0, scaled - (r["wrong_penalty"] * wrong + r["incomplete_penalty"] * incomplete))


def validate(body):
    """Returns (facts, error). Rejects impossible or inconsistent run facts."""
    try:
        version = str(body["rules_version"])
        if version not in RULES:
            return None, "unsupported rules_version"
        name = str(body["name"]).strip()
        if not NAME_RE.match(name):
            return None, "invalid name"
        f = {
            "name": name, "install_id": str(body["install_id"])[:32], "rules_version": version,
            "house": str(body["house"]), "creature": str(body["creature"]), "time": float(body["time"]),
            "true_evidence": int(body["true_evidence"]), "incorrect_attempts": int(body["incorrect_attempts"]),
            "incomplete_attempts": int(body["incomplete_attempts"]), "wounds": int(body["wounds"]),
            "clean_hunts_survived": int(body["clean_hunts_survived"]), "blind": bool(body["blind"]),
            "vanquished": bool(body["vanquished"]), "claimed_score": int(body["claimed_score"]),
            "seed": int(body.get("seed", 0)), "event_digest": str(body.get("event_digest", ""))[:64],
            "game_version": str(body.get("game_version", ""))[:16],
        }
    except (KeyError, TypeError, ValueError):
        return None, "malformed submission"
    if f["house"] not in HOUSES:
        return None, "unknown house"
    if f["creature"] not in CREATURE_EVIDENCE:
        return None, "unknown creature"
    if not f["vanquished"]:
        return None, "only vanquished runs are ranked"
    if not (8.0 <= f["time"] <= 3600.0):
        return None, "implausible time"
    if not (0 <= f["true_evidence"] <= CREATURE_EVIDENCE[f["creature"]]):
        return None, "implausible evidence count"
    if not (0 <= f["wounds"] <= 1):
        return None, "a vanquishing investigator has at most one wound"
    if f["incorrect_attempts"] < 0 or f["incomplete_attempts"] < 0 or f["clean_hunts_survived"] < 0:
        return None, "negative counters"
    if f["creature"] == "harbinger" and f["incorrect_attempts"] < 2:
        return None, "the Harbinger only answers recklessness"
    if f["blind"] and (f["true_evidence"] > 0 or f["incorrect_attempts"] > 0):
        return None, "inconsistent blind flag"
    if f["clean_hunts_survived"] > int(f["time"] // 10) + 1:
        return None, "too many hunts for the run length"
    if len(f["event_digest"]) not in (0, 64):
        return None, "bad digest"
    score = compute_score(f, version)
    if score != f["claimed_score"]:
        return None, "score mismatch"
    f["score"] = score
    return f, None


class Store:
    def __init__(self, path):
        self.lock = threading.Lock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute("""CREATE TABLE IF NOT EXISTS scores (
            id INTEGER PRIMARY KEY, name TEXT, install_id TEXT, rules_version TEXT, house TEXT,
            creature TEXT, time REAL, score INTEGER, seed INTEGER, digest TEXT, game_version TEXT,
            created REAL)""")
        self.db.execute("CREATE INDEX IF NOT EXISTS scores_rank ON scores(rules_version, score DESC)")
        self.db.commit()

    def recent_count(self, install_id, window=3600):
        with self.lock:
            cur = self.db.execute("SELECT COUNT(*) FROM scores WHERE install_id=? AND created>?",
                                  (install_id, time.time() - window))
            return cur.fetchone()[0]

    def insert(self, f):
        with self.lock:
            dup = self.db.execute("SELECT 1 FROM scores WHERE install_id=? AND digest=? AND digest!=''",
                                  (f["install_id"], f["event_digest"])).fetchone()
            if dup:
                return None
            self.db.execute("INSERT INTO scores (name, install_id, rules_version, house, creature, time, score, seed,"
                            " digest, game_version, created) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
                            (f["name"], f["install_id"], f["rules_version"], f["house"], f["creature"], f["time"],
                             f["score"], f["seed"], f["event_digest"], f["game_version"], time.time()))
            self.db.commit()
            rank = self.db.execute("SELECT COUNT(*) FROM scores WHERE rules_version=? AND score>?",
                                   (f["rules_version"], f["score"])).fetchone()[0] + 1
            return rank

    def top(self, limit, house=None, version=None):
        version = version or max(RULES)
        q = "SELECT name, score, time, house, creature, created FROM scores WHERE rules_version=?"
        args = [version]
        if house:
            q += " AND house=?"
            args.append(house)
        q += " ORDER BY score DESC, time ASC LIMIT ?"
        args.append(limit)
        with self.lock:
            rows = self.db.execute(q, args).fetchall()
        return [{"name": r[0], "score": r[1], "time": r[2], "house": r[3], "creature": r[4], "created": r[5]} for r in rows]


def make_handler(store):
    class Handler(BaseHTTPRequestHandler):
        def _send(self, code, obj):
            data = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, fmt, *args):
            pass

        def do_GET(self):
            u = urlparse(self.path)
            if u.path != "/v1/scores":
                return self._send(404, {"error": "not found"})
            qs = parse_qs(u.query)
            limit = max(1, min(100, int(qs.get("limit", ["20"])[0] or 20)))
            house = qs.get("house", [None])[0]
            self._send(200, {"scores": store.top(limit, house), "rules_version": max(RULES)})

        def do_POST(self):
            if urlparse(self.path).path != "/v1/scores":
                return self._send(404, {"error": "not found"})
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > MAX_BODY:
                return self._send(413, {"error": "bad body size"})
            try:
                body = json.loads(self.rfile.read(length))
            except ValueError:
                return self._send(400, {"error": "invalid json"})
            facts, err = validate(body if isinstance(body, dict) else {})
            if err:
                return self._send(422, {"error": err})
            if store.recent_count(facts["install_id"]) >= RATE_LIMIT:
                return self._send(429, {"error": "rate limited"})
            rank = store.insert(facts)
            if rank is None:
                return self._send(409, {"error": "duplicate run"})
            self._send(201, {"ok": True, "score": facts["score"], "rank": rank})
    return Handler


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--db", default="server/leaderboard.sqlite3")
    a = ap.parse_args()
    srv = ThreadingHTTPServer((a.host, a.port), make_handler(Store(a.db)))
    print(f"SPECTRAL RUN leaderboard on http://{a.host}:{a.port}")
    srv.serve_forever()


if __name__ == "__main__":
    main()

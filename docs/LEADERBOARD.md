# Global leaderboard

SPECTRAL RUN is fully playable offline. Offline rankings compare you against
**fictional** legendary hunters (`scripts/core/rankings.gd`). Local records are
never presented as a verified global leaderboard.

## Client

`scripts/autoload/online.gd` activates only when `user://online.cfg` contains:

```ini
[leaderboard]
url="https://your-host.example/api"
```

(`install_id` is generated automatically: a random, non-secret identifier used
for rate limiting and duplicate detection.) The client holds **no privileged
credentials**. After a vanquished run it POSTs the run facts and its claimed
score; the results screen shows the server's verdict and the server-verified rank.

## Reference server

`server/leaderboard_server.py` — Python 3 standard library only (http.server +
sqlite3). Run it locally:

```bash
python3 server/leaderboard_server.py --port 8787 --db server/leaderboard.sqlite3
```

Tests:

```bash
python3 server/test_leaderboard_server.py
```

What it does:

* recomputes every score from the submitted facts using the **versioned rules**
  (`RULES["1.0.0"]`, identical to `scripts/core/scoring.gd`) and rejects any
  mismatch;
* rejects impossible or inconsistent facts (unknown house/creature, too much
  evidence, more than one wound on a victory, a Harbinger without
  recklessness, contradictory "blind" flags, too many hunts for the run length,
  implausible times);
* validates display names, rate-limits per install (12/hour), rejects
  duplicate submissions of the same run (event digest);
* ranks per rules version, so rebalanced rules never mix with old scores.

## What is required for a real deployment

1. A host for the server (any VPS/container) behind **HTTPS** (e.g. Caddy or
   nginx as a reverse proxy). For scale, swap SQLite for Postgres.
2. Set the URL in `user://online.cfg` (or ship a default config with the build).
3. Optional hardening, recommended before a public launch:
   * **Replay verification.** Runs are currently validated for consistency, not
     re-simulated. The client already records a full replay and an event digest;
     uploading the replay and checking it server-side (evidence timestamps,
     movement speeds, attempt order) would make fabricated runs much harder.
   * Account-based display names / profanity filtering.
   * Per-IP rate limiting at the proxy.

No external infrastructure was available while building this, so no live
global leaderboard exists yet.

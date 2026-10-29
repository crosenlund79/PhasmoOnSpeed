# SPECTRAL RUN — Scoring Rules v1.0.0

Implemented in `scripts/core/scoring.gd` and mirrored exactly by the reference
server (`server/leaderboard_server.py`). Any change to a constant **must** bump
`Scoring.RULES_VERSION`; scores are stored and ranked per rules version so
rebalancing never silently mixes old and new results.

Only **vanquished** runs score. A run that ends in death scores 0.

| Component | Points | Rule |
|---|---|---|
| Vanquished | 4000 | flat |
| Swiftness | 0–3000 | `3000 × clamp((420 − t) / 360, 0, 1)` — full at ≤ 60 s, zero at ≥ 7 min |
| Evidence | 300 each, max 900 | only evidence belonging to the entity actually vanquished; capped at 3 |
| Clean identification | 1000 | no incorrect and no incomplete vanquishing attempts |
| Unharmed | 800 | never wounded |
| Hunts survived | 150 each, max 450 | hunts that ended without a wound; hunts provoked by a reckless reaction and Harbinger hunts never count |
| Audacity | 250 | correct, completely blind victory (no evidence, no meaningful investigation, no wrong attempts) |
| Creature difficulty | ×1.00 – ×1.30 | Shade 1.00, Poltergeist 1.05, Vampire 1.15, Werewolf 1.20, Shapeshifter 1.30, Harbinger 1.25 — applied to everything above |
| Reckless attempts | −700 each | every incorrect vanquishing attempt (applied after the multiplier, uncapped) |
| Incomplete attempts | −250 each | right identity but missing preparation (wrong room for a rite, unexposed shapeshifter) |

`total = max(0, round(subtotal × difficulty) − penalties)` (round half away from zero).

## Balance and anti-farming

* **Evidence vs. stalling.** Swiftness decays by ~8.3 points per second, so one
  extra piece of evidence (300) is worth about 36 seconds. Evidence beyond the
  entity's three never scores. Searching is worthwhile when it prevents a wrong
  attempt (−700 and the loss of the 1000 clean-identification bonus) — not as a
  way to pad a run.
* **Fast, correct early victories stay competitive.** A 75-second victory with
  a single clue beats a careful 3-minute run with all three (see tests).
* **Recklessness never pays.** The Harbinger requires at least two wrong
  attempts (≥ −1400), always forfeits clean identification and evidence, and
  its hunts never count as survived hunts. Its ×1.25 multiplier only partly
  compensates for the extra danger, so a Harbinger victory is always worth
  less than the equivalent clean run.
* **Caps.** Evidence ≤ 3, hunts ≤ 3, swiftness ≤ 3000. Theoretical maximum is
  13 195 (a Shapeshifter in under a minute, with everything else perfect).
* **Determinism.** The score depends only on the run facts listed in the
  summary; the same facts always produce the same score on client and server.

## Worked examples

| Run | Score |
|---|---|
| Shade, 3:00, 3 evidence, clean, unharmed, 1 hunt survived | 4000+2000+900+1000+800+150 = **8850** |
| Werewolf, same performance | 8850 × 1.2 = **10620** |
| Vampire, 0:50, blind stake, unharmed | (4000+3000+1000+800+250) × 1.15 = **10408** |
| Harbinger, 3:00, two reckless attempts, unharmed | (4000+2000+800) × 1.25 − 1400 = **7100** |

## Fictional legends

The offline rankings (`scripts/core/rankings.gd`) list twelve **fictional**
legendary hunters with scores on this same scale (6 380 – 11 420). The UI labels
them as fictional everywhere they appear.

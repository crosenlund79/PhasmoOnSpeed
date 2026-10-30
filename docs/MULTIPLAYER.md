# Competitive multiplayer

Two to four rival investigators share one haunted house and one randomly chosen
entity, and compete for the highest **individual** score. One successful
vanquishing ends the match for everyone; the vanquisher earns a bonus but is not
automatically the winner. Solo play is unchanged and kept completely separate.

## Playing

1. Main menu → **Competitive Hunt**.
2. **Host:** enter your name and a port (default **24680**) and press **Host Game**.
   Choose the house, press **Ready**, and **Start Match** once every hunter is
   ready (at least two hunters).
3. **Join:** enter your name, the host's address and port, press **Join Game**,
   then **Ready**.

### Local network (LAN)

The host shares their local IPv4 address (Windows: `ipconfig` → "IPv4 Address",
e.g. `192.168.1.23`). Joiners type that address. Windows Firewall will ask to
allow SPECTRAL RUN the first time you host — allow it on private networks.

### Over the internet

The game uses **UDP** on the chosen port (ENet). The host must:

* forward **UDP port 24680** (or the port they chose) on their router to their
  PC's local IP address, and allow it through the firewall;
* share their **public** IP address (e.g. from a "what is my IP" site).

There is no relay or matchmaking server; if port forwarding is impossible (some
mobile/CGNAT connections), use a LAN or a virtual LAN tool (e.g. a VPN that puts
everyone on one network) and join by its address.

## Controls specific to matches

| Input | Action |
|---|---|
| G | **Shove** the rival in front of you (close range, ~5 s cooldown) |
| Tab / Shift+Tab | Choose your suspected entity (all entities are listed) |
| Esc | Menu — pauses the match for **everyone** (see below) |
| Click / Q (when dead) | Switch which surviving hunter you spectate |

Everything else is the same as solo play.

## Rules of the house

* Each hunter has their **own private journal** and equipment. Evidence you find
  is never sent to rivals' screens.
* The house, the entity, occupants, resources (only one garlic!) and every
  placed item are shared. Rivals can grab resources first.
* **Shove:** pushes a rival away along your facing direction with a short
  stagger. It never damages, has a 5 s cooldown (1 s if you miss), and the
  victim is briefly immune to further shoves. It earns no points — but a rival
  who gets mauled right after being shoved may earn you a remark.
* **Two creature hits** kill a hunter. Their score is kept and they spectate the
  survivors without being able to interact. If every hunter dies the match is lost.
* Recklessness is shared misery: wrong attempts by anyone count towards summoning
  the Harbinger.

## Authority model (anti-cheat)

The host runs the only simulation (`scripts/game/run.gd`): the entity's type
and AI, evidence, the shared world, damage, shoves, vanquishing attempts and
scoring. Clients (`scripts/game/client_run.gd`) send their hunter's position,
aim and button state; they render the world from host snapshots and events and
never decide outcomes. The host rejects impossible movement (teleporting or
over-speed) and corrects the client. The entity's true type is never sent to
clients during a match (they see only its token).

Network traffic (all on `/root/Net`, `scripts/autoload/net.gd`):

| Stream | Direction | Mode |
|---|---|---|
| Hunter input (position, aim, buttons) | client → host | unreliable ordered, channel 1, 60 Hz |
| World snapshot (all actors) | host → all | unreliable ordered, channel 1, 20 Hz |
| Private HUD state (readings, slots, prompts) | host → one | reliable, channel 2, 10 Hz |
| World events (decals, sounds, lights, speech) | host → all | reliable |
| Private messages (evidence, toasts, knockback, death) | host → one | reliable |
| Results + compressed replay | host → all | reliable, chunked |

## Shared menu pause

Opening the menu (Esc) asks the host to pause. The host alone decides: it
freezes its simulation (entity, hunts, occupants, run clock, replay) and tells
every client, which freeze too and show a *MATCH PAUSED — Name opened the menu*
banner with the remaining time. The opener can use the menu normally.

* **Limit Menu Pause to 10 Seconds** (lobby, host only, default On): the pause
  ends by itself after 10 real seconds — the opener's menu may stay open — and
  no new pause can start for the next 20 s, so the match can never be held
  indefinitely by reopening the menu. Off: the pause lasts until the opener
  closes their menu (or disconnects).
* While a pause is held, other hunters may open their own menus but cannot take
  over or extend it.

The host also picks **Normal / Nightmare** difficulty for the match in the lobby.

## Testing

`tests/net_test.sh` starts a real host and N client processes on localhost and
checks joining, ready/start, movement synchronisation, private journals, shove
knockback and cooldown, a remote death with spectating, a client's own
vanquishing ending the match, results and replay delivery, a client dropping
out mid-match and the host shutting down:

```bash
GODOT=/path/to/godot tests/net_test.sh 3 full   # 4 hunters
GODOT=/path/to/godot tests/net_test.sh 2 drop   # disconnects
GODOT=/path/to/godot tests/net_test.sh 2 pause  # shared pause, 10 s limit, cooldown, Nightmare option
```

## Known limitations

* No relay/NAT traversal or matchmaking; internet play needs port forwarding.
* Client movement is client-predicted (responsive) and host-validated; a very
  high-latency connection can cause brief corrections.
* No host migration: if the host leaves, the match ends for everyone.
* Competitive scores are local records only; there is no online competitive
  leaderboard yet (the solo leaderboard is unaffected).

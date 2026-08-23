# Spellfall — Roadmap

Phases are gated, not scheduled. **A phase does not start until the one before it is
genuinely done**, and Phase 1 is judged by whether the game is fun, not by a checklist.

Current position: **every Phase 1 step is built.** What is left is not a step - it is the
gate below, and it is answered by playing the game rather than by writing more of it.

---

## Phase 1 — Make the combat fun (offline)

Everything here is single-player against a bot, on one device. No accounts, no network, no
progression, no shop, no cosmetics. If that rule gets bent, the project is off track.

| # | Step | State |
|---|---|---|
| 1 | Project skeleton, arena, player, desktop movement, fixed camera | **done** |
| 2 | Mobile controls: touch stick, multi-touch safe, scalable across screen sizes | **done** |
| 3 | Ability framework (Resource-driven) + Fireball | **done** |
| 4 | Instability component + HUD readout | **done** |
| 5 | Knockback system, wired to instability | **done** |
| 6 | Fall detection and elimination | **done** |
| 7 | Force Wave, Blink, Arcane Shield | **done** |
| 8 | Drag-to-aim + aim indicators | **done** |
| 9 | Round manager: countdown, spawn, win, reset, score | **done** (landed early with #6) |
| 10 | One simple bot opponent | **done** |
| 11 | Game feel pass: hit pause, camera shake, particles, audio, haptics | **done** |

**Gate to Phase 2 — now the only thing standing between here and Phase 2.** Every question in
`GAME_DESIGN.md` under "What Phase 1 must prove" answers yes. Specifically — movement feels good, aiming feels good on a touchscreen,
Fireball and Force Wave are satisfying, knockback is predictable, instability creates real
tension, falling off is reliable, the bot is a useful sparring partner, rounds reset cleanly,
and the loop is fun enough that you keep playing after you stop testing.

If the loop is not fun, **the answer is to change the combat, not to add features.**

---

## Phase 2 — Depth, still offline

Only once Phase 1 is fun.

- Between-round upgrades: pick 1 of 3, aiming for interesting build combinations.
- Bot difficulty levels.
- A second arena shape, to prove the arena is data and not hardcoded.

**Gate to Phase 3:** upgrades produce genuinely different builds rather than flat stat bumps.

---

## Phase 3 — Networking

Follows the progression from the brief. No skipping.

| Phase | Scope |
|---|---|
| **A** | Offline player vs bot — *this is Phase 1, already the current target* |
| **B** | Local test architecture: two clients on one machine, authoritative loop proven offline |
| **C** | Online 1v1 |
| **D** | 2v2 and 4-player free-for-all |
| **E** | Dedicated server |
| **F** | Matchmaking, accounts, backend |

Server-authoritative throughout: positions, cast validation, cooldowns, hits, instability,
knockback, elimination and round results all belong to the server. The client is never trusted
with a competitive outcome.

**Backend choice is deferred until Phase E**, and will be made by comparing cost, complexity,
scalability and fit for a small indie mobile game — Nakama, a lightweight custom server, and
managed services all on the table. Choosing now would be guessing.

---

## Phase 4 — Product

Nothing here is designed yet and nothing here is a Phase 1 concern. Listed only so it is clear
it was considered and deliberately postponed: more wizards, more arenas, more spells, ranked
mode, progression, cosmetics, seasons, achievements, social features.

---

## Standing constraints

These apply to every phase.

- **Mobile-first.** Landscape, touch, scalable UI, 60 FPS target on mid-range Android and
  playable at 30.
- **Everything original.** No characters, maps, names, art, sound, spell designs, UI or text
  taken from any existing game.
- **Placeholders until the game is fun.** Final art is wasted effort before then.
- **Earn complexity.** Every system has to justify itself against the current phase.

# Spellfall

A small original arena brawler: knock the other wizard off the stone and into the lava.
Hit them, they get shakier, shakier means they fly further — push them off, don't be pushed off.

Godot 4.7, mobile-first, and playable in a desktop browser with a mouse and keyboard.

## Playing

| Desk | Phone |
|---|---|
| **Right click** the ground to walk there | left thumb on the stick |
| **Q W E R** arms a spell | drag off a spell button to aim it |
| **Left click** sends it where you clicked | lift to cast |
| Right click, or the key again, puts it away | — |
| Wards (guard slot) fire on the key, no click | — |
| Arrow keys walk, if you prefer a keyboard | — |

The desk scheme is the one the Warcraft III arena map this game follows uses — a key arms, a
click says where — and which spells skip the click was read out of that map rather than chosen.

The same build serves both. It shows the thumb controls the first time a real finger touches
the screen and never from a capability flag — see ARCHITECTURE.md on why that distinction is
load-bearing.

## Spells

You carry four. **Fireball** is always one of them; the other three are chosen before the match,
one from each column — four ways to threaten, three ways to move, three ways to survive a hit.
Eleven in all. Then 1v1 or 2v2 against bots.

Spell damage is a chip, never a win condition: no spell empties a full health bar in under ten
clean hits, and a trip into the lava costs more than all ten. The game is won at the edge.

## Building and testing

There are no unit tests. Verification is an argument-gated harness inside `main.gd` —
seventeen suites, run by passing a flag after a bare `--`:

```
godot --headless --path . core/game/main.tscn --quit-after 6000 -- --spells-test
```

`--pc-test`, `--touch-test`, `--button-test`, `--twothumb-test`, `--aim-test` and `--key-test`
need a real window: injected input does not reach `_input()` under `--headless`.
`ARCHITECTURE.md` lists every flag and every trap that cost a session to find.

## Documents

- **GAME_DESIGN.md** — what the game is, what each spell does, and what is still unbalanced
- **ARCHITECTURE.md** — how it is built, and the traps
- **ROADMAP.md** — phase gates
- **TASKS.md** — what was done each session, and what is still open

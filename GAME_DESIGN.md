# Spellfall — Game Design

> Status: **Phase 1 prototype.** Movement, touch controls, all four spells, instability,
> knockback, elimination, the round loop and a bot opponent are built. Everything marked
> _(planned)_ is design intent, not built code. Keep that distinction honest — this file has
> one job, which is to stop us from misremembering what already exists.

## The pitch

Two wizards. One small floating arena. No health bars.

Every spell you land makes your opponent **less stable**, and the less stable they are, the
further your next hit throws them. You do not kill anyone by grinding their health to zero —
you destabilise them until one clean hit sends them off the edge into the void.

The player should understand the whole game in about five seconds of watching it:

> Hit them. They get shakier. Shakier means they fly further. Push them off. Don't be pushed off.

## Originality

This project takes inspiration from the *philosophy* of knockback-elimination arena games and
from the *usability* of modern mobile action games. It copies nothing. No characters, maps,
names, art, sound, spell designs, UI layouts or text come from any existing game. Every asset
and every name in this repo is original to it. That constraint is not negotiable and applies
to future art and audio too.

## Core loop

1. Both wizards spawn on opposite sides of the arena.
2. A short countdown, then the round is live.
3. Players move, aim and cast. Landing a spell adds **Instability** to the target.
4. Knockback scales with the target's instability, so hits get more dangerous over time.
5. A wizard knocked past the arena edge falls and is eliminated for that round.
6. Last wizard standing takes the round.
7. _(planned)_ The loser picks one of three upgrades — a small catch-up mechanic.
8. Next round. First to a set number of round wins takes the match.

Steps 1-6 and 8 are built. A round opens with a frozen three-second countdown, goes live,
ends when one wizard is left standing, shows the winner, and resets.

Rounds are meant to run roughly 30–60 seconds. A whole match should fit in the time someone
is waiting for a bus.

## Instability — the core mechanic

Instability replaces health. It starts at 0% and only goes up within a round.

| Instability | What it feels like |
|---|---|
| 0%   | Hits barely move you. You can hold ground near the edge. |
| 50%  | You slide noticeably. The edge starts to matter. |
| 100% | Every hit is a threat. You want to fight from the middle. |
| 150%+| One good hit ends you from almost anywhere. |

Those numbers are a **starting shape, not a balance decision**. They live in exported
variables and data resources so they can be retuned without touching logic — see
`ARCHITECTURE.md`.

Why this instead of health:

- **The tension curve is automatic.** A round gets more dangerous the longer it runs, without
  a shrinking arena or a timer forcing it.
- **Comebacks stay possible.** Being at high instability is dangerous but not lost — you are
  never "out of health", so good dodging still saves you.
- **It reads without a tutorial.** A number that goes up and makes you fly further is easier
  to grasp than armour types or damage mitigation.

Knockback is computed as a modular formula:

```
final_knockback = ability_base_knockback * instability_multiplier
instability_multiplier = base + (instability / 100) * per_100      (clamped)
```

It deliberately does **not** live inside individual spell scripts. One place to read, one
place to tune, one place a future server has to agree with — `combat/knockback/knockback.gd`.

At the shipped values the multiplier is 1x at 0%, 2x at 100% and 2.5x at 150%. Because the
distance you travel goes as speed *squared*, 50% instability carries you **2.25x** as far.
That quadratic is the whole tension curve: the number climbs gently, the consequences climb
fast. Tuning lives in `data/knockback_rules.tres`.

## Controls

Landscape only. Designed for thumbs, tested with a keyboard.

- **Left thumb — movement.** Virtual joystick with a deadzone and configurable sensitivity.
- **Right thumb — four spells.** A cluster of four buttons: the primary in the corner, three
  smaller ones fanned along the arc a thumb sweeps. **Press, drag to aim, lift to cast**, with
  an indicator on the ground showing the lane, the fan or the landing spot — built. A tap with
  no drag still casts, where you are heading, which is what tapping always did.
- **Desktop (development only).** WASD or arrow keys to move. The number row and Space cast
  instantly, where you are heading; a mouse drives the buttons through touch emulation, so
  drag-to-aim can be played with a mouse on a dev build.

The layout is our own. It follows general mobile-action conventions — movement left, actions
bottom-right, aim by dragging — because those are conventions, but no other game's specific
arrangement, iconography or styling is reproduced.

## The proportions, and where they came from

The first phone build played cramped: the wizard crossed the whole arena in two seconds and
Fireball reached everywhere from anywhere, so position meant nothing and a shot was a click.

Rather than guess at better numbers, the ones from the Warcraft III custom map this game takes
after were measured out of the map file itself. **Proportions and physics only** - no names, no
spell designs, no art, no code. What matters is the shape of the relationships:

| | The original | Spellfall before | Spellfall now |
|---|---|---|---|
| Walk speed | 210 units/s | 6.5 m/s | **4.0 m/s** |
| Arena radius | 1408 units (shrinks each round) | 7 m | **10 m** |
| **Seconds to walk across** | **~13.4** | 2.2 | **5.0** |
| Main projectile | 750 units/s, 1s | 18 m/s, 1.2s | **12 m/s, 0.45s** |
| Projectile / walk speed | 3.6x | 2.8x | **3.0x** |
| **Projectile range / arena radius** | **0.53** | 3.1 | **0.54** |

The last row is the one that was wrong. In the original a bolt reaches barely half way to the
rim, so **threatening someone means walking to them** - and walking is the whole game. Ours
out-ranged the entire board three times over, which is why standing still worked.

The arena is not the original's 13 seconds across, and deliberately so: that map's camera
follows the player, and this one shows the whole ring at once because in a knockback game the
edge is the most important thing on screen. Five seconds is what fits on one screen while
still leaving the wizard readable on a phone - it costs the wizard about 3% of screen height.

**What this changed that nobody asked for:** knockback now moves you less relative to the ring.
A clean Force Wave at 0% instability slides you 4.8m, which used to be 69% of the way to the
rim and is now 48%. The escalation still bites - the same hit at 100% instability throws you
19m - but early exchanges are survivable and rounds run longer. That is the tension curve
stretching, not breaking, and it is the first thing to re-measure after a play session.

## Cover

Two rocks and two trees stand in the arena. A spell dies against them - projectile or cone,
the same rule - and so does a wizard walking into one.

They are there to make the ring a place rather than a plate. Without them the only thing
position means is "how far from the edge am I", and every fight is the same fight: two wizards
in the open trading skillshots. With them there is somewhere to break line of sight, somewhere
to force an opponent around, and a wall to be shoved into instead of thrown off.

They are placed point-symmetrically, and the lane between the two spawns is left clear. Neither
is decoration: an arena that favours one spawn is a fight decided before it starts, and an
opening lane full of rock is a round that starts with both players walking sideways.

## Weight

Movement has a ramp: about a sixth of a second to get going, a third to stop, and a third to
reverse. It was instant before, and instant is what made the wizard feel like a cursor rather
than a body. Now a direction is a small commitment, stopping is a decision made slightly in
advance, and a slide from a hit is something you steer out of rather than something you cancel.

Fireball leaves at 15.5 m/s and arrives at 9. The shot is a punch up close and a lob at the
end of its reach, which means the answer to "am I close enough" is now visible in the flight
itself. Neither of these is a new mechanic; both are the same spells with weight added.

## What a hit feels like

Knockback is the mechanic; this is how the game says so. A hit stops the world for a few
hundredths of a second, throws a spray of sparks at the contact point, jolts the camera,
thumps, and buzzes the handset — all scaled by the same number, the knockback that actually
landed. A hit somebody shrugged off with Arcane Shield feels shrugged off, because the reading
is taken after the shield, not before.

None of it is information the player did not already have. It is the same event the HUD
percentage and the slide already reported, arriving at the moment of contact, where the eye
already is.

**Everything is placeholder and everything is cheap to change.** The sounds are synthesized
from tones rather than recorded, the sparks are untextured spheres, and the shake is a number.
That is deliberate at this phase: the feel is meant to be tuned by playing, and none of it
should cost anything to throw away.

## The four starting spells

All four are **built**. Numbers below are placeholders to be tuned in playtesting, and they
live in `data/abilities/*.tres` — one file each, no scripts.

| Spell | Type | Instability | Knockback | Role |
|---|---|---|---|---|
| **Fireball** | Aimed projectile, disappears on hit | 12 | 6 | Your main damage. Rewards prediction. 0.9s cooldown. |
| **Force Wave** | 110° cone, 4m, fires instantly | 5 | 11 | The finisher. Weak in the open, lethal near an edge. Throws away from YOU, not along the aim. 3.5s. |
| **Blink** | 5m teleport | — | — | Dodge and reposition. Clamped inside the arena, cancels the slide you are in, keeps the hitstun. 5s. |
| **Arcane Shield** | 1.2s defensive buff | — | — | 35% of a hit gets through. Measured: a hit that carries 2.35m carries 0.30m through it. 8s. |

The intended tension: Fireball builds instability from range, Force Wave converts it into a
kill but forces you to close in, Blink is both your escape and your approach, and Shield is a
read — spend it early and it is gone when the real hit lands.

Arcane Shield ships as **knockback reduction** rather than projectile-blocking. Reduction is
one number multiplied into the existing knockback formula; blocking needs projectile
ownership, hit cancellation and its own visual language. Blocking is the better long-term
version and stays on the roadmap.

## Arena

One circular floating platform, currently **7 metres in radius** — about 14 metres across, or
roughly seven wizard-lengths. It is deliberately small: you should never be more than a
second or two from a lethal edge.

There are **no walls.** Being knocked off is the entire win condition, so the boundary is
communicated visually — a bright emissive rim — rather than physically. Anything below the
platform is a fall.

## Win condition

- Fall off the arena, and you are eliminated for the round.
- Last wizard standing wins the round.
- First to `wins_needed` round wins takes the match (currently 3).
- If everyone falls in the same instant it is a draw and nobody scores.

## Modes

Phase 1 is **one player against one bot**, offline. The bot exists so the game can be tested
solo, not as a product feature.

The architecture is being built to support 1v1, 2v2 and 4-player free-for-all later, and
online play after that. None of it is built yet, and none of it will be built until the
offline combat is actually fun. See `ROADMAP.md`.

## Look and feel

Stylised, colourful, readable. Not photorealistic. Strong silhouettes, spells that are
instantly distinguishable at a glance, and an arena edge you can never mistake.

**Readability beats spectacle.** If an effect looks impressive but hides a projectile, the
effect is wrong. Prototype visuals are untextured primitives on purpose — art comes after the
game is fun.

## What Phase 1 must prove

Not a feature list. These are the questions the prototype has to answer "yes" to:

- Does moving feel immediate and precise?
- Does aiming feel good with a thumb?
- Is landing a Fireball satisfying?
- Is Force Wave near an edge exciting?
- Is knockback predictable enough to plan around?
- Does rising instability actually create tension?
- Does falling off work reliably and read clearly?
- Do rounds start and reset cleanly?
- **Is the core loop genuinely fun?**

Until those are yes, nothing about accounts, matchmaking, cosmetics or progression gets built.

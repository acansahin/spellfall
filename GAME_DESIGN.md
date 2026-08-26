# Spellfall — Game Design

> Status: **Phase 1 prototype.** Movement, touch controls, all four spells, instability,
> knockback, elimination, the round loop and a bot opponent are built. Everything marked
> _(planned)_ is design intent, not built code. Keep that distinction honest — this file has
> one job, which is to stop us from misremembering what already exists.

## The pitch

Two wizards. One stone ring in a lake of lava. No health bars in the fight.

Every spell you land makes your opponent **less stable**, and the less stable they are, the
further your next hit throws them. Most of the roster still says nothing about a health bar —
you destabilise someone until one clean hit sends them off the stone, where they burn and have
a few seconds to walk back. **Fireball is the exception**: a straight shot that drains health
outright, on top of the instability it always dealt. Two ways to lose are live at once.

The player should understand the whole game in about five seconds of watching it:

> Hit them. They get shakier. Shakier means they fly further. Push them off. Don't be pushed off.

## Originality

This project takes inspiration from the *philosophy* of knockback-elimination arena games and
from the *usability* of modern mobile action games.

**Session 16 narrowed this constraint deliberately, and it is worth reading the change rather
than the rule.** It used to say that nothing at all came from any existing game, spell designs
included. The spell roster is now taken from the Warcraft III arena map this project takes
after: its list was read straight out of the map file - see `docs` on `extract_w3x` in the
sibling tower-defense repo - and eleven spells were built from what it does, not from what a
wiki says about it. What each spell *is* comes from there.

What still does not, and is not negotiable:

- **No names.** Every spell in this repo is named here. `Fireball` is a word, not a borrowing.
- **No art, sound, models, text or UI layouts.** All of it is original and all of it is
  placeholder.
- **No numbers.** The map's cooldowns are a set of RATIOS - its main spell recharges in 4.8s
  and its lightning in 16.5s - and those ratios were mapped onto our own Fireball. Nothing was
  copied at face value onto an arena a fifth the size.
- **No code.** Nothing was decompiled and nothing was ported.

The trade is the same one the proportions section below already made and says out loud: this
game is a small original arena brawler standing on a design that fifteen years of players have
already sanded smooth, and pretending otherwise produced worse spells, not more original ones.

## Core loop

1. Both wizards spawn on opposite sides of the arena.
2. A short countdown, then the round is live.
3. Players move, aim and cast. Landing a spell adds **Instability** to the target.
4. Knockback scales with the target's instability, so hits get more dangerous over time.
5. A wizard knocked off the stone lands in the lava and starts burning. They can walk back.
   Burn all the way down and they are out of the round.
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

## The eleven spells, and the four you take

You carry **four**. Fireball is one of them, always, and the other three are chosen before the
match from three columns of three or four. Nine choices in, that is 36 loadouts, and every one
of them still opens with the same spell — which is what keeps the game teachable while the
build is yours.

All eleven are **built**. Numbers are placeholders to be tuned in playtesting, and they live in
`data/abilities/*.tres` — one file each, no scripts. The roster is
`data/spell_catalogue.tres`; adding a spell is a file and a line, never a code change.

**Spell damage is a chip, and there is a hard floor under it: no spell may empty a full health
bar in under ten clean hits.** Five spells drain health at all; the other six do nothing to it.
This is the one balance number in the game that is a rule rather than a taste, because it
decides what the game IS. Fireball shipped at five hits for a session and that was long enough
to see the problem: at five, the fastest way to win is to stand still and shoot, the ring stops
mattering, and the instability curve that is supposed to be the escalation never gets used. The
comparison that keeps it honest — **a trip into the lava empties a bar in 4.5 seconds; the
fastest spell needs 9 seconds of perfect uptime to do the same.** `--loadout-test` asserts both.

### Always with you

| Spell | Type | Inst | Knock | Role |
|---|---|---|---|---|
| **Fireball** | Aimed projectile, dies on hit | 12 | 6 | Your main threat, and the only spell that is a habit rather than a decision. Ten clean hits to empty a bar. 0.9s. |

### STRIKE — your second way to land one

| Spell | Type | Inst | Knock | Role |
|---|---|---|---|---|
| **Force Wave** | 110° cone, 4m, instant | 5 | 11 | The finisher. Weak in the open, lethal near an edge. Throws away from YOU, not along the aim. 3.5s. |
| **Arc Lance** | Flat, fast, 15m | 10 | 5 | Crosses the ring almost instantly and barely pushes. The answer to someone who will not come close. 3.1s. |
| **Seeker** | Slow projectile, turns 220°/s | 14 | 7 | Corrects an aim that was wrong, and still loses somebody who walks across its nose. 2.6s. |
| **Loopshot** | Flies out 11m, returns, pierces | 9 | 8 | Two chances at the same wizard from one cast — if you are still standing where it comes home. 3.0s. |

### MOTION — how you close a gap, or leave one

| Spell | Type | Inst | Knock | Role |
|---|---|---|---|---|
| **Blink** | 5m teleport | — | — | Dodge and reposition. Clamped inside the arena, cancels the slide you are in, keeps the hitstun. 5s. |
| **Lunge** | 6m charge that hits | 10 | 9 | The same escape, spent as an attack. It shoves what it runs through, and it puts you where they are. 5.3s. |
| **Warp Bolt** | Projectile, trades places | — | — | Hurts nobody. It takes the ground they were standing on — including the ground over the lava. 5s. |

### GUARD — what you do about the hit you saw coming

| Spell | Type | Inst | Knock | Role |
|---|---|---|---|---|
| **Arcane Shield** | 1.2s ward | — | — | 35% of a hit gets through. Measured: a hit that carries 2.35m carries 0.30m through it. 8s. |
| **Rewind** | Undo, 3.2s later | — | — | Puts you back where you cast it, with the health you had. It does NOT give back instability — the round still remembers. 7s. |
| **Momentum** | 6s, converts | — | — | Half of every hit is swallowed and paid back as walking speed, up to +2.5 m/s. The only guard that rewards standing in a fight. 6.5s. |

The intended tension is unchanged and now has three shapes instead of one: something builds
instability from range, something converts it into a kill but costs you position, something
moves you, and something is a read — spend it early and it is gone when the real hit lands.

Each spell has its own **shape** on the button, not just its own colour — a flame, a fan, a
bolt, a spiral, a boomerang, a hop, three chevrons, two swapping arrows, a shield, a clock, a
surge. All eleven are drawn in code and all eleven are placeholder, like everything else here.
Colour alone carried four spells and stopped carrying eleven.

In flight they differ too: Fireball is a ball, Arc Lance a long spike, Seeker a dart with its
point forward, Loopshot a flat bar spinning as it goes, and Warp Bolt a hoop lying flat. What a
spell HITS with is still the same sphere for all five — the shape is what it looks like, never
what it catches you with.

**The bot brings a random loadout every match.** Not for difficulty: it is the cheapest way to
make sure a spell you never chose is still a spell you have had used against you.

Arcane Shield ships as **knockback reduction** rather than projectile-blocking. Reduction is
one number multiplied into the existing knockback formula; blocking needs projectile
ownership, hit cancellation and its own visual language. Blocking is the better long-term
version and stays on the roadmap.

## Arena

One circular stone platform. It starts **12 metres in radius** — 24 across, six seconds of
walking — and **closes during the round**. Around it, lava: a flat field you can be knocked
onto, stand on, and walk back off. The stone sits 8cm proud of it, which a wizard's capsule
rides up without noticing.

## The ring closes

Twelve seconds at full size, then the stone gives way at 0.3 metres a second until it is
4.5m in radius. A round nobody wins outright is therefore over in well under a minute.

It closes **during** a round, not between rounds. The map this game takes after shrinks one
step per round, which bounds a match but leaves a single round able to run forever - and that
is the problem the lava created: now that being knocked out is survivable, nobody goes out by
accident, and two careful players can circle each other indefinitely. A ring on a clock turns
"hold your ground" into a decision with a deadline.

The twelve seconds of grace are not padding. The opening exchange should happen on the whole
board, or the squeeze arrives before there is anything to break.

**The camera comes in with it**, holding the same framing at every size. So the wizards grow
on screen as the ring tightens - from about a fifteenth of the screen's height to nearly a
fifth - which puts the most readable picture of the fight exactly where the fight is hardest.
The cover moves in too, at a fixed fraction of the radius: a ring that closed over its own
rocks would spend its second half as a bare plate.

There are **no walls.** Being pushed off is the entire point, so the boundary is communicated
by colour rather than by physics: **green grass inside, orange lava everywhere outside**, with
a cold rim and a molten shore marking the line between them. There is no black anywhere on
screen - the lava field is 60 metres across and covers everything the camera can see, because
a void reads as "off the map" and lava reads as "somewhere you can be, briefly".

## Burning, and why it is not a fall

Being knocked out of the ring used to be instant: you touched the void and the round was over.
One mistake was the whole story of a round, and there was no such thing as a comeback.

Now the outside is lava. It burns **22 points a second** out of 100, so you have four and a
half seconds out there - two or three of walking back, plus a margin for being hit again on
the way. Stone mends 10 a second, deliberately less than half the burn: a dunk should cost
something that lasts.

**Fireball is the only spell that touches it directly** - 20 points a hit, on a 100-point
total, so five landed shots end a fighter the way five seconds in the lava does. Force Wave,
Blink and Arcane Shield still say nothing to it; the fight is still mostly about instability
and position, with one straight-line threat that skips the knockback question entirely.

**Standing on stone no longer heals it.** A trip into the lava or a Fireball to the face costs
something for the rest of the round - only the next round's `reset()` gives it back. So the
number is a budget as much as a bar: how many hits and how many seconds outside can this
fighter take before the round starts asking harder questions about position.

A bar appears over a burning wizard's head and disappears again when they are whole. It is
where the eye already is while you are on fire and steering for the stone - the HUD row has
the exact number, but the corner of the screen is not where anybody is looking at that
moment. It stays hidden while nothing has burned: two permanently full bars over two wizards
would be furniture, and furniture is what the eye stops seeing, including on the one occasion
it moves.

## Win condition

- Burn all the way down in the lava, and you are eliminated for the round.
- Last wizard standing wins the round.
- First to `wins_needed` round wins takes the match (currently 3).
- If everyone goes out in the same instant it is a draw and nobody scores.

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

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

**Session 24 narrowed it again, and much further.** The rule about numbers is gone. The map's
own movement, damage, knockback, cooldowns, ranges, health and arena size are what this game
runs on now, and its roster is the roster this game is building toward. That was decided
deliberately and it is recorded here rather than quietly applied.

Why: every attempt to keep "the shape but not the numbers" produced a game that felt wrong in
ways nobody could name. The proportions section below shows the last one - three numbers moved
across at two different scales, leaving a wizard walking its ring 2.4x faster than the map's
does. There is one scale now, **1 metre = 128 Warcraft III units**, it is written down in
`docs/warlock-reference.md`, and every measurement in the game derives from it.

**The spell names are the map's too**, as of the same session. Ten of them had invented
names here - Force Wave, Arc Lance, Seeker, Loopshot, Blink, Lunge, Warp Bolt, Arcane Shield,
Rewind, Momentum - and they are now Scourge, Lightning, Homing, Boomerang, Teleport, Thrust,
Swap, Shield, Time Shift and Rush. The other eleven arrived carrying the map's names already.

**Their `id` keys did not follow, deliberately.** `Ability.id` is a stable key in code and in
save data and is never shown to a player, and four of the map's names collide head-on with
fields this code already has: `swaps_places` for Swap, `homing_turn` for Homing,
`apply_shield` for Shield, `begin_rewind` for Time Shift. Those fields are named after
BEHAVIOURS on purpose, so that whatever spell uses one can be called anything - renaming them
to match would undo exactly that. So `force_wave.tres` holds a spell called Scourge, and that
is the field doing its job rather than drift.

What still does not come from the map, and is not negotiable:

- **No art, sound, models, text or UI layouts.** All of it is original and all of it is
  placeholder. The spells are coloured shapes drawn in code.
- **No code.** Nothing was decompiled and nothing was ported. `tools/w3x.py` reads the
  archive's file format; what it prints is a table of numbers and the map's own tooltips.

The trade is the one the proportions section already made, taken to its end: this is a small
arena brawler standing on a design that fifteen years of players have already sanded smooth,
and pretending otherwise produced worse spells, not more original ones.

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

**This mechanic is the reference map's, and that was discovered rather than designed.** The
map keeps a wizard's accumulated damage in the unit's mana pool, and its hit function reads

```
dv = (100 + damage_points) * damage * push_mult * 0.03
```

which is exactly the curve below, arrived at here independently: 100 points doubles the push.
`data/knockback_rules.tres` needed no change at all when the port landed.

Knockback is computed as a modular formula:

```
final_knockback = base_impulse(damage, push_mult) * instability_multiplier
base_impulse    = damage * push_mult * 100 / 128        (128 units to the metre)
instability_multiplier = base + (instability / 100) * per_100      (clamped)
```

It deliberately does **not** live inside individual spell scripts. One place to read, one
place to tune, one place a future server has to agree with — `combat/knockback/knockback.gd`.

At the shipped values the multiplier is 1x at 0%, 2x at 100% and 2.5x at 150%. Distance under
the map's exponential drag is **linear** in the impulse, so 50% instability carries you 1.5x as
far and not the 2.25x the old linear friction gave. The escalation is gentler; the absolute
distances are much larger:

| damage points | one Fireball | carries |
|---|---|---|
| 0 | 5.47 m/s | **8.1 m** |
| 50 | 8.20 m/s | 12.2 m |
| 100 | 10.94 m/s | 16.2 m |

On an 11 m ring. So the pressure comes from EVERY exchange rather than only from late ones,
and the first clean hit of a round is already a threat. Tuning lives in
`data/knockback_rules.tres`; `--knockback-test` prints that table on every run.

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
after were measured out of the map file itself.

**Session 11 did that with three numbers and no stated scale, and that is the bug.** It moved
the walk speed across at 52.5 units per metre and laid the arena out at 140, so a wizard that
was supposed to take thirteen seconds to cross its ring took five. Every "the game feels too
fast" report since is that one inconsistency.

There is one scale now: **1 metre = 128 units**, the map's own terrain cell. It is written down
in `docs/warlock-reference.md` and everything derives from it.

| | The map | Session 11 | Now |
|---|---|---|---|
| Walk speed | 210 units/s | 4.0 m/s (at 52.5 u/m) | **1.641 m/s** (at 128) |
| Arena radius | 1408 units | 10 m (at 140 u/m) | **11.0 m** |
| **Seconds to walk across** | **13.4** | 5.0 | **13.4** |
| Main projectile | 750 units/s | 12 m/s | **5.86 m/s** |
| Projectile / walk speed | 3.6x | 3.0x | **3.6x** |
| Projectile range / arena radius | 0.53 | 0.54 | **0.53** |
| Getting going | ~0.6 s | 0.16 s | **0.6 s** |
| Stopping | coast, no brake | 0.34 s | **coast, no brake** |
| Health | 100, no regen | 100, no regen | 100, no regen |

The projectile row was already right in ratio, and that is worth noticing: Session 11 fixed the
relationship and left the absolute pace wrong, which is exactly the kind of error a ratio table
hides. In the map a bolt reaches barely half way to the rim, so **threatening someone means
walking to them** - and walking is the whole game.

**The arena is now the map's thirteen seconds across, which it deliberately was not before.**
The old argument was that this game shows the whole ring at once where the map's camera follows
the player, so a thirteen-second board would leave the wizard too small to read. That is still
true and it is the cost being paid: the wizard is a smaller figure on a bigger-feeling board.
The trade was taken on purpose, because the alternative was a fight that resolves before the
player has made a decision.

**What this changes that nobody asked for:** knockback moves you a great deal MORE relative to
the ring, because the map's drag is exponential and its impulses are large. A clean Fireball at
zero damage points carries 8.1 m on an 11 m ring - three quarters of the way to the rim, from
the very first exchange. That is the number to re-measure after a play session, and if it is
wrong the honest lever is each spell's `push_mult`, not the drag: the drag is the walk.

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

## What a wizard looks like

A hooded figure in a coloured robe, carrying a staff with a lit orb on it, and it walks: legs
that swing, a body that rises on each step, a hem that lags a beat behind, and a staff that
comes up the instant a spell leaves. It is built out of cylinders and spheres in
`characters/player/wizard_rig.gd` rather than modelled, for the same reason the sounds are
synthesised and the spell icons are vector shapes - and for one specific to it: **the wizard
is about a twelfth of the screen's height.** At sixty pixels, silhouette and motion are the
whole of what a player can see, and neither of them is bought with polygons.

Everything cloth-coloured takes the side's tint and everything skin-, wood- or metal-coloured
deliberately does not, so four wizards in four tints are still four PEOPLE rather than four
swatches.

**The staff is also the facing indicator.** A yellow bar used to stick out of the capsule's
front to say which way it was looking; the staff does that job now and does it better, being
longer, asymmetric, and the part of the figure a player is already watching.

## Weight

Movement is **momentum**, which is the reference map's own model rather than a ramp toward a
target. About six tenths of a second to reach walking speed, and **no brake at all**: let go
and you coast, halving your speed roughly once a second. A direction is a commitment, stopping
is a decision made a full second in advance, and a slide from a hit is something you steer out
of rather than something you cancel.

Three models have stood here - instant, then an asymmetric 0.16/0.34 ramp, now this. The ramp
was an attempt to buy the map's feel with different arithmetic and it got most of the way
there; what it could not reproduce is the coast, because a ramp toward zero *stops*.

Fireball flies at a **constant 5.86 m/s** now, where it used to leave at 15.5 and arrive at 9.
That deceleration was this repo's invention and the map has none - its missiles fly flat. What
answers "am I close enough" is the range itself, which reaches half way to the rim.

## What a hit feels like

Knockback is the mechanic; this is how the game says so. A hit stops the world for a few
hundredths of a second, throws a spray of sparks at the contact point, jolts the camera,
thumps, and buzzes the handset — all scaled by the same number, the knockback that actually
landed. A hit somebody shrugged off with Shield feels shrugged off, because the reading
is taken after the shield, not before.

None of it is information the player did not already have. It is the same event the HUD
percentage and the slide already reported, arriving at the moment of contact, where the eye
already is.

**Everything is placeholder and everything is cheap to change.** The sounds are synthesized
from tones rather than recorded, the sparks are untextured spheres, and the shake is a number.
That is deliberate at this phase: the feel is meant to be tuned by playing, and none of it
should cost anything to throw away.

## The twenty-two spells, and the four you take

You carry **four**. Fireball is one of them, always, and the other three are chosen before the
match from three columns. Twenty-one choices in, that is 336 loadouts, and every one of them
still opens with the same spell — which is what keeps the game teachable while the build is
yours.

The roster is the reference map's, all of it. **The map offers seven columns and you pick one
from each, carrying eight spells; this offers three columns and you carry four.** That is the
one structural departure and it is a UI limit rather than a design choice: four thumb buttons,
four keys. The twenty-one are grouped by what they DO rather than by the map's own column
letters, which is why Scourge and Cataclysm sit under GUARD - a burst centred on yourself that
hurts you too is a defensive decision, whatever else it is.

All twenty-two are **built**. Numbers are the map's own level-1 values and they live in
`data/abilities/*.tres` — one file each, no scripts. The roster is
`data/spell_catalogue.tres`; adding a spell is a file and a line, never a code change.

Eight of them needed genuinely new runtime and the rest are existing fields in new
combinations. `--roster-test` is one section per MECHANIC rather than per spell, for that
reason: a blast, a split, a stream, a bounce, a root, a drain, a pull and a tether.

### Always with you

| Spell | Type | Dmg | Push | Role |
|---|---|---|---|---|
| **Fireball** | Aimed projectile, dies on hit | 7.0 | 1.0 | Your main threat, and the only spell that is a habit rather than a decision. 5.9 m/s over 5.9 m, which is half way to the rim. Fifteen clean hits to empty a bar. 4.8s. |

### STRIKE — your second way to land one

| Spell | Type | Dmg | Push | Role |
|---|---|---|---|---|
| **Lightning** | Flat, 13.3 m/s, 12m | 7.0 | 1.2 | Crosses the ring almost instantly and shoves hard. The answer to someone who will not come close, and it costs you a sixteen-second wait. 16.5s. |
| **Homing** | Slow projectile, turns 220°/s, 9.4m | 7.0 | 1.0 | Corrects an aim that was wrong, and still loses somebody who walks across its nose. 14.0s. |
| **Boomerang** | Flies out 8.4m, returns, pierces | 7.2 | 1.2 | Two chances at the same wizard from one cast — if you are still standing where it comes home. 16.0s. |
| **Meteor** | Lands at 6.3m, 3.2m blast | 10.0 | 1.0 | The only spell that does not need to touch anybody. Falls off to nothing at the edge of its own blast, so the middle is the worst place to stand. 20.0s. |
| **Splitter** | Breaks into six at the end of its flight | 3.0 | 1.4 | Weak on its own and dangerous where it lands. The six carry the heaviest push in the roster. 30.0s. |
| **Fire Spray** | Six shots down one line, 0.16s apart | 2.6 | **0.6** | One cast, six chances, and an aim you committed to before the first one left. The map's own "60% knockback". 16.0s. |
| **Bouncer** | Finds the next enemy within 7m, three times | 6.0 | 1.0 | A single-target spell in a 1v1 and the best spell in the column in a 2v2. A fifth weaker each hop. 20.0s. |
| **Drain** | Slow projectile | 6.0 | 0.6 | Takes their health and gives it to you. The only way in the game to undo a trip into the lava. 22.0s. |

### CONTROL — where the two of you are standing

| Spell | Type | Dmg | Push | Role |
|---|---|---|---|---|
| **Teleport** | 6.0m teleport | — | — | Dodge and reposition. Clamped inside the arena, cancels the slide you are in, keeps the hitstun. 16.0s. |
| **Thrust** | 5.5m charge that hits | 5.4 | 1.15 | The same escape, spent as an attack. It shoves what it runs through, and it puts you where they are. 17.0s. |
| **Swap** | Projectile, 6.25m, trades places | — | — | Hurts nobody. It takes the ground they were standing on — including the ground over the lava. 16.0s. |
| **WindWalk** | 7.0m charge that hits | 5.4 | 1.15 | Thrust with a longer run and a much longer wait. The map's own charge form. 30.0s. |
| **Entangle** | Projectile, roots for 4.5s | — | — | Takes their legs and nothing else. Knockback still moves them and the lava still burns them, which is the whole spell: it is only lethal where they are already standing. 27.0s. |
| **Gravity** | Slow projectile dragging everything within 4.5m | 3.0 | **0.1** | Barely pushes and pulls constantly. It is the one spell that moves people without hitting them, and it moves you too. 26.0s. |
| **Link** | Projectile, then 8s of 2.5/s | 0.2 | 0.2 | A commitment you make early and forget about. Twenty points over eight seconds, from a spell that does nothing on arrival. 16.0s. |

### GUARD — what you do about the hit you saw coming

| Spell | Type | Dmg | Push | Role |
|---|---|---|---|---|
| **Shield** | 2.8s ward | — | — | 35% of a hit gets through. Measured: a hit that carries 5.05m carries 2.53m through it. 25.0s. |
| **Time Shift** | Undo, 3.6s later | — | — | Puts you back where you cast it, with the health you had. It does NOT give back damage points — the round still remembers. 22.0s. |
| **Rush** | 7s, converts | — | — | Half of every hit is swallowed and paid back as walking speed, up to +2.5 m/s — which on a 1.64 m/s walk is more than doubling it. The only guard that rewards standing in a fight. 21.0s. |
| **Scourge** | Cone, 4m, instant | 10.0 | 0.8 | The map's heaviest single hit, and the ten-hit floor in person. Weak in the open, lethal near an edge. Throws away from YOU, not along the aim. 3.0s. |
| **Cataclysm** | 5m burst around you, **you included** | 6.0 | 1.0 | Everything nearby, yourself at the centre taking the worst of it. Two-second cooldown, and the self-hit near a rim is a way to travel rather than only a cost. 2.0s. |
| **Pious** | 3.6m burst around you, **you included**, allies mended 5 | 10.0 | 0.8 | Costs a lone caster five health and pays for itself the moment somebody is standing with you. 3.0s. |

Each spell has its own **shape** on the button, not just its own colour. Twenty-two spells and
twenty-two drawings would be a lot of drawing to protect a comparison nobody makes, so the
rule is now **unique within a column** plus the primary being unique against all of them: what
you compare is a column while picking, and what you carry is Fireball plus one from each
column, so your four buttons are always four different shapes. `--loadout-test` asserts it.

In flight they differ too, under the same per-column rule: a ball, a spike, a dart, a spinning
bar, a hoop, a lump, a speck, a four-sided sliver and a cone arriving mouth-first. What a
spell HITS with is still the same sphere for all of them — the shape is what it looks like,
never what it catches you with.

## Playing at a desk

The desk controls are the ones the Warcraft III arena map this game follows uses, and they were
read out of the map rather than guessed at: `war3map.w3a` gives each spell a hotkey and a base
ability, and the base ability says whether it needs a place to go.

| | |
|---|---|
| **Right click** the ground | walk there |
| **Q W E R** | arm a spell — nothing is cast yet |
| **Left click** | send the armed spell where you clicked |
| **Right click** / the same key again | put it away |
| **arrow keys** | walk, for anyone who wants a keyboard |

**A key arms, a click sends.** Pressing Q does not throw a Fireball; it picks one up. That is
the map's own model, and it costs a mis-typed key nothing — a wrong spell is put back with the
key you already have a finger on.

**A ward needs no click.** Shield, Time Shift and Rush fire the instant you press their
key, because they are not pointed at anything. That is not a convenience anybody invented: the
map's own three wards — Shield, Time Shift, Rush — are exactly the abilities there that take no
target either, and the split falls out of a field this game already had.

**WASD is gone.** W, E and R are spells now. The map has no keyboard movement at all, and a key
cannot be both the second spell and "walk forward".

The map's own hotkeys are **G** for its main spell and **D E R T Y C F** for its seven columns —
it has eight columns to place and a whole keyboard to place them on. Four slots compress to
QWER.

## Two a side

The loadout screen offers **1v1** or **2v2**, and 2v2 gives you a bot ally against two bots. The
ring, the lava, the shrink clock and every spell are the same; what changes is that a round ends
when a SIDE is gone rather than when one wizard is, and the score is kept by side.

**Friendly fire is off, and off means your ally is not in the way at all** — spells pass
through them and reach whoever is standing behind. The alternative was tried on paper and
rejected for this phase: a bot ally will shove you into the lava by accident, and Phase 1 is
trying to answer "is the combat fun", where that is noise rather than signal. It is one field
away from being switched on when there are humans on the other end of it.

Sides are read by colour: **cool is a friend, warm is a foe.** You are blue and your ally teal;
the opposition is pink and orange. The ally was briefly cyan, which is more obviously "your
colour" and made the screenshot come back with two blue wizards and no way to tell which was
you — reading your side matters, and finding yourself matters more.

**The bot brings a random loadout every match.** Not for difficulty: it is the cheapest way to
make sure a spell you never chose is still a spell you have had used against you.

Shield ships as **knockback reduction** rather than projectile-blocking. Reduction is
one number multiplied into the existing knockback formula; blocking needs projectile
ownership, hit cancellation and its own visual language. Blocking is the better long-term
version and stays on the roadmap.

## Arena

One circular stone platform. It starts **11 metres in radius** — 22 across, thirteen and a
half seconds of walking, which is the map's own ring at 128 units to the metre — and **closes
during the round**. Around it, lava: a flat field you can be knocked
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

**The camera very nearly does not come in with it**, and that is a reversal. It used to hold
the same framing at every size, so the wizards grew on screen as the ring tightened - from
about a fifteenth of the screen's height to nearly a fifth. The argument was that this puts
the most readable picture of the fight where the fight is hardest.

Watched rather than reasoned about, it does something else: the wizard inflates while the
island shrinks under them, and two things moving in opposite directions is what makes it look
wrong. The lens travelled 41% of its own distance over one close.

It follows a **quarter** of the shrink now - about 3.5m of travel and 11% of growth over
twenty seconds, slow enough not to be seen happening. The ring closes by exactly as much as it
always did; the squeeze is entirely in the geometry, which is where a player can read it. The
cover still moves in at a fixed fraction of the radius: a ring that closed over its own rocks
would spend its second half as a bare plate.

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
total, so five landed shots end a fighter the way five seconds in the lava does. Scourge,
Teleport and Shield still say nothing to it; the fight is still mostly about instability
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
- Is Scourge near an edge exciting?
- Is knockback predictable enough to plan around?
- Does rising instability actually create tension?
- Does falling off work reliably and read clearly?
- Do rounds start and reset cleanly?
- **Is the core loop genuinely fun?**

Until those are yes, nothing about accounts, matchmaking, cosmetics or progression gets built.

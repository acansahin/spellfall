# The reference map's own numbers

Everything here was read out of **`Warlock097.w3x`** (WarlockBrawl 0.97, Zymoran &
Demestotenes) with `tools/warlock_dump.py`. Nothing here is from a wiki, from memory, or from
watching a video. **Change a number in this port only against this file or a fresh tool run.**

```
python tools/warlock_dump.py units       # the wizard
python tools/warlock_dump.py abilities   # the 22 spells, with the map's own tooltips
python tools/warlock_dump.py hits        # every damage/push call site
python tools/warlock_dump.py speeds      # every per-second constant
python tools/warlock_dump.py metres      # all of it converted at 128 units / metre
```

The map lives outside this repo, at
`C:\Users\alica\OneDrive\Desktop\Warcraft III\Maps\Download\Warlock097.w3x`
(a second copy sits in `…\Downloads\`). Every file inside it is MPQ-encrypted;
`tools/w3x.py`'s docstring says what that costs and why the sibling tower-defense repo's
reader refuses it.

---

## 1. The scale

**1 metre = 128 Warcraft III units = one terrain cell.** One number, applied to everything.

This is the correction that started the port. Session 11 moved three numbers across and used
two different scales while doing it — walk speed at 52.5 u/m and the arena at 140 u/m — so
the wizard ended up walking its ring 2.4× faster than the map's does. That is what "the game
feels too fast" was.

| | map | at 128 u/m |
|---|---|---|
| Walk speed | 210 u/s | **1.641 m/s** |
| Arena radius | 1408 u | **11.0 m** |
| Seconds to cross | 13.4 | **13.4** |
| Obstacle collision | 70 u | **0.547 m** (there are ten of them) |
| Fireball blast | 160 u | **1.25 m** |

## 2. The wizard

`war3map.w3u`, unit `h000`/`h003` "Warlock":

| | |
|---|---|
| Max HP | **100** |
| HP regeneration | **0** — nothing heals inside a round |
| Movement speed | **210** |
| Collision size | 0 (the map does its own collision) |
| Model scale | 0.92 |

Ten obstacles, `obs0`…`obs9`, collision radius **70**, scales 1.0 to 1.8.

## 3. Movement is momentum, not a ramp

The map integrates at a **0.03 s tick**. `IA = 210*.03` is top speed per tick and
`AA = IA/20` is acceleration per tick:

```jass
r = Q*vx + S*vy              # speed already along the wished direction
if r <= VE then              # VE = this fighter's top speed per tick
    Q = (Q + AA*vx*r/IA) * .98
else
    Q = Q * .98              # at top speed: drag only
```

Two things fall out of that shape and both matter more than the numbers:

- **Releasing the stick does not brake.** There is no deceleration term at all — only drag.
  You coast. `Time Shift`'s tooltip calls this "momentum" and restores it along with your
  position, which is the map telling you the slide is part of the state of the fight.
- **Acceleration is applied along the wish only while you are under top speed in that
  direction**, so a hard turn accelerates immediately while a straight run does not.

Converted to Godot's 60 Hz tick:

| | value |
|---|---|
| Top speed | **1.641 m/s** |
| Acceleration | **2.734 m/s²** (350 u/s²) |
| Drag | **×0.5100 per second** — `0.98 ^ (1/0.03)` |
| Time to top speed | **0.60 s** |
| Coast half-life | ~1.03 s |

## 4. Damage and knockback are one number

`WW(caster, victim, damage, push_mult)` is the map's hit function. `SW(...)` is the same
thing pushing along the **projectile's travel** instead of along caster→victim.

```jass
UW = ('d' + GetUnitState(F[KW], UNIT_STATE_MANA)) * GP * BH[caster] * CH[victim] * .03 * DH[victim] * TW
Q[KW] = Q[KW] + dx * UW
```

`'d'` is the character literal, **100**. `UNIT_STATE_MANA` is where the map keeps a wizard's
accumulated **damage points**. `GP` is the spell's damage; `TW` is its push multiplier;
`BH`/`CH`/`DH` are shop upgrades, all 1 in this port.

> **Δv (u/s) = (100 + damage_points) × damage × push_mult**
> **Δv (m/s) = (100 + damage_points) × damage × push_mult ÷ 128**

**The instability curve this game already shipped is exactly this curve.** 100 damage points
doubles the push; `data/knockback_rules.tres` is `base_multiplier 1.0, per_100 1.0`. That was
arrived at independently and it is the map's own formula.

**There is no separate knockback stat.** One `damage` drives HP loss, damage points and push
together. The only per-spell knob is `push_mult`.

The impulse decays under the same movement drag — there is no separate knockback friction —
so a hit carries `Δv ÷ 0.673` metres (`0.673 = -ln 0.51`):

| damage points | Fireball impulse | carries |
|---|---|---|
| 0 | 5.47 m/s | **8.12 m** |
| 50 | 8.20 m/s | 12.18 m |
| 100 | 10.94 m/s | 16.24 m |
| 150 | 13.67 m/s | 20.30 m |

On an 11 m ring. A clean hit is a long ride; that is the game.

## 5. The call sites

Straight from `warlock_dump.py hits`. `GV[PN]` is the spell's level, `VC`/`EC`/`BC`/`NC` are
shop upgrades, `SM` a damage passed in, `BQ` a distance.

| call | damage | push | reads as |
|---|---|---|---|
| `WW(PN,QN,7+.7*(GV-1),1)` | 7.0 | 1.0 | **Fireball** |
| `WW(PN,QN,1.1*(7+.7*(GV-1)),.9)` | 7.7 | 0.9 | Fireball's upgraded form |
| `WW(PN,QN,6+1*GV,1.2*G2(...))` | 7 | 1.2 | **Lightning** |
| `WW(PN,QN,6.4+.8*GV,1.2*VY)` | 7.2 | 1.2 | **Boomerang** |
| `WW(PN,QN,$A+2*GV,.8)` | 10 | 0.8 | **Scourge** |
| `WW(PN,QN,2.5+.5*GV,.65)` | 3.0 | 0.65 | **Splitter**, per missile |
| `WW(PN,QN,3,1.4)` | 3 | **1.4** | the heaviest push in the map |
| `SW(PN,QN,2.4+.2*GV,.6)` | 2.6 | **0.6** | **Fire Spray** — its tooltip says "60% knockback" |
| `SW(PN,QN,2.6+.4*GV,.65)` | 3.0 | 0.65 | Fire Spray's cluster form |
| `WW(PN,QN,VE[PN]*(5.1+.9*GV),1.15)` | scales with the caster's SPEED | 1.15 | **Thrust / WindWalk** |
| `WW(PN,QN,3,.1)` | 3 | **0.1** | **Gravity** — almost no push |
| `WW(PN,QN,LS,.2)` | — | 0.2 | **Link** |
| `WW(FC,QM,SM-BQ/60,1)` | falls off with distance | 1.0 | **Cataclysm** |
| `WW(FC,QM,SM,1-BQ/$3E8)` | — | falls off over 1000 u | **Meteor** |

Two of these are worth keeping in mind while balancing: **push and damage are not
correlated.** Gravity does 3 damage at 0.1 push; the `3, 1.4` call does the same damage at
fourteen times the push. That is the whole design space this port gets for free.

## 6. Speeds

Every `N*.03` literal in the script, i.e. every per-second speed the map uses:

| units/s | m/s | uses |
|---|---|---|
| 210 | 1.64 | the wizard |
| 250 | 1.95 | 1 |
| 280 / 300 | 2.19 / 2.34 | 1 each |
| 400 | 3.12 | 4 |
| 425 | 3.32 | 1 |
| 500 | 3.91 | 1 |
| **600** | **4.69** | **10** — the commonest projectile speed in the map |
| 700 | 5.47 | 6 |
| 741 / 750 | 5.79 / 5.86 | 1 / 3 |
| 800 | 6.25 | 3 |
| **900** | **7.03** | **9** |
| 1000 | 7.81 | 5 |
| 1200 | 9.38 | 2 |
| 1300 | 10.16 | 1 — Thrust's dash |
| 1500 | 11.72 | 1 |
| 1700 | 13.28 | 1 |

For contrast, this game's Fireball flew at **15.5 m/s** before the port — faster than
anything in the map.

## 7. The 22 spells

`war3map.w3a`. Cooldowns are level 1; the map has up to 9 levels bought from a shop, which
this port does not build. Hotkeys are the map's own: **G** for the fixed spell, then one
spell chosen from each of the seven columns **D E R T Y C F**.

| id | spell | key | cd | the map's own tooltip, trimmed |
|---|---|---|---|---|
| S000 | **Fireball** | G | 4.8 | Releases a fireball. Damage 7.0 |
| S002 | Lightning | D | 16.5 | Damages the first warlock it strikes. Damage 7 |
| S003 | Homing | D | 14.0 | A magical bolt that tracks enemy warlocks. Damage 7 |
| S004 | Boomerang | D | 16.0 | A shuriken which returns to its caster. Damage 7.2 |
| S008 | Meteor | E | 20.0 | Damage 7–14 depending on range between impact and nearby warlocks |
| S009 | Splitter | E | 30.0 | Splits into minor missiles. Damage per missile 3.0 |
| S010 | WindWalk | E | 30.0 | Invisibility and +200 movement speed; ends on collision, as a backstab. Damage 5.4, duration 3.1 |
| S011 | Teleport | R | 16.0 | Teleports to the targeted point. Range 770 |
| S012 | Thrust | R | 17.0 | Accelerates toward a point, damaging the first warlock in the way. Damage 5.4, range 700 |
| S013 | Swap | R | 16.0 | A missile that swaps you with the target on impact. Range 800 |
| S014 | Drain | T | 22.0 | Steals life and movement speed. Damage 6, duration 4 |
| S015 | Fire Spray | T | 16.0 | Multiple projectiles over time. Damage 2.6 (**60% knockback**), 6 missiles |
| S016 | Bouncer | T | 20.0 | Bounces from each target. −20% damage per hit. Damage 6, range 900 |
| S017 | Entangle | Y | 27.0 | Binds its target to its current position. Duration 4.5 |
| S018 | Gravity | Y | 26.0 | Pulls nearby missiles and warlocks. Force 12, damage 0.3 |
| S019 | Link | Y | 16.0 | Links you to a warlock, which takes damage until the link ends. Damage 0.2 |
| S005 | Shield | C | 25.0 | Reflects all incoming missiles. Duration 2.8 |
| S006 | Time Shift | C | 22.0 | After 3.6 s you return 3.6 s back: location, hitpoints and momentum. You still take 70% damage points |
| S007 | Rush | C | 21.0 | Absorbs 50% of damage and converts each point into 15 movement speed. Duration 7.0 |
| S001 | Scourge | F | 3.0 | Damages nearby warlocks by 10, including yourself |
| S020 | Cataclysm | F | 2.0 | Damages nearby warlocks including yourself, by distance; speeds you up and dispels link |
| S021 | Pious | F | 3.0 | Damages nearby by 10 including yourself; heals allies 5, −5 damage points, +60 speed for 4 s |

Three of them — **Shield, Time Shift, Rush** — take no target and fire on the key press.
Every other spell is armed by its key and sent with a left click. That split is not a
convention somebody invented: it falls out of each ability's base ability in `war3map.w3a`.

## 7b. The one number not taken at face value

**Meteor.** The map's tooltip says "Damage: 7-14 depending on range between impact location
and nearby warlocks", and 14 out of 100 health is seven clean hits to a full bar. This repo has
one balance rule that is a rule rather than a taste - **no spell may empty a bar in under ten
clean hits** - and 14 breaks it where every other spell in the map obeys it.

So Meteor ships at **10 at the centre**, falling to nothing at the edge of its 3.2m blast. The
shape of the map's spell is intact, the direction of its falloff is intact, and the number is
this port's. It is recorded here rather than in a comment because it is the only place the
port and the map disagree about a number.

## 7c. The arena's shrink - CORRECTING WHAT THIS FILE USED TO SAY

This file listed the shrink under "what is not in here" and said **the map shrinks between
rounds, not during one**. That was wrong, and it was wrong because nobody had looked rather
than because the script hid it. Here is the whole mechanism:

```jass
function WY takes nothing returns nothing        // one shrink tick
  set LG = LG - 1                                // the radius, IN TILES, minus one
  call PY(LG)                                    // repaint the arena at that radius
  if LG > 0 then
    call TimerStart(KG, NN * SquareRoot(UH), false, function WY)
  else
    call PauseTimer(KG)
  endif
```

`PY(radius)` paints ground out to `radius` and leaves everything past it as `'Idki'` - lava.
`LG` is a radius in TILES, and a Warcraft III tile is 128 units, which is **one metre on this
port's scale**. `NN` is 10. `UH` is how many wizards are still ALIVE this round; `SH` is how
many are in the game at all.

| | the map |
|---|---|
| Starting radius | `9 + SH/2` tiles - **10m** at two players, 11 at four, 13 at eight |
| Step | **one tile at a time**, discrete, not a smooth close |
| Interval | `10 * sqrt(alive)` seconds - **14.1s** at two alive, 20s at four, 28.3s at eight |
| Grace before the first step | none as such, but the first interval is a full 14.1s |
| Floor | **zero.** It closes all the way |
| Between rounds | reset to `8 + UH/2` and the timer paused |

Three things in there are worth more than the numbers:

- **It speeds up as people die.** The interval is recomputed from `UH` on every tick, so the
  last two alive in an eight-player game are on a 14.1s clock rather than a 28.3s one. The
  closing ring is the loser's punishment and the winner's reward in one number.
- **It STEPS.** A whole ring of ground turns to lava at one moment. That is a different kind
  of pressure from a rim creeping inward - you can be standing somewhere safe and be standing
  in lava a moment later without having moved.
- **It never stops.** There is no minimum radius, so a round always ends.

**This port closes 4.2x faster than the map.** Ours takes 11m down to 4.5m in 21.7 seconds of
shrinking (0.3 m/s after 12s of grace); at the map's two-player rate the same 6.5 metres takes
91.7 seconds. Whether to match that is a design decision rather than a porting one - this game
shrinks during a round for a reason of its own, recorded in GAME_DESIGN.md.

## 8. What is NOT in here

- **Lava damage per second.** The lava's damage is applied by a trigger whose constant has
  not been found. This port keeps its own 22/s until someone digs it out.
- **The shop.** Gold, items and the per-level spell scaling are the `BH`/`CH`/`DH`/`BC`/`EC`/
  `NC`/`VC` multipliers above. This port pins every one of them at 1.

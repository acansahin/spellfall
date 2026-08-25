# Spellfall — Architecture

Engine: **Godot 4.7**, GDScript, **Forward Mobile** renderer.
Read `GAME_DESIGN.md` first for what the game is. This file is how it is put together.

> Everything described as _(planned)_ does not exist yet. What is built: the arena, the
> wizard, movement, the fixed camera, the touch controls, the ability framework with one
> spell, instability, knockback, the HUD, elimination, the round loop, the bot opponent,
> all four spells, drag-to-aim with its ground indicators, the game-feel pass, cover to hide
> behind, and a lava field that burns instead of killing outright. Every Phase 1 step is built; whether the result is FUN is the open
> question, and it is a question for a human.

## Ground rules

1. **Composition over inheritance.** Behaviour goes in components a character owns, not in a
   deep class tree. A wizard is a body plus an instability component plus an ability set.
2. **Signals to decouple upward, direct calls downward.** A component may emit that something
   happened; it does not reach up and drive the UI or the round system.
3. **Data in Resources, not literals.** Every tunable number is an exported variable or a
   `Resource` file, so balancing never means editing logic.
4. **No god objects.** There is no `GameManager`. `main.gd` wires a level together and does
   nothing else; rounds, spawning and combat each own themselves.
5. **Build what is needed now.** The seams below exist because they are load-bearing for
   multiplayer or for touch input. Anything not needed yet is deliberately absent.

## Folder layout

```
res://
  core/
    game/          main.tscn + main.gd - level wiring and the scripted-run harness
    input/         InputCommand, PlayerInputController
    utilities/
  characters/
    player/        player.tscn + player.gd - one script for every fighter
    bot/           bot_controller.gd + bot_wizard.tscn - the opponent
    components/    instability_component.gd, health_component.gd; haptics later
  combat/
    abilities/     ability.gd (Resource) + ability_component.gd (runtime) + cone_cast.gd
    projectiles/   projectile.gd/.tscn + projectile_pool.gd
    knockback/     knockback.gd (the formula) + knockback_rules.gd (its tuning)
  arena/           arena.tscn, arena_camera.gd, kill_zone.gd
    obstacles/     rock.tscn, tree.tscn - cover, instanced into the arena
  ui/
    hud/           hud.gd/.tscn - instability, round number, score, banner
    mobile_controls/ touch_stick, ability_button (press-drag-lift to aim), mobile_controls
    loadout/       loadout_screen.gd/.tscn - the spell picker, built from the catalogue;
                   spell_icon.gd - a glyph as a laid-out rectangle
  systems/
    round/         round_manager.gd - countdown, elimination, score, reset
    feel/          game_feel.gd - hitstop, shake, sparks, sound and haptics, in one place
    loadout/       spell_catalogue.gd + spell_column.gd (the roster, as data) +
                   loadout_store.gd (user://loadout.cfg, by spell id)
    spawn/         (planned)
  data/            abilities/*.tres (eleven spells), spell_catalogue.tres, knockback_rules.tres
  network/         (planned) Phase C onward
  vfx/             spell_glyph.gd - the eleven icons, as vector shapes in a unit box;
                   ground_shapes.gd - flat meshes; spell_flash.gd - the fan Force Wave
                   draws; aim_indicator.gd - what a spell will do, before it does it;
                   impact_burst.gd - sparks; ground_streak.gd - the smear a Blink leaves
  audio/           sound_bank.gd - every sound, synthesized. There are no audio files
  tests/  assets/
```

Empty folders carry a `.gitkeep` so the structure survives a clone.

## Input architecture

This is the most important seam in the project, and it exists already.

```
   keyboard                  TouchStick                 network replay (planned)
   (Input actions)      (ui/mobile_controls)
       \                        |                                  /
        \                       v                                 /
         ----------->  PlayerInputController  <--------------------
                                |
                                |               BotController
                                |               (extends it, no device polling)
                                v                       |
                          InputCommand  <---------------+   <- plain data, world space
                                |
                                v
                         Player (CharacterBody3D)
                                |
                                v
                          AbilityComponent
```

- **`InputCommand`** (`core/input/input_command.gd`) is plain data: a world-space `move_dir`
  and a `has_move_input` flag. No logic, no node references.
- **`PlayerInputController`** (`core/input/player_input_controller.gd`) is the *only* script
  in the project that knows a keyboard or a touchscreen exists. It reads whichever source is
  active and fills one `InputCommand` per frame.
- **`Player`** reads `InputCommand`. It cannot tell how the command was produced - by a
  thumb, by a key, or by the bot. See "The bot" below for why that is load-bearing rather
  than decorative.

Two consequences worth stating plainly:

- The touch stick is a **UI scene with no gameplay logic**. It does not know what a Player is.
  It reports where a thumb is and `main.gd` decides that this means movement.
- `set_override_vector()` lets an automated run steer the character with no input events at
  all. That is what makes the prototype testable without a human holding a key.

### The touch stick

`ui/mobile_controls/` holds two scenes:

| Scene | Job |
|---|---|
| `touch_stick.tscn` | One thumbstick. Draws a base and a thumb, tracks **one** finger, emits `vector_changed(vector, active)`. Knows nothing else. |
| `mobile_controls.tscn` | A `CanvasLayer` that holds the stick, decides *where* it sits (margins, safe area) and *whether* it is shown. Future ability buttons become children here. |

The wiring is one line, in `main.gd`:

```gdscript
_mobile.joystick.vector_changed.connect(_input.set_touch_vector)
```

That is the whole `TouchStick -> PlayerInputController` link. The stick is connected *to* the
controller rather than holding a reference *to* it, which is the "signals decouple upward"
rule — and it means a second control feeding the same command is a new connection, not a new
code path. That prediction was tested by drag-to-aim: aiming turned out to belong on the spell
buttons rather than on a second stick, and it still cost three `connect` lines in `main.gd` and
nothing at all downstream.

**Why it is not called `VirtualJoystick`:** Godot 4.7 ships a **native `VirtualJoystick`
Control**, so that `class_name` is taken. The native one is also a poor fit here: it drives
**InputMap actions** (`action_left`, `action_right`, …) and exposes no way to read its vector.
Routing touch through actions would make it indistinguishable from the keyboard, leave
`set_touch_vector()` and `touch_deadzone` unused, and put the deadzone in a UI node — i.e. it
is built for an action-based architecture, and this project is command-based. Worth revisiting
if the command pipeline is ever abandoned; until then the collision is just a naming problem.

#### Touch ownership

This is the part that matters for a two-thumb game, and it is why the stick handles raw
`InputEventScreenTouch` in `_input()` rather than using `_gui_input`: Godot's GUI routing is
built around a single pointer, and a second finger would be swallowed by it.

The rule is one line of state — `_touch_index` — and it means:

- A press is claimed **only** if the stick is idle *and* the finger landed in its activation
  area. Everything else is left completely alone, never inspected further and never consumed.
- Drags and releases are matched **by index**. Another finger dragging or lifting anywhere on
  screen cannot move or free the stick.
- Consumed events are marked handled; unclaimed ones are not. Ability buttons on the right
  will therefore receive their touches untouched, with no coordination between them.

A hidden stick claims nothing: `Node._input()` keeps firing on invisible nodes (unlike
`Control._gui_input`), so there is an explicit `is_visible_in_tree()` guard. Without it a
desktop build would silently eat mouse-emulated touches with nothing drawn to explain why.

The stick is **fixed-position**. A floating/dynamic stick that springs to wherever the thumb
lands is a one-line change — `_centre` is already a variable rather than `size * 0.5`, and the
claim branch in `_handle_touch()` would set it to the touch point. Nothing downstream would
move. It is not done now because a fixed stick is the thing that needs proving first.

#### Deadzone

The deadzone lives in `PlayerInputController._shape_stick()`, **not** in the stick. The stick
reports honestly where the thumb is; the gameplay layer decides how much of that to ignore.
Putting it in the UI would make the drawn thumb and the gameplay value disagree.

It **rescales rather than clips**. A plain cutoff — "below the threshold return zero,
otherwise return the raw value" — means the slowest speed a player can ask for is the deadzone
itself, so the wizard snaps from stationary to 15% speed the instant the thumb clears the dead
spot. Remapping the live range back onto 0..1 removes that step. The harness asserts it: just
outside the deadzone the output is ~0.02, where a clipping deadzone would give ~0.15.

Magnitude is always clamped **circularly**, never per-axis, so a diagonal is never faster than
a cardinal. This holds for the keyboard too, and both are asserted.

#### The ability button

`ability_button.tscn` is built the same way as the stick and for the same reason: one claimed
touch index, foreign fingers ignored and never consumed. That is what lets a left thumb hold
the stick while a right thumb aims and casts, which `--twothumb-test` asserts directly.

It casts on the **lift**, not the press — and it used to be the other way round, deliberately,
because waiting for a lift adds latency in a game where a dodge is a third of a second. Aiming
bought that latency back and more: a thumb has no other way to say *where*, and a spell aimed
where you meant it beats the same spell fired 60ms sooner at wherever you happened to be
walking. A tap is still a cast; it is just a cast whose aim you did not give.

The button deliberately does **not** release when the finger slides off its disc. Dragging away
is the gesture, not a mistake, so the claimed index holds until the finger actually lifts.

It reads the spellbook, but only to draw — the spell's colour and the cooldown wedge. That is
the normal direction for UI (a view reads its model). What would be wrong is holding gameplay
state here, or writing to it. It never calls `try_cast`; it emits `pressed_slot`, the level
turns that into `request_ability()`, and touch therefore takes the identical route to the
Space key.

The cooldown wedge is verified by **measuring pixels**, not by eye: casting at t=1.0s with a
0.9s cooldown and sampling the button disc at +0.05s, +0.45s and +0.85s gives 94%, 50% and 5%
darkened.

#### Placement and screen shapes

Stretch is `canvas_items` / `expand`, so the canvas is always 720 units tall and grows *wider*
on taller-aspect phones. The stick is anchored to the **bottom-left corner** and offset in
canvas units, which puts it at the same physical spot on the glass on every device — a 16:9
and a 20:9 phone differ in how much void is visible at the sides, not in where your thumb
rests. Margins are therefore plain canvas units and **not** a fraction of viewport width,
which would drift the stick inward as the screen got wider.

Measured, not assumed — `--layout-probe` at four shapes:

| Window | Viewport | Aspect | Left gap | Bottom gap |
|---|---|---|---|---|
| 1280x720 | 1280x720 | 1.78 (16:9) | 96.0 | 76.0 |
| 1560x720 | 1560x720 | 2.17 (19.5:9) | 96.0 | 76.0 |
| 1600x720 | 1600x720 | 2.22 (20:9) | 96.0 | 76.0 |
| 960x720 | 1280x960 | 1.33 (4:3) | 96.0 | 76.0 |

Safe-area insets (notch, home indicator) are read from
`DisplayServer.get_display_safe_area()` and added to those margins, but **only on mobile** —
on desktop that call reports the whole monitor while the window is smaller, so the arithmetic
would be meaningless. That guard is the entire extent of device-specific handling, on purpose.

#### Desktop

`input_devices/pointing/emulate_touch_from_mouse=true` is set in `project.godot` so a mouse
drives the stick in a desktop dev build. There is no mouse on Android or iOS, so this cannot
affect real mobile behaviour. `MobileControls.Visibility.AUTO` shows the controls when a
touchscreen is present **or** when that emulation is on, which is why they appear on a desktop
run; a shipped desktop build would turn the emulation off and the controls would vanish.

Keyboard and touch feed the same `InputCommand`. A finger on the stick takes priority over a
held key, and the keyboard resumes the moment the finger lifts — both asserted by `--key-test`.

### Screen space vs world space

A player pushing "up" on a joystick means "away from me on screen", not "world -Z". Those
only coincide while the camera has no yaw. `PlayerInputController._screen_to_world()` rotates
the stick vector using the **active camera's basis**, once, before anyone downstream sees it.
Doing it there means rotating or tilting the camera later cannot silently invert the controls.

## Movement and why it is not a RigidBody

`Player` is a `CharacterBody3D` with hand-integrated velocity. This is deliberate and it is
the decision most likely to be second-guessed later, so:

**What this is NOT claiming.** Godot's physics is floating-point, and neither
`CharacterBody3D`, `move_and_slide()` nor the underlying solver is guaranteed to produce
bit-for-bit identical results across different CPUs, operating systems, GPU drivers or engine
builds. Nothing in this architecture may ever depend on two machines simulating the same
inputs and landing on the same float. Lockstep determinism is explicitly **not** the plan —
see the networking section below for what is.

**What it IS claiming.** Hand-integrated movement is *simple, inspectable and cheap to
re-simulate*. Knockback is the centrepiece mechanic, and the thing it needs is that one
authoritative simulation can be rewound and replayed — which is exactly what client-side
prediction and reconciliation do, many times a second. Replaying a handful of ticks of
`velocity += …; move_and_slide()` is trivial. Replaying a rigid-body solver is not: its result
depends on the whole contact graph, the island it was solved in, and the order bodies were
processed, so rewinding one body means rewinding everything it touched. That is fine for
debris and wrong for the thing the whole game is judged on.

It also means the knockback formula is *readable*. When a hit sends someone the wrong
distance, the answer is in one function, not distributed across a solver's internals.

So: gameplay runs at a **fixed 60Hz tick**
(`physics/common/physics_ticks_per_second=60`), all gameplay integration happens in
`_physics_process`, and nothing gameplay-relevant reads the rendered framerate. A fixed tick
is still wanted — it makes behaviour consistent between a 30fps phone and a 120fps one, keeps
tuning values meaningful, and lets the server and a predicting client run *the same code at
the same rate*, which keeps their results close. Close, not identical: the reconciliation step
exists precisely because they will drift.

Movement tuning lives in exports on `player.gd`:

| Export | Now | Why |
|---|---|---|
| `move_speed` | 6.5 m/s | Crosses the 14m arena in ~2.2s |
| `accel_time` | 0.0 | Instant. A brawler wants direction changes to be immediate |
| `decel_time` | 0.0 | Instant, predictable stops |
| `air_control` | 0.25 | Knocked off you feel committed, but recovery skill still exists |
| `turn_speed` | 14 rad/s | Cosmetic only - turning never gates movement |

`accel_time` and `decel_time` at 0.0 mean instant; the ramp exists so adding weight later is a
tuning change and not a rewrite.

## Camera

`arena/arena_camera.gd` is a rig that **derives** its framing. You set `pitch_degrees`,
`distance` and `fov`; it places the camera on a sphere around the arena centre and aims it
back at the middle. Re-framing for a different arena is one number, not a hand-built transform.

The current values were **solved, not eyeballed**:

| | Value | Consequence |
|---|---|---|
| arena radius | 7.0 m | - |
| `pitch_degrees` | 55 | Reads positions clearly without flattening silhouettes |
| `distance` | 22 m | Near rim reaches 77% of the screen half-height |
| `fov` | 45 | Narrow enough that the rim stays close to a circle |

At those values the 2m wizard stands **11% of the screen height** - about as small as a facing
direction can still be read on a phone. Going to a 9m arena drops that to 8.6%, which is why
the arena is small. If the arena size changes, re-solve; do not nudge.

`follow_weight` defaults to **0.0 - a genuinely fixed camera.** In a knockback game the arena
edge is the most important thing on screen, and a camera that slides around moves the edge,
making "am I about to die" harder to read. The follow lerp exists to be tried, not because it
is wanted.

### Screen shapes

Stretch is `canvas_items` / `expand`, so wider phones see more horizontally rather than getting
black bars. The 3D camera keeps vertical FOV, and the arena already fits vertically with margin
- so a wider phone gains **void at the sides, not more arena.** No screen shape sees more of
the playfield than another, which matters once this is competitive.

## Rounds and elimination

Three pieces that each refuse to know about the others:

| Piece | Knows |
|---|---|
| `KillZone` (`arena/kill_zone.gd`) | that a body left the world. Not what that means. |
| `RoundManager` (`systems/round/`) | the round loop and the score. Nothing about combat. |
| `Player.eliminate()` | how to take itself out of play. Nothing about rounds. |

`main.gd` joins them, as it joins everything else.

**Why a real `Area3D` and not the `y < fall_limit` check it replaced.** A threshold test only
runs for bodies something remembered to poll, so every new fighter had to be added to a list
by hand. The area detects anything on the players layer, including a fighter nobody has
written code for yet — which is precisely the case that a 2v2 or a free-for-all creates.

`RoundManager` never reads instability, never applies knockback and never spawns anything.
`report_fall()` is the only way in, so a future out-of-bounds rule, a self-destruct, or a
server reporting a disconnect all arrive through one door. That is the separation the brief
warns about with "do not build a giant GameManager": a round system tangled into combat cannot
be tested without playing the game.

### The loop

```
COUNTDOWN  fighters revived at spawns, input frozen, banner counts down
   |  countdown_seconds
LIVE       input returned; falls are accepted
   |  a fall leaves one fighter standing
OVER       winner scores, banner shown, input frozen again
   |  interlude_seconds
COUNTDOWN  next round, or a new match if someone reached wins_needed
```

Freezing is `Player.accepts_input`, not disabled physics: during a countdown everyone stands
still, but gravity still applies and a knockback landed on the last frame of the previous
round still resolves. Nobody hangs in mid-air.

Elimination **stops physics processing** rather than merely ignoring the body, so a fallen
fighter cannot keep accelerating into the void forever, and cannot be hit on the way down by a
spell already in flight. Its collision layer is cleared with `set_deferred`, because
elimination is reached from inside an `Area3D` callback where changing collision state
directly is not allowed.

## Knockback and instability

Two separate pieces, deliberately:

- **`InstabilityComponent`** tracks one number, raises it on hit, resets between rounds and
  emits when it changes. It does not know what knockback is and must never learn.
- **`Knockback`** (`combat/knockback/knockback.gd`) is the formula, as pure static functions.
  Abilities supply a base value and a direction; it reads the target's instability and returns
  a velocity. No spell script, no projectile and no receiving body computes its own knockback.

Keeping them apart means the HUD can show instability without touching combat, and the formula
can be rebalanced without touching either.

`KnockbackRules` is a **Resource** (`data/knockback_rules.tres`) so the game's central
mechanic is tuned by editing data, never logic. It describes the **hit**; how fast a body
slides to a stop and how long it loses control for are properties of the **fighter** and live
on `player.gd`, because a heavier character should travel less from the identical hit.

### The curve is linear on purpose

`multiplier = base + (instability / 100) * per_100`, clamped. At the shipped values that is
1x at 0%, 2x at 100%, 2.5x at 150%. Linear because a player has to be able to look at a number
and predict what the next hit does; an exponential curve makes that guesswork.

Distance goes as **speed squared**, so 50% instability (1.5x speed) carries 2.25x as far. That
quadratic is the tension curve — the numbers climb gently and the consequences climb fast.

### The legs have a ramp now

`accel_time` and `decel_time` were 0.0 - movement was assigned outright, which is instant and,
on a phone, weightless: the wizard teleports between directions and a hit you walk out of reads
as a hiccup. They are now **0.16 and 0.34**, asymmetric on purpose: getting going is nearly as
quick as it was, stopping takes twice as long, and reversing costs about a third of a second.
That third of a second is the whole of "momentum" as a player feels it.

The reference map reaches the same place by different arithmetic - it damps one velocity per
tick and adds the walk on top of whatever is left, rather than ramping toward a target. **The
exponential half of that model was deliberately not copied.** Knockback here decays linearly,
which is what gives the slide a closed form (below); exponential decay never quite stops, and
the question "how far does this hit throw someone" would stop having an answer. The ramp buys
the feel; the linear drag keeps the mathematics.

### Drag is linear on purpose too

`knockback_friction` bleeds the hit off at a constant m/s², which gives the slide a closed
form: **v² / 2f**. So "how much knockback throws someone off a 7m arena?" has an answer
instead of a playtest, and the harness can check that the measured slide is the intended one.
Exponential decay never quite stops and makes the same question unanswerable.

### Two velocity accumulators

`player.gd` keeps `_input_velocity` and `_knockback` **separate**, summing them once per tick.
This is load-bearing, not tidiness. It was written when `accel_time` was 0 and the input path
assigned `velocity.x` outright every tick, which erased any knockback folded into `velocity` on
the very next frame. The ramp softens that particular failure without removing the need for the
split: the two decay by different rules - the walk ramps toward what the thumb asks for, the
hit bleeds off at a constant m/s² - and a single accumulator cannot obey both.
Worse, reading `velocity` back after `move_and_slide()` as "what I was doing" folds the last
frame's knockback into this frame's input, and any reduced-authority path (hitstun, airborne)
then keeps a fraction of it *and* adds the knockback again — the hit compounds with itself and
one Fireball launches someone across the arena. Two accumulators, summed at the end, assigned
rather than accumulated.

Knockback **replaces** rather than stacks: two hits a frame apart should not combine into a
launch neither earned, so the harder one wins.

`_apply_gravity` checks `velocity.y <= 0.0` before pinning to the floor. Without it the
downward pin squashes the `lift` on every hit, and victims grind along the floor instead of
popping clear of the arena lip.

### Hitstun

A hit costs control for `hitstun_per_speed` seconds per m/s, during which steering authority
drops to `hitstun_control`. That is what stops a player simply walking out of every knockback.
Authority scales the **target** velocity rather than blending toward the previous one, so no
setting can leave a residue that outlives the hitstun.

### Who applies a hit

`main.gd._on_projectile_hit` is the single place. Instability is raised **first** and the
knockback reads the new value, so a landed hit is amplified by the destabilisation it just
caused and combos escalate. Reading the pre-hit value is defensible and duller.

## Abilities

A spell is a **`Resource`** (`combat/abilities/ability.gd`) holding identity, cast type,
cooldown, combat numbers and projectile numbers. `data/abilities/fireball.tres` is the first
one. Adding a spell is authoring a file; it is not writing a fifth unrelated script.

Not every field applies to every cast type — `projectile_speed` means nothing to a buff — and
unused fields simply stay at their defaults. A subclass per cast type would buy nothing until
a spell needs different **control flow** rather than different numbers.

The pipeline, and who is allowed to know what:

```
  AbilityComponent          decides a cast MAY happen (cooldown, slot valid)
        | cast_requested
        v
  main.gd                   turns the request into an effect
        | ProjectilePool.fire()
        v
  Projectile                travels, detects a hit, emits `hit`
        | projectile_hit (relayed by the pool)
        v
  main.gd                   decides what a hit MEANS  <- instability/knockback land here
```

Three deliberate splits:

- **`AbilityComponent` spawns nothing.** It cannot know where the projectile pool lives, and
  keeping it ignorant is what lets a bot or a dummy carry the same component. It is also the
  natural interception point when casting becomes server-authoritative: validate at
  `cast_requested`, and the client's own component degrades into a prediction.
- **The projectile decides nothing.** It emits `hit` and lets the combat layer apply the
  consequences. A projectile that knew about knockback would be a second place the formula
  lived, which is exactly what `GAME_DESIGN.md` forbids.
- **Cooldowns tick in `_physics_process`**, on the fixed 60Hz gameplay tick, so a 30fps phone
  and a 144fps desktop agree on how long a spell takes to come back.

`ability_component.gd` guards **both** its arrays. Checking `abilities.size()` and then
indexing `_cooldowns` crashed once, because the bounds that were tested were not the bounds
that were used; `abilities` now resizes the cooldown array through its setter, so a spellbook
assigned at runtime cannot desync the two.

### The eleven spells

All eleven are `.tres` files in `data/abilities/`. None of them has a script. What differs
between them is numbers and which **cast type** they select, and each cast type has exactly
one runtime, in `main.gd`, at the seam where a cast request becomes something in the world.

| Spell | Cast type | Runtime | The rule that makes it that spell |
|---|---|---|---|
| Fireball | `PROJECTILE` | `ProjectilePool.fire` | travels, hits the first body, expires |
| Arc Lance | `PROJECTILE` | the same | no drag and three times the speed — it is Fireball's numbers, nothing more |
| Seeker | `PROJECTILE` | the same + `Projectile._home` | turns at `homing_turn` deg/s toward the nearest fighter |
| Loopshot | `PROJECTILE` | the same + `_turn_for_home` | turns at `returns_after` of its life and flies at the caster; `pierces` lets it catch the same wizard twice |
| Warp Bolt | `PROJECTILE` | the same + `_swap_places` | `swaps_places` — the caster and the target exchange positions |
| Force Wave | `CONE` | `_cast_cone` → `ConeCast.targets` | thrown **away from the caster**, not along the aim |
| Blink | `DASH` | `_cast_dash` | landing point **clamped inside the arena** |
| Lunge | `DASH` | the same + `_dash_targets` | `dash_hits` — the corridor is swept and everyone in it goes through `_apply_hit` |
| Arcane Shield | `BUFF` | `_cast_buff` → `Player.apply_shield` | a multiplier on incoming knockback, not a block |
| Momentum | `BUFF` | the same | `speed_per_absorbed` — what the ward swallowed is paid back as walking speed |
| Rewind | `BUFF` | `_cast_buff` → `Player.begin_rewind` | position and health recorded at CAST time, restored at resolve time |

**Eleven spells need eleven SHAPES, not eleven tints.** `Ability.glyph` picks one of
`SpellGlyph`'s vector icons, drawn straight into the spell button and into each menu row.
Four spells were four tinted discs and that read; eleven are eleven tinted discs, three of them
some shade of blue, under a thumb, mid-fight. The shapes are named for what they look like
(`FLAME`, `FAN`, `BOLT`, …) rather than for the spell that uses one, so a twelfth spell reaches
for the closest fit before anybody draws a new one — and `--loadout-test` asserts that no two
spells in the roster share a shape.

Two details are worth keeping:

- **Every glyph is authored in a UNIT BOX**, -1..1 with y down, and scaled at draw time. One
  drawing therefore serves a 72px button and a 32px "always with you" row, and a resized button
  cannot leave its icon behind. Only the line width is in pixels, deliberately: a hairline
  scaled down disappears.
- **`Node3D.scale = …` keeps the rotation.** A pooled projectile relaunched as a different
  shape came back still lying at the previous shape's angle, and only for the shapes that do
  not re-aim themselves every tick — visible in about one screenshot in ten. Assign the whole
  basis when a reused node must start clean.
- **`draw_colored_polygon` triangulates without checking.** A concave outline comes out with
  chunks missing rather than with an error, which is why the flame is two convex shapes stacked
  rather than one honest fire silhouette.

**In the air, shape carries the identity too.** `Ability.bolt` picks one of five meshes built
once and shared by every projectile that ever flies with it: an `ORB` (Fireball), a `SHARD`
(Arc Lance), a `DART` (Seeker), a spinning `BLADE` (Loopshot) and a flat `RING` (Warp Bolt).
`--bolt-pose` fires all five down parallel lanes so one screenshot compares them.

Three rules hold it together:

- **The hitbox is ALWAYS a sphere of `projectile_radius`, whatever is drawn.** What a spell
  catches you with has to be the thing you learned from Fireball; a per-shape collider would
  make "did that graze me?" a different question for every spell.
- **A shape may stretch only ALONG the flight.** Its cross-section matches the sphere, so a
  drawing can never be wider than what hits — the length reads as speed, and nobody judges the
  exact extent of something crossing at 30 m/s.
- **Only the MESH is turned, never the Area3D.** Rotating the node would rotate the collider
  with it, which changes nothing today and is a subtle bug waiting for the day the collider
  stops being a sphere. `ORB` and `RING` are not aimed at all — a ball has no direction, and a
  hoop stood across the flight path is a vertical sliver from this camera's angle.

**Seven spells were added in one session and no cast type was.** Four ride on existing runtimes
with nothing but different numbers; three added a field to `Ability` and a handful of lines
where that field is read. The test for a new cast type has not changed: different CONTROL FLOW,
not different numbers — and a swap, a charge and a rewind all still fly, sweep or tick exactly
the way their neighbours do.

Four details are load-bearing:

- **A rewind restores position and health, never instability.** What the round took out of you
  stays taken, so the escalation curve survives the spell. `Ability.rewind` says so in its own
  doc comment, and `--loadout-test` asserts it rather than trusting it.

- **Force Wave pushes outward, not forward.** A wave shoves what it touches, so someone caught
  at the shoulder of the fan is thrown sideways — which near a rim is off it. That is the
  whole reason it is the finisher, and `--spells-test` asserts the direction rather than
  trusting it.
- **Blink is clamped by the LEVEL, not by the spell.** `main.gd` is the only thing that knows
  where the edge is, and it already reads the radius off the platform's collision shape. A
  spell that could drop you in the void is a spell nobody would ever press.
- **The shield is applied in `Player.apply_knockback`, not in `Knockback.velocity`.** The
  formula answers "how hard was that hit"; the shield answers "how much of it landed on *me*",
  and only the recipient knows that. Hitstun then falls out of the reduced speed for free.

**One door for every hit.** `_apply_hit()` raises instability and hands out knockback, and both
a projectile arriving and a cone catching someone go through it. A second path would be a
second place the escalation rule lived.

### The loadout

Which spells a wizard carries is decided in `main.gd` and nowhere else. Three pieces:

| Piece | Owns |
|---|---|
| `SpellCatalogue` (`data/spell_catalogue.tres`) | the roster: one fixed spell, one `SpellColumn` per remaining slot |
| `LoadoutScreen` (`ui/loadout/`) | drawing the choice and reporting `confirmed(picks)`. Decides nothing |
| `LoadoutStore` | reading and writing `user://loadout.cfg`, by spell ID |

The same three-step shape the touch controls already use: a widget reports, a rule decides, the
level performs. `_on_loadout_confirmed` is the only thing that writes an `AbilityComponent`.

Four things are deliberate:

- **The screen is BUILT from the catalogue**, not laid out in a scene. Adding a fourth option
  to a column is one line in a `.tres` — no node, no index, no label to retype.
- **Picks are stored as IDS, not indices.** Reordering a column would otherwise silently hand a
  returning player a different spell. An id the catalogue no longer holds leaves that column on
  its default rather than failing the whole loadout.
- **A harness run never sees the menu.** `_show_loadout` starts as "were there no user args at
  all", because fifteen suites open by awaiting a live round and a menu waiting on a human
  would hang every one of them. `--loadout:on` is the deliberate exception.
- **Nothing fights behind it.** `Player.accepts_input` defaults to true and the round system has
  not started yet, so the screen turns both fighters off and the HUD with them. The first
  screenshot of the menu caught the bot shooting the player through it.

`ConeCast` runs a physics query rather than walking a list of known fighters, for the same
reason `KillZone` is an `Area3D`: it finds anything on the players layer, including a fighter
nobody has written code for yet. Its query objects are `static` and reused, because building a
`SphereShape3D` per cast allocates mid-fight.

`SpellFlash` (`vfx/`) draws the fan, taking its reach and angle **from the same two fields the
hit test reads**, so the shape on screen cannot drift from the shape that hits. The fan itself
is built by `GroundShapes`, which is also what the aim indicator uses — the fan you sighted
down and the fan that went off are one mesh builder called twice, not two pieces of
trigonometry that happen to agree. It is a child
of each fighter, which is why nothing pools it: there is one per wizard, it is already where
the caster is, and a fighter's body never rotates — only its `Visual` does — so a local yaw is
a world yaw.

### Four buttons, and why the hit area is a disc

The right thumb has a cluster: the primary keeps the corner the single button used to hold, and
three smaller ones fan up and left along the arc a thumb sweeps. Angles and radius are exported;
`mobile_controls.gd` reads the buttons out of the scene and sorts them by `slot`, so adding a
fifth spell is a node and an angle.

`AbilityButton` tests a **disc**, not its bounding box. A round button with a square hit area
claims the corners of a square nobody can see, and in a cluster those invisible corners overlap
— which turns "tap Blink" into "cast whichever button happens to sit earlier in the scene
tree", with nothing on screen looking wrong. Matching the hit area to the drawing is what lets
the cluster be tight enough to reach without moving your hand. `--twothumb-test` asserts no two
buttons can share a finger, and `--button-test` asserts a tap in the gap between two of them
casts nothing at all.

### Projectile pooling

### A projectile can slow down

`Ability.projectile_drag` is the fraction of its speed a spell still has one second later; 1.0
flies flat. Fireball is 0.3 - it leaves at 15.5 m/s and arrives at the end of its range at 9.
Point blank is lethal, the far end is a lob you can walk out of, and the range is limited by
physics rather than by a lifetime cutting the spell off in mid-air.

The decay is applied as `pow(drag, delta)` rather than as a per-tick multiply, so a 30fps phone
and a 144fps desktop agree on where the spell lands.

`Ability.effective_range()` integrates it - `v0 * (drag^t - 1) / ln(drag)` - so the aim
indicator and the bot's reach check stay honest without either of them knowing the field
exists. Anything that computes `projectile_speed * lifetime` by hand is now wrong; the bot did,
and it was the second time that product went stale.

`ProjectilePool` prewarms eight projectiles and reuses them. Spawning and freeing nodes
mid-fight is the classic mobile stutter, and a four-player fight throws a lot of spells. It is
a pool, not an object-pool framework: one scene, grows if it runs dry, no eviction policy.
Generalise it when a second pooled type actually exists.

The harness asserts reuse rather than growth — six casts leave `total_count()` at eight.

### Aim

**Press a spell button, drag to aim, lift to cast.** The prediction written here before it was
built held exactly: `InputCommand.aim_dir` gained a second source and **nothing downstream
changed**, because the character already read the field rather than asking how it was produced.

Three things can fill the aim, and `PlayerInputController._publish_aim()` picks between them in
this order:

1. **A live drag.** A finger is on a spell button and has passed the deadzone.
2. **The aim latched with a released cast**, until the cast is consumed. See below.
3. **`move_dir`.** You cast where you are heading — which is all a tap has ever done.

The deadzone (`aim_deadzone`, 28 canvas units) lives in the controller, not in the button, for
the same reason the stick's does. The drag is measured from **where the finger landed**, not
from the button's centre: a thumb lands wherever it lands, and measuring from the centre folds
that landing error into every shot.

#### The aim is latched WITH the cast

This is the part that needed care. The finger lifts during an input flush; the character
consumes the cast on the next physics tick; `_process` runs at render rate in between and would
overwrite `aim_dir` with wherever the player is walking. The spell then leaves in a direction
nobody chose — rarely, and only when the two clocks line up, which on a desktop is roughly
never and on a loaded phone is often.

So `end_aim()` stores the direction **in world space** alongside the latched slot, and
`consume_ability()` releases both together. `player.gd` also reads the aim *before* consuming
the slot rather than after, so the correctness does not depend on the order the controller
happens to clear things in. `--aim-test` asserts it directly: aim forward, walk right, lift,
and check which one the spell believed.

#### The indicators

`vfx/aim_indicator.gd` is a child of every fighter and is shown for the human only. Each cast
type draws its own shape, built by `GroundShapes` from the ability's own numbers:

| Cast type | Drawn | Reach |
|---|---|---|
| `PROJECTILE` | a lane, starting at `spawn_offset` | `speed x lifetime`, **trimmed at the rim** |
| `CONE` | the fan, at the spell's own half-angle | `area`, never trimmed |
| `DASH` | a line to a ring on the landing spot | the **clamped** landing distance |
| `BUFF` | a ring around the caster | none — it has no direction to give |

Two of those are decisions rather than drawings:

- **The lane stops at the arena rim.** Fireball flies 21.6m and the arena is 14m across, so an
  honest lane is a stripe over a void where there is nothing left to hit.
- **The fan is NOT trimmed**, because a wave cast at the edge really does catch someone hanging
  over it. Shortening it would be a lie about who gets hit.
- **The dash line ends where the dash ends.** `main.gd._blink_landing()` answers that question
  once and both the preview and the cast ask it, so the line cannot promise a landing spot the
  spell then refuses. `--aim-test` measures the drawn length and the travelled distance and
  requires them equal.

The level drives the indicator every rendered frame, rather than on a signal, because the thing
being previewed moves: you walk while you aim. It is driven by `main.gd` and not by the fighter
for the same reason Blink is clamped there — the arena's size is the level's knowledge.

### Casting is latched, not sampled

Four slots, four actions (`cast_1` to `cast_4`, with Space still on the first), polled in one
loop rather than as four special cases. `ability_pressed` is held by `PlayerInputController`
until someone calls `consume_ability()`.
Input is read in `_process` (render rate) and acted on in `_physics_process` (fixed 60Hz), so
a press read as "just happened" can be missed entirely when two render frames land between
ticks, or acted on twice when two ticks land between frames. Latching makes a tap exactly one
cast. Every touch button and every cast key goes through `request_ability()`, which is what
stops the two drifting apart - and it is why going from one spell to four needed no new
plumbing at all.

## The bot

`characters/bot/bot_controller.gd` **extends `PlayerInputController`** and fills the same
`InputCommand` a thumb fills. The fighter it drives cannot tell the difference: same
`move_dir`, same `aim_dir`, same latched cast, consumed on the same tick.

```
   keyboard / TouchStick                    BotController
            |                                     |  extends it, and overrides _process
            v                                     |  to nothing, so no key and no finger
   PlayerInputController                          |  can ever reach it
            |                                     |
            +------------>  InputCommand  <-------+
                                  |
                            Player (a fighter)
```

That is not tidiness. A bot that called `try_cast()` and wrote `velocity` directly could do
things no player can, and every bug found while fighting it would live in a code path the real
game never runs. Everything it does is a *request* that `Player` and `AbilityComponent` are
free to refuse, exactly as they refuse the human's.

**It thinks in `_physics_process`**, not in `_process` like the human's controller. Its
reaction time is a gameplay number: it must not sharpen on a 144Hz desktop and dull on a
30fps phone.

### What it does

| Job | Rule |
|---|---|
| Hold a range | closes outside `preferred_range + range_slack`, backs off inside `preferred_range - range_slack`, circles in between |
| Aim | at where the target is *going* — led by the projectile's flight time |
| Shoot | once the spell is ready and it has dawdled for `cast_gap` |
| Choose a spell | get back on the arena (Blink), shove off whoever is in its face (Force Wave), brace if it is nearly gone (Shield), otherwise Fireball |
| Stay on the arena | never *asks* to move outward past `arena_radius - edge_margin`, and the further past that line it is, the more of its steering goes to getting back |

Being thrown off is the game; walking off is a bug. Knockback still removes it exactly as it
removes the player.

It finds its spells **by cast type, not by slot index**, so a wizard with a different loadout -
or with only two spells - is playable by the same bot with nothing changed here. Blink is the
one cast it does not aim at you: it is the escape, so it is aimed at the middle of the arena,
and because facing follows aim the wizard visibly runs for safety rather than moonwalking.

The arena radius is **read off the platform's own `CylinderShape3D`** by `main.gd` and handed
over, like every other dependency here. A number typed into the bot would go stale the first
time the arena was resized — silently, and only for the bot.

### Difficulty is four numbers, and not one of them is a stat bonus

`BotController.PROFILES` is one table with three rows. A `SHARP` bot moves at the same speed,
casts the same Fireball and takes the same knockback as a `CALM` one and as the player. It is
better because it **notices sooner** (`reaction`), **aims truer** (`aim_error`), **shoots more
often** (`cast_gap`), **leads its target** (`lead`) and **keeps further from the rim**
(`edge_margin`). A bot that cheated on speed or on damage would be teaching the player about a
game nobody else is playing; `--bot-test` asserts that it does not.

`reaction` is a real handicap and not a cosmetic delay: every decision is computed from a
*remembered* target position refreshed on that clock, so a slow bot genuinely mis-tracks a
moving player. The aim error is re-rolled on the same clock, because an error re-rolled every
frame twitches the wizard's head and averages out to a perfect shot over the flight of a
projectile — noisy rather than wrong.

### Aim now wins over travel for facing

`Player` used to turn to face wherever it was moving. It now faces its `aim_dir` when it has
one, and falls back to travel when it does not. Nothing changed for the human, whose aim still
mirrors their movement — but a bot that circles left while shooting at you has to *look* like
it is shooting at you, or the strafe reads as a retreat and the spell that follows reads as a
cheat. Drag-to-aim inherits the behaviour for free when it lands.

### The training dummy is gone

`characters/dummy/` held a driverless fighter that existed so a spell had something to hit. The
bot is that, and it plays back. The four suites written against a target that stands still
(`--cast-test`, `--twothumb-test`, `--knockback-test`, `--round-test`) now park it with
`_freeze_bot()` instead of dodging the question: an opponent that moves would break all four
for entirely correct reasons, which is the most expensive kind of test failure.

## Networking _(planned, Phase C+)_

Server-authoritative when it arrives. The server owns positions, cast validation, cooldowns,
hits, instability, knockback, elimination and round results. The client is never trusted with
a competitive outcome.

The intended model, in order:

```
client input  ->  local prediction (where it helps)  ->  authoritative server simulation
                                                                     |
              client reconciliation / interpolation  <-  server snapshots
```

The client sends *input*, not results. It may predict its own movement immediately so the
stick feels instant, but the server's simulation is the truth; when a snapshot disagrees, the
client corrects to it and replays any inputs the server had not yet processed. Other players
are interpolated between snapshots rather than predicted.

**This design assumes divergence and corrects it.** It does not assume the client and server
compute identical floats, because with Godot's physics across mixed hardware they will not.
Anything that would require lockstep determinism — running the whole match in parallel on
every client and trusting the results to agree — is off the table.

Nothing networked is being built now. What is being built now that makes it possible later:

- A **fixed 60Hz gameplay tick**, so prediction and the server advance in the same units.
- Movement that is cheap to **re-simulate**, which is what reconciliation replays.
- Input funnelled through one replaceable `InputCommand` producer — the seam a network
  input stream will substitute into, exactly like the joystick and the keyboard do today.
- Knockback as one pure formula rather than scattered per-spell code, so client and server
  run the same rule.
- No gameplay state living in UI scripts.

That is the whole down-payment. Anything more would be speculative.

## Performance

Targets 60 FPS on mid-range Android, playable at 30. Current budget choices: Forward Mobile
renderer, one directional light, no realtime GI, MSAA 2x, soft-shadow filtering off, flat
colour background with colour-source ambient instead of a sky, and primitive meshes.

`import_etc2_astc=true` is set in `project.godot` **before any texture exists**, because the
Android export aborts with a configuration error without it. This is a known cost - it is set
now so it cannot be discovered later.

Performance gets **profiled, not guessed**, once there is enough on screen to profile.

## The camera stops before the ring does

`Arena.min_radius` (4.5m) and `CAMERA_FLOOR_RADIUS` (6.5m) in `main.gd` are different numbers
on purpose. The ring keeps closing past the camera's floor, so the last stretch of the squeeze
is felt as the RING tightening around two wizards who stay a readable size, rather than as the
lens lunging at them - `_on_arena_resized()` clamps what it hands the camera:
`distance = max(radius, CAMERA_FLOOR_RADIUS) * CAMERA_FRAMING`.

## The ring, and who owns its size

`arena/arena.gd` owns the radius. It used to be a number typed into a collision shape and read
once at startup; it moves now, so five readers ask instead of copying: Blink clamps against
it, the bot keeps clear of it, the aim lane stops at it, the lava burns whoever is outside it,
and the camera frames it. It arrives by `radius_changed` rather than being fetched, because a
stale copy would put the bot's idea of the edge, the lava's idea of it and the drawn rim in
three different places.

`_apply()` moves the platform mesh and its collision shape, the rim, the molten shore and the
obstacles - the last at a fixed FRACTION of the radius, so cover shrinks with the ring instead
of being swallowed by it. Every mesh and shape it writes to is `duplicate()`d in `_ready()`,
the same precaution `projectile.gd` takes and for the same reason: sub-resources are shared
between instances of a scene, and geometry that is rewritten every frame must not be.

`Arena.shrinking = false` is the fourth thing a measuring suite parks, after the bot, the game
feel and the cover. Several suites run longer than the grace period and every one of them
picks its distances by hand, so without it the ground moves under the measurement - and the
failure looks like a broken spell rather than a moving arena.

## The lava

The arena is a stone disc inside a 60m field of lava, both solid, the stone standing 8cm
proud. Being knocked out of the ring is no longer a fall and no longer instant: out there a
fighter burns, and burning is a countdown they can walk out of.

`HealthComponent` counts it. It shipped under the rule that no spell may ever touch it, to
keep the fight entirely in instability and knockback - that rule is gone. `Ability.health_damage`
lets a spell drain it directly, `_apply_hit()` applies it alongside instability rather than
instead of it, and Fireball is the one spell that carries a non-zero value (20, against a
100-point total). The lava still burns it; **stone no longer mends it** - `reset()` between
rounds is the only way back to full, which is what turns the number into a budget rather than
a bar that tops up between exchanges.

Who is burning is decided by `main.gd._tick_lava()` with a **radius test**, not an `Area3D`.
The arena is a circle and every other rule in the file already knows it - Blink clamps against
it, the bot keeps clear of it, the aim lane stops at it - so a fifth way of asking "am I inside
the ring" would be a fifth thing to keep in step.

Burning to nothing goes through `RoundManager.report_out()`, the same single door a fall used
to. That method was called `report_fall` while falling was the only way to lose; the lava made
the name a lie, and the doc comment on it had already promised the door would take other
causes.

**The climb back is load-bearing and is asserted.** A `CharacterBody3D` does not step up
walls; what gets a wizard over the 8cm lip is the capsule's lower sphere meeting it at about
33 degrees off vertical, inside the 45 the body counts as floor. That is a chain of three
assumptions about someone else's physics engine, and the difference between a second chance
and a wizard stuck against a kerb until it burns to death. `--lava-test` walks the trip.

`vfx/health_bar.gd` draws the same number over the fighter's head - two billboarded quads, no
textures, hidden whenever nothing has burned. The fighter wires its own bar to its own
component in `_ready()`: that is internal wiring rather than the class reaching upward, and it
means a third fighter gets a working bar by existing. It is a child of the BODY and not of
`Visual`, which spins to face the aim and would turn the bar edge-on every time the wizard
looked sideways.

`KillZone` still sits under the world and still reports through the same door. Nothing reaches
it any more unless a hit clears 60 metres, which is why it is now a backstop rather than the
rule.

## Cover

Four obstacles stand in the arena - two rocks and two trees - and they do three things.

**They stop spells.** They sit on the `world` physics layer, and `Projectile`'s mask includes
it, so a Fireball dies against a rock. The level's `_apply_hit` then finds the body is not a
`Player` and does nothing, which is exactly what hitting a rock should mean. `ConeCast` casts
a sight line against the same layer for the same reason: **cover has to mean one thing**, and
a rock that stops a Fireball but not a Force Wave teaches a rule and then breaks it.

The sight line runs between two fighters' ORIGINS, which sit at chest height on a 2m capsule -
so an obstacle has to be about that tall to be cover, and both of these are. It is cast against
`world` only, so a second fighter is never cover: a wave catches everyone in its fan.

**They stop walking**, for free - a fighter's mask already includes `world`.

**They are placed point-symmetrically.** Turn the arena 180 degrees and it is the same arena,
which is the only arrangement under which two fighters starting opposite each other face the
same problem. The lane between the two spawns is deliberately clear, so the opening exchange of
a round is never a wall. `--cover-test` asserts all of it, symmetry included: an arena that
quietly favours one spawn is a fairness bug that reads as "the bot is good today".

Adding another obstacle is instancing `rock.tscn` or `tree.tscn` under `Arena/Obstacles` and
giving it a transform - **and its mirror**, or the suite fails.

Every OTHER suite calls `_clear_cover()` first. Third in the family after `_freeze_bot()` and
`GameFeel.enabled = false`, for the same reason each time: those suites were written against an
empty arena and pick the spot they measure from by hand.

## Game feel

`systems/feel/game_feel.gd` is one node holding hitstop, camera shake, sparks, sound and
haptics. One node because these are **one decision**: "that hit was heavy" has to mean the
same thing to the camera, the speaker, the phone's motor and the frame clock, and five
systems each reading `knockback` separately is five places to disagree about what heavy is.
They are handed a single strength and scale off it.

It is not a manager. It owns no gameplay state, decides nothing about the fight, and nothing
reads back out of it. Every call is one-way, and every one can be skipped with no consequence
beyond a duller game — which is exactly what `enabled = false` does.

It hangs off the doors that already existed. `_apply_hit()` was already the single place a hit
means something; the feel call sits next to the `print` that was already there. The same is
true of casts, dashes, eliminations and the countdown: the feel layer is the game's own log
made audible.

| Channel | What it does | Scaled by |
|---|---|---|
| Hitstop | `Engine.time_scale` to 0.12 for 35-85ms | knockback speed |
| Shake | camera offset in its own screen plane, decaying | knockback speed, halved for a hit on the opponent |
| Sparks | a pooled `CPUParticles3D` burst at the contact point | knockback speed sets how far they fly, never how many |
| Sound | one name into `SoundBank` | a light hit and a heavy one are different samples |
| Haptics | `Input.vibrate_handheld`, mobile only | light or heavy |

Three decisions worth keeping:

- **Hitstop is not a freeze.** 0.12 speed, not 0. A full stop reads as a dropped frame, which
  on a phone is a complaint rather than a compliment. It is also SHORT, and the numbers to pull
  down first if the game ever feels sticky: for as long as it lasts, the player's thumb does
  less than it should, and this is a game about dodging.
- **The strength a hit FEELS is the one that landed**, read back off the fighter after
  `apply_knockback` rather than the impulse that was thrown at them. A shield takes 65% of a
  hit, and a shrugged-off hit has to feel shrugged off.
- **Sparks scale their spread, not their count.** The count is what the eye uses to decide
  "did something happen" and should be the same every time; how far they fly is what says how
  hard it was.

`enabled = false` is not a debug leftover. Eight suites measure distances and durations, and
hitstop moves both — a slide measured over a fixed number of ticks comes out short, a cooldown
read after a fixed wait comes out long. They park the feel in their setup exactly as they park
the bot, and `--feel-test` is where it gets to run.

### Sound is synthesized, and there are no audio files

`audio/sound_bank.gd` builds ten sounds at startup out of swept sines, filtered noise and an
exponential envelope. That is what "placeholders until the game is fun" means for audio: a
recorded thump commits to a feel before anyone knows what the hit should feel like, costs a
licence or a session to replace, and lands in the repo as a binary nobody can diff. A tone with
an envelope is four numbers, and every one of them is a one-line edit.

The vocabulary is deliberately small — a sweep DOWN is weight (a thump, a fall), a sweep UP is
effort (a cast, a countdown going somewhere), and noise is the crack on top that says two
things touched. Real audio is Phase 4 work and will replace `play()` calls, not anything that
reads this file.

## Testing without a human

Godot cannot be driven by injected input from an automated session, so `main.gd` carries an
argument-gated harness. Everything after a bare `--` reaches `OS.get_cmdline_user_args()`:

```bash
"C:\Program Files\Godot\Godot.exe.exe" --path . res://core/game/main.tscn --resolution 1280x720 --quit-after 220 -- --shot:1 --move=0.85,0.5 --trace
```

| Flag | Does |
|---|---|
| `--move=X,Y` | Steers the player with a constant stick vector, no input events |
| `--trace` | Prints position and velocity once a second |
| `--shot` / `--shot:N` | Saves a drawn frame to `user://shot.png` / `shot_N.png` |
| `--touch-ui:on\|off` | Forces the mobile controls visible or hidden, whatever the device |
| `--touch-test` | Injects a scripted multi-touch sequence and asserts 18 properties |
| `--key-test` | Injects key presses and asserts the keyboard path still drives movement |
| `--layout-probe` | Prints where the stick actually landed, for anchor checks |
| `--stick-hold=X,Y` | Holds the stick deflected so a screenshot shows a live thumb |
| `--cast-test` | Asserts the cast round-trip: cooldown, pooling, flight, impact |
| `--twothumb-test` | Holds the stick and the cast button at once, on separate fingers |
| `--cast-at:N[,S]` | Casts spell S (default 0) N seconds in, so a delayed shot catches it |
| `--knockback-test` | Asserts the instability curve and the distance a hit carries |
| `--round-test` | Asserts a full round cycle: countdown, elimination, score, reset |
| `--bot-test` | Asserts the bot: range, aim, facing, edge safety, difficulty, and that it does not cheat |
| `--bot:off` | Parks the bot, for a screenshot or a suite that measures something else |
| `--bot-skill:S` | `calm`, `steady` or `sharp`, to play a different difficulty |
| `--spells-test` | Asserts Force Wave, Blink and Arcane Shield do what they claim |
| `--button-test` | Asserts a finger on button N casts spell N and nothing else |
| `--aim-test` | Asserts drag-to-aim: the indicator, the direction, the latch, and the dash clamp |
| `--aim-hold:S,X,Y` | Holds a drag on button S toward X,Y and never lifts, so a shot catches the indicator |
| `--feel-test` | Asserts hitstop, shake, sparks, sound, the dash streak, and that the feel can be switched off |
| `--feel:off` | Parks the game feel, for a suite that measures a distance or a duration |
| `--cover-test` | Asserts cover stops spells and walking, and that the layout is fair to both spawns |
| `--lava-test` | Asserts the lava burns, stone only stops it, a Fireball drains health directly, a dunk is survivable, you can climb back, and burning out ends the round |
| `--shrink-test` | Asserts the ring holds through the grace, closes at its rate, stops at the floor, and drags the lava rule, the bot, the camera and the cover with it |
| `--burn-pose` | Parks the player in the lava, so a delayed shot catches the burn bar part-way down |
| `--bolt-pose` | Fires every projectile spell down parallel lanes, over and over, so one delayed shot compares all five flight shapes from the same angle |
| `--loadout-test` | Asserts the catalogue, the picks, the screen end to end, and each added spell's own rule |
| `--loadout:on` | Opens the spell-picking screen even though other harness args were given, for a screenshot of it |
| `--loadout:off` | Skips it. This is the default whenever ANY user arg is passed |
| `--loadout:a,b,c` | Arms the player with these spell ids |
| `--wipe-loadout` | Forgets the stored picks, so the next plain launch opens the menu with nothing chosen |

**Any user argument at all puts the run on the DEFAULT loadout.** The stored one belongs to the
player. A suite that inherited whatever the last play session picked would measure a different
wizard every day — and it did, once: `--aim-test` went looking for a cone slot, found a stored
loadout that had none, and crashed on a null.

**None of these may be run with `--headless`.** `--shot` needs real rendering, and the input
tests need a real window: the headless display driver does not route injected
`InputEventScreenTouch`/`InputEventKey` to `_input()`, and it ignores `--resolution` too — so
every assertion silently reads zero and the run reports failures that say nothing about the
code. That was observed, not assumed: the same `--touch-test` reports 11 failures headless and
18 passes windowed.

This is not optional tooling. The facing-direction bug below was invisible to `--trace` and
obvious in one frame, and touch ownership cannot be checked by hand at all.

## Traps already hit

Each of these cost real time in the first session.

- **Writing project files from Python without `encoding="utf-8"`.** On Turkish Windows,
  `pathlib.write_text()` uses cp1254, so an em-dash becomes byte `0x97` and Godot refuses to
  load the script - reporting it as a *type error in a different file*. Always pass the
  encoding, or write through the shell.
- **`Transform3D` in `.tscn` is read row-major, but GDScript's `basis[i]` returns columns.**
  Assembling a literal from `basis[0][0], basis[0][1], ...` stores the **transpose**, which for
  a rotation is its inverse. The key light ended up shining upward and the arena went flat.
  Use `var_to_str(node.transform)` - it emits exactly what the parser reads back.
- **Godot 4.7 ships a native `VirtualJoystick` Control**, so that `class_name` is taken and
  a script claiming it fails to load with "hides a native class" — which surfaces as a
  *parse error in whatever file referenced it*, not in the file at fault. Ours is
  `TouchStick`. Check `ClassDB.class_exists()` before claiming a generic `class_name`.
- **Injected input needs a real window.** `Input.parse_input_event()` with touch or key
  events does nothing useful under `--headless`, and `--resolution` is ignored there as well
  (the viewport came back 1280x1280). An input test that "fails" headless is telling you
  about the display driver, not the code.
- **`Area3D.monitorable = false` silently disables body detection.** Its documented job is
  "other monitoring areas can detect this area", which reads as free to switch off for a
  projectile nothing else looks for. In Godot 4.7 it also kills `body_entered` and
  `get_overlapping_bodies()` on that area — with `monitoring` still reporting `true`, layers
  correct, shape correct. A manual `intersect_shape()` using the node's own shape, transform
  and mask found the target while the area saw nothing. Isolated with two identical areas
  flown through the same body; only the `monitorable` one detected it.
- **Injected input is buffered.** `Input.parse_input_event()` alone leaves the event queued
  for an unpredictable number of frames, so a scripted test passes or fails depending on how
  many frames it happened to wait — and sends you hunting for a bug in the code under test.
  Call `Input.flush_buffered_events()` straight after. The harness's `_dispatch()` does.
- **Check `substr()` offsets against the prefix length.** `"--cast-at:"` is ten characters;
  `substr(9)` yields `":1.0"`, which `float()` parses as **0.0** without complaint. The spell
  fired at t=0 instead of t=1, every screenshot caught an expired cooldown, and two correct
  drawing implementations were rewritten chasing a bug that was in the argument parser.
- **GDScript lambdas capture local variables BY VALUE.** A closure doing `found = true`
  writes to its own copy, and the outer local stays false forever — with no warning. Arrays
  and other reference types work, which makes the failure look inconsistent rather than
  systematic. Use an Array, or a member variable.
- **A test that freezes must wait for the game to un-freeze.** Once the round loop landed,
  every suite that casts or steers had to `await _wait_for_live()` first; without it they
  measure a fighter that was correctly told to stand still, which looks exactly like a broken
  control.
- **A test that measures gameplay must wait on the gameplay clock.** `_settle()` straddles
  render frames on purpose, because injected input is read in `_process`. On a machine whose
  renderer is slower than its 60Hz physics, a dozen physics ticks can turn over inside one
  `_settle()` - and `--cast-test` then reported four failures that were all about the frame
  rate: the spell had crossed the arena and the cooldown had visibly drained before anything
  was read. Measured here at fraction 0.70 where the assertion wanted 0.85, reproducing on the
  commit before the bot existed. Wait on `physics_frame` for anything that is gameplay state.
- **A windowed screenshot run can be driven by the mouse sitting on top of it.**
  `emulate_touch_from_mouse` is on and `MobileControls.AUTO` shows the controls because of
  it, so a pointer resting where the spell buttons are drawn presses them - and the run casts
  spells and walks the wizard around with nothing in the harness asking it to. It reads as a
  bug in whatever was just changed. Pass `--touch-ui:off` for any screenshot that is not
  ABOUT the controls; hidden controls claim nothing.
- **A property assigned in `_ready()` silently overrides the `.tscn`.** `Projectile` sets its
  own `collision_layer` and `collision_mask` in code, so editing the mask in
  `projectile.tscn` - where it is also written, and where you would naturally look - changed
  nothing at all. The file said 3, the flying projectile said 2, and cover did not work. When
  a value lives in both places, the script wins; move it there or delete one of the two.
- **`display/window/handheld/orientation` is an enum, and 1 is PORTRAIT.** It sat at 1 for
  four sessions under a comment reading "Landscape, mobile-first". The setting only applies to
  a handheld, so every desktop run looked correct and the first phone build was the first time
  anybody could see it. 4 is `SCREEN_SENSOR_LANDSCAPE`, which Godot writes into the manifest as
  `userLandscape`. Check the built APK, not the project file: `aapt2 dump xmltree <apk> --file
  AndroidManifest.xml | grep screenOrientation`.
- **`respawn_at()` resets what your suite is measuring.** The other suites pin a fighter by
  calling it every tick, which is what a round start does - it clears instability AND health.
  `--lava-test` copied the trick and measured the lava burning 0.4 points in a second against
  an advertised 22. Pin by writing `global_position` when the thing under test is state that
  a respawn clears.
- **Adding a parameter to a signal silently breaks every lambda already listening.** The
  projectile's `hit` grew a `shooter` argument, and two harness listeners written as
  `func(b, _d, _a)` stopped receiving anything at all. Godot refuses the call at emit time, so
  what you see is not an arity error - it is a suite reporting `hits=0`, a projectile that
  "never arrived", and a caster that "was not hit by its own spell". `grep` for every
  `.connect(` on a signal before changing its shape; the compiler will not.
- **A signal connected after the event is a race, not a listener.** `--cast-test` connected
  its hit listener four physics ticks after firing, which was fine while the spell was slow
  and became a phantom failure - "the projectile never arrived" - the moment it left at
  15.5 m/s and arrived inside those four ticks. Connect before the thing you are watching for.
- **A suite must derive its distances from the numbers under test, not from the scene.**
  `--cast-test` and `--knockback-test` fired at whatever gap the SPAWNS happened to put
  between the fighters, and Fireball happened to out-range it. Retuning the spell and growing
  the arena broke both, and they reported a broken projectile rather than a stale test. They
  now place the fighters at a fraction of the spell's own `effective_range()`.
- **Two numbers that must agree will drift.** The bot preferred to stand at 5.5m and refused
  to shoot past 4.86m, so after the retune it held a distance from which it would not fire and
  stood there for a whole round doing nothing. `holding_range()` now derives from
  `cast_reach()` - and has to subtract the slack too, because the bot stops closing as soon as
  it is anywhere inside its comfort band.
- **A timer must not be counted down with the clock it slowed.** Hitstop scales
  `Engine.time_scale`, and `_process`'s delta is scaled with it — so counting the hitstop
  down in delta stretches it by exactly the factor applied, and a 35ms stop lasts 290ms. It
  looks like a design problem ("hitstop feels awful"), not like a bug. Deadlines for anything
  that changes time scale go through `Time.get_ticks_msec()`.
- **Particles cast shadows by default.** A dozen sparks over a dark arena drew a dozen tiny
  BLACK specks around every hit, which reads as the impact smudging the floor rather than as
  light coming off it. `cast_shadow = SHADOW_CASTING_SETTING_OFF`. Only a screenshot showed
  it; the code looked right.
- **Effect sizes are set against the SCREEN, not the world.** A physically sensible 7cm spark
  is four pixels at this camera distance and reads as dirt on the lens. The arena is 14m
  across and drawn 600px wide, and anything meant to be seen has to be sized for that.
- **A latched input needs everything it will be acted on with, latched with it.** The cast
  slot was held across the gap between the lift and the physics tick, and the aim was not —
  so `_process` could overwrite the direction in between and the spell left sideways. It
  reproduces on a slow renderer and never on a fast one, which is the worst shape a bug can
  have. Latch the whole decision, and release it in one place.
- **A wrong facing formula passes every numeric test.** Godot yaw 0 faces -Z, and yaw `a`
  faces `(-sin a, 0, -cos a)`; solving that for a travel direction needs `atan2(-x, -z)`.
  Dropping both signs aims the wizard exactly backwards, and position/velocity traces look
  perfect. Only a screenshot caught it.

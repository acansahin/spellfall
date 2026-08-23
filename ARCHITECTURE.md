# Spellfall — Architecture

Engine: **Godot 4.7**, GDScript, **Forward Mobile** renderer.
Read `GAME_DESIGN.md` first for what the game is. This file is how it is put together.

> Everything described as _(planned)_ does not exist yet. Only the movement prototype is built.

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
    player/        player.tscn + player.gd
    bot/           (planned) AI opponent
    components/    (planned) instability, abilities, haptics
  combat/
    abilities/     (planned) Ability resources + runtime
    projectiles/   (planned)
    knockback/     (planned) the one knockback formula
  arena/           arena.tscn, arena_camera.gd
  ui/
    hud/           (planned) instability readout, round score
    mobile_controls/ (planned) joystick, spell buttons, aim indicators
  systems/
    round/         (planned) RoundManager
    spawn/         (planned)
  data/            (planned) ability + character Resources
  network/         (planned) Phase C onward
  audio/  vfx/  tests/  assets/
```

Empty folders carry a `.gitkeep` so the structure survives a clone.

## Input architecture

This is the most important seam in the project, and it exists already.

```
   keyboard              virtual joystick (planned)        network replay (planned)
       \                        |                                  /
        \                       v                                 /
         ----------->  PlayerInputController  <--------------------
                                |
                                v
                          InputCommand          <- plain data, world space
                                |
                                v
                         Player (CharacterBody3D)
                                |
                                v
                          Abilities (planned)
```

- **`InputCommand`** (`core/input/input_command.gd`) is plain data: a world-space `move_dir`
  and a `has_move_input` flag. No logic, no node references.
- **`PlayerInputController`** (`core/input/player_input_controller.gd`) is the *only* script
  in the project that knows a keyboard or a touchscreen exists. It reads whichever source is
  active and fills one `InputCommand` per frame.
- **`Player`** reads `InputCommand`. It cannot tell how the player produced it.

Two consequences worth stating plainly:

- The virtual joystick, when built, is a **UI scene that calls `set_touch_vector()`**. It
  contains no gameplay logic. That is the rule the design brief asked for, enforced by shape
  rather than by discipline.
- `set_override_vector()` lets an automated run steer the character with no input events at
  all. That is what makes the prototype testable without a human holding a key.

### Screen space vs world space

A player pushing "up" on a joystick means "away from me on screen", not "world -Z". Those
only coincide while the camera has no yaw. `PlayerInputController._screen_to_world()` rotates
the stick vector using the **active camera's basis**, once, before anyone downstream sees it.
Doing it there means rotating or tilting the camera later cannot silently invert the controls.

## Movement and why it is not a RigidBody

`Player` is a `CharacterBody3D` with hand-integrated velocity. This is deliberate and it is
the decision most likely to be second-guessed later, so:

Knockback is the centrepiece mechanic, and it must be **reproducible** - the same hit from the
same angle at the same instability has to send you the same distance, every time, on a server
that never rendered a frame. Rigid-body solvers are tuned to make contacts look plausible, not
to be deterministic; they resolve differently depending on how many bodies are touching and in
what order. That is fine for debris and wrong for the thing the whole game is judged on.

So: physics runs at a **fixed 60Hz tick** (`physics/common/physics_ticks_per_second=60`), all
gameplay integration happens in `_physics_process`, and nothing gameplay-relevant reads the
rendered framerate. A future authoritative server runs the same tick.

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

## Knockback and instability _(planned)_

Two separate components, deliberately:

- **`InstabilityComponent`** tracks one number, raises it on hit, resets between rounds and
  emits when it changes. It does not know what knockback is.
- **The knockback formula** lives once, in `combat/knockback/`. Abilities supply a base value
  and a direction; the formula reads the target's instability and returns a velocity. No spell
  script computes its own knockback.

Keeping them apart means the UI can show instability without touching combat, and the formula
can be rebalanced without touching either.

## Abilities _(planned)_

An ability is a **`Resource`** (name, cooldown, cast type, range, instability, knockback,
projectile speed, area, charges) plus a small runtime that reads it. Adding a spell should be
authoring a data file, not writing a fifth unrelated script.

## Networking _(planned, Phase C+)_

Server-authoritative when it arrives. The server owns positions, cast validation, cooldowns,
hits, instability, knockback, elimination and round results. The client is never trusted with
a competitive outcome.

Nothing networked is being built now. What is being built now that makes it possible later:

- Fixed-tick, deterministic movement integration.
- Input funnelled through one replaceable `InputCommand` producer.
- Knockback as one pure formula rather than scattered per-spell code.
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

`--shot` needs real rendering, so **do not pass `--headless` with it.** This is not optional
tooling: the facing-direction bug below was invisible to `--trace` and obvious in one frame.

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
- **A wrong facing formula passes every numeric test.** Godot yaw 0 faces -Z, and yaw `a`
  faces `(-sin a, 0, -cos a)`; solving that for a travel direction needs `atan2(-x, -z)`.
  Dropping both signs aims the wizard exactly backwards, and position/velocity traces look
  perfect. Only a screenshot caught it.

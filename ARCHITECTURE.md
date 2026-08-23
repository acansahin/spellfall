# Spellfall — Architecture

Engine: **Godot 4.7**, GDScript, **Forward Mobile** renderer.
Read `GAME_DESIGN.md` first for what the game is. This file is how it is put together.

> Everything described as _(planned)_ does not exist yet. What is built: the arena, the
> wizard, movement, the fixed camera, and the touch controls. Nothing combat-related.

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
    mobile_controls/ touch_stick + mobile_controls; spell buttons and aim later
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
   keyboard                  TouchStick                 network replay (planned)
   (Input actions)      (ui/mobile_controls)
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
rule — and it means a second stick (aiming, later) is a new connection, not a new code path.

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
- **A wrong facing formula passes every numeric test.** Godot yaw 0 faces -Z, and yaw `a`
  faces `(-sin a, 0, -cos a)`; solving that for a travel direction needs `atan2(-x, -z)`.
  Dropping both signs aims the wizard exactly backwards, and position/velocity traces look
  perfect. Only a screenshot caught it.

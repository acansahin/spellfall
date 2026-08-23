# Spellfall — Tasks

Small, actionable items. Tick things off as they land. Phase gates live in `ROADMAP.md`.

---

## Session 1 — Project skeleton and movement ✅

- [x] Inspect the working directory for an existing Godot project
- [x] Confirm the installed Godot version (4.7.stable.official)
- [x] Write `GAME_DESIGN.md`, `ARCHITECTURE.md`, `ROADMAP.md`, `TASKS.md`
- [x] Create `project.godot` — Forward Mobile renderer, landscape, 60Hz physics tick
- [x] Create the folder structure
- [x] Build the arena: circular platform, glowing rim, centre mark
- [x] Build a placeholder wizard: capsule + facing indicator on a `CharacterBody3D`
- [x] `InputCommand` + `PlayerInputController` — the keyboard/touch seam
- [x] Desktop movement: WASD and arrow keys, camera-relative
- [x] Fixed three-quarter camera with derived framing
- [x] Solve arena size and camera distance for on-screen character size
- [x] Scripted-run harness: `--move`, `--trace`, `--shot`
- [x] Run the project and verify movement works
- [x] Fix: facing indicator pointed backwards (`atan2` sign)
- [x] Fix: key light shone upward (`Transform3D` written transposed)
- [x] Fix: `player.gd` written in cp1254 instead of UTF-8

---

## Session 2 — Mobile controls (next)

- [ ] `VirtualJoystick` scene under `ui/mobile_controls/`
  - [ ] Draws a base and a thumb; thumb clamps to the base radius
  - [ ] Deadzone and sensitivity as exported values
  - [ ] Scales correctly on different screen sizes and aspect ratios
  - [ ] Calls `PlayerInputController.set_touch_vector()` and contains **no** gameplay logic
- [ ] Confirm keyboard still works with the joystick present (both feed one `InputCommand`)
- [ ] Test at 1280x720, a tall 20:9 phone shape, and a tablet 4:3 shape
- [ ] Decide fixed-position vs floating joystick, and write down why

## Session 3 — Ability framework and Fireball

- [ ] `Ability` Resource: name, cooldown, cast type, range, instability, knockback, speed, area
- [ ] `AbilityComponent` on the wizard: holds a set, runs cooldowns, casts
- [ ] Extend `InputCommand` with ability intents and an aim direction
- [ ] Projectile scene with a pooled spawner
- [ ] Fireball as a data file, not a bespoke script
- [ ] Four spell buttons in the HUD with cooldown sweeps
- [ ] Verify a full cast round-trip in a scripted run

## Session 4 — Instability and knockback

- [ ] `InstabilityComponent`: track, add, reset, emit on change
- [ ] Knockback formula in `combat/knockback/`, reading instability
- [ ] Apply knockback as velocity on `CharacterBody3D`, not physics impulse
- [ ] HUD instability readout
- [ ] Confirm the same hit at the same instability always throws the same distance

## Session 5 — Falling, elimination, rounds

- [ ] Replace the `fall_limit` stopgap in `main.gd` with a proper `KillZone` `Area3D`
- [ ] Elimination: mark out, disable input, notify the round system
- [ ] `RoundManager`: countdown, spawn, detect last standing, show winner, reset
- [ ] Round score
- [ ] Verify a full round cycle end to end in a scripted run

## Session 6 — Bot

- [ ] Bot drives the same `InputCommand` path the player does
- [ ] Keep distance, face the player, aim, cast on a delay
- [ ] Do not walk off the edge
- [ ] Exported difficulty

## Session 7 — Game feel

- [ ] Hit particles, impact audio, brief hit pause
- [ ] Small camera shake on heavy knockback
- [ ] Haptics on cast, heavy hit, elimination
- [ ] Round start and victory audio
- [ ] Readability check: nothing hides a projectile

---

## Carried debt

Small things deliberately left, so they do not get silently forgotten.

- [ ] `main.gd` respawns on `y < fall_limit` as a stopgap. Real elimination replaces it (Session 5).
- [ ] No `README.md` yet — add one when the repo is worth explaining to someone else.
- [ ] No Android export preset yet. `import_etc2_astc` is already set, so it should be uneventful.
- [ ] No CI. Worth adding once there is something worth building automatically.
- [ ] `characters/components/`, `core/utilities/`, `data/`, `network/` are empty placeholders.
- [ ] Character shadow is faint at the current light angle. Cosmetic; revisit in the feel pass.

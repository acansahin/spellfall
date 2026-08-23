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

## Session 2 — Mobile controls ✅

- [x] `TouchStick` scene under `ui/mobile_controls/`
  - [x] Draws a base and a thumb; thumb clamps circularly to the base radius
  - [x] Deadzone and sensitivity as exported values (on the controller, not the UI)
  - [x] Scales correctly on different screen sizes and aspect ratios
  - [x] Feeds `PlayerInputController.set_touch_vector()` and contains **no** gameplay logic
- [x] `MobileControls` CanvasLayer owning placement, safe-area margins and visibility
- [x] Multi-touch: stick claims exactly one finger by index, ignores all others
- [x] Hidden stick claims nothing (`is_visible_in_tree()` guard)
- [x] Confirm keyboard still works with the stick present (both feed one `InputCommand`)
- [x] Touch takes priority over a held key; keyboard resumes when the finger lifts
- [x] Rescaling deadzone instead of the old hard cutoff
- [x] `emulate_touch_from_mouse` so a mouse drives the stick in a desktop dev build
- [x] Test at 16:9, 19.5:9, 20:9 and a 4:3 tablet — measured, not assumed
- [x] Decide fixed-position vs floating stick, and write down why
- [x] Correct ARCHITECTURE.md's cross-platform determinism claim
- [x] Harness: `--touch-test`, `--key-test`, `--layout-probe`, `--stick-hold`, `--touch-ui`
- [x] Renamed off `VirtualJoystick` — Godot 4.7 ships a native class with that name

## Session 3 — Ability framework and Fireball ✅

- [x] `Ability` Resource: identity, cast type, cooldown, combat and projectile numbers
- [x] `AbilityComponent` on the wizard: holds a set, runs cooldowns, gates casts
- [x] Extend `InputCommand` with a latched ability intent and an aim direction
- [x] Projectile scene with a pooled spawner (prewarm 8, reuse asserted)
- [x] Fireball as a data file, not a bespoke script
- [x] **One** spell button with a cooldown wedge — three more when three more spells exist
- [x] Training dummy so a cast has something to hit
- [x] Verify a full cast round-trip in a scripted run (`--cast-test`, 17 assertions)
- [x] Verify stick + button on separate fingers (`--twothumb-test`, 13 assertions)
- [x] Fix: `Area3D.monitorable = false` silently disabled all hit detection
- [x] Fix: harness `substr()` off-by-one made `--cast-at:N` fire at t=0
- [x] Fix: `--shot:1.05` and `--shot:1.85` both wrote `shot_1.png`
- [x] Fix: injected input needed `Input.flush_buffered_events()` to be deterministic
- [x] Fix: `AbilityComponent` guarded `abilities` but indexed `_cooldowns`

## Session 4 — Instability and knockback ✅

- [x] `InstabilityComponent`: track, add, reset, emit on change
- [x] Knockback formula in `combat/knockback/`, reading instability
- [x] `KnockbackRules` Resource so the central mechanic is tuned as data
- [x] Apply knockback as velocity on `CharacterBody3D`, not physics impulse
- [x] Separate input velocity from knockback velocity so instant movement cannot erase a hit
- [x] Hitstun, so a hit cannot simply be walked out of
- [x] HUD instability readout, colour-coded by danger band
- [x] Training dummy rebuilt as a driverless fighter, so it can be knocked off
- [x] Confirm the same hit at the same instability always throws the same distance
      (measured 1.3364m twice — identical to four decimals)
- [x] Confirm the measured slide matches the closed form v²/2f
- [x] Fix: reading `velocity` back after `move_and_slide()` compounded knockback with itself
- [x] Fix: the floor pin squashed the upward lift on every hit

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
- [ ] **Android export is untested — export templates are not installed.** See below.
- [ ] `export_presets.cfg` is in `.gitignore`, so the Android preset written during Session 2
      lives only on this machine. Reconsider committing it once a build actually succeeds —
      CI would need it, and it holds no secrets (the keystore path is an editor setting).
- [ ] No CI. Worth adding once there is something worth building automatically.
- [ ] `core/utilities/`, `network/`, `data/characters/` are empty placeholders.
- [ ] Knockback is horizontal plus a fixed `lift`. Per-ability launch angles are a
      tuning surface nobody has asked for yet.
- [ ] `InstabilityComponent.add()` ignores negative amounts. If a spell should ever
      reduce instability, that is a design decision to make deliberately.
- [ ] `TrainingDummy` is a prototype target, not a design feature. The bot replaces it.
- [ ] `Player` now means "a fighter" — the dummy uses the same script with no input
      controller, and the bot will too. Renaming the class was judged more churn than
      it is worth; revisit if it starts confusing people.
- [ ] `Ability.charges`, `area`, `cone_angle` are authored but not read yet — they belong
      to Blink, splash and Force Wave, which arrive in Session 7.
- [ ] Cast types CONE, DASH and BUFF warn loudly and do nothing. Only PROJECTILE runs.
- [ ] Character shadow is faint at the current light angle. Cosmetic; revisit in the feel pass.
- [ ] `PlayerInputController` samples input in `_process` (render rate) while the character
      consumes it in `_physics_process` (fixed 60Hz). Harmless now, but a predicting client
      will want one command sampled per tick. Revisit when networking starts, not before.
- [ ] The stick's activation area must never grow to overlap the future ability buttons on
      the right. It is currently base + 44 units, bottom-left only.

## Android export status

Blocked, and **not** by anything in this project. Attempting a real export
(`--export-debug "Android"`) reports exactly:

```
No export template found at the expected path:
  .../export_templates/4.7.stable/android_debug.apk
No export template found at the expected path:
  .../export_templates/4.7.stable/android_release.apk
A valid Java SDK path is required in Editor Settings.
```

What is already present on this machine:

| Piece | State |
|---|---|
| Android SDK | present — `build-tools/36.0.0`, `platforms/android-36.1`, `platform-tools` |
| JDK | present — Temurin OpenJDK 21.0.12 on `PATH` |
| Godot's `android_sdk_path` | already set in editor settings |
| **Godot export templates for 4.7** | **absent — the whole `export_templates/` folder is empty** |
| **`export/android/java_sdk_path`** | **empty in editor settings** |
| Debug keystore | editor settings point at `.../Godot/keystores/debug.keystore`, which does not exist |

To unblock, in the Godot editor: **Editor → Manage Export Templates → Download and Install**
(~1 GB), then **Editor → Editor Settings → Export → Android** and set the Java SDK path to the
Temurin 21 install. Not done here because it is a large download that was not asked for.

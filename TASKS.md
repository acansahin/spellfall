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

## Session 5 — Falling, elimination, rounds ✅

- [x] Replace the `fall_limit` stopgap in `main.gd` with a proper `KillZone` `Area3D`
- [x] Elimination: mark out, disable input, stop physics, notify the round system
- [x] `RoundManager`: countdown, spawn, detect last standing, show winner, reset
- [x] Round score, carried across rounds
- [x] Match end at `wins_needed`, then a fresh match
- [x] HUD: round number, score, countdown and winner banner
- [x] Verify a full round cycle end to end in a scripted run (`--round-test`, 23 assertions)
- [x] Gate the other suites on `_wait_for_live()` now that a countdown freezes fighters
- [x] Fix: GDScript lambda captured a bool by value, so a test flag never became true

## Session 6 — Bot ✅

- [x] Bot drives the same `InputCommand` path the player does
- [x] Keep distance, face the player, aim, cast on a delay
- [x] Do not walk off the edge
- [x] Exported difficulty
- [x] `BotController` extends `PlayerInputController` and overrides `_process` to nothing, so
      no key and no finger can reach it
- [x] Thinks in `_physics_process`, so its reaction time is a gameplay number rather than a
      function of the frame rate
- [x] Reaction time implemented as a *remembered* target position, refreshed on a clock —
      a slow bot genuinely mis-tracks a moving player
- [x] Aim error re-rolled on that same clock, not per frame (per frame averages out to a
      perfect shot over a projectile's flight)
- [x] Leads the target by the projectile's flight time, scaled by difficulty
- [x] Arena radius read off the platform's own `CylinderShape3D` and handed over by the level
- [x] `bot_wizard.tscn` inherits `player.tscn` and only recolours it — the opponent is a
      re-skin of the fighter, not a fork of it
- [x] Facing now follows `aim_dir` and falls back to travel, so a strafing bot looks like it
      is shooting at you. Nothing changes for the human until drag-to-aim lands
- [x] Training dummy deleted; the four suites that needed a motionless target park the bot
      with `_freeze_bot()` instead
- [x] Harness: `--bot-test` (26 assertions), `--bot:off`, `--bot-skill:calm|steady|sharp`
- [x] Fix: `--cast-test` was measuring the frame rate, not the cast. `_settle()` spans render
      frames, and on a slow renderer a dozen physics ticks pass inside it. Reproduced on the
      commit before this session, so it was not caused by the bot

## Session 7 — The other three spells ✅

ROADMAP step 7. The ability framework was built for this in Session 3; the test of it was
whether three spells that share nothing with Fireball could be added without touching it.

- [x] `Ability` gains `dash_distance`, `duration` and `knockback_resist`; `area` and
      `cone_angle` are finally read rather than merely authored
- [x] Force Wave — `.tres` only, no script. `CONE` cast type, `ConeCast` finds who is in the
      fan with a physics query, and the push goes **away from the caster** rather than along
      the aim, which is what makes catching someone at the shoulder of the fan lethal
- [x] Blink — `DASH` cast type. The landing point is clamped inside the arena by the LEVEL,
      which is the only thing that knows where the edge is
- [x] Blink cancels the slide you are in but keeps the hitstun, so it is an escape and not a
      free reset. If it plays too strong, turn the cooldown first
- [x] Arcane Shield — `BUFF` cast type, applied in `Player.apply_knockback` rather than in the
      knockback formula: the formula says how hard the hit was, the shield says how much of it
      landed on *me*
- [x] `_apply_hit()` — one door for every hit in the game, projectile or cone
- [x] `SpellFlash` draws the fan from the same two numbers the hit test reads, so what is on
      screen cannot drift from what actually hits
- [x] A shield bubble on the fighter, so "I am protected" is visible and not just a number
- [x] Four buttons: primary in the corner, three fanned along a thumb arc, angles exported,
      read out of the scene and sorted by slot
- [x] `AbilityButton` claims a **disc** instead of its bounding box — a cluster of round
      buttons with square hit areas mis-fires in the invisible corners, and nothing about the
      screen looks wrong when it does
- [x] `cast_1`..`cast_4` on Space and the number row, polled in one loop
- [x] The bot picks a spell by CAST TYPE, not by slot index: escape, shove, brace, or Fireball
- [x] Harness: `--spells-test` (21 assertions), `--button-test` (14), `--cast-at:N,S`
- [x] Photographed the fan and the shield bubble rather than trusting the numbers

## Session 8 — Game feel

- [ ] Hit particles, impact audio, brief hit pause
- [ ] Small camera shake on heavy knockback
- [ ] Haptics on cast, heavy hit, elimination
- [ ] Round start and victory audio
- [ ] Readability check: nothing hides a projectile

---

## Carried debt

Small things deliberately left, so they do not get silently forgotten.

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
- [ ] A draw (everyone falls at once) scores nobody. Fine for 1v1; revisit for FFA.
- [ ] The bot does not dodge. It circles, which dodges by accident. Deliberate — Phase 1 wants
      a sparring partner, not something that wins.
- [ ] The bot never plays the edge: it does not try to line you up against the rim, which is
      the most interesting thing an opponent in this game could do. Phase 2 material.
- [ ] Difficulty is reachable from the inspector and `--bot-skill:` only. No in-game selector
      until there is a menu to put one in.
- [ ] Six suites now depend on `_freeze_bot()`. A seventh that forgets it will fail in a way
      that looks like a code bug.
- [ ] The Force Wave fan is drawn as a flat mesh at ground height, so a wave cast near the rim
      hangs over the void. Correct, and it looks odd. Feel pass.
- [ ] Blink has no visual at all — the wizard simply appears elsewhere. It reads, but a trail
      or an afterimage is the obvious thing the feel pass should add.
- [ ] Arcane Shield reduces knockback; it does not block projectiles or stop instability. That
      is the shipping decision recorded in GAME_DESIGN.md, not an oversight.
- [ ] The bot spends Shield on a plain instability threshold. It has no idea whether a hit is
      actually coming, which is the difference between a read and a habit.
- [ ] Nothing shows the player where a spell will land before they cast it. That is step 8.
- [ ] No round timer. A stalemate where nobody attacks currently lasts forever.
- [ ] The winner banner conjugates "YOU" as a special case in `main.gd`. Fine while the
      level owns both titles; revisit if titles ever come from elsewhere.
- [ ] `Player` now means "a fighter" — the dummy uses the same script with no input
      controller, and the bot will too. Renaming the class was judged more churn than
      it is worth; revisit if it starts confusing people.
- [ ] `Ability.charges` is authored but never read. It belongs to a spell that banks more
      than one cast, and no spell does.
- [ ] `Ability.area` is read as the CONE's reach. Splash on a projectile still is not built.
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

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

## Session 8 — Drag-to-aim and the indicators ✅

ROADMAP step 8. The seam was written for this in Session 1: `InputCommand.aim_dir` existed as
a separate field precisely so a second source could fill it. The test of that was whether
aiming could land without a single line changing downstream of the input controller.

- [x] `AbilityButton` becomes press-drag-lift: it reports `aim_started`, `aim_moved` and
      `cast_released`, and still casts nothing itself
- [x] The cast moves from the press to the **lift**, reversing a Session 3 decision on
      purpose — a thumb has no other way to say *where*, and that is worth the latency
- [x] Deadzone in `PlayerInputController`, not in the button, matching the stick
- [x] The drag is measured from where the finger LANDED, not from the button's centre
- [x] The button holds its finger after it slides off the disc — dragging away is the gesture
- [x] **The aim is latched WITH the cast** and released with it, so a `_process` between the
      lift and the physics tick cannot overwrite the direction the spell goes out with
- [x] `player.gd` reads the aim before consuming the slot, so nothing depends on the order the
      controller clears things in
- [x] `AimIndicator` on every fighter, shown for the human: lane, fan, dash line and ring,
      self ring — one per cast type, all from the ability's own numbers
- [x] `GroundShapes` — one fan builder for the indicator AND for `SpellFlash`, so the shape
      you sight down is the shape that goes off
- [x] `Ability.effective_range()` — range asked once, whatever kind of spell is asking
- [x] `main.gd._blink_landing()` shared by the cast and the preview, so the line cannot
      promise a landing spot the spell refuses
- [x] The projectile lane is trimmed at the arena rim; the fan deliberately is not
- [x] An aim nub on the button itself, so the thumb doing the aiming can be seen doing it
- [x] Harness: `--aim-test` (23 assertions), `--aim-hold:S,X,Y`
- [x] Photographed all three shapes rather than trusting the meshes
- [x] Re-ran all nine existing suites; `--twothumb-test` updated for cast-on-lift

## Session 9 — Game feel ✅

ROADMAP step 11, and the last thing before the Phase 1 gate. Every Phase 1 step is now built;
what remains is playing it and answering the gate honestly.

- [x] `GameFeel` — one node holding hitstop, shake, sparks, sound and haptics, because "that
      hit was heavy" has to mean the same thing to all five
- [x] Hitstop: `Engine.time_scale` to 0.12 for 35-85ms, scaled by the knockback that landed.
      Not a freeze — a full stop reads as a dropped frame
- [x] The strength read back off the fighter AFTER `apply_knockback`, so a hit taken through
      Arcane Shield feels shrugged off
- [x] Camera shake in the camera's own screen plane, decaying on a squared curve; a hit on
      the opponent shakes at 55% of one on you
- [x] `ImpactBurst` — a pooled `CPUParticles3D` spray at the contact point. Strength scales
      how far the sparks fly, never how many there are
- [x] `SoundBank` — ten sounds synthesized from swept sines, filtered noise and an envelope.
      **Still no audio files in the repo**
- [x] Cast, blink, shield, hit, heavy hit, fall, countdown tick, GO, win, lose
- [x] Haptics on a hit you took, on your own Blink, and on your own elimination; mobile-gated
- [x] `GroundStreak` — the smear a Blink leaves, so the spell finally has a visual
- [x] `enabled = false`, and eight measuring suites park the feel the way they park the bot
- [x] Harness: `--feel-test` (22 assertions), `--feel:off`
- [x] Hitstop deadline in `Time.get_ticks_msec()`, not in delta — counting it down with the
      clock it slowed makes a 35ms stop last 290ms, and the suite measures wall-clock to prove
      it does not
- [x] Fix: sparks cast shadows, which drew black specks around every hit. Screenshot caught it
- [x] Fix: a 7cm spark is four pixels at this camera. Effect sizes are set against the screen
- [x] Readability check, photographed: a Fireball crossing a Force Wave fan stays clearly
      visible, and the sparks do not hide either fighter
- [x] All ten existing suites re-run and green

## Session 10 — First phone test, and what it found ✅

The first build on real hardware, and the first three notes from a player rather than a suite.

- [x] **The game was in PORTRAIT.** `window/handheld/orientation` was `1`, which is
      `SCREEN_PORTRAIT`, under a comment saying "Landscape". Now `4`
      (`SCREEN_SENSOR_LANDSCAPE`); verified in the built APK's manifest as `userLandscape`
- [x] Cover: two rocks and two trees, `rock.tscn` / `tree.tscn` instanced under
      `Arena/Obstacles`
- [x] Projectiles stop against cover - the mask lives in `projectile.gd`, not the scene
- [x] `ConeCast` casts a sight line, so Force Wave is stopped by cover too. One rule
- [x] Point-symmetric placement, open lane between the spawns, both asserted
- [x] `_clear_cover()`, and the eight measuring suites call it
- [x] Harness: `--cover-test` (7 assertions)
- [x] Fix: `collision_mask` set in `_ready()` silently overrode the `.tscn` edit. The file
      said 3, the flying projectile said 2, and cover did nothing
- [x] Fix: the walk-into-a-rock assertion first passed while the wizard walked the OTHER
      way. It now requires the distance to close as well as to stop
- [x] All twelve suites green

### Still open from that test

- [x] ~~**"Alan çok küçük" - the arena may be too small.**~~ Re-judged in landscape: still
      too small. Answered in Session 11 by measuring the original rather than nudging - the
      arena was six times too small in seconds-of-walking, and Fireball out-ranged it three
      times over.
- [x] ~~Cover eats an arena this size.~~ It does not eat a 20m one; the four obstacles moved
      out with the rim and now read as furniture rather than as a maze.

## Session 11 — The proportions, measured against the original

- [x] Read the reference map's own numbers out of the map file (protected archive; the file
      key is derivable from the name, which is ordinary MPQ reading). **Proportions and
      physics only** - no names, no spell designs, no code
- [x] Arena 7 -> 10m radius, area doubled; rim, centre mark, spawns and cover all moved with it
- [x] Camera distance 22 -> 31.5, which is the same 3.14x-the-radius framing
- [x] Walk speed 6.5 -> 4.0 m/s: the arena now takes 5 seconds to cross instead of 2.2
- [x] Fireball 18 m/s / 1.2s -> 12 m/s / 0.45s: range 21.6m -> 5.4m, so it reaches half way
      to the rim instead of three times across the board
- [x] Fix: the bot preferred a range it could no longer shoot from and stood still for whole
      rounds. `holding_range()` now derives from `cast_reach()`, slack included
- [x] Fix: `--cast-test` and `--knockback-test` fired across the spawn gap and assumed the
      spell out-ranged it; both now place fighters at a fraction of the spell's own reach
- [x] Fix: `--aim-test` asserted the lane is always trimmed at the rim - true only while the
      spell out-ranged the arena. It now checks both cases
- [x] Fix: `--bot-test` asserted the arena radius equals a literal 7.0; it reads the
      platform's own shape now
- [x] All twelve suites green

### Still open

- [ ] **Knockback is now weaker relative to the ring.** A clean Force Wave at 0% instability
      moves you 48% of the way to the rim where it used to move you 69%. Rounds will run
      longer. Re-measure after a play session before touching it - the escalation at high
      instability is untouched and still lethal.
- [ ] Blink (5m) and Force Wave (4m reach) were left at their absolute sizes, so both are
      relatively smaller on the bigger board. Deliberate: only the three numbers that were
      asked for moved.
- [ ] The wizard is about 8% of screen height, down from 11%, which the camera's own comment
      called the smallest that still reads a facing direction on a phone. Judge it on the
      phone. The dial is `ArenaCamera.distance`, and there is room to come in ~10% before the
      rim leaves the screen.

## Session 12 — Weight: momentum in the legs, drag on the shot ✅

The other half of "the shooting does not feel good", taken from the same reference and with
one deliberate departure from it.

- [x] `accel_time` 0 -> 0.16, `decel_time` 0 -> 0.34. Asymmetric: quick to start, slow to
      stop, about a third of a second to reverse
- [x] **The reference's exponential velocity damping was NOT copied.** It reaches the same
      feel by damping one velocity and adding the walk on top; ours ramps toward a target and
      keeps knockback on a separate, LINEAR decay. That linearity is what gives the slide a
      closed form (v squared over 2f) and makes "how far does this throw someone" answerable
- [x] `Ability.projectile_drag` - the fraction of speed left after one second, as data
- [x] Fireball: 12 m/s flat -> 15.5 m/s decaying to 9. Same 5.4m range, very different shot
- [x] Decay applied as `pow(drag, delta)`, so framerate cannot change where a spell lands
- [x] `effective_range()` integrates the drag, so the aim indicator and the bot's reach check
      stay right without knowing the field exists
- [x] Fix: the bot computed reach as speed x lifetime, which is wrong the moment there is
      drag. It asks `effective_range()` now - the second time that product went stale
- [x] Fix: `--cast-test` connected its hit listener AFTER firing. Fine at 12 m/s, a phantom
      failure at 15.5 when the impact landed inside the gap
- [x] All twelve suites green

### Still open

- [ ] The ramp is the first thing to re-judge on a phone. If it feels sluggish the dial is
      `accel_time`; if it does not feel like anything, raise `decel_time` rather than
      lowering `accel_time`.
- [ ] Only Fireball has drag. Whether the other three want it is a question for after a
      play session, not before.

## Session 13 - Lava instead of a void

- [x] A 60m lava field around the arena, solid and standable. No more empty space
- [x] `HealthComponent` - burned by lava at 22/s, mended by stone at 10/s, out of 100.
      **No spell may ever touch it**; hits still raise instability and nothing else
- [x] Burning to nothing goes through `RoundManager.report_out()` - renamed from
      `report_fall`, which the lava made into a lie
- [x] `_tick_lava()` decides who is burning with a radius test, the same question Blink,
      the bot and the aim lane already ask
- [x] HUD shows the burn only while it is below full, and takes over the row's colour when
      it does - a countdown beats a slow build for attention
- [x] Sizzle and sparks while burning, rate-limited inside GameFeel rather than at the call
      site
- [x] The stone stands 8cm proud, and **the climb back is asserted** - a CharacterBody3D
      does not step up walls; the capsule's curve is what saves it
- [x] Look: three passes. Flat emissive orange filled the screen and drowned the UI; a dark
      ember field plus a narrow molten shore reads as lava and leaves the arena brightest
- [x] Harness: `--lava-test` (12 assertions)
- [x] Fix: the suite pinned the fighter with `respawn_at()`, which resets health every tick.
      It measured the lava burning 0.4/s against an advertised 22
- [x] All thirteen suites green

### Still open

- [x] ~~**Rounds can now stall.**~~ Answered in Session 14 by a ring that closes on a clock -
      and during a round rather than between rounds, which is where the stall actually was.
- [ ] The lava is one flat colour. It wants movement - a slow pulse, or brighter cracks - but
      that is a shader, and the placeholder rule says not yet.
- [ ] Nothing marks a burning fighter except the HUD row and the sparks. A tint on the wizard
      would read from across the arena.
- [ ] `KillZone` is now unreachable unless a hit clears 60m. Kept as a backstop.

## Session 14 - The ring closes

- [x] `arena/arena.gd` owns the radius. It starts at 12m, holds for 12 seconds, then closes
      at 0.3 m/s to a floor of 4.5m - so a round nobody wins is over in well under a minute
- [x] **During a round, not between rounds.** The reference shrinks one step per round, which
      bounds a match and leaves a single round able to run forever - and that is exactly the
      stall the lava created by making a knock-out survivable
- [x] Five readers ask the arena instead of copying: the lava rule, the bot, Blink's clamp,
      the aim lane and the camera. By signal, so none of them can hold a stale edge
- [x] The camera comes in with it at a fixed 3.14x framing, so the wizards GROW on screen as
      the ring tightens - about a fifteenth of screen height to nearly a fifth
- [x] Cover moves in at a fixed fraction of the radius; a ring that closed over its own rocks
      would spend its second half as a bare plate
- [x] Meshes and shapes `duplicate()`d before being written to every frame
- [x] `Arena.shrinking = false` is the fourth thing a measuring suite parks
- [x] Spawns moved out to half the starting radius
- [x] Harness: `--shrink-test` (15 assertions)
- [x] Fix: three call sites still asked the deleted `_arena_radius()`, which also produced a
      type-inference error two files away - the parser reports where the type is missing, not
      where the function went
- [x] All fourteen suites green

### Still open

- [ ] Fireball's health damage (20) and the lava's burn rate (22/s) were picked to feel
      similar - five hits kills about as fast as five seconds outside - but never played
      against each other. The first thing to judge on a phone.
- [ ] Only Fireball drains health. Whether Force Wave should too is a question for after a
      play session, not a default to reach for now.
- [ ] The burn bar is sized for the WIDEST zoom, so it is chunky by the time the ring has
      closed and the camera has come in 2.7x. Scaling it against the camera distance would
      fix that and would also be the first thing in the game to do so.
- [ ] The lava is one flat orange. It covers the whole screen, so it reads as a coloured
      backdrop rather than as molten rock - it wants cooled crust, a slow pulse, or cracks,
      and all three are shader or texture work the placeholder rule defers.
- [ ] The squeeze has no warning. A player who is not watching the rim will be standing in
      lava without knowing why. A sound at the moment it starts, or a tightening pulse on the
      shore, is the cheap version.
- [ ] Nothing shows how long the grace has left, and nothing says how long a round can run.
      Both are numbers only the arena knows.
- [ ] 12s / 0.3 m/s / 4.5m are three numbers picked to make a round land under a minute. They
      have never been played. That is the first thing a session on a phone should judge.

---

## Carried debt

Small things deliberately left, so they do not get silently forgotten.

- [ ] No `README.md` yet — add one when the repo is worth explaining to someone else.
- [x] ~~Android export is untested — export templates are not installed.~~ Unblocked and a
      signed debug APK built, 2026-08-23. See below.
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
- [ ] **The bot has no idea cover exists.** It walks into rocks and shoots them, because its
      aim is a straight line to where you will be. Its own suite clears the obstacles, so it
      is not measured against them either. Phase 2 material, and the first thing that will
      make the bot look stupid on a phone.
- [ ] Blink can put you inside cover. The landing point is clamped to the ARENA and knows
      nothing about obstacles; physics pushes you out, which works and looks like a bug.
- [ ] The bot does not dodge. It circles, which dodges by accident. Deliberate — Phase 1 wants
      a sparring partner, not something that wins.
- [ ] The bot never plays the edge: it does not try to line you up against the rim, which is
      the most interesting thing an opponent in this game could do. Phase 2 material.
- [ ] Difficulty is reachable from the inspector and `--bot-skill:` only. No in-game selector
      until there is a menu to put one in.
- [ ] Six suites now depend on `_freeze_bot()`. A seventh that forgets it will fail in a way
      that looks like a code bug.
- [ ] The Force Wave fan is drawn as a flat mesh at ground height, so a wave cast near the rim
      hangs over the void. Correct, and it looks odd.
- [ ] A DRAW makes no sound. The round-ended path returns before the feel call, deliberately —
      neither the win nor the lose sting is right for it, and a third one was not worth writing
      before anyone has seen a draw happen.
- [ ] Nothing in the feel layer distinguishes the killing blow from any other hit. The fall
      sound covers it, but the hit that ENDS a round is the one moment that could earn more.
- [ ] Haptics are unverified on real hardware — `vibrate_handheld` is a no-op on desktop, so
      the harness can only assert that the call is reachable. Check it on a phone.
- [ ] The synthesized bank has never been heard on a phone speaker. Low tones are the first
      thing a small speaker loses, and `hit` and `heavy` are both low.
- [ ] Arcane Shield reduces knockback; it does not block projectiles or stop instability. That
      is the shipping decision recorded in GAME_DESIGN.md, not an oversight.
- [ ] The bot spends Shield on a plain instability threshold. It has no idea whether a hit is
      actually coming, which is the difference between a read and a habit.
- [ ] Casting on the lift adds the press-to-lift duration to every cast. Correct for aiming,
      and it is a real cost. If it ever feels sluggish the dial is a quick-cast setting, not a
      return to casting on the press.
- [ ] There is no way to cancel an aim once started - lifting always casts.
      `PlayerInputController.cancel_aim()` exists and nothing calls it; a drag back onto the
      button, or into a cancel zone, is the obvious gesture and is a button change away.
- [ ] The indicator does not say whether the spell is READY. The button's cooldown wedge does,
      and the button is under a thumb. Watch for players sighting down a lane that cannot fire.
- [ ] The projectile lane stops at the rim, so aiming at someone already knocked over the void
      draws a line that stops short of them. The direction is still right.
- [ ] Keyboard casts are still instant and preview nothing. Desktop aiming works only through
      mouse-to-touch emulation on the buttons.
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

**Working.** A signed arm64 debug APK builds locally in about a minute:

```
"C:\Program Files\Godot\Godot.exe.exe" --headless --path . --export-debug "Android" "build/spellfall-debug.apk"
```

First build produced 28.6 MB, signed `CN=Android Debug`, `arm64-v8a` only, game data under
`assets/`. `build/` and `*.apk` are gitignored, so nothing lands in the repo.

Three things had to be set up once, on this machine, and none of them were in the project:

| Piece | What was done |
|---|---|
| Godot 4.7 export templates | `export_templates/` was empty. Downloaded `Godot_v4.7-stable_export_templates.tpz` (1.28 GB) from the godotengine/godot 4.7-stable release and unpacked it into `%APPDATA%/Godot/export_templates/4.7.stable/` |
| `export/android/java_sdk_path` | Was empty in editor settings. Set to the Temurin 21 install already on the machine |
| Debug keystore | The path in editor settings pointed at a file that did not exist. Generated with `keytool` at `%APPDATA%/Godot/keystores/debug.keystore`, alias `androiddebugkey`, pass `android` |

Android SDK (build-tools 36.0.0, platform-tools) and JDK 21 were already present.

**No gradle build is involved.** The preset has `gradle_build/use_gradle_build=false`, so the
export uses the prebuilt template APK - which is why the Android build template and a working
gradle setup are not needed at all.

**`export_presets.cfg` is still in `.gitignore`**, so this preset lives only on this machine.
Now that a build has actually succeeded, committing it is worth reconsidering: it holds no
secrets (the keystore path is an editor setting, not a preset field) and CI would need it.

To put a build on a phone: `adb install -r build/spellfall-debug.apk` with the device
connected and USB debugging on, or copy the APK across and open it.

## Session 15 - Range, damage, no mending, and a camera floor

- [x] Fireball's lifetime 0.45 -> 0.6s, range 5.4m -> 6.6m (drag makes it arrive slower too:
      9 m/s at the old range, ~7 m/s at the new one)
- [x] `Ability.health_damage`, 0 for every spell but Fireball. `_apply_hit()` applies it
      alongside instability, not instead of it - two ways to lose are live at once now
- [x] Fireball: 20 health per hit, picked to kill in about as many hits as the lava takes
      seconds - never played against the lava, first thing to judge on a phone
- [x] **Stone no longer mends.** `HealthComponent.mend()` and `mend_per_second` removed;
      `_tick_lava()` only burns. The total is a budget now - `reset()` between rounds is the
      only way back to full
- [x] `HealthComponent`'s doc comment rewritten - it no longer claims no spell can touch it
- [x] Camera stops closing in past a 6.5m ring radius, even though the ring itself keeps
      shrinking to 4.5m. The last stretch of the squeeze is the RING tightening around two
      readable-sized wizards, not the lens lunging at them
- [x] Harness: `--lava-test` gained a direct-damage assertion and a floor-holds assertion in
      `--shrink-test`; the two mend assertions became one "stops, does not reverse" assertion
- [x] Fourteen suites green

### Still open

- [ ] Fireball's range (6.6m) still does not reach the opening gap. Each spawn sits 6m from
      centre - half the starting 12m radius - so the two start 12m apart. The first exchange
      of a round now requires closing distance on purpose. Confirm that reads as a choice on
      a phone, not as "my spell doesn't work".

---

## Session 16 - Eleven spells, and a choice before the match

Read the roster out of the Warcraft III arena map this game follows, rather than guessing at
one. `Warlock097.w3x` -> `war3map.w3a` gives the whole list with its own tooltips, cooldowns
and column structure: one fixed spell and seven columns of three, pick one per column. That IS
a loadout screen, and it is the shape this session built.

- [x] Read the map's ability table (the tower-defense repo's `extract_w3x.py` needed MPQ file
      decryption to get at it - every file in that map is encrypted, and the key is derived
      from the filename)
- [x] Seven new spells, all `.tres`, no new cast type and no subclass:
  - [x] **Arc Lance** - flat and fast, 15m, barely pushes. Pure data, not one line of runtime
  - [x] **Seeker** - `homing_turn` 220 deg/s toward the nearest fighter. A turn RATE, so
        walking across its nose still loses it
  - [x] **Loopshot** - `returns_after` 0.5 of its life, then flies at the caster; `pierces`
        lets it catch the same wizard going and coming
  - [x] **Lunge** - `dash_hits`: the corridor is swept and everyone in it goes through
        `_apply_hit`, the same door a projectile uses
  - [x] **Warp Bolt** - `swaps_places`. Hurts nobody; takes the ground they were standing on
  - [x] **Rewind** - position and health recorded at CAST time, restored `duration` later.
        Instability deliberately NOT restored
  - [x] **Momentum** - `speed_per_absorbed`: what the ward swallowed comes back as walking
        speed, capped at +2.5 m/s
- [x] `SpellCatalogue` + `SpellColumn` as Resources - the roster is `data/spell_catalogue.tres`
- [x] `LoadoutScreen`, BUILT from the catalogue. A fourth option in a column is one line of
      data and no node
- [x] `LoadoutStore` - `user://loadout.cfg`, keyed by spell ID so reordering a column cannot
      hand a returning player a different spell
- [x] The bot draws a random loadout every match, so every spell gets used against the player
- [x] The bot picks the hardest projectile it has ready and in range, and charges with a dash
      that hits. Without this it would have carried a spell and never thrown it
- [x] `--loadout-test` (36 assertions), `--loadout:on|off|a,b,c`, `--wipe-loadout`
- [x] Fix: `Projectile.hit` grew a `shooter` argument and two harness lambdas silently stopped
      receiving anything - `--cast-test` and `--bot-test` reported a projectile that never
      arrived. Written up in ARCHITECTURE.md
- [x] Fix: nothing froze the fighters while the menu was up, so the bot opened fire on a player
      still reading the spell list. Caught by the first screenshot of the screen
- [x] Fix: `--wipe-loadout` deleted the file after `_ready` had already read it, so the run
      still played the loadout it was told to forget
- [x] GAME_DESIGN.md's Originality section rewritten - spell DESIGNS now come from the map;
      names, art, sound, text, UI and numbers still do not
- [x] An icon per spell: `Ability.Glyph` + `vfx/spell_glyph.gd`, eleven vector shapes drawn
      in a unit box and scaled at draw time. On the spell buttons and on every menu row, and
      Fireball shown once on the menu as the spell you do not choose
- [x] `--loadout-test` asserts no two spells in the roster share a shape
- [x] Fix: the spell button only redrew when its cooldown moved, so applying a loadout to the
      same AbilityComponent left the previous spell's glyph on the button until the next cast
- [x] Fix: the flame drawn as one shape read as a WATER droplet at button size. Two convex
      shapes stacked - concave is the honest silhouette and `draw_colored_polygon`
      triangulates it wrong without complaining
- [x] Five flight shapes: `Ability.Bolt` - orb, shard, dart, spinning blade, flat ring. One
      shared mesh per shape, sized by the node so `projectile_radius` is the only number that
      decides how big a spell looks. Hitbox stays a sphere for all five
- [x] Projectile emission 2.2 -> 1.15. At 2.2 every tint blew toward white, which was survivable
      while all five were identical spheres and is a straight loss now that shape carries the
      identity
- [x] `--bolt-pose`: all five down parallel lanes, so one shot compares them from one angle
- [x] Fix: `Node3D.scale =` keeps the rotation, so a pooled projectile relaunched as a hoop kept
      the shard's angle from its last flight
- [x] Fix: a ring stood across the flight path is a vertical sliver from this camera. Laid flat
- [x] Sixteen suites green

- [x] **Spell damage halved across the board.** Fireball 20 -> 10, Arc Lance 16 -> 8, Seeker
      18 -> 9, Lunge 14 -> 7, Loopshot 12 -> 6. Five Fireballs killed; ten do now. At five the
      fastest way to win was to stand still and shoot, which is not this game
- [x] The floor is a RULE now, not a number in a file: no spell empties a full bar in under ten
      clean hits, and the lava stays the quickest way to empty one (4.5s against the best
      spell's 9s at perfect uptime). `--loadout-test` asserts both

### Still open

- [ ] **Does the round now drag?** Damage was the thing finishing fights, and it has just been
      halved. If rounds run long, the dial to turn is `instability` per hit - the escalation
      curve - and NOT the damage back up. Judge it on a phone before touching either.
- [ ] **Four of the map's seven columns are not built.** Meteor / Splitter / WindWalk,
      Drain / Fire Spray / Bouncer, Entangle / Gravity / Link, and the self-centred novas
      (Scourge / Cataclysm / Pious). Each needs a runtime this game does not have yet -
      a ground-targeted cast, a tether, a root, invisibility - and there are only four
      buttons on the screen, so a fourth column needs the UI to grow first.
- [ ] Nothing is balanced. The cooldowns are the map's RATIOS mapped onto our Fireball, and
      the damage numbers are guesses beside it. Judge Seeker's 220 deg/s and Momentum's
      +2.5 m/s ceiling on a phone before touching anything else.
- [ ] The bot never casts Warp Bolt - it scores zero on a ranking made of damage, which is
      honest but means one spell is never used against the player.

---

## Session 17 - Two a side

- [x] `Player.team` - an int on the fighter, not a physics layer per side. Four queries mask the
      one "players" layer and all four would have to learn about teams to save one comparison
- [x] `RoundManager` counts SIDES: a round ends when one is gone, score is kept per side, and
      `wins_for()` answers for a side's name or any fighter on it. A duel is two sides of one
      and reads exactly as before
- [x] Friendly fire OFF, and off means an ally is NOT THERE - the projectile flies on, the
      seeker will not lock onto them, the fan skips them and catches the enemy behind. Three
      places, one rule, asserted rather than assumed
- [x] The bot picks the nearest living enemy and re-picks on its own reaction clock; a target
      that leaves the round is dropped immediately, because reaction time is a handicap on
      noticing and not a licence to keep fighting a body that has gone
- [x] `_begin_match()` - the squad is formed AFTER the mode is known. Everything that depends
      on how many wizards there are moved out of `_ready`
- [x] 1v1 / 2v2 row on the loadout screen, remembered in `user://loadout.cfg` with the picks
- [x] Every bot gets its own random loadout, drawn one after another from one seeded stream
- [x] `--2v2` and `--team-test` (15 assertions)
- [x] Fix: `--bot:off` and `--bot-skill:` reached only the scene's bot. Both now cover every
      brain, in whichever order the squad happens to be formed
- [x] Fix: driving the loadout screen a second time re-registered the whole roster - two HUD
      rows per fighter and two of each body in the round system, which never ends
- [x] Sixteen suites green

### Still open

- [ ] **Four wizards on a ring that closes to 4.5m.** The shrink numbers were tuned for two
      bodies. Judge whether a 2v2 needs a wider floor, a slower clock, or neither.
- [ ] **The ally is not a teammate yet, it is a second bot facing the same way.** It does not
      cover, does not focus what you are shooting, and does not stay out of your line. Whether
      any of that is worth building is a question to answer by playing, not by listing.
- [ ] Cover is placed point-symmetrically for TWO spawns. With four it is no longer obviously
      fair to every start.


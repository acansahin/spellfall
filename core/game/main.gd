extends Node3D

## Level wiring for the movement prototype, plus the scripted-run harness.
##
## Nothing here is a "GameManager". It connects the input controller to the character and
## nothing else; the round system, spawning and combat get their own nodes when they land.
##
## HARNESS (everything after a bare `--` on the command line):
##   --shot            save one drawn frame to user://shot.png and print the path
##   --shot:N          same, but N seconds in, landing in user://shot_N.png (repeatable)
##   --move=X,Y        steer the player with a constant stick vector, no input events
##   --trace           print the player's position once a second
##   --touch-ui:on|off force the mobile controls visible or hidden, whatever the device
##   --touch-test      inject a scripted multi-touch sequence and assert the results
##   --key-test        inject key presses and assert the keyboard path still drives movement
##   --cast-test       assert the full cast round-trip: cooldown, pooling, flight, impact
##   --twothumb-test   hold the stick and the cast button at once, on separate fingers
##   --knockback-test  assert the instability curve and the distance a hit carries
##   --round-test      assert a full round cycle: countdown, elimination, score, reset
##   --bot-test        assert the bot: range, aim, facing, edge safety, difficulty, fairness
##   --bot:off         park the bot, for a screenshot or a suite measuring something else
##   --bot-skill:S     play against calm|steady|sharp instead of the scene's setting
##   --spells-test     assert Force Wave, Blink and Arcane Shield do what they claim
##   --button-test     assert a finger on button N casts spell N and nothing else
##   --aim-test        assert drag-to-aim: the indicator, the direction, and the latch
##   --aim-hold:S,X,Y  hold a drag on button S toward X,Y and never lift, for a screenshot
##   --feel-test       assert hitstop, shake, sparks, sound and the dash streak all fire
##   --feel:off        park the game feel, for a suite that measures distance or duration
##   --cast-at:N[,S]   cast spell S (default 0) N seconds in, so a delayed shot catches it
## Screenshots need real rendering, so DO NOT pass --headless with --shot.
## The two input tests ALSO need a real window: the headless display driver does not
## route injected InputEventScreenTouch/Key to _input(), so every assertion silently
## reads zero and the run reports failures that say nothing about the code.

## Where the player is put on start and after falling off.
@export var spawn_point := Vector3(0.0, 1.2, 3.5)

## Where the bot stands. Directly opposite the player, so neither side opens the round
## nearer the edge than the other.
@export var bot_spawn := Vector3(0.0, 1.2, -3.5)

## How a hit is turned into speed. A Resource so the central mechanic is tuned by editing
## data, never by editing logic - see combat/knockback/knockback_rules.gd.
@export var knockback_rules: KnockbackRules = null

@onready var _player: Player = $Player
@onready var _input: PlayerInputController = $PlayerInputController
@onready var _mobile: MobileControls = $MobileControls
@onready var _pool: ProjectilePool = $ProjectilePool
@onready var _bot: Player = $BotWizard
@onready var _brain: BotController = $BotController
@onready var _hud: Hud = $Hud
@onready var _rounds: RoundManager = $Rounds
@onready var _kill_zone: KillZone = $Arena/KillZone
@onready var _camera_rig: ArenaCamera = $CameraRig
@onready var _feel: GameFeel = $Feel

var _trace := false

## The platform's radius, measured once in _ready. Blink clamps against it and the bot is
## handed it; nothing else in the level needs to know the arena has a size.
var _arena_edge := 7.0

## How far inside the rim a Blink is allowed to land. Enough that you arrive ON the platform
## rather than on its lip, where the next breath of knockback removes you anyway.
const BLINK_EDGE_MARGIN := 0.6

## The direction the last cast actually went out with, and which spell it was.
##
## Recorded for the harness alone. "Did it cast?" is easy to assert and answers half the
## question; drag-to-aim needs the other half - that the spell left along the line the thumb
## drew - and this is the one place every cast type passes through on its way to happening.
var _last_cast_dir := Vector3.ZERO
var _last_cast_id: StringName = &""


func _ready() -> void:
	# The character is handed its input source rather than reaching out for one, so a bot
	# or a network replay can be substituted without the character noticing.
	_player.input_controller = _input
	# ...and here is that substitution made good. The bot's fighter takes a BotController
	# where the human's takes a PlayerInputController, and player.gd holds not one line that
	# knows which of the two it got.
	_bot.input_controller = _brain
	_brain.body = _bot
	_brain.target = _player
	_wire_feel()
	_arena_edge = _arena_radius()
	_brain.arena_radius = _arena_edge
	# The stick is a dumb widget that reports where a thumb is; this single line is what
	# gives its output a meaning. Wiring it here rather than inside either node keeps the
	# stick reusable and keeps PlayerInputController unaware that a UI exists - the same
	# hand-it-its-dependencies pattern already used for the character above.
	_mobile.joystick.vector_changed.connect(_input.set_touch_vector)
	_wire_combat()
	# The HUD reads instability and nothing else. It is handed its sources here rather than
	# hunting for them, so a second fighter is one more line and not a rewrite.
	_hud.add_readout("YOU", _player.instability())
	_hud.add_readout("BOT", _bot.instability())
	_wire_rounds()
	_parse_harness_args()
	_rounds.start_match()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_respawn"):
		_rounds.begin_round()
	_update_aim_indicator()


## The platform's radius, read off the arena's own collision shape rather than typed in a
## second time. The bot needs to know where the edge is, and a copied number would go stale
## the first time the arena is resized - silently, and only for the bot.
func _arena_radius() -> float:
	var shape := get_node_or_null(^"Arena/Platform/Collision") as CollisionShape3D
	if shape != null:
		var cylinder := shape.shape as CylinderShape3D
		if cylinder != null:
			return cylinder.radius
	push_warning("arena radius not found; the bot is falling back to 7.0")
	return 7.0


func _parse_harness_args() -> void:
	# Settings first: --touch-test needs the stick already shown and laid out, and a suite
	# that reads a bot number must read the one the run asked for.
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-ui:on":
			_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
		elif arg == "--touch-ui:off":
			_mobile.visibility_mode = MobileControls.Visibility.HIDDEN
		elif arg == "--bot:off":
			_freeze_bot()
			print("[harness] bot parked")
		elif arg == "--feel:off":
			_quiet_feel()
		elif arg.begins_with("--bot-skill:"):
			# Twelve characters. Counted, not guessed - see ARCHITECTURE.md on --cast-at.
			_set_bot_skill(arg.substr(12))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--move="):
			var parts := arg.substr(7).split(",")
			if parts.size() == 2:
				var v := Vector2(float(parts[0]), float(parts[1]))
				_input.set_override_vector(v, true)
				print("[harness] steering override %s" % v)
		elif arg == "--trace":
			_trace = true
			_run_trace()
		elif arg == "--shot":
			_shoot("user://shot.png", 0.0)
		elif arg.begins_with("--shot:"):
			# Name from the raw argument, not int(seconds): --shot:1.05 and --shot:1.85 both
			# rounded to "shot_1.png" and silently overwrote each other, so a run that asked
			# for three frames quietly produced one.
			var label := arg.substr(7).replace(".", "_")
			_shoot("user://shot_%s.png" % label, float(arg.substr(7)))
		elif arg == "--touch-test":
			_run_touch_tests()
		elif arg == "--key-test":
			_run_key_tests()
		elif arg == "--cast-test":
			_run_cast_tests()
		elif arg == "--twothumb-test":
			_run_two_thumb_tests()
		elif arg == "--knockback-test":
			_run_knockback_tests()
		elif arg == "--round-test":
			_run_round_tests()
		elif arg == "--bot-test":
			_run_bot_tests()
		elif arg == "--spells-test":
			_run_spell_tests()
		elif arg == "--button-test":
			_run_button_tests()
		elif arg == "--aim-test":
			_run_aim_tests()
		elif arg == "--feel-test":
			_run_feel_tests()
		elif arg.begins_with("--aim-hold:"):
			# "--aim-hold:0,1,0" aims spell 0 to screen-right. Eleven characters in the
			# prefix, counted rather than guessed - see ARCHITECTURE.md on --cast-at.
			var held := arg.substr(11).split(",")
			if held.size() == 3:
				_hold_aim(int(held[0]), Vector2(float(held[1]), float(held[2])))
		elif arg == "--layout-probe":
			_probe_layout()
		elif arg.begins_with("--cast-at:"):
			# "--cast-at:1.5", or "--cast-at:1.5,1" for a slot other than the first. Ten
			# characters in the prefix; substr(9) yields ":1.5", which float() reads as 0.0
			# without complaining. That cost a session once - see ARCHITECTURE.md.
			var when := arg.substr(10).split(",")
			var slot := 0
			if when.size() > 1:
				slot = int(when[1])
			_cast_at(float(when[0]), slot)
		elif arg.begins_with("--stick-hold="):
			var hp := arg.substr(13).split(",")
			if hp.size() == 2:
				_hold_stick(Vector2(float(hp[0]), float(hp[1])))


## Parks the bot without unwiring it.
##
## Every suite written before the bot existed assumed the second fighter stood still: the
## cast suite fires down the -Z line and expects a hit, the knockback suite measures a slide
## with no steering in it, the round suite expects a body to stay where it was put. An
## opponent that dodges breaks all three for entirely correct reasons, which is the most
## expensive kind of test failure. They park it; --bot-test is where it gets to play.
func _freeze_bot() -> void:
	_brain.enabled = false


## Turns the game feel off for a suite that measures.
##
## The same shape as `_freeze_bot()` above and for the same reason: hitstop scales
## `Engine.time_scale`, so a slide measured over a fixed number of ticks comes out short and a
## cooldown read after a fixed wait comes out long. Both would be correct behaviour breaking a
## correct test, which is the most expensive kind of failure to read.
func _quiet_feel() -> void:
	_feel.enabled = false
	print("[harness] game feel parked")


func _set_bot_skill(level: String) -> void:
	match level.to_lower():
		"calm":
			_brain.skill = BotController.Skill.CALM
		"steady":
			_brain.skill = BotController.Skill.STEADY
		"sharp":
			_brain.skill = BotController.Skill.SHARP
		_:
			push_warning("unknown bot skill '%s'; leaving it alone" % level)
			return
	print("[harness] bot skill = %s" % level.to_upper())


func _run_trace() -> void:
	while _trace and is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(_player):
			return
		print("[trace] pos=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f)" % [
			_player.global_position.x, _player.global_position.y, _player.global_position.z,
			_player.velocity.x, _player.velocity.y, _player.velocity.z,
		])


func _shoot(path: String, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# The viewport texture only holds a complete frame after the draw pass, so grabbing it
	# any earlier returns the previous frame or an empty image.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("screenshot failed: %s" % err)
		return
	print("[shot] %s -> %s" % [path, ProjectSettings.globalize_path(path)])


# ---------------------------------------------------------------------------------------
# Touch harness
#
# Godot cannot be driven by a real finger from an automated session, so these inject
# InputEventScreenTouch/Drag directly. That is the only way to prove the things that
# actually matter about a two-thumb layout: that the stick claims exactly one finger, that
# a second finger cannot disturb it, and that a diagonal is not faster than a cardinal.
#
# Positions are in canvas units, which equal window pixels only at the 1280x720 design
# size, so run the touch tests at that resolution and the stretch transform stays identity.
# ---------------------------------------------------------------------------------------

var _touch_failures := 0


func _emit_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_dispatch(event)


func _emit_drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	_dispatch(event)


## Pushes an injected event through immediately.
##
## Godot buffers input by default (`use_accumulated_input`), so parse_input_event() alone
## leaves the event sitting in a queue for an unpredictable number of frames - which shows
## up as a test that passes or fails depending on how many frames it happened to wait, and
## sends you hunting for a bug in the code under test. Flushing makes the dispatch
## deterministic, which is the whole point of a scripted run.
func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Waits for the whole input pipeline to turn over.
##
## An injected event is flushed, read by PlayerInputController in _process, and acted on by
## the character in _physics_process. Two idle frames can straddle the flush and leave the
## command one frame behind the inputs that produced it - which looks exactly like a bug and
## is not one. Awaiting a physics frame between two idle frames covers every ordering.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _expect(label: String, passed: bool, detail: String) -> void:
	if not passed:
		_touch_failures += 1
	print("  [%s] %-44s %s" % ["PASS" if passed else "FAIL", label, detail])


func _run_touch_tests() -> void:
	await _settle()
	var stick := _mobile.joystick
	var centre := stick.get_global_rect().get_center()
	var radius: float = stick.base_radius
	print("[touch-test] viewport=%s stick centre=%s radius=%.0f" % [
		get_viewport().get_visible_rect().size, centre, radius])

	# --- claiming a finger -------------------------------------------------------------
	_emit_touch(0, centre, true)
	await _settle()
	_expect("press inside claims finger 0", stick.touch_index() == 0,
		"owner=%d" % stick.touch_index())

	# --- full right deflection ---------------------------------------------------------
	_emit_drag(0, centre + Vector2(radius, 0.0))
	await _settle()
	var right_cmd: Vector2 = _input.command.move_dir
	_expect("stick right -> value (1,0)", stick.value().is_equal_approx(Vector2(1.0, 0.0)),
		"value=%s" % stick.value())
	_expect("stick right -> world +X (screen-right)",
		right_cmd.x > 0.9 and absf(right_cmd.y) < 0.05, "move_dir=%s" % right_cmd)

	# --- a second finger must not disturb it -------------------------------------------
	var elsewhere := Vector2(get_viewport().get_visible_rect().size.x - 140.0, centre.y)
	_emit_touch(1, elsewhere, true)
	await _settle()
	_expect("second finger ignored (ownership)", stick.touch_index() == 0,
		"owner=%d" % stick.touch_index())
	_expect("second finger leaves value intact",
		stick.value().is_equal_approx(Vector2(1.0, 0.0)), "value=%s" % stick.value())

	_emit_drag(1, elsewhere + Vector2(0.0, -120.0))
	await _settle()
	_expect("foreign drag leaves value intact",
		stick.value().is_equal_approx(Vector2(1.0, 0.0)), "value=%s" % stick.value())

	_emit_touch(1, elsewhere, false)
	await _settle()
	_expect("foreign release does not free stick", stick.touch_index() == 0,
		"owner=%d value=%s" % [stick.touch_index(), stick.value()])

	# --- screen directions map to screen directions ------------------------------------
	_emit_drag(0, centre + Vector2(0.0, -radius))
	await _settle()
	var up_cmd: Vector2 = _input.command.move_dir
	_expect("stick up -> value (0,1)", stick.value().is_equal_approx(Vector2(0.0, 1.0)),
		"value=%s" % stick.value())
	# Screen-up is world -Z with this camera: the wizard walks away from the viewer.
	_expect("stick up -> world -Z (up the screen)",
		up_cmd.y < -0.9 and absf(up_cmd.x) < 0.05, "move_dir=%s" % up_cmd)

	_emit_drag(0, centre + Vector2(-radius, 0.0))
	await _settle()
	var left_cmd: Vector2 = _input.command.move_dir
	_expect("stick left -> world -X (screen-left)",
		left_cmd.x < -0.9 and absf(left_cmd.y) < 0.05, "move_dir=%s" % left_cmd)

	# --- diagonals must not be faster --------------------------------------------------
	_emit_drag(0, centre + Vector2(radius, -radius))
	await _settle()
	var diag: float = _input.command.move_dir.length()
	var cardinal: float = right_cmd.length()
	_expect("diagonal is not faster than cardinal", absf(diag - cardinal) < 0.02,
		"diagonal=%.4f cardinal=%.4f" % [diag, cardinal])
	_expect("diagonal magnitude clamped to 1.0", diag <= 1.0001, "len=%.4f" % diag)

	# --- deadzone ----------------------------------------------------------------------
	var inside_dead: float = _input.touch_deadzone * radius * 0.5
	_emit_drag(0, centre + Vector2(inside_dead, 0.0))
	await _settle()
	_expect("inside deadzone -> no movement",
		_input.command.move_dir.length() < 0.0001,
		"stick=%.3f move_dir=%.4f" % [stick.value().length(), _input.command.move_dir.length()])

	# Just outside the deadzone the output must ramp up from ~0, not jump to the deadzone
	# value. This is exactly what the rescaling in _shape_stick buys.
	var just_outside: float = (_input.touch_deadzone + 0.02) * radius
	_emit_drag(0, centre + Vector2(just_outside, 0.0))
	await _settle()
	var edge: float = _input.command.move_dir.length()
	_expect("just outside deadzone ramps from ~0", edge > 0.0 and edge < 0.06,
		"len=%.4f (a clipping deadzone would give ~%.2f)" % [edge, _input.touch_deadzone])

	# --- release -----------------------------------------------------------------------
	_emit_touch(0, centre + Vector2(just_outside, 0.0), false)
	await _settle()
	_expect("release frees the stick", stick.touch_index() == -1,
		"owner=%d" % stick.touch_index())
	_expect("release snaps value to centre", stick.value() == Vector2.ZERO,
		"value=%s" % stick.value())
	_expect("release stops the wizard", _input.command.move_dir.length() < 0.0001,
		"move_dir=%s" % _input.command.move_dir)
	_expect("controller reports no move input after release",
		not _input.command.has_move_input, "has_move_input=%s" % _input.command.has_move_input)

	print("[touch-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


func _emit_key(physical_keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	_dispatch(event)


## Proves the desktop path still reaches the character now that a stick shares the pipeline.
## Both feed the same InputCommand, so a regression here would mean the touch branch had
## started swallowing input that no finger was actually producing.
func _run_key_tests() -> void:
	await _settle()
	print("[key-test] keyboard through the same InputCommand pipeline")

	_emit_key(KEY_D, true)
	await _settle()
	var right: Vector2 = _input.command.move_dir
	_expect("D -> world +X (screen-right)", right.x > 0.9 and absf(right.y) < 0.05,
		"move_dir=%s" % right)
	_emit_key(KEY_D, false)
	await _settle()

	_emit_key(KEY_W, true)
	await _settle()
	var fwd: Vector2 = _input.command.move_dir
	_expect("W -> world -Z (up the screen)", fwd.y < -0.9 and absf(fwd.x) < 0.05,
		"move_dir=%s" % fwd)

	# Diagonal on the keyboard must obey the same circular clamp the stick does.
	_emit_key(KEY_D, true)
	await _settle()
	var diag: float = _input.command.move_dir.length()
	_expect("W+D diagonal is not faster", absf(diag - right.length()) < 0.02,
		"diagonal=%.4f cardinal=%.4f" % [diag, right.length()])

	_emit_key(KEY_W, false)
	_emit_key(KEY_D, false)
	await _settle()
	_expect("releasing keys stops the wizard", _input.command.move_dir.length() < 0.0001,
		"move_dir=%s" % _input.command.move_dir)

	# A finger on the stick must take priority over a held key, not fight it.
	var centre := _mobile.joystick.get_global_rect().get_center()
	_emit_key(KEY_A, true)
	await _settle()
	_emit_touch(0, centre, true)
	_emit_drag(0, centre + Vector2(_mobile.joystick.base_radius, 0.0))
	await _settle()
	var contested: Vector2 = _input.command.move_dir
	_expect("touch wins over a held key", contested.x > 0.9,
		"A held + stick right -> move_dir=%s" % contested)

	_emit_touch(0, centre, false)
	await _settle()
	var after: Vector2 = _input.command.move_dir
	_expect("keyboard resumes when the finger lifts", after.x < -0.9,
		"A still held -> move_dir=%s" % after)
	_emit_key(KEY_A, false)
	await _settle()

	print("[key-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Presses the stick and leaves it deflected, so a screenshot shows a live thumb rather
## than a stick at rest. Purely for looking at the thing; no assertions.
func _hold_stick(normalised: Vector2) -> void:
	await _settle()
	var stick := _mobile.joystick
	var centre := stick.get_global_rect().get_center()
	# Screen y is down, the stick convention is y-up, so flip to place the thumb.
	var offset := Vector2(normalised.x, -normalised.y) * stick.base_radius
	_emit_touch(0, centre, true)
	_emit_drag(0, centre + offset)
	print("[harness] holding stick at %s" % normalised)


## Prints where the stick actually landed, so anchor behaviour across screen shapes is
## measured rather than assumed. The numbers that must stay constant are the distances to
## the bottom-left corner; the viewport width is expected to change and the arena with it.
func _probe_layout() -> void:
	await _settle()
	var view := get_viewport().get_visible_rect().size
	var r := _mobile.joystick.get_global_rect()
	print("[layout] viewport=%.0fx%.0f aspect=%.2f | stick rect=%s | left_gap=%.1f bottom_gap=%.1f | visible=%s" % [
		view.x, view.y, view.x / view.y, r, r.position.x, view.y - r.end.y,
		_mobile.joystick.is_visible_in_tree()])
	get_tree().quit()


# ---------------------------------------------------------------------------------------
# Combat wiring
#
# The spellbook decides a cast MAY happen; this turns that into something in the world. The
# component cannot do it itself without knowing where the projectile pool lives, and the
# pool has no opinion about cooldowns. Joining them is the level's job, exactly like the
# joystick above.
#
# This is also the seam a server slots into: when casts become authoritative, the request is
# validated here (or refused) rather than anywhere inside the character.
# ---------------------------------------------------------------------------------------

func _wire_combat() -> void:
	# Every fighter's spellbook arrives at the same handler, so the bot's Fireball IS the
	# player's Fireball: same pool, same flight, same hit resolution, same knockback. A
	# separate path for the opponent would be a second set of rules to keep in step.
	var fighters: Array[Player] = [_player, _bot]
	for fighter in fighters:
		var spellbook := fighter.abilities()
		if spellbook == null:
			push_warning("%s has no AbilityComponent; it will never cast" % fighter.name)
			continue
		spellbook.cast_requested.connect(_on_cast_requested)
	_pool.projectile_hit.connect(_on_projectile_hit)
	# A button reports a press; the controller latches it; the character consumes it on the
	# next tick. Touch therefore takes the same route as the number keys, which is what stops
	# the two drifting apart - and it is why four buttons needed no new plumbing at all.
	for button in _mobile.buttons:
		# Press, drag, lift. The button says what the thumb did; the controller decides what
		# that means and latches the cast, exactly as the stick's vector is given meaning by
		# a single line up here rather than inside either node.
		button.aim_started.connect(_input.begin_aim)
		button.aim_moved.connect(_input.update_aim)
		button.cast_released.connect(_input.end_aim)
		# Read-only, for drawing the cooldown wedge and the spell's colour. The buttons belong
		# to the human, so they watch the human's spellbook.
		button.source = _player.abilities()


func _on_cast_requested(ability: Ability, origin: Vector3, direction: Vector3, caster: Node3D) -> void:
	if caster == _player:
		_last_cast_dir = direction
		_last_cast_id = ability.id
	_feel.cast(ability, caster == _player)
	match ability.cast_type:
		Ability.CastType.PROJECTILE:
			_pool.fire(ability, origin, direction, caster)
		Ability.CastType.CONE:
			_cast_cone(ability, direction, caster)
		Ability.CastType.DASH:
			_cast_dash(ability, direction, caster)
		Ability.CastType.BUFF:
			_cast_buff(ability, caster)
		_:
			# Nothing reaches here today. Kept so that a cast type added to the enum and
			# forgotten here is loud rather than silent - which is how the other three spent
			# a session doing nothing at all.
			push_warning("cast type %d has no runtime (%s)" % [ability.cast_type, ability.id])


## The projectile pool reports contact and stops there. Every hit in the game, from any
## source, goes through `_apply_hit` below.
func _on_projectile_hit(body: Node3D, direction: Vector3, ability: Ability) -> void:
	_apply_hit(body, direction, ability)


## Force Wave. Everything standing in the fan is hit on this frame, and thrown AWAY FROM THE
## CASTER rather than along the aim.
##
## That difference is the spell. A wave shoves what it touches outward, so catching someone at
## the shoulder of the cone throws them sideways off the rim - which is why it is the finisher
## and why it is worth walking into range for.
func _cast_cone(ability: Ability, direction: Vector3, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter != null:
		var flash := fighter.spell_flash()
		if flash != null:
			# The drawing takes its shape from the same two numbers the hit test uses, so the
			# fan on screen cannot disagree with the fan that hits.
			flash.play(ability.area, ability.cone_angle, ability.colour, direction)
	var space := get_world_3d().direct_space_state
	for body in ConeCast.targets(space, caster.global_position, direction, ability, caster):
		var push := body.global_position - caster.global_position
		push.y = 0.0
		if push.length_squared() < 0.0001:
			push = direction
		_apply_hit(body, push.normalized(), ability)


## Blink. The landing point is clamped INSIDE the arena here, in the level, because the level
## is the only thing that knows where the edge is - and a spell that could drop you in the
## void is a spell nobody would ever press.
func _cast_dash(ability: Ability, direction: Vector3, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter == null:
		return
	var from := fighter.global_position
	var landing := _blink_landing(fighter, direction, ability)
	fighter.blink_to(landing)
	_feel.dashed(from, landing, ability.colour)


## Where a dash from `fighter` along `direction` would put them, clamped to the arena.
##
## Pulled out of the cast so the AIM INDICATOR can ask the same question. A preview that drew
## the unclamped distance would promise a landing spot the cast then refuses to use, and the
## player would learn to distrust the only thing telling them where they are about to be.
func _blink_landing(fighter: Player, direction: Vector3, ability: Ability) -> Vector3:
	var landing := fighter.global_position + direction.normalized() * ability.dash_distance
	var flat := Vector2(landing.x, landing.z)
	var limit := maxf(_arena_edge - BLINK_EDGE_MARGIN, 0.5)
	if flat.length() > limit:
		flat = flat.normalized() * limit
	return Vector3(flat.x, fighter.global_position.y, flat.y)


## Arcane Shield. Reduction rather than blocking - see GAME_DESIGN.md for why blocking is the
## better long-term version and still not the one that ships.
func _cast_buff(ability: Ability, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter == null:
		return
	fighter.apply_shield(ability.duration, ability.knockback_resist)
	print("[buff] %s -> %s | %.0f%% of a hit gets through, for %.1fs" % [
		ability.id, fighter.name, ability.knockback_resist * 100.0, ability.duration])


## What a hit MEANS, for every source of one. A projectile arriving and a cone catching
## someone both end up here, so instability is raised in exactly one place and knockback is
## handed out in exactly one place.
##
## `direction` is the way the victim gets thrown: a projectile's travel direction, or the line
## out from the caster for a cone.
func _apply_hit(body: Node3D, direction: Vector3, ability: Ability) -> void:
	var fighter := body as Player
	if fighter == null:
		return

	# Instability is raised FIRST, and the knockback reads the new value. So a hit is
	# amplified by the destabilisation it just caused, which makes a landed combo escalate
	# instead of plateauing. The alternative - reading the value from before the hit - is
	# defensible and duller.
	var inst := fighter.instability()
	if inst != null:
		inst.add(ability.instability)
	var level := inst.current if inst != null else 0.0

	var impulse := Knockback.velocity(ability.knockback, direction, level, knockback_rules)
	fighter.apply_knockback(impulse)
	var shielded := " (shielded)" if fighter.is_shielded() else ""
	# What the victim ACTUALLY took, not what was thrown at them: the shield is applied inside
	# apply_knockback, and a hit somebody shrugged off has to feel like one.
	var landed := Vector2(fighter.knockback_velocity().x, fighter.knockback_velocity().z).length()
	_feel.hit(fighter.global_position, ability.colour, landed, fighter == _player)
	print("[hit] %s -> %s | instability %.0f%% | knockback %.1f m/s%s" % [
		ability.id, body.name, level, Vector2(impulse.x, impulse.z).length(), shielded])


# ---------------------------------------------------------------------------------------
# Game feel
#
# Handed its channels here rather than finding them, like everything else in this file. Every
# one of them is optional on the other side, so a scene missing the sparks node is a scene
# with no sparks - never a scene that fails to run.
# ---------------------------------------------------------------------------------------

func _wire_feel() -> void:
	_feel.camera = _camera_rig
	_feel.sounds = $Sounds as SoundBank
	_feel.sparks = $Sparks as ImpactBurst
	_feel.streak = $Streak as GroundStreak


# ---------------------------------------------------------------------------------------
# Aim indicator
#
# The fighter carries the drawing; the level decides what it says. That split is not tidiness
# - a dash preview has to stop where the arena does, and the arena's size is knowledge this
# node owns and the wizard deliberately does not.
#
# Driven every rendered frame rather than on a signal, because the thing being previewed
# moves: the wizard walks while aiming, and a preview refreshed only when the thumb moves
# would trail behind their own feet.
# ---------------------------------------------------------------------------------------

func _update_aim_indicator() -> void:
	var indicator := _player.aim_indicator()
	if indicator == null:
		return
	var slot := _input.command.aiming_slot
	var book := _player.abilities()
	if slot < 0 or book == null or _player.is_eliminated() or not _player.accepts_input:
		indicator.clear()
		return
	var ability := book.ability_in(slot)
	if ability == null:
		indicator.clear()
		return
	var aim := _preview_direction(book)
	indicator.show_for(ability, aim, _preview_reach(ability, aim))


## The direction a cast would go out with RIGHT NOW, decided exactly the way the cast decides
## it: the command's aim if there is one, and the caster's own facing if there is not.
##
## Asking AbilityComponent for the fallback rather than working it out again is the point. The
## two answers agreeing is then a property of there being one answer.
func _preview_direction(book: AbilityComponent) -> Vector3:
	var command := _input.command
	if command.has_aim and command.aim_dir.length_squared() > 0.0001:
		return Vector3(command.aim_dir.x, 0.0, command.aim_dir.y).normalized()
	return book.caster_facing().normalized()


## How far the preview should reach, which is not always how far the spell does.
##
## A dash stops where it will actually land. A projectile stops at the rim: Fireball flies
## 21.6m and the arena is 14m across, so an honest lane is a stripe across the whole screen,
## most of it over a void where there is nothing left to hit. The fan is NOT trimmed - a wave
## cast at the edge really does catch someone hanging over it, and shortening the drawing
## would be a lie about who gets hit.
func _preview_reach(ability: Ability, aim: Vector3) -> float:
	match ability.cast_type:
		Ability.CastType.DASH:
			var landing := _blink_landing(_player, aim, ability)
			var travel := landing - _player.global_position
			return Vector2(travel.x, travel.z).length()
		Ability.CastType.PROJECTILE:
			return minf(ability.effective_range(), _distance_to_rim(_player.global_position, aim))
		_:
			return ability.effective_range()


## Metres from `from` to the arena's rim along `aim`, on the ground plane.
##
## A ray against a circle, solved rather than stepped. `from` is assumed to be inside the
## arena, which makes the near root negative and the far one the answer; a wizard already
## over the void gets the clamp below rather than a square root of a negative number.
func _distance_to_rim(from: Vector3, aim: Vector3) -> float:
	var p := Vector2(from.x, from.z)
	var d := Vector2(aim.x, aim.z)
	if d.length_squared() < 0.0001:
		return _arena_edge
	d = d.normalized()
	var b := p.dot(d)
	var c := p.length_squared() - _arena_edge * _arena_edge
	var disc := b * b - c
	if disc <= 0.0:
		return _arena_edge
	return maxf(-b + sqrt(disc), 0.5)


# ---------------------------------------------------------------------------------------
# Round wiring
#
# The round system never learns what a KillZone is, and the KillZone never learns what a
# round is. One reports that a body left the world; the other decides that this means
# elimination. Joining them is the level's job, like every other seam here.
# ---------------------------------------------------------------------------------------

func _wire_rounds() -> void:
	_rounds.add_fighter(_player, spawn_point, "YOU")
	_rounds.add_fighter(_bot, bot_spawn, "BOT")
	_kill_zone.fighter_fell.connect(_rounds.report_fall)

	_rounds.round_started.connect(_on_round_started)
	_rounds.countdown_changed.connect(_on_countdown)
	_rounds.fighter_eliminated.connect(_on_eliminated)
	_rounds.round_ended.connect(_on_round_ended)
	_rounds.score_changed.connect(_hud.set_score)
	_rounds.match_ended.connect(_on_match_ended)


func _on_round_started(number: int) -> void:
	_kill_zone.clear()
	_hud.set_round(number)
	print("[round] %d start" % number)


func _on_countdown(remaining: int) -> void:
	_hud.set_banner("GO" if remaining <= 0 else str(remaining))
	_feel.countdown(remaining)
	if remaining <= 0:
		# Let "GO" sit for a beat, then clear it rather than leaving it over the fight.
		await get_tree().create_timer(0.6).timeout
		if _rounds.is_live():
			_hud.set_banner("")


func _on_eliminated(fighter: Player, title: String) -> void:
	# Read before `eliminate()` hides the body - which the round system has already done by
	# the time this fires, but the position it left behind is still the right place to mark.
	_feel.eliminated(fighter.global_position, fighter == _player)
	print("[round] %s eliminated" % title)


func _on_round_ended(winner: Player, title: String) -> void:
	if winner == null:
		_hud.set_banner("DRAW", Color(0.85, 0.85, 0.9))
		print("[round] draw")
		return
	# "YOU WINS" reads badly. main.gd owns these titles, so main.gd conjugates them.
	_hud.set_banner("YOU WIN" if title == "YOU" else "%s WINS" % title,
		Color(1.0, 0.85, 0.35))
	_feel.round_over(winner == _player)
	print("[round] %s wins the round" % title)


func _on_match_ended(_winner: Player, title: String) -> void:
	_hud.set_banner("YOU TAKE THE MATCH" if title == "YOU" else "%s TAKES THE MATCH" % title,
		Color(0.55, 1.0, 0.6))
	print("[round] %s takes the match" % title)


func _run_cast_tests() -> void:
	await _settle()
	_quiet_feel()
	# a moving target would make every flight assertion a coin toss.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var book := _player.abilities()
	var fireball := book.ability_in(0)
	print("[cast-test] %s: cooldown=%.2fs speed=%.0fm/s lifetime=%.2fs" % [
		fireball.id, fireball.cooldown, fireball.projectile_speed, fireball.lifetime])

	# --- the spellbook is data-driven ---------------------------------------------------
	_expect("slot 0 holds an Ability resource", fireball != null and fireball.id == &"fireball",
		"id=%s" % fireball.id)
	_expect("starts off cooldown", book.is_ready(0), "ready=%s" % book.is_ready(0))

	# --- pool starts prewarmed, nothing in flight ----------------------------------------
	var built_at_start := _pool.total_count()
	_expect("pool prewarmed, nothing in flight",
		_pool.active_count() == 0 and built_at_start > 0,
		"built=%d active=%d" % [built_at_start, _pool.active_count()])

	# --- a cast produces exactly one projectile ------------------------------------------
	var fired: bool = book.try_cast(0, Vector3(0, 0, -1))
	# One physics tick, NOT _settle(). _settle() straddles render frames, and on a machine
	# whose renderer is slower than its 60Hz physics a dozen ticks can turn over inside it -
	# by which time the spell has crossed the arena and the cooldown has visibly drained. The
	# suite then reports failures that are about the frame rate and not about the code (it
	# reported four of them here). Everything asserted below is gameplay state, so it waits
	# on the gameplay clock.
	await get_tree().physics_frame
	_expect("try_cast succeeded", fired, "returned %s" % fired)
	_expect("one projectile in flight", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())
	_expect("cast put the slot on cooldown", not book.is_ready(0),
		"remaining=%.2fs" % book.cooldown_remaining(0))
	_expect("cooldown fraction near 1.0 right after casting",
		book.cooldown_fraction(0) > 0.85, "fraction=%.2f" % book.cooldown_fraction(0))

	# --- a second cast during cooldown is refused ----------------------------------------
	var again: bool = book.try_cast(0, Vector3(0, 0, -1))
	_expect("second cast refused while on cooldown", not again, "returned %s" % again)
	_expect("refused cast spawned nothing", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())

	# --- it actually flies, in the aimed direction ---------------------------------------
	var shot: Projectile = null
	for child in _pool.get_children():
		if (child as Projectile).is_active():
			shot = child
			break
	var start_z: float = shot.global_position.z
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var moved: float = start_z - shot.global_position.z
	_expect("projectile travels along the aim (-Z)", moved > 0.1,
		"moved %.3fm in 3 ticks" % moved)

	# --- it hits the bot, and the pool takes it back -----------------------------------
	var hit_body: Array = []
	_pool.projectile_hit.connect(func(b, _d, _a): hit_body.append(b), CONNECT_ONE_SHOT)
	var waited := 0.0
	while _pool.active_count() > 0 and waited < 2.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	_expect("projectile reached the opponent", hit_body.size() == 1,
		"hits=%d after %.2fs" % [hit_body.size(), waited])
	_expect("pool reclaimed it", _pool.active_count() == 0,
		"active=%d" % _pool.active_count())
	_expect("the caster was not hit by its own spell",
		hit_body.size() == 1 and hit_body[0] != _player,
		"hit %s" % (hit_body[0].name if hit_body.size() > 0 else "<nothing>"))

	# --- cooldown expires and the slot comes back ----------------------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_expect("slot ready again after cooldown", book.is_ready(0),
		"fraction=%.2f" % book.cooldown_fraction(0))

	# --- reuse, not growth ----------------------------------------------------------------
	for i in 5:
		book.try_cast(0, Vector3(1, 0, 0))
		while not book.is_ready(0):
			await get_tree().physics_frame
		while _pool.active_count() > 0:
			await get_tree().physics_frame
	_expect("pool reuses instead of allocating", _pool.total_count() == built_at_start,
		"built %d at start, %d after 6 casts" % [built_at_start, _pool.total_count()])

	# --- the input latch turns one press into exactly one cast ----------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_input.request_ability(0)
	await _settle()
	_expect("a latched request casts once", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())
	await _settle()
	_expect("the latch does not re-fire", book.cooldown_remaining(0) > 0.0 and _pool.active_count() <= 1,
		"active=%d remaining=%.2f" % [_pool.active_count(), book.cooldown_remaining(0)])

	print("[cast-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## The test the whole ownership design exists for: a left thumb steering while a right thumb
## casts. Two controls, two finger indices, neither aware of the other. If this ever fails,
## the game is unplayable on a phone no matter how good everything else is.
func _run_two_thumb_tests() -> void:
	await _settle()
	_quiet_feel()
	# the wizard must move because the STICK moved it, nothing else.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var stick := _mobile.joystick
	var button := _mobile.buttons[0]
	var book := _player.abilities()
	var stick_centre := stick.get_global_rect().get_center()
	var button_centre := button.get_global_rect().get_center()
	print("[twothumb] stick=%s button=%s (gap %.0f units)" % [
		stick_centre, button_centre, stick_centre.distance_to(button_centre)])

	for i in _mobile.buttons.size():
		var other: AbilityButton = _mobile.buttons[i]
		_expect("stick and button %d do not overlap" % i,
			not stick.get_global_rect().grow(44.0).intersects(other.get_global_rect().grow(16.0)),
			"stick=%s button=%s" % [stick.get_global_rect(), other.get_global_rect()])
	# And no two spells share a finger. A cluster tight enough to thumb is a cluster tight
	# enough to mis-tap, and a mis-tapped Blink at the rim is a lost round.
	for i in _mobile.buttons.size():
		for j in range(i + 1, _mobile.buttons.size()):
			var a: AbilityButton = _mobile.buttons[i]
			var b: AbilityButton = _mobile.buttons[j]
			var gap: float = a.get_global_rect().get_center().distance_to(b.get_global_rect().get_center())
			var need: float = a.radius + a.activation_padding + b.radius + b.activation_padding
			_expect("buttons %d and %d cannot share a finger" % [i, j], gap >= need,
				"centres %.0f apart, need %.0f" % [gap, need])

	# --- left thumb takes the stick -------------------------------------------------------
	_emit_touch(0, stick_centre, true)
	_emit_drag(0, stick_centre + Vector2(stick.base_radius, 0.0))
	await _settle()
	_expect("finger 0 owns the stick", stick.touch_index() == 0,
		"stick owner=%d" % stick.touch_index())
	_expect("button untouched by the stick's finger", button.touch_index() == -1,
		"button owner=%d" % button.touch_index())
	var moving_before: Vector2 = _input.command.move_dir

	# --- right thumb taps the button, while the left is still down ------------------------
	var before_active := _pool.active_count()
	_emit_touch(1, button_centre, true)
	await _settle()
	_expect("finger 1 owns the button", button.touch_index() == 1,
		"button owner=%d" % button.touch_index())
	_expect("stick keeps its own finger", stick.touch_index() == 0,
		"stick owner=%d" % stick.touch_index())
	_expect("movement is unaffected by the aim",
		_input.command.move_dir.is_equal_approx(moving_before),
		"before=%s after=%s" % [moving_before, _input.command.move_dir])
	# The press opens an aim and casts nothing. That is drag-to-aim, not a regression -
	# --aim-test is where the whole gesture is asserted.
	_expect("the press only starts aiming", _pool.active_count() == before_active,
		"active %d -> %d" % [before_active, _pool.active_count()])

	# --- releasing the right thumb casts, and must not disturb the left -------------------
	_emit_touch(1, button_centre, false)
	await _settle()
	_expect("the lift actually cast", _pool.active_count() == before_active + 1,
		"active %d -> %d" % [before_active, _pool.active_count()])
	_expect("casting put the slot on cooldown", not book.is_ready(0),
		"remaining=%.2fs" % book.cooldown_remaining(0))
	_expect("button released cleanly", button.touch_index() == -1,
		"button owner=%d" % button.touch_index())
	_expect("stick still steering after the button lifted",
		stick.touch_index() == 0 and _input.command.move_dir.is_equal_approx(moving_before),
		"stick owner=%d move_dir=%s" % [stick.touch_index(), _input.command.move_dir])

	# --- and the wizard really is moving while all this happens ---------------------------
	var pos_before: Vector3 = _player.global_position
	for i in 10:
		await get_tree().physics_frame
	var travelled: float = _player.global_position.distance_to(pos_before)
	_expect("wizard moved while casting", travelled > 0.3,
		"travelled %.2fm in 10 ticks" % travelled)

	# --- left thumb lifts -----------------------------------------------------------------
	_emit_touch(0, stick_centre, false)
	await _settle()
	_expect("both controls idle after both fingers lift",
		stick.touch_index() == -1 and button.touch_index() == -1
			and _input.command.move_dir.length() < 0.0001,
		"stick=%d button=%d move_dir=%s" % [
			stick.touch_index(), button.touch_index(), _input.command.move_dir])

	# --- a finger landing on neither control disturbs nothing -----------------------------
	var empty_spot := get_viewport().get_visible_rect().size * 0.5
	_emit_touch(3, empty_spot, true)
	await _settle()
	_expect("a touch on empty screen claims nothing",
		stick.touch_index() == -1 and button.touch_index() == -1,
		"stick=%d button=%d" % [stick.touch_index(), button.touch_index()])
	_emit_touch(3, empty_spot, false)
	await _settle()

	print("[twothumb] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Casts a spell N seconds in, so a delayed --shot can catch it. It goes through the same
## latch a thumb does, so the screenshot shows what a player would have seen.
func _cast_at(seconds: float, slot: int) -> void:
	await get_tree().create_timer(seconds).timeout
	_input.request_ability(slot)


# ---------------------------------------------------------------------------------------
# Knockback harness
#
# The central mechanic, so it is checked by measurement rather than by feel. Two things must
# hold: the same hit at the same instability always carries the same distance, and that
# distance is the one the formula intends. Linear drag makes the second checkable in closed
# form - v squared over 2f - which is exactly why the drag is linear.
# ---------------------------------------------------------------------------------------

## Hits the bot with a known speed and returns how far it slid on the ground plane.
func _measure_slide(speed: float, instability: float) -> float:
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame
	var start := _bot.global_position
	var impulse := Knockback.velocity(speed, Vector3(0, 0, -1), instability, knockback_rules)
	_bot.apply_knockback(impulse)
	var guard := 0
	while _bot.knockback_velocity().length() > 0.001 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	var moved := _bot.global_position - start
	return Vector2(moved.x, moved.z).length()


func _run_knockback_tests() -> void:
	await _settle()
	_quiet_feel()
	# a slide with steering in it measures the bot, not the formula.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var rules := knockback_rules
	print("[knockback] rules: base=%.1f per100=%.1f max=%.1f lift=%.1f | bot friction=%.1f" % [
		rules.base_multiplier, rules.per_100_instability, rules.max_multiplier, rules.lift,
		_bot.knockback_friction])

	# --- the curve is pure arithmetic, check it directly ---------------------------------
	_expect("multiplier at 0% is 1.0",
		is_equal_approx(Knockback.multiplier(0.0, rules), 1.0),
		"%.3f" % Knockback.multiplier(0.0, rules))
	_expect("multiplier at 100% is 2.0",
		is_equal_approx(Knockback.multiplier(100.0, rules), 2.0),
		"%.3f" % Knockback.multiplier(100.0, rules))
	_expect("multiplier at 150% is 2.5",
		is_equal_approx(Knockback.multiplier(150.0, rules), 2.5),
		"%.3f" % Knockback.multiplier(150.0, rules))
	_expect("multiplier is capped",
		is_equal_approx(Knockback.multiplier(9999.0, rules), rules.max_multiplier),
		"%.3f" % Knockback.multiplier(9999.0, rules))

	# --- direction: you are thrown the way the spell was travelling ----------------------
	var dir_impulse := Knockback.velocity(6.0, Vector3(0, 0, -1), 0.0, rules)
	_expect("thrown along the spell's line", dir_impulse.z < -5.9 and absf(dir_impulse.x) < 0.01,
		"impulse=%s" % dir_impulse)
	_expect("a hit adds lift", is_equal_approx(dir_impulse.y, rules.lift),
		"y=%.2f" % dir_impulse.y)

	# --- measured slide matches the closed form ------------------------------------------
	var base_speed := 6.0
	var predicted := Knockback.slide_distance(base_speed, _bot.knockback_friction)
	var measured := await _measure_slide(base_speed, 0.0)
	_expect("slide at 0% matches v^2/2f",
		absf(measured - predicted) / predicted < 0.15,
		"predicted %.2fm, measured %.2fm" % [predicted, measured])

	# --- the same hit twice carries the same distance ------------------------------------
	var again := await _measure_slide(base_speed, 0.0)
	_expect("identical hits carry identical distance",
		absf(again - measured) < 0.02, "%.4fm then %.4fm" % [measured, again])

	# --- instability escalates it, quadratically -----------------------------------------
	# Speed scales by the multiplier, and distance goes as speed squared, so 50% instability
	# (1.5x speed) must carry 2.25x as far. That relationship is the whole tension curve.
	var at50 := await _measure_slide(base_speed, 50.0)
	var ratio := at50 / measured
	_expect("50% instability carries ~2.25x as far", absf(ratio - 2.25) < 0.25,
		"%.2fm vs %.2fm = %.2fx" % [at50, measured, ratio])

	# --- and eventually it throws you off ------------------------------------------------
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame
	var hard := Knockback.velocity(base_speed, Vector3(0, 0, -1), 200.0, knockback_rules)
	_bot.apply_knockback(hard)
	var left_arena := false
	for i in 240:
		await get_tree().physics_frame
		var p := _bot.global_position
		if Vector2(p.x, p.z).length() > 7.2 or p.y < 0.0:
			left_arena = true
			break
	_expect("a hit at 200% throws the target off the arena", left_arena,
		"ended at %s" % _bot.global_position)
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame

	# --- instability accumulates, and a respawn clears it ---------------------------------
	var inst := _bot.instability()
	_expect("the target starts stable", is_equal_approx(inst.current, 0.0), "%.1f%%" % inst.current)
	inst.add(12.0)
	inst.add(12.0)
	_expect("instability accumulates", is_equal_approx(inst.current, 24.0),
		"%.1f%%" % inst.current)
	_bot.respawn_at(bot_spawn)
	_expect("respawn resets instability", is_equal_approx(inst.current, 0.0),
		"%.1f%%" % inst.current)

	# --- hitstun exists and expires ------------------------------------------------------
	_bot.apply_knockback(Knockback.velocity(base_speed, Vector3(0, 0, -1), 0.0, rules))
	_expect("a hit causes hitstun", _bot.is_in_hitstun(), "in hitstun=%s" % _bot.is_in_hitstun())
	var waited := 0
	while _bot.is_in_hitstun() and waited < 300:
		await get_tree().physics_frame
		waited += 1
	_expect("hitstun expires", not _bot.is_in_hitstun(), "after %d ticks" % waited)

	# --- end to end: a real Fireball raises instability and moves the target --------------
	_bot.respawn_at(bot_spawn)
	_player.respawn_at(spawn_point)
	for i in 20:
		await get_tree().physics_frame
	var before_pos := _bot.global_position
	_player.abilities().try_cast(0, Vector3(0, 0, -1))
	var hit_seen := false
	for i in 120:
		await get_tree().physics_frame
		if _bot.instability().current > 0.0:
			hit_seen = true
			break
	_expect("a cast Fireball raises the target's instability", hit_seen,
		"instability=%.1f%%" % _bot.instability().current)
	for i in 60:
		await get_tree().physics_frame
	var shifted := (_bot.global_position - before_pos)
	_expect("and pushes it away from the caster", shifted.z < -0.3,
		"moved %.2fm along z" % shifted.z)

	print("[knockback] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Waits until the round is actually live. The countdown freezes input, so a test that
## steers or casts before this returns is measuring a fighter that has been told to stand
## still - which looks exactly like a broken control and is not one.
func _wait_for_live() -> void:
	var guard := 0
	while not _rounds.is_live() and guard < 1200:
		await get_tree().process_frame
		guard += 1


func _run_round_tests() -> void:
	await _settle()
	_quiet_feel()
	# a fighter that walks off on its own would end the round early.
	_freeze_bot()
	print("[round-test] countdown=%.1fs interlude=%.1fs wins_needed=%d" % [
		_rounds.countdown_seconds, _rounds.interlude_seconds, _rounds.wins_needed])

	# --- a match opens in countdown, with everyone frozen ---------------------------------
	_expect("match opens in countdown", _rounds.state == RoundManager.State.COUNTDOWN,
		"state=%d" % _rounds.state)
	_expect("fighters are frozen during the countdown",
		not _player.accepts_input and not _bot.accepts_input,
		"player=%s bot=%s" % [_player.accepts_input, _bot.accepts_input])
	_expect("round 1", _rounds.round_number == 1, "round=%d" % _rounds.round_number)
	_expect("score starts level", _rounds.wins_for("YOU") == 0 and _rounds.wins_for("BOT") == 0,
		"%s" % str(_rounds.scores()))

	# --- steering really is ignored while frozen ------------------------------------------
	_input.set_override_vector(Vector2(1, 0), true)
	var frozen_at := _player.global_position
	for i in 15:
		await get_tree().physics_frame
	var drift := Vector2(_player.global_position.x - frozen_at.x,
		_player.global_position.z - frozen_at.z).length()
	_expect("a frozen fighter does not move", drift < 0.05, "drifted %.3fm" % drift)

	# --- it goes live ---------------------------------------------------------------------
	await _wait_for_live()
	_expect("round goes live after the countdown", _rounds.is_live(), "state=%d" % _rounds.state)
	_expect("input is returned on go", _player.accepts_input and _bot.accepts_input,
		"player=%s bot=%s" % [_player.accepts_input, _bot.accepts_input])

	var live_at := _player.global_position
	for i in 15:
		await get_tree().physics_frame
	var moved := Vector2(_player.global_position.x - live_at.x,
		_player.global_position.z - live_at.z).length()
	_expect("and the fighter can move again", moved > 0.5, "moved %.2fm" % moved)
	_input.set_override_vector(Vector2.ZERO, false)

	# --- knock the bot off and check the whole cascade -----------------------------------
	_expect("two fighters standing", _rounds.alive_count() == 2,
		"alive=%d" % _rounds.alive_count())
	_bot.apply_knockback(Vector3(0, 4, -40))
	var guard := 0
	while _rounds.alive_count() > 1 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	_expect("the faller is eliminated", _bot.is_eliminated(),
		"eliminated=%s pos=%s" % [_bot.is_eliminated(), _bot.global_position])
	_expect("an eliminated fighter is hidden", not _bot.visible, "visible=%s" % _bot.visible)
	_expect("round ends when one is left", _rounds.state == RoundManager.State.OVER,
		"state=%d" % _rounds.state)
	_expect("the survivor scores", _rounds.wins_for("YOU") == 1,
		"scores=%s" % str(_rounds.scores()))
	_expect("the faller does not", _rounds.wins_for("BOT") == 0,
		"scores=%s" % str(_rounds.scores()))

	# --- and it all resets -----------------------------------------------------------------
	_player.instability().add(40.0)
	var guard2 := 0
	while _rounds.round_number < 2 and guard2 < 1200:
		await get_tree().process_frame
		guard2 += 1
	_expect("a new round begins", _rounds.round_number == 2, "round=%d" % _rounds.round_number)
	_expect("the eliminated fighter is back", not _bot.is_eliminated() and _bot.visible,
		"eliminated=%s visible=%s" % [_bot.is_eliminated(), _bot.visible])
	_expect("both are standing again", _rounds.alive_count() == 2,
		"alive=%d" % _rounds.alive_count())
	_expect("instability is cleared on reset",
		is_equal_approx(_player.instability().current, 0.0),
		"player=%.1f%%" % _player.instability().current)
	_expect("fighters are back at their spawns",
		_bot.global_position.distance_to(bot_spawn) < 0.5,
		"bot at %s, spawn %s" % [_bot.global_position, bot_spawn])
	_expect("the score carries across rounds", _rounds.wins_for("YOU") == 1,
		"scores=%s" % str(_rounds.scores()))
	_expect("the new round starts frozen again",
		_rounds.state == RoundManager.State.COUNTDOWN, "state=%d" % _rounds.state)

	# --- a fall outside a live round is ignored --------------------------------------------
	var before := _rounds.alive_count()
	_rounds.report_fall(_bot)
	_expect("a fall during the countdown is ignored", _rounds.alive_count() == before,
		"alive %d -> %d" % [before, _rounds.alive_count()])

	# --- the match ends when someone reaches the target ------------------------------------
	# The real 3s countdown and 2s interlude have already been verified above. Shorten them
	# now so proving the match-end condition does not cost thirty seconds of wall clock.
	_rounds.countdown_seconds = 0.15
	_rounds.interlude_seconds = 0.15
	await _wait_for_live()
	# An Array, not a bool. GDScript lambdas capture local variables BY VALUE, so
	# `matched = true` inside the closure would write to a copy and the outer variable would
	# stay false forever. Arrays are reference types, so appending is visible outside.
	var matched: Array = []
	_rounds.match_ended.connect(func(_w, _t): matched.append(true), CONNECT_ONE_SHOT)
	var safety := 0
	# Exit on the signal, not on the score: start_match() zeroes the wins the moment the
	# match is won, so a score-based condition would never see the target reached.
	while matched.is_empty() and safety < 40:
		await _wait_for_live()
		_rounds.report_fall(_bot)
		var g := 0
		while _rounds.state != RoundManager.State.COUNTDOWN and g < 1200:
			await get_tree().process_frame
			g += 1
		safety += 1
	_expect("reaching the target ends the match", not matched.is_empty(),
		"wins=%d needed=%d" % [_rounds.wins_for("YOU"), _rounds.wins_needed])

	print("[round-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Bot harness
#
# The bot is the first thing in this project that PLAYS the game, so it is judged the way a
# player would be: does it hold its distance, does it point at what it is shooting at, does
# it stay on the arena, does difficulty change anything, and does it cheat. Almost none of
# this reads the bot's internals - the assertions read the same InputCommand the fighter
# reads and the same positions a screenshot would show, so a bot rewritten from scratch
# would still have to pass them.
# ---------------------------------------------------------------------------------------

## Puts both fighters where a test wants them and holds them there while the bot notices.
##
## Pinned every tick, not placed once. The bot's reaction time is a real delay, so a reading
## taken on the frame after a teleport is its memory of the PREVIOUS arrangement - which
## looks exactly like a broken bot and is not one. Holding them still also means the answer
## is about the arrangement that was asked for, and not about wherever the two of them had
## walked to by the time the reading was taken.
func _place_fighters(bot_at: Vector3, player_at: Vector3) -> void:
	await _wait_for_live()
	var settled := 0.0
	while settled < 0.75:
		_bot.respawn_at(bot_at)
		_player.respawn_at(player_at)
		await get_tree().physics_frame
		settled += 1.0 / 60.0


## Distance from the centre of the arena, on the ground plane.
func _radius_of(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


## Metres between the two fighters, on the ground plane.
func _gap() -> float:
	return Vector2(_bot.global_position.x - _player.global_position.x,
		_bot.global_position.z - _player.global_position.z).length()


## Unit vector from the bot to the player: what a perfect aim would be.
func _true_aim() -> Vector2:
	var offset := Vector2(_player.global_position.x - _bot.global_position.x,
		_player.global_position.z - _bot.global_position.z)
	if offset.length_squared() < 0.0001:
		return Vector2.ZERO
	return offset.normalized()


## Which way a fighter's wizard is actually pointing. Same convention as player.gd's facing:
## yaw 0 looks down -Z, so a yaw of `a` looks along (-sin a, -cos a).
func _facing_of(fighter: Player) -> Vector2:
	var visual := fighter.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return Vector2.ZERO
	return Vector2(-sin(visual.rotation.y), -cos(visual.rotation.y))


func _run_bot_tests() -> void:
	await _settle()
	_quiet_feel()
	# The bot rolls its aim error and its strafe timing. A suite that fails one run in ten is
	# worse than no suite at all, so the random stream is pinned for the duration.
	_brain.reseed(20260823)
	# The human stands still throughout: a zero override beats both the keyboard and the
	# stick, so nothing that happens to be held can wander the player into a measurement.
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var budget: float = float(BotController.PROFILES[_brain.skill]["aim_error"]) + 8.0
	print("[bot-test] skill=%d reaction=%.2fs aim_error=%.1fdeg safe=%.2fm of %.2fm" % [
		_brain.skill,
		float(BotController.PROFILES[_brain.skill]["reaction"]),
		float(BotController.PROFILES[_brain.skill]["aim_error"]),
		_brain.safe_radius(), _brain.arena_radius])

	# --- one seam, two drivers -----------------------------------------------------------
	_expect("both fighters are driven through the same seam",
		_player.input_controller is PlayerInputController
			and _bot.input_controller is PlayerInputController
			and _player.input_controller != _bot.input_controller,
		"player=%s bot=%s" % [_player.input_controller, _bot.input_controller])
	_expect("the bot drives the fighter it was handed",
		_brain.body == _bot and _brain.target == _player,
		"body=%s target=%s" % [_brain.body, _brain.target])
	_expect("the arena radius is read off the arena, not typed in",
		get_node_or_null(^"Arena/Platform/Collision") != null
			and is_equal_approx(_brain.arena_radius, 7.0),
		"radius=%.2fm" % _brain.arena_radius)

	# --- and no device can reach it -------------------------------------------------------
	# A key that a device-polling controller would obey. The bot inherits exactly such a
	# controller and overrides its _process to nothing; this is that override, asserted. With
	# move_left held down, the bot must still walk towards a target that is to its RIGHT.
	Input.action_press("move_left")
	await _place_fighters(Vector3(-4.0, 1.2, 0.0), Vector3(4.5, 1.2, 0.0))
	var keyed: Vector2 = _brain.command.move_dir
	Input.action_release("move_left")
	_expect("a held key cannot steer the bot", keyed.dot(Vector2(1.0, 0.0)) > 0.3,
		"move_left held, bot asked for %s" % keyed)

	# --- keeping its distance -------------------------------------------------------------
	_expect("too far away: it closes in", keyed.dot(Vector2(1.0, 0.0)) > 0.3,
		"gap %.1fm -> %s" % [_gap(), keyed])

	await _place_fighters(Vector3(0.0, 1.2, 0.0), Vector3(1.6, 1.2, 0.0))
	_expect("too close: it backs off", _brain.command.move_dir.dot(Vector2(-1.0, 0.0)) > 0.3,
		"gap %.1fm -> %s" % [_gap(), _brain.command.move_dir])

	var half := _brain.preferred_range * 0.5
	await _place_fighters(Vector3(-half, 1.2, 0.0), Vector3(half, 1.2, 0.0))
	_expect("at its preferred range it circles instead of charging",
		absf(_brain.command.move_dir.dot(Vector2(1.0, 0.0))) < 0.25,
		"gap %.1fm -> %s" % [_gap(), _brain.command.move_dir])

	# --- aiming at what it is shooting at ---------------------------------------------------
	var aim: Vector2 = _brain.command.aim_dir
	var wanted := _true_aim()
	_expect("it always has an aim", _brain.command.has_aim and aim.length() > 0.99,
		"has_aim=%s aim=%s" % [_brain.command.has_aim, aim])
	var aim_off := rad_to_deg(absf(aim.angle_to(wanted)))
	_expect("the aim lands inside the skill's error budget", aim_off <= budget,
		"%.1f degrees off, budget %.1f" % [aim_off, budget])
	# move_dir and aim_dir have been separate fields since Session 3 with nothing to prove
	# it. This is the first thing in the project that fills them differently.
	_expect("it aims where it is not walking",
		absf(aim.dot(_brain.command.move_dir)) < 0.5,
		"aim=%s move=%s" % [aim, _brain.command.move_dir])
	var face_off := rad_to_deg(absf(_facing_of(_bot).angle_to(wanted)))
	_expect("and the wizard is turned to face it", face_off <= budget,
		"%.1f degrees off, budget %.1f" % [face_off, budget])

	# --- it will not walk off ---------------------------------------------------------------
	# Standing past its own safe line, with the target luring it further out. From here the
	# one rule it may never break is asking to move outward.
	await _place_fighters(Vector3(_brain.safe_radius() + 0.5, 1.2, 0.0), Vector3(9.0, 1.2, 0.0))
	var outward := Vector2(1.0, 0.0)
	_expect("past the safe line it never asks to go further out",
		_brain.command.move_dir.dot(outward) <= 0.001,
		"at %.2fm (safe %.2fm) -> %s" % [
			_radius_of(_bot.global_position), _brain.safe_radius(), _brain.command.move_dir])
	_expect("it heads back towards the centre",
		_brain.command.move_dir.dot(-outward) > 0.3, "move=%s" % _brain.command.move_dir)

	# Now let it run, with the lure still sitting off the rim. Being thrown off the arena is
	# the game; walking off it is a bug.
	var lure := Vector3(8.5, 1.2, 0.0)
	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 6.0:
		_player.respawn_at(lure)
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		# The first stretch is the walk back in from the placement above, which is the bot
		# obeying the rule rather than breaking it.
		if elapsed > 1.2:
			worst = maxf(worst, _radius_of(_bot.global_position))
	_expect("chasing a target off the arena, it stays on the arena",
		worst <= _brain.safe_radius() + 0.35,
		"reached %.2fm, safe line %.2fm, rim %.2fm" % [
			worst, _brain.safe_radius(), _brain.arena_radius])
	_expect("and is still standing", not _bot.is_eliminated(),
		"eliminated=%s at %s" % [_bot.is_eliminated(), _bot.global_position])

	# --- and it actually fights ---------------------------------------------------------------
	var post := Vector3(0.0, 1.2, 0.0)
	await _place_fighters(Vector3(0.0, 1.2, -_brain.preferred_range), post)
	# Arrays, not counters. A GDScript lambda captures a local by VALUE, so an int would be
	# incremented inside the closure and stay zero outside it - see ARCHITECTURE.md.
	var casts: Array = []
	var landed: Array = []
	var on_cast := func(_slot: int, _ability: Ability) -> void:
		casts.append(1)
	var on_hit := func(body: Node3D, _direction: Vector3, _ability: Ability) -> void:
		if body == _player:
			landed.append(1)
	_bot.abilities().cast_performed.connect(on_cast)
	_pool.projectile_hit.connect(on_hit)
	var fighting := 0.0
	while fighting < 5.0:
		_player.respawn_at(post)
		await get_tree().physics_frame
		fighting += 1.0 / 60.0
	_bot.abilities().cast_performed.disconnect(on_cast)
	_pool.projectile_hit.disconnect(on_hit)
	_expect("it uses its spell unprompted", casts.size() >= 2, "%d casts in 5s" % casts.size())
	_expect("and lands them on a stationary target", landed.size() >= 1,
		"%d of %d casts hit" % [landed.size(), casts.size()])

	# --- difficulty is real, and it is not a stat bonus ----------------------------------------
	var calm: Dictionary = BotController.PROFILES[BotController.Skill.CALM]
	var sharp: Dictionary = BotController.PROFILES[BotController.Skill.SHARP]
	_expect("a sharper bot reacts sooner", float(sharp["reaction"]) < float(calm["reaction"]),
		"sharp %.2fs vs calm %.2fs" % [float(sharp["reaction"]), float(calm["reaction"])])
	_expect("a sharper bot aims truer", float(sharp["aim_error"]) < float(calm["aim_error"]),
		"sharp %.1fdeg vs calm %.1fdeg" % [float(sharp["aim_error"]), float(calm["aim_error"])])
	_expect("a sharper bot shoots more often", float(sharp["cast_gap"]) < float(calm["cast_gap"]),
		"sharp %.2fs vs calm %.2fs" % [float(sharp["cast_gap"]), float(calm["cast_gap"])])
	_expect("a sharper bot respects the edge more",
		float(sharp["edge_margin"]) > float(calm["edge_margin"]),
		"sharp %.2fm vs calm %.2fm" % [float(sharp["edge_margin"]), float(calm["edge_margin"])])

	var was := _brain.skill
	_brain.skill = BotController.Skill.CALM
	var calm_line := _brain.safe_radius()
	_brain.skill = BotController.Skill.SHARP
	var sharp_line := _brain.safe_radius()
	_brain.skill = was
	_expect("changing difficulty takes effect at once", sharp_line < calm_line,
		"safe radius: calm %.2fm, sharp %.2fm" % [calm_line, sharp_line])

	# The assertion the whole difficulty design exists for. A bot that cheated on speed, on
	# how far a hit throws it, or on which spell it carries would be teaching the player
	# about a game nobody else is playing.
	_expect("the bot fights with the player's numbers",
		is_equal_approx(_bot.move_speed, _player.move_speed)
			and is_equal_approx(_bot.knockback_friction, _player.knockback_friction)
			and is_equal_approx(_bot.hitstun_per_speed, _player.hitstun_per_speed),
		"speed %.1f/%.1f friction %.1f/%.1f" % [
			_bot.move_speed, _player.move_speed,
			_bot.knockback_friction, _player.knockback_friction])
	_expect("and with the player's spell",
		_bot.abilities().ability_in(0) == _player.abilities().ability_in(0),
		"%s vs %s" % [_bot.abilities().ability_in(0).id, _player.abilities().ability_in(0).id])

	# --- a countdown freezes it, with nothing queued up behind the freeze -----------------------
	_rounds.begin_round()
	await _settle()
	var parked := _bot.global_position
	for i in 20:
		await get_tree().physics_frame
	var drift := Vector2(_bot.global_position.x - parked.x,
		_bot.global_position.z - parked.z).length()
	_expect("a frozen bot does not steer", drift < 0.05, "drifted %.3fm" % drift)
	_expect("and holds no cast behind the countdown", _brain.command.ability_pressed == -1,
		"latched slot %d" % _brain.command.ability_pressed)
	_input.set_override_vector(Vector2.ZERO, false)

	print("[bot-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Spell harness
#
# Three of the four spells do not throw a projectile, so nothing about them can be watched
# flying across the arena. Force Wave hits on the frame it is cast, Blink moves the caster
# between one tick and the next, and Arcane Shield is a number that changes what a LATER hit
# does. Each of those is easy to write and easy to get silently wrong, which is exactly the
# shape of thing that needs measuring rather than playing.
# ---------------------------------------------------------------------------------------

## First slot holding a spell of the given type, or -1. The suite finds spells the way the
## bot does, by what they ARE, so re-ordering the spellbook cannot quietly re-point a test.
func _slot_with(book: AbilityComponent, cast_type: Ability.CastType) -> int:
	for slot in book.slot_count():
		var ability := book.ability_in(slot)
		if ability != null and ability.cast_type == cast_type:
			return slot
	return -1


## Flat displacement of the bot over `seconds`, starting now.
func _drift_of(fighter: Player, seconds: float) -> Vector2:
	var from := fighter.global_position
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	return Vector2(fighter.global_position.x - from.x, fighter.global_position.z - from.z)


func _run_spell_tests() -> void:
	await _settle()
	_quiet_feel()
	# The suite casts AT the bot and measures where it ends up, so it must not steer.
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()

	var book := _player.abilities()
	var target := _bot.instability()
	var fireball := _slot_with(book, Ability.CastType.PROJECTILE)
	var cone := _slot_with(book, Ability.CastType.CONE)
	var dash := _slot_with(book, Ability.CastType.DASH)
	var buff := _slot_with(book, Ability.CastType.BUFF)
	print("[spells] slots: projectile=%d cone=%d dash=%d buff=%d of %d" % [
		fireball, cone, dash, buff, book.slot_count()])

	# --- the loadout ---------------------------------------------------------------------
	_expect("the wizard carries four spells", book.slot_count() == 4,
		"%d slots" % book.slot_count())
	_expect("one of each cast type, and all four found",
		fireball >= 0 and cone >= 0 and dash >= 0 and buff >= 0,
		"projectile=%d cone=%d dash=%d buff=%d" % [fireball, cone, dash, buff])
	_expect("the keyboard can reach every slot",
		InputMap.has_action("cast_1") and InputMap.has_action("cast_2")
			and InputMap.has_action("cast_3") and InputMap.has_action("cast_4"),
		"cast_1..4 in the input map")

	var wave := book.ability_in(cone)
	var jump := book.ability_in(dash)
	var shield := book.ability_in(buff)

	# --- Force Wave: it hits what is in the fan --------------------------------------------
	# The bot is put two and a half metres along +X, and the wave is aimed the same way.
	await _place_fighters(Vector3(2.5, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	var before: float = target.current
	var cone_fired: bool = book.try_cast(cone, Vector3(1, 0, 0))
	_expect("Force Wave was ready", cone_fired, "try_cast returned %s" % cone_fired)
	await get_tree().physics_frame
	_expect("a target inside the fan is hit",
		is_equal_approx(target.current - before, wave.instability),
		"instability %.0f%% -> %.0f%%, spell adds %.0f" % [before, target.current, wave.instability])
	var pushed := await _drift_of(_bot, 0.35)
	_expect("and is thrown away from the caster", pushed.x > 1.0 and absf(pushed.y) < 0.6,
		"moved %s" % pushed)
	_expect("Force Wave hits harder than Fireball", wave.knockback > book.ability_in(fireball).knockback,
		"%.1f vs %.1f" % [wave.knockback, book.ability_in(fireball).knockback])

	# --- ...and misses what is not ----------------------------------------------------------
	# Out of range: the same aim, half again as far as the fan is long.
	await _place_fighters(Vector3(wave.area * 1.5, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	before = target.current
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	_expect("a target beyond the fan's reach is missed",
		is_equal_approx(target.current, before),
		"at %.1fm, reach %.1fm, instability %.0f%%" % [wave.area * 1.5, wave.area, target.current])

	# Out of angle: well inside the reach, but off to the side of where the wave was aimed.
	await _place_fighters(Vector3(0.0, 1.2, -2.5), Vector3(0.0, 1.2, 0.0))
	book.reset()
	before = target.current
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	_expect("a target beside the fan is missed", is_equal_approx(target.current, before),
		"90 degrees off a %.0f degree half-angle, instability %.0f%%" % [wave.cone_angle, target.current])

	# The push follows the line out from the caster, not the line the wave was aimed along.
	# That is the whole reason Force Wave is a finisher: standing at the shoulder of the fan
	# throws you sideways, which near a rim is off it.
	await _place_fighters(Vector3(2.0, 1.2, -1.6), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var shoved := await _drift_of(_bot, 0.35)
	_expect("the push is away from the caster, not along the aim",
		shoved.y < -0.4 and shoved.x > 0.4,
		"target sat up and left of the aim; it moved %s" % shoved)

	# --- Blink: it moves you, exactly as far as it says --------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	var from := _player.global_position
	var dash_fired: bool = book.try_cast(dash, Vector3(1, 0, 0))
	_expect("Blink was ready", dash_fired, "try_cast returned %s" % dash_fired)
	await get_tree().physics_frame
	var jumped := Vector2(_player.global_position.x - from.x, _player.global_position.z - from.z)
	_expect("Blink moves the caster its full distance",
		absf(jumped.x - jump.dash_distance) < 0.2 and absf(jumped.y) < 0.2,
		"moved %s, spell says %.1fm" % [jumped, jump.dash_distance])
	_expect("and put itself on cooldown", not book.is_ready(dash),
		"remaining %.2fs" % book.cooldown_remaining(dash))

	# --- ...and never into the void -----------------------------------------------------------
	var rim := _arena_radius() - 0.4
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(rim, 1.2, 0.0))
	book.reset()
	book.try_cast(dash, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var landed := _radius_of(_player.global_position)
	_expect("Blink aimed off the arena lands on the arena", landed <= _arena_radius() - 0.5,
		"from %.2fm outward, landed at %.2fm, rim %.2fm" % [rim, landed, _arena_radius()])

	# --- ...and cancels the slide, but not the stun --------------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	_player.apply_knockback(Knockback.velocity(8.0, Vector3(1, 0, 0), 0.0, knockback_rules))
	_expect("hit, and sliding", _player.knockback_velocity().length() > 1.0,
		"%.1f m/s" % _player.knockback_velocity().length())
	book.try_cast(dash, Vector3(-1, 0, 0))
	await get_tree().physics_frame
	_expect("Blink cancels the slide", _player.knockback_velocity().length() < 0.01,
		"%.3f m/s" % _player.knockback_velocity().length())
	_expect("but not the hitstun, so it is not a free reset", _player.is_in_hitstun(),
		"in hitstun=%s" % _player.is_in_hitstun())

	# --- Arcane Shield: it goes up, and it comes down --------------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	var buff_fired: bool = book.try_cast(buff, Vector3.ZERO)
	_expect("Shield was ready", buff_fired, "try_cast returned %s" % buff_fired)
	await get_tree().physics_frame
	_expect("the shield is up", _player.is_shielded(), "is_shielded=%s" % _player.is_shielded())
	var elapsed := 0.0
	while _player.is_shielded() and elapsed < shield.duration * 3.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	_expect("and it expires on time", absf(elapsed - shield.duration) < 0.12,
		"lasted %.2fs, spell says %.2fs" % [elapsed, shield.duration])

	# --- ...and a shielded hit carries less ---------------------------------------------------------
	# The same hit, twice, on the same body: once bare, once behind the shield. Measured as
	# distance travelled, because that is the thing a player actually experiences.
	var blow := Knockback.velocity(8.0, Vector3(1, 0, 0), 0.0, knockback_rules)
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	_player.apply_knockback(blow)
	var bare := await _drift_of(_player, 0.7)
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(buff, Vector3.ZERO)
	await get_tree().physics_frame
	_player.apply_knockback(blow)
	var guarded := await _drift_of(_player, 0.7)
	_expect("a shielded hit carries a fraction as far",
		guarded.length() < bare.length() * 0.5 and bare.length() > 0.5,
		"%.2fm bare, %.2fm shielded (spell lets %.0f%% through)" % [
			bare.length(), guarded.length(), shield.knockback_resist * 100.0])

	print("[spells] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## The four buttons, end to end: a finger on button N casts spell N and nothing else.
##
## Separate from the suite above because it needs injected touch and therefore a real window,
## while everything above is arithmetic and physics that would run anywhere.
func _run_button_tests() -> void:
	await _settle()
	_quiet_feel()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var book := _player.abilities()
	_expect("there is a button per spell", _mobile.buttons.size() == book.slot_count(),
		"%d buttons, %d spells" % [_mobile.buttons.size(), book.slot_count()])

	for i in _mobile.buttons.size():
		var button: AbilityButton = _mobile.buttons[i]
		_expect("button %d drives slot %d" % [i, i], button.slot == i, "slot=%d" % button.slot)
		_expect("button %d can read its spell" % i, button.source == book,
			"source=%s" % button.source)

	for i in _mobile.buttons.size():
		var button: AbilityButton = _mobile.buttons[i]
		while not book.is_ready(i):
			await get_tree().physics_frame
		var centre := button.get_global_rect().get_center()
		_emit_touch(0, centre, true)
		await _settle()
		_emit_touch(0, centre, false)
		await _settle()
		_expect("tapping button %d casts %s" % [i, book.ability_in(i).id],
			not book.is_ready(i), "remaining %.2fs" % book.cooldown_remaining(i))

	# A finger between two buttons must not cast either. The hit areas are discs, so the
	# corner where two bounding boxes would have overlapped belongs to nobody.
	var a: AbilityButton = _mobile.buttons[0]
	var b: AbilityButton = _mobile.buttons[1]
	# The midpoint of the FREE interval, not the midpoint of the line: the primary button is
	# larger, so halfway between two centres is still inside the big one.
	var ca := a.get_global_rect().get_center()
	var cb := b.get_global_rect().get_center()
	var span := ca.distance_to(cb)
	var near := a.radius + a.activation_padding
	var far := span - (b.radius + b.activation_padding)
	var between := ca.lerp(cb, ((near + far) * 0.5) / maxf(span, 0.001))
	_emit_touch(1, between, true)
	await _settle()
	_expect("a tap in the gap between two buttons claims nothing",
		a.touch_index() == -1 and b.touch_index() == -1,
		"gap at %s claimed by %d/%d" % [between, a.touch_index(), b.touch_index()])
	_emit_touch(1, between, false)
	await _settle()

	print("[buttons] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Aim harness
#
# Drag-to-aim is three claims, and only the first is easy to see by playing: a press opens an
# aim instead of casting, the lift fires along the line the thumb drew, and the direction
# latched at the lift survives the gap before the character consumes it. That third one is
# the reason this suite exists. It fails only when a render frame lands between the lift and
# the physics tick, which on a desktop is roughly never and on a phone under load is often -
# so it is exactly the bug that ships.
# ---------------------------------------------------------------------------------------

## How far the harness drags, in canvas units. Comfortably past the aim deadzone, so a test
## failing here is about the aim and not about the threshold.
const AIM_DRAG := 130.0


## Screen-right and screen-forward, on the ground plane, read off the live camera.
##
## Worked out from the camera rather than assumed to be +X and -Z. The camera is un-yawed
## today, so the two agree - and the day it is not, this suite says which of the two moved.
func _screen_axes() -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return [Vector2.RIGHT, Vector2.UP]
	var right3: Vector3 = cam.global_transform.basis.x
	var fwd3: Vector3 = -cam.global_transform.basis.z
	return [
		Vector2(right3.x, right3.z).normalized(),
		Vector2(fwd3.x, fwd3.z).normalized(),
	]


## Flat direction of the last cast the player made.
func _last_aim() -> Vector2:
	var flat := Vector2(_last_cast_dir.x, _last_cast_dir.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector2.ZERO


## Presses button `slot`, drags `screen_dir` (y-up), and leaves the finger down.
## Returns where the finger now is, so the caller can lift it in the right place - a lift at
## the button centre would erase the drag and turn the whole gesture back into a tap.
func _drag_aim(slot: int, screen_dir: Vector2) -> Vector2:
	var button: AbilityButton = _mobile.buttons[slot]
	var centre := button.get_global_rect().get_center()
	_emit_touch(0, centre, true)
	await _settle()
	var to := centre + Vector2(screen_dir.x, -screen_dir.y).normalized() * AIM_DRAG
	_emit_drag(0, to)
	await _settle()
	return to


func _run_aim_tests() -> void:
	await _settle()
	_quiet_feel()
	# Nothing here is about the opponent, and a bot walking into a Fireball would end a round
	# in the middle of a measurement.
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var book := _player.abilities()
	var indicator := _player.aim_indicator()
	var axes := _screen_axes()
	var screen_right: Vector2 = axes[0]
	var screen_fwd: Vector2 = axes[1]
	var fireball := book.ability_in(0)
	print("[aim-test] deadzone=%.0f drag=%.0f right=%s forward=%s" % [
		_input.aim_deadzone, AIM_DRAG, screen_right, screen_fwd])

	_expect("the fighter has an aim indicator", indicator != null,
		"indicator=%s" % indicator)
	if indicator == null:
		get_tree().quit(1)
		return
	_expect("nothing is drawn before a finger lands", not indicator.is_showing(), "clear")

	# --- a press opens the aim, and casts nothing -----------------------------------------
	var button: AbilityButton = _mobile.buttons[0]
	var centre := button.get_global_rect().get_center()
	var before := _pool.active_count()
	_emit_touch(0, centre, true)
	await _settle()
	_expect("press starts aiming slot 0", _input.command.aiming_slot == 0,
		"aiming=%d" % _input.command.aiming_slot)
	_expect("press alone casts nothing",
		_pool.active_count() == before and book.is_ready(0),
		"active=%d ready=%s" % [_pool.active_count(), book.is_ready(0)])
	_expect("the indicator is up", indicator.is_showing(),
		"shape=%d" % indicator.shape())
	_expect("a projectile draws a lane", indicator.shape() == AimIndicator.Shape.LANE,
		"shape=%d" % indicator.shape())

	# The lane is trimmed at the rim, so the far end of it should be ON the rim - measured
	# here from the position and the aim, not by asking the code that drew it.
	var aim_now := _preview_direction(book)
	var tip := _player.global_position + aim_now * indicator.reach()
	_expect("the lane stops at the arena rim",
		indicator.reach() < fireball.effective_range() and absf(_radius_of(tip) - _arena_edge) < 0.05,
		"reach %.2fm of %.2fm, tip at r=%.2f (edge %.2f)" % [
			indicator.reach(), fireball.effective_range(), _radius_of(tip), _arena_edge])

	# --- a small roll is a tap, not an aim ------------------------------------------------
	_emit_drag(0, centre + Vector2(10.0, 0.0))
	await _settle()
	_expect("a roll under the deadzone is not an aim", not _input.command.has_aim,
		"has_aim=%s aim=%s" % [_input.command.has_aim, _input.command.aim_dir])

	# --- drag right: the aim, the wizard and the indicator all turn -----------------------
	var held := centre + Vector2(AIM_DRAG, 0.0)
	_emit_drag(0, held)
	await _settle()
	var aim: Vector2 = _input.command.aim_dir
	_expect("dragging right aims screen-right", aim.normalized().dot(screen_right) > 0.99,
		"aim=%s right=%s" % [aim, screen_right])
	for i in 24:
		await get_tree().physics_frame
	_expect("the wizard turns to face the drag", _facing_of(_player).dot(screen_right) > 0.98,
		"facing=%s" % _facing_of(_player))

	# --- the lift is the cast, and it goes where the thumb pointed ------------------------
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, held, false)
	await _settle()
	_expect("the lift casts", _pool.active_count() == before + 1,
		"active %d -> %d" % [before, _pool.active_count()])
	_expect("the spell left along the drag", _last_aim().dot(screen_right) > 0.99,
		"cast=%s right=%s" % [_last_aim(), screen_right])
	_expect("the indicator goes away on the lift", not indicator.is_showing(), "cleared")

	# --- the aim latched at the lift survives the tick that consumes it -------------------
	#
	# The finger lifts and the character casts on the NEXT physics tick. If the walking
	# direction is allowed to overwrite the aim in between, the spell comes out sideways -
	# rarely, and only under load. So: aim forward, walk right, lift, and check which one
	# the spell believed.
	while not book.is_ready(0):
		await get_tree().physics_frame
	_input.set_override_vector(Vector2(1.0, 0.0), true)
	var landed := await _drag_aim(0, Vector2(0.0, 1.0))
	_expect("the drag beats the walking direction",
		_input.command.aim_dir.normalized().dot(screen_fwd) > 0.99,
		"aim=%s forward=%s" % [_input.command.aim_dir, screen_fwd])
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, landed, false)
	await _settle()
	_expect("the latched aim survived to the cast", _last_aim().dot(screen_fwd) > 0.99,
		"cast=%s forward=%s move=%s" % [_last_aim(), screen_fwd, _input.command.move_dir])

	# --- and a plain tap still casts where you are heading --------------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, centre, true)
	await _settle()
	_emit_touch(0, centre, false)
	await _settle()
	_expect("a tap still casts where you are heading", _last_aim().dot(screen_right) > 0.99,
		"cast=%s move=%s" % [_last_aim(), _input.command.move_dir])
	_input.set_override_vector(Vector2.ZERO, true)

	# --- every cast type draws its own shape ----------------------------------------------
	var cone_slot := _slot_with(book, Ability.CastType.CONE)
	var cone := book.ability_in(cone_slot)
	var cone_at := await _drag_aim(cone_slot, Vector2(0.0, 1.0))
	_expect("a cone draws a fan", indicator.shape() == AimIndicator.Shape.FAN,
		"shape=%d" % indicator.shape())
	_expect("the fan is the spell's own fan",
		is_equal_approx(indicator.reach(), cone.area)
			and is_equal_approx(indicator.half_angle(), cone.cone_angle),
		"reach=%.2f (area %.2f) half=%.1f (cone %.1f)" % [
			indicator.reach(), cone.area, indicator.half_angle(), cone.cone_angle])
	_emit_touch(0, cone_at, false)
	await _settle()

	var buff_slot := _slot_with(book, Ability.CastType.BUFF)
	var buff_at := await _drag_aim(buff_slot, Vector2(0.0, 1.0))
	_expect("a self-cast draws a ring around you",
		indicator.shape() == AimIndicator.Shape.SELF, "shape=%d" % indicator.shape())
	_emit_touch(0, buff_at, false)
	await _settle()

	# --- a dash previews where it will REALLY land ----------------------------------------
	#
	# Standing 3m out and aiming outward, a 5m Blink would leave the arena, so the preview
	# has to be shorter than the spell. Then the lift proves the promise: the wizard travels
	# exactly as far as the line said it would.
	var dash_slot := _slot_with(book, Ability.CastType.DASH)
	var dash := book.ability_in(dash_slot)
	await _place_fighters(Vector3(0.0, 1.2, -3.5), Vector3(3.0, 1.2, 0.0))
	var dash_at := await _drag_aim(dash_slot, Vector2(1.0, 0.0))
	_expect("a dash draws a line to a landing spot",
		indicator.shape() == AimIndicator.Shape.DASH, "shape=%d" % indicator.shape())
	var previewed := indicator.reach()
	_expect("the preview is clamped by the arena", previewed < dash.dash_distance - 0.5,
		"previewed %.2fm of %.2fm" % [previewed, dash.dash_distance])
	var from := _player.global_position
	_emit_touch(0, dash_at, false)
	await _settle()
	var travelled := Vector2(_player.global_position.x - from.x,
		_player.global_position.z - from.z).length()
	_expect("the wizard lands exactly where the line ended",
		absf(travelled - previewed) < 0.05,
		"drew %.2fm, travelled %.2fm" % [previewed, travelled])
	_expect("and lands inside the arena", _radius_of(_player.global_position) <= _arena_edge,
		"r=%.2f edge=%.2f" % [_radius_of(_player.global_position), _arena_edge])

	print("[aim] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Holds a drag on a spell button and never lifts it, so a delayed --shot photographs the
## indicator. Nothing casts: the cast is the lift, and this run never lifts.
func _hold_aim(slot: int, direction: Vector2) -> void:
	await _wait_for_live()
	if slot < 0 or slot >= _mobile.buttons.size():
		push_warning("--aim-hold: no button %d" % slot)
		return
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var button: AbilityButton = _mobile.buttons[slot]
	var centre := button.get_global_rect().get_center()
	# A finger index nothing else in the harness uses, so an --aim-hold can be combined with
	# another injected gesture without the two claiming each other's events.
	_emit_touch(9, centre, true)
	await _settle()
	_emit_drag(9, centre + Vector2(dir.x, -dir.y) * AIM_DRAG)
	print("[harness] holding aim on slot %d toward %s" % [slot, dir])


# ---------------------------------------------------------------------------------------
# Game feel harness
#
# Feel is the one thing in this project that cannot be judged by a number - "does that hit
# land well" is a question for a human. What CAN be checked is that every channel actually
# fires, that they scale with the hit rather than being on or off, and that hitstop gives the
# engine back afterwards. A hitstop that leaks is not a subtle bug: the whole game runs at a
# tenth speed forever, and it would pass every other suite in this file, because they all
# park the feel.
# ---------------------------------------------------------------------------------------

## Waits for a shake to die, so the next reading starts from zero. Bounded, because a stuck
## shake should fail an assertion rather than hang the run.
func _settle_shake() -> void:
	var guard := 0
	while _camera_rig.shake_level() > 0.001 and guard < 600:
		await get_tree().process_frame
		guard += 1


## Applies one hit and returns how much shake it added, read on the same frame so nothing has
## decayed yet.
func _shake_from_hit(victim: Player, ability: Ability) -> float:
	await _settle_shake()
	var inst := victim.instability()
	if inst != null:
		inst.reset()
	var before := _camera_rig.shake_level()
	_apply_hit(victim, Vector3(1.0, 0.0, 0.0), ability)
	return _camera_rig.shake_level() - before


func _run_feel_tests() -> void:
	await _settle()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	# Both fighters in the middle, so a Force Wave at full strength cannot throw either of
	# them off the arena in the middle of a measurement.
	await _place_fighters(Vector3(0.0, 1.2, -2.5), Vector3(0.0, 1.2, 0.0))
	var book := _player.abilities()
	var light := book.ability_in(0)
	var heavy := book.ability_in(_slot_with(book, Ability.CastType.CONE))
	var sounds := $Sounds as SoundBank
	var sparks := $Sparks as ImpactBurst
	var streak := $Streak as GroundStreak
	print("[feel-test] stop=%.3f-%.3fs heavy at %.1f m/s, %d sounds in the bank" % [
		_feel.stop_min, _feel.stop_max, _feel.heavy_speed, sounds.names().size()])

	_expect("the feel layer has all four channels",
		_feel.camera != null and _feel.sounds != null and _feel.sparks != null
			and _feel.streak != null,
		"camera=%s sounds=%s sparks=%s streak=%s" % [
			_feel.camera != null, _feel.sounds != null, _feel.sparks != null,
			_feel.streak != null])
	for id in [&"cast", &"hit", &"heavy", &"fall", &"tick", &"go", &"win", &"lose", &"blink"]:
		_expect("the bank has a %s" % id, sounds.has(id), "")

	# --- one hit reaches every channel -----------------------------------------------------
	await _settle_shake()
	var sparks_before := sparks.active_count()
	var began := Time.get_ticks_msec()
	_apply_hit(_player, Vector3(1.0, 0.0, 0.0), light)
	_expect("a hit throws sparks", sparks.active_count() > sparks_before,
		"active %d -> %d" % [sparks_before, sparks.active_count()])
	_expect("a hit shakes the camera", _camera_rig.shake_level() > 0.0,
		"shake=%.3f" % _camera_rig.shake_level())
	_expect("a hit slows the world", _feel.is_stopped() and Engine.time_scale < 1.0,
		"time_scale=%.3f" % Engine.time_scale)
	_expect("a hit makes a noise", sounds.playing_count() > 0,
		"%d voice(s)" % sounds.playing_count())

	# --- and gives the engine back ---------------------------------------------------------
	#
	# Measured in WALL CLOCK time, which is the whole point. Counting a hitstop down with a
	# delta that the hitstop itself scaled stretches it by exactly the factor applied - the
	# 0.035s stop would last 0.29s and still look like it worked.
	var guard := 0
	while Engine.time_scale < 1.0 and guard < 600:
		await get_tree().process_frame
		guard += 1
	var stopped_for := (Time.get_ticks_msec() - began) / 1000.0
	_expect("the world speeds back up", is_equal_approx(Engine.time_scale, 1.0),
		"time_scale=%.3f after %d frames" % [Engine.time_scale, guard])
	# The tolerance is a rendered frame either way: this poll can only notice the engine came
	# back on a frame boundary, so a 0.072s stop reads as 0.087s on a 60fps run. What it is
	# really guarding against is an order of magnitude - a hitstop counted down with its own
	# slowed delta comes out EIGHT times too long and would still look fine in a log.
	_expect("the hitstop lasted about as long as it asked to (within a frame)",
		stopped_for >= _feel.stop_min * 0.5 and stopped_for <= _feel.stop_max + 0.10,
		"%.3fs, asked for %.3f-%.3f" % [stopped_for, _feel.stop_min, _feel.stop_max])

	# --- the channels scale with the hit ---------------------------------------------------
	var light_shake := await _shake_from_hit(_player, light)
	var heavy_shake := await _shake_from_hit(_player, heavy)
	_expect("a heavier hit shakes harder", heavy_shake > light_shake + 0.01,
		"light %.3f, heavy %.3f" % [light_shake, heavy_shake])
	var on_bot := await _shake_from_hit(_bot, heavy)
	_expect("a hit on the opponent shakes less than one on you",
		on_bot < heavy_shake * 0.9 and on_bot > 0.0,
		"you %.3f, them %.3f" % [heavy_shake, on_bot])

	# --- a dash leaves a streak, and takes it away again ------------------------------------
	var dash := book.ability_in(_slot_with(book, Ability.CastType.DASH))
	_cast_dash(dash, Vector3(1.0, 0.0, 0.0), _player)
	await get_tree().process_frame
	_expect("a dash draws a streak", streak.is_showing(), "showing=%s" % streak.is_showing())
	var waited := 0.0
	while streak.is_showing() and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_expect("the streak fades on its own", not streak.is_showing(),
		"still up after %.2fs" % waited)

	# --- and the whole thing can be switched off --------------------------------------------
	while sparks.active_count() > 0:
		await get_tree().process_frame
	_feel.enabled = false
	await _settle_shake()
	_apply_hit(_player, Vector3(1.0, 0.0, 0.0), heavy)
	_expect("a parked feel throws no sparks", sparks.active_count() == 0,
		"active=%d" % sparks.active_count())
	_expect("a parked feel does not shake", _camera_rig.shake_level() <= 0.001,
		"shake=%.3f" % _camera_rig.shake_level())
	_expect("a parked feel leaves time alone", is_equal_approx(Engine.time_scale, 1.0),
		"time_scale=%.3f" % Engine.time_scale)

	print("[feel] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)

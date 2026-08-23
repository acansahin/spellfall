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
## Screenshots need real rendering, so DO NOT pass --headless with --shot.
## The two input tests ALSO need a real window: the headless display driver does not
## route injected InputEventScreenTouch/Key to _input(), so every assertion silently
## reads zero and the run reports failures that say nothing about the code.

## Where the player is put on start and after falling off.
@export var spawn_point := Vector3(0.0, 1.2, 3.5)

## Falling below this counts as off the arena. The real elimination system replaces this.
@export var fall_limit := -10.0

@onready var _player: Player = $Player
@onready var _input: PlayerInputController = $PlayerInputController
@onready var _mobile: MobileControls = $MobileControls

var _trace := false


func _ready() -> void:
	# The character is handed its input source rather than reaching out for one, so a bot
	# or a network replay can be substituted without the character noticing.
	_player.input_controller = _input
	# The stick is a dumb widget that reports where a thumb is; this single line is what
	# gives its output a meaning. Wiring it here rather than inside either node keeps the
	# stick reusable and keeps PlayerInputController unaware that a UI exists - the same
	# hand-it-its-dependencies pattern already used for the character above.
	_mobile.joystick.vector_changed.connect(_input.set_touch_vector)
	_player.respawn_at(spawn_point)
	_parse_harness_args()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_respawn"):
		_player.respawn_at(spawn_point)
	if _player.global_position.y < fall_limit:
		print("[fall] player left the arena at %.1f,%.1f" % [
			_player.global_position.x, _player.global_position.z
		])
		_player.respawn_at(spawn_point)


func _parse_harness_args() -> void:
	# Visibility first: --touch-test needs the stick already shown and laid out.
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-ui:on":
			_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
		elif arg == "--touch-ui:off":
			_mobile.visibility_mode = MobileControls.Visibility.HIDDEN
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
			var secs := float(arg.substr(7))
			_shoot("user://shot_%d.png" % int(secs), secs)
		elif arg == "--touch-test":
			_run_touch_tests()
		elif arg == "--key-test":
			_run_key_tests()
		elif arg == "--layout-probe":
			_probe_layout()
		elif arg.begins_with("--stick-hold="):
			var hp := arg.substr(13).split(",")
			if hp.size() == 2:
				_hold_stick(Vector2(float(hp[0]), float(hp[1])))


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
	Input.parse_input_event(event)


func _emit_drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	Input.parse_input_event(event)


## Waits long enough for an injected event to reach _input() AND for the controller's
## _process to have folded it into the command every downstream reader sees.
func _settle() -> void:
	await get_tree().process_frame
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
	Input.parse_input_event(event)


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

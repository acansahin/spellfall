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
## Screenshots need real rendering, so DO NOT pass --headless with --shot.
## The two input tests ALSO need a real window: the headless display driver does not
## route injected InputEventScreenTouch/Key to _input(), so every assertion silently
## reads zero and the run reports failures that say nothing about the code.

## Where the player is put on start and after falling off.
@export var spawn_point := Vector3(0.0, 1.2, 3.5)

## Where the training dummy stands.
@export var dummy_spawn := Vector3(0.0, 1.0, -3.0)

## Falling below this counts as off the arena. The real elimination system replaces this.
@export var fall_limit := -10.0

## How a hit is turned into speed. A Resource so the central mechanic is tuned by editing
## data, never by editing logic - see combat/knockback/knockback_rules.gd.
@export var knockback_rules: KnockbackRules = null

@onready var _player: Player = $Player
@onready var _input: PlayerInputController = $PlayerInputController
@onready var _mobile: MobileControls = $MobileControls
@onready var _pool: ProjectilePool = $ProjectilePool
@onready var _dummy: Player = $TrainingDummy
@onready var _hud: Hud = $Hud

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
	_wire_combat()
	# The HUD reads instability and nothing else. It is handed its sources here rather than
	# hunting for them, so a second fighter is one more line and not a rewrite.
	_hud.add_readout("YOU", _player.instability())
	_hud.add_readout("DUMMY", _dummy.instability())
	_player.respawn_at(spawn_point)
	_parse_harness_args()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_respawn"):
		_player.respawn_at(spawn_point)
	# Both fighters fall the same way. Elimination replaces this wholesale in Session 5;
	# respawning keeps the prototype testable rather than leaving a body in the void.
	_check_fall(_player, spawn_point, "player")
	_check_fall(_dummy, dummy_spawn, "dummy")


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
		elif arg == "--layout-probe":
			_probe_layout()
		elif arg.begins_with("--cast-at:"):
			_cast_at(float(arg.substr(10)))
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
	var book := _player.abilities()
	if book == null:
		push_warning("player has no AbilityComponent; casting disabled")
		return
	book.cast_requested.connect(_on_cast_requested)
	_pool.projectile_hit.connect(_on_projectile_hit)
	# The button reports a press; the controller latches it; the character consumes it on
	# the next tick. Touch therefore takes exactly the same route as the Space key, which
	# is what stops the two drifting apart.
	_mobile.cast_button.pressed_slot.connect(_input.request_ability)
	# Read-only, for drawing the cooldown wedge and the spell's colour.
	_mobile.cast_button.source = book


func _on_cast_requested(ability: Ability, origin: Vector3, direction: Vector3, caster: Node3D) -> void:
	match ability.cast_type:
		Ability.CastType.PROJECTILE:
			_pool.fire(ability, origin, direction, caster)
		_:
			# Cone, dash and buff are authored in the Ability but have no runtime yet. Warn
			# loudly rather than failing silently, so a half-built spell is obvious.
			push_warning("cast type %d not implemented yet (%s)" % [ability.cast_type, ability.id])


## What a hit MEANS. The projectile reports contact and stops there; this is the one place
## instability is raised and the one place knockback is handed out.
func _on_projectile_hit(body: Node3D, direction: Vector3, ability: Ability) -> void:
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
	print("[hit] %s -> %s | instability %.0f%% | knockback %.1f m/s" % [
		ability.id, body.name, level, Vector2(impulse.x, impulse.z).length()])


func _check_fall(fighter: Player, respawn: Vector3, label: String) -> void:
	if not is_instance_valid(fighter) or fighter.global_position.y >= fall_limit:
		return
	print("[fall] %s left the arena" % label)
	fighter.respawn_at(respawn)


func _run_cast_tests() -> void:
	await _settle()
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
	await _settle()
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

	# --- it hits the dummy, and the pool takes it back -----------------------------------
	var hit_body: Array = []
	_pool.projectile_hit.connect(func(b, _d, _a): hit_body.append(b), CONNECT_ONE_SHOT)
	var waited := 0.0
	while _pool.active_count() > 0 and waited < 2.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	_expect("projectile reached the training dummy", hit_body.size() == 1,
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
	var stick := _mobile.joystick
	var button := _mobile.cast_button
	var book := _player.abilities()
	var stick_centre := stick.get_global_rect().get_center()
	var button_centre := button.get_global_rect().get_center()
	print("[twothumb] stick=%s button=%s (gap %.0f units)" % [
		stick_centre, button_centre, stick_centre.distance_to(button_centre)])

	_expect("stick and button do not overlap",
		not stick.get_global_rect().grow(44.0).intersects(button.get_global_rect().grow(16.0)),
		"stick=%s button=%s" % [stick.get_global_rect(), button.get_global_rect()])

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
	_expect("movement is unaffected by the cast",
		_input.command.move_dir.is_equal_approx(moving_before),
		"before=%s after=%s" % [moving_before, _input.command.move_dir])
	_expect("the tap actually cast", _pool.active_count() == before_active + 1,
		"active %d -> %d" % [before_active, _pool.active_count()])
	_expect("casting put the slot on cooldown", not book.is_ready(0),
		"remaining=%.2fs" % book.cooldown_remaining(0))

	# --- releasing the right thumb must not disturb the left ------------------------------
	_emit_touch(1, button_centre, false)
	await _settle()
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


## Casts the primary spell N seconds in, so a delayed --shot can catch a spell mid-flight.
func _cast_at(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	_input.request_ability(0)


# ---------------------------------------------------------------------------------------
# Knockback harness
#
# The central mechanic, so it is checked by measurement rather than by feel. Two things must
# hold: the same hit at the same instability always carries the same distance, and that
# distance is the one the formula intends. Linear drag makes the second checkable in closed
# form - v squared over 2f - which is exactly why the drag is linear.
# ---------------------------------------------------------------------------------------

## Hits the dummy with a known speed and returns how far it slid on the ground plane.
func _measure_slide(speed: float, instability: float) -> float:
	_dummy.respawn_at(dummy_spawn)
	for i in 20:
		await get_tree().physics_frame
	var start := _dummy.global_position
	var impulse := Knockback.velocity(speed, Vector3(0, 0, -1), instability, knockback_rules)
	_dummy.apply_knockback(impulse)
	var guard := 0
	while _dummy.knockback_velocity().length() > 0.001 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	var moved := _dummy.global_position - start
	return Vector2(moved.x, moved.z).length()


func _run_knockback_tests() -> void:
	await _settle()
	var rules := knockback_rules
	print("[knockback] rules: base=%.1f per100=%.1f max=%.1f lift=%.1f | dummy friction=%.1f" % [
		rules.base_multiplier, rules.per_100_instability, rules.max_multiplier, rules.lift,
		_dummy.knockback_friction])

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
	var predicted := Knockback.slide_distance(base_speed, _dummy.knockback_friction)
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
	_dummy.respawn_at(dummy_spawn)
	for i in 20:
		await get_tree().physics_frame
	var hard := Knockback.velocity(base_speed, Vector3(0, 0, -1), 200.0, knockback_rules)
	_dummy.apply_knockback(hard)
	var left_arena := false
	for i in 240:
		await get_tree().physics_frame
		var p := _dummy.global_position
		if Vector2(p.x, p.z).length() > 7.2 or p.y < 0.0:
			left_arena = true
			break
	_expect("a hit at 200% throws the target off the arena", left_arena,
		"ended at %s" % _dummy.global_position)
	_dummy.respawn_at(dummy_spawn)
	for i in 20:
		await get_tree().physics_frame

	# --- instability accumulates, and a respawn clears it ---------------------------------
	var inst := _dummy.instability()
	_expect("dummy starts stable", is_equal_approx(inst.current, 0.0), "%.1f%%" % inst.current)
	inst.add(12.0)
	inst.add(12.0)
	_expect("instability accumulates", is_equal_approx(inst.current, 24.0),
		"%.1f%%" % inst.current)
	_dummy.respawn_at(dummy_spawn)
	_expect("respawn resets instability", is_equal_approx(inst.current, 0.0),
		"%.1f%%" % inst.current)

	# --- hitstun exists and expires ------------------------------------------------------
	_dummy.apply_knockback(Knockback.velocity(base_speed, Vector3(0, 0, -1), 0.0, rules))
	_expect("a hit causes hitstun", _dummy.is_in_hitstun(), "in hitstun=%s" % _dummy.is_in_hitstun())
	var waited := 0
	while _dummy.is_in_hitstun() and waited < 300:
		await get_tree().physics_frame
		waited += 1
	_expect("hitstun expires", not _dummy.is_in_hitstun(), "after %d ticks" % waited)

	# --- end to end: a real Fireball raises instability and moves the target --------------
	_dummy.respawn_at(dummy_spawn)
	_player.respawn_at(spawn_point)
	for i in 20:
		await get_tree().physics_frame
	var before_pos := _dummy.global_position
	_player.abilities().try_cast(0, Vector3(0, 0, -1))
	var hit_seen := false
	for i in 120:
		await get_tree().physics_frame
		if _dummy.instability().current > 0.0:
			hit_seen = true
			break
	_expect("a cast Fireball raises the target's instability", hit_seen,
		"instability=%.1f%%" % _dummy.instability().current)
	for i in 60:
		await get_tree().physics_frame
	var shifted := (_dummy.global_position - before_pos)
	_expect("and pushes it away from the caster", shifted.z < -0.3,
		"moved %.2fm along z" % shifted.z)

	print("[knockback] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)

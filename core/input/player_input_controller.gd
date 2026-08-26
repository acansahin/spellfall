class_name PlayerInputController
extends Node

## Translates raw device input into a camera-relative InputCommand.
##
## This node is the ONLY place in the project that knows a keyboard or a touchscreen
## exists. Everything downstream reads InputCommand instead, which is what will let the
## virtual joystick, the bot and a future server replay all drive the same character code.
##
## Screen space vs world space: the player pushes "up" on a joystick meaning "away from
## me on screen", not "world -Z". Those only coincide while the camera has no yaw. The
## conversion happens here, once, so a camera rotation can never silently invert control.

## Emitted after the command is refreshed for this frame.
signal command_updated(command: InputCommand)

## Ignore stick noise below this fraction of full deflection. Applies to touch only;
## keyboard input is already discrete. Exported so it can be tuned per device without
## touching code. See `_shape_stick` for how it is applied - it rescales, it does not clip.
@export_range(0.0, 0.5, 0.01) var touch_deadzone := 0.15

## Scales how far the joystick must travel to reach full speed.
@export_range(0.1, 2.0, 0.05) var touch_sensitivity := 1.0

## How far a thumb must drag off a spell button, in canvas units, before it counts as aiming
## rather than as a tap. Below this the cast falls back to where you are heading, which is
## exactly what tapping did before drag-to-aim existed.
##
## Measured against the button's own grab room: a finger resting on a 72-unit button rolls a
## good 15 units without the player meaning anything by it. 28 clears that and still lands
## well inside the button, so a deliberate aim never has to leave it.
@export var aim_deadzone := 28.0

## The live command. Read this, don't cache it — it is refreshed in place each frame.
var command := InputCommand.new()

var _touch_vector := Vector2.ZERO
var _touch_active := false
var _pending_ability := -1
var _override_vector := Vector2.ZERO
var _override_active := false

## The slot a finger is currently holding, and where that finger has dragged to. Screen
## space, y-up, already past the deadzone - `_aim_vector` stays zero while the drag is still
## inside it, which is what makes a tap a tap.
var _aim_slot := -1
var _aim_vector := Vector2.ZERO

## The aim a released cast was fired with, WORLD space, held until the cast is consumed.
##
## This is the whole reason drag-to-aim needed care rather than a signal. The finger lifts
## during an input flush; the character consumes the cast on the next physics tick; in
## between, `_process` runs and would overwrite `aim_dir` with wherever the player happened
## to be walking. The spell would then come out in a direction the player never chose, and
## only when the two clocks lined up a certain way - which is the kind of bug that shows up
## once in twenty casts and gets blamed on the touchscreen.
var _latched_aim := Vector2.ZERO
var _latched_has_aim := false

## Where a mouse is pointing, WORLD space, and whether one is being used at all.
##
## Handed in by the level exactly as the joystick's vector is - see `set_pointer_aim`. This
## node still knows nothing about cameras, wizards or ground planes; it knows that something
## upstream has an opinion about where the player is aiming.
var _pointer_aim := Vector2.ZERO
var _pointer_active := false

## The slot waiting for a place to go, or -1.
##
## This is the whole of the Warcraft III casting model the map this game follows uses: a key
## ARMS a spell, and the next left click says WHERE. Nothing is cast on the key press, so a
## mis-typed key costs a cooldown of nothing and can be taken back with a right click.
##
## Spells that need no place - the wards - are not armed at all; the level fires those the
## moment they are armed, because it is the only thing that knows what kind of spell a slot
## holds. See `main.gd _release_instant_casts`.
var _armed_slot := -1

## A walk order given by right-clicking the ground, as a WORLD direction refreshed every frame
## by the level. Same split as the aim: the level owns the ground plane, this owns the intent.
var _click_move := Vector2.ZERO
var _click_move_active := false

## A right click the level has not yet turned into a walk order. Held for exactly one frame.
##
## The click is READ here, because this node is the only place allowed to know a mouse exists,
## and it is INTERPRETED there, because turning a cursor into a patch of ground needs a camera.
var _move_click_pending := false


func _process(_delta: float) -> void:
	_poll_ability_keys()
	var raw := _read_raw()
	var world := _screen_to_world(raw)
	if world != Vector2.ZERO:
		# A key beats a standing walk order, and cancels it. Resuming a click order the moment
		# a key is released would send the wizard back off toward somewhere they had already
		# decided against.
		_click_move_active = false
	elif _click_move_active:
		# Already world space - it came from the ground, not from a stick.
		world = _click_move
	command.move_dir = world
	command.has_move_input = world.length_squared() > 0.0
	_publish_aim(world)
	command.aiming_slot = _aim_slot if _aim_slot != -1 else _armed_slot
	command.ability_pressed = _pending_ability
	command_updated.emit(command)


## Decides which of the three things speaking gets to fill the aim, in priority order.
##
## A live drag wins: the thumb is pointing right now. Failing that, a MOUSE wins, because on a
## desktop the cursor is a continuous statement of intent and there is nothing stale about it -
## unlike a latched aim, which exists only to survive the gap between a lift and the next tick.
## Failing both, a cast already released but not yet consumed keeps the direction it was fired
## with. Failing all three, aim mirrors movement, which is what tapping has always done.
func _publish_aim(world_move: Vector2) -> void:
	if _aim_slot != -1 and _aim_vector != Vector2.ZERO:
		command.aim_dir = _screen_to_world(_aim_vector)
		command.has_aim = true
		return
	# ONLY WHILE A SPELL IS ARMED. A wizard whose head follows the cursor all round the arena
	# looks like a twin-stick shooter, and this is not one: the map this follows faces you where
	# you are walking until you actually point at something.
	if _armed_slot != -1 and _pointer_active and _pointer_aim != Vector2.ZERO:
		command.aim_dir = _pointer_aim
		command.has_aim = true
		return
	if _latched_has_aim:
		command.aim_dir = _latched_aim
		command.has_aim = true
		return
	command.aim_dir = world_move
	command.has_aim = command.has_move_input


## Desktop casting. The touch buttons call `request_ability()` directly, so this is only the
## keyboard's way into the same latch.
##
## A plain Array and not a PackedStringArray: `const X := PackedStringArray([...])` is a
## constructor call rather than a constant expression and does not compile.
const SLOT_KEYS: Array = ["cast_1", "cast_2", "cast_3", "cast_4"]

## The left mouse button: it says WHERE an armed spell goes, and does nothing otherwise.
##
## It is deliberately not a second event on `cast_1`. `emulate_mouse_from_touch` is on by
## default and turns every finger into a left click, so a left button bound to a cast action
## meant that TAPPING ANYWHERE ON A PHONE cast a spell - the menu included. Here it only ever
## fires something already armed, and nothing on a phone ever arms.
const PRIMARY_CLICK := "cast_primary"

## Right click: walk there, or take back the spell you were about to cast.
const MOVE_CLICK := "move_command"


## The whole desk control scheme, in one place: a key arms, a left click sends, a right click
## either takes it back or walks you somewhere.
func _poll_ability_keys() -> void:
	for slot in SLOT_KEYS.size():
		if not Input.is_action_just_pressed(String(SLOT_KEYS[slot])):
			continue
		# The same key again puts it away. A player who armed the wrong spell should be able to
		# undo it with the key they already have a finger on.
		if _armed_slot == slot:
			disarm()
		else:
			arm(slot)

	if Input.is_action_just_pressed(MOVE_CLICK):
		if _armed_slot != -1:
			# Right click CANCELS an armed spell and issues no walk order. Two meanings on one
			# button, and the map this follows resolves them the same way: whatever you were
			# about to do, you are not doing it now.
			disarm()
		else:
			_move_click_pending = true

	if _armed_slot != -1 and Input.is_action_just_pressed(PRIMARY_CLICK):
		_send_armed()


## Casts the armed spell at wherever the cursor is pointing.
##
## The aim is LATCHED, exactly as a lifted thumb latches one, and for the same reason: the
## character consumes the cast on the next physics tick, and between now and then `_process`
## would otherwise overwrite the direction with wherever the wizard happens to be walking.
func _send_armed() -> void:
	var slot := _armed_slot
	disarm()
	if _pointer_aim != Vector2.ZERO:
		_latched_aim = _pointer_aim
		_latched_has_aim = true
		command.aim_dir = _latched_aim
		command.has_aim = true
	request_ability(slot)


## Holds a spell, waiting for a place to put it.
func arm(slot: int) -> void:
	_armed_slot = slot
	command.aiming_slot = slot


func disarm() -> void:
	_armed_slot = -1
	if _aim_slot == -1:
		command.aiming_slot = -1


## The slot waiting for a target, or -1. The level reads it to fire the spells that need no
## target, and the aim indicator reads it to draw the one that does.
func armed_slot() -> int:
	return _armed_slot


## Takes a pending right-click, if there is one. The level turns it into a patch of ground.
func consume_move_click() -> bool:
	var clicked := _move_click_pending
	_move_click_pending = false
	return clicked


## Called by the level every frame while a walk order stands. `direction` is WORLD space and
## points at the destination from wherever the wizard now is.
func set_click_move(direction: Vector2, active: bool) -> void:
	_click_move = direction
	_click_move_active = active


## True while a right-click walk order is being followed.
func is_click_moving() -> bool:
	return _click_move_active


## Called by the virtual joystick once it exists. `vector` is in screen space with
## y pointing UP the screen, matching how a stick is drawn; length 0..1.
func set_touch_vector(vector: Vector2, active: bool) -> void:
	_touch_vector = vector
	_touch_active = active


## Called by the level every frame on a machine with a mouse. `direction` is already in WORLD
## space, on the ground plane, pointing from the wizard toward the cursor.
##
## The conversion is the LEVEL's job and not this node's, which is the same split the joystick
## already makes: the stick reports where a thumb is and one line upstream gives it meaning.
## Turning a cursor into an aim needs the camera, the ground plane AND the wizard's position -
## three things this node deliberately does not know, and would have to be handed anyway.
func set_pointer_aim(direction: Vector2, active: bool) -> void:
	_pointer_aim = direction
	_pointer_active = active


## True while a mouse is driving the aim. The level asks, so the aim indicator can be drawn
## for a cursor as well as for a thumb.
func is_pointing() -> bool:
	return _pointer_active and _pointer_aim != Vector2.ZERO


## Asks for an ability. Called by a touch button, by the keyboard poll above, and by the
## test harness. The request is held rather than acted on here - this node decides what the
## player WANTS, never what happens.
func request_ability(slot: int) -> void:
	_pending_ability = slot


## A finger landed on a spell button. Nothing is cast yet - this only opens the aim.
##
## Press used to cast outright, and deliberately so: waiting for a lift adds latency in a
## game where a dodge is a third of a second. Aiming is worth paying that for. A thumb has no
## other way to say WHERE, and a spell aimed where you meant it beats the same spell fired
## 60ms sooner at where you happened to be walking. A tap still casts - it just casts on the
## lift - so the only thing lost is firing without seeing the aim.
func begin_aim(slot: int) -> void:
	_aim_slot = slot
	_aim_vector = Vector2.ZERO


## The finger moved. `vector` is screen space, y-UP (the TouchStick convention), measured
## from where the finger LANDED rather than from the button's centre, so a player can start
## the drag anywhere on the button and still aim from under their own thumb.
##
## The deadzone is applied here rather than in the button for the same reason the stick's
## lives here: the widget reports honestly where the thumb is, and the gameplay layer decides
## how much of that it believes.
func update_aim(slot: int, vector: Vector2) -> void:
	if slot != _aim_slot:
		return
	if vector.length() < aim_deadzone:
		_aim_vector = Vector2.ZERO
		return
	_aim_vector = vector.normalized()


## The finger lifted: latch the cast, and latch the aim with it.
##
## Both together, always. Latching the slot without the direction is the bug written up on
## `_latched_aim` above.
func end_aim(slot: int) -> void:
	if slot != _aim_slot:
		return
	if _aim_vector != Vector2.ZERO:
		_latched_aim = _screen_to_world(_aim_vector)
		_latched_has_aim = true
		# Write it through immediately as well. The physics tick that consumes this cast may
		# land before the next _process, and a cast must not depend on which of the two
		# happened to run first.
		command.aim_dir = _latched_aim
		command.has_aim = true
	_aim_slot = -1
	_aim_vector = Vector2.ZERO
	command.aiming_slot = -1
	request_ability(slot)


## Drops an aim without casting. Nothing calls this yet; it is the seam a drag-back-to-cancel
## gesture would use, and it exists so that gesture is a button change rather than a rewrite.
func cancel_aim() -> void:
	_aim_slot = -1
	_aim_vector = Vector2.ZERO
	command.aiming_slot = -1


## The slot being aimed, or -1. For the indicator, for the button, and for the harness.
func aiming_slot() -> int:
	return _aim_slot


## Where the live drag is pointing, screen space and y-up, or zero. Only the harness and the
## button's own nub want this; gameplay reads `command.aim_dir`, which is in world space.
func aim_vector() -> Vector2:
	return _aim_vector


## Takes the pending request and clears it, so one press produces exactly one cast. A
## character calls this from _physics_process; anything that only wants to look should read
## `command.ability_pressed` instead.
##
## Consuming the cast also releases the aim latched with it: that direction was held only to
## survive the gap between the lift and this tick, and holding it any longer would pin the
## wizard's facing to the last thing they cast.
## Drops a standing walk order and anything armed. The level calls this when a round resets:
## a wizard respawned at their spawn point must not immediately set off toward wherever they
## had clicked in the round before.
func clear_orders() -> void:
	_click_move_active = false
	_click_move = Vector2.ZERO
	_move_click_pending = false
	disarm()


func consume_ability() -> int:
	var slot := _pending_ability
	_pending_ability = -1
	if slot >= 0:
		_latched_has_aim = false
		_latched_aim = Vector2.ZERO
	return slot


## Test-harness entry point. Lets an automated run steer the player without synthetic
## input events, which is the only way to verify movement in a headless/scripted run.
func set_override_vector(vector: Vector2, active: bool) -> void:
	_override_vector = vector
	_override_active = active


func _read_raw() -> Vector2:
	if _override_active:
		return _override_vector.limit_length(1.0)
	if _touch_active:
		return _shape_stick(_touch_vector)
	# Keyboard fallback for desktop testing. y is +1 for "forward/up the screen" so it
	# matches the joystick convention above and needs no special case downstream.
	return Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_back", "move_forward")
	).limit_length(1.0)


## Turns a raw stick reading into a movement request, applying the deadzone and sensitivity.
##
## The deadzone RESCALES rather than clipping. A plain cutoff - "below the threshold return
## zero, otherwise return the raw value" - means the slowest speed a player can ask for is
## the deadzone itself, so the wizard snaps from stationary to 15% speed the moment the
## thumb clears the dead spot. Remapping the live range back onto 0..1 removes that step,
## which is the difference between a stick that feels analogue and one that feels like a
## d-pad with extra travel.
##
## Magnitude is handled as a single circular value, never per-axis. A per-axis clamp would
## let a diagonal reach a length of 1.414 and make the wizard measurably faster on the
## diagonals - the classic bug this game cannot afford, since positioning is the whole
## skill expression.
func _shape_stick(raw: Vector2) -> Vector2:
	var magnitude := raw.length()
	if magnitude <= touch_deadzone:
		return Vector2.ZERO
	var live := (magnitude - touch_deadzone) / (1.0 - touch_deadzone)
	return (raw / magnitude) * minf(live * touch_sensitivity, 1.0)


## Rotates a screen-space stick vector onto the world ground plane using the active
## camera's yaw. With the prototype's un-yawed camera this is close to identity, but
## going through the camera means tilting or rotating it later cannot invert the controls.
func _screen_to_world(raw: Vector2) -> Vector2:
	if raw == Vector2.ZERO:
		return Vector2.ZERO
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# No camera yet (first frame of a scene change). Treat screen-up as world -Z.
		return Vector2(raw.x, -raw.y)
	# Flatten the camera's basis onto the ground plane. "into the screen" is -Z locally.
	var forward := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var flat_forward := Vector2(forward.x, forward.z)
	var flat_right := Vector2(right.x, right.z)
	if flat_forward.length_squared() < 0.0001:
		# Camera points straight down; its "up" on screen is the -Y basis instead.
		var up := cam.global_transform.basis.y
		flat_forward = Vector2(up.x, up.z)
	flat_forward = flat_forward.normalized()
	flat_right = flat_right.normalized()
	return flat_right * raw.x + flat_forward * raw.y

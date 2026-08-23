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

## The live command. Read this, don't cache it — it is refreshed in place each frame.
var command := InputCommand.new()

var _touch_vector := Vector2.ZERO
var _touch_active := false
var _override_vector := Vector2.ZERO
var _override_active := false


func _process(_delta: float) -> void:
	var raw := _read_raw()
	var world := _screen_to_world(raw)
	command.move_dir = world
	command.has_move_input = world.length_squared() > 0.0
	command_updated.emit(command)


## Called by the virtual joystick once it exists. `vector` is in screen space with
## y pointing UP the screen, matching how a stick is drawn; length 0..1.
func set_touch_vector(vector: Vector2, active: bool) -> void:
	_touch_vector = vector
	_touch_active = active


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

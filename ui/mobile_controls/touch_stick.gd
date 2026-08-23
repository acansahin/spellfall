class_name TouchStick
extends Control

## An on-screen thumbstick. Produces a normalised Vector2 and nothing else.
##
## This scene contains ZERO gameplay logic. It does not know what a Player is, what
## PlayerInputController is, or what its output will be used for. It emits
## `vector_changed` and something above it decides what that means — which is the
## "signals decouple upward" rule from ARCHITECTURE.md, and is what makes this scene
## reusable for any future stick (a second one for aiming, for instance).
##
## Deadzone deliberately lives DOWNSTREAM in PlayerInputController, not here. This node
## reports honestly where the thumb is; the gameplay layer decides how much of that to
## ignore. Keeping the deadzone here would mean the visual thumb and the gameplay value
## disagreed, and would put a tuning number in a UI scene.
##
## TOUCH OWNERSHIP: this is the part that matters for a two-thumb game. The stick claims
## exactly one touch index — the finger that went down inside its activation area — and
## ignores every other finger completely. Events belonging to other indices are never
## consumed, so future ability buttons on the right side receive them untouched.

## Emitted whenever the stick value changes. `vector` has y pointing UP the screen (the
## opposite of Godot's screen-y) because that is the convention PlayerInputController
## documents for `set_touch_vector`. Length is 0..1.
signal vector_changed(vector: Vector2, active: bool)

## Radius of the drawn base, in canvas units. The Control's own rect is sized to match.
@export var base_radius := 110.0:
	set(value):
		base_radius = value
		custom_minimum_size = Vector2.ONE * value * 2.0
		size = custom_minimum_size
		queue_redraw()

## Radius of the drawn thumb.
@export var thumb_radius := 48.0:
	set(value):
		thumb_radius = value
		queue_redraw()

## Extra grab room around the base, in canvas units. A thumb that lands slightly outside
## the drawn circle should still take the stick. Keep this modest — the activation area
## must never reach across to where the ability buttons will live.
@export var activation_padding := 44.0

@export_group("Appearance")
@export var base_fill := Color(1, 1, 1, 0.10)
@export var base_ring := Color(1, 1, 1, 0.38)
@export var thumb_fill := Color(0.72, 0.86, 1.0, 0.40)
@export var thumb_ring := Color(0.85, 0.94, 1.0, 0.65)

## The finger currently driving the stick. -1 means nobody. This is the whole of the
## multi-touch story: one index, claimed on press, released on that same index lifting.
var _touch_index := -1

## Centre the thumb is measured from, in this Control's LOCAL space. Held as a variable
## rather than always being `size * 0.5` so a floating/dynamic stick is a small change
## later: the claim branch in `_handle_touch()` would set this to the touch point instead
## of leaving it where `_recentre()` put it, and nothing else in this file — or anywhere
## downstream — would need to move. That is the only line dynamic mode would touch.
var _centre := Vector2.ZERO

## Thumb offset from `_centre`, in local space, already clamped to `base_radius`.
var _thumb_offset := Vector2.ZERO

var _vector := Vector2.ZERO


func _ready() -> void:
	# Raw touch events are handled in _input() with a manual hit test, so this Control
	# must not also participate in GUI picking - that would let Godot's single-pointer
	# GUI routing swallow a second finger.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * base_radius * 2.0
	size = custom_minimum_size
	_recentre()
	resized.connect(_recentre)


func _recentre() -> void:
	_centre = size * 0.5
	queue_redraw()


func _input(event: InputEvent) -> void:
	# A hidden stick must not claim fingers. Node._input keeps firing on invisible nodes
	# (unlike Control._gui_input), so without this the desktop build would silently eat
	# mouse-emulated touches with nothing drawn to explain why.
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		# Only claim if we are idle AND this finger landed on us. Any other press is
		# left entirely alone - not consumed, not inspected further.
		if _touch_index == -1 and _activation_rect().has_point(event.position):
			_touch_index = event.index
			_move_thumb(event.position)
			get_viewport().set_input_as_handled()
	elif event.index == _touch_index:
		_release()
		get_viewport().set_input_as_handled()


func _handle_drag(event: InputEventScreenDrag) -> void:
	# A drag from a finger we do not own is someone else's business.
	if event.index != _touch_index:
		return
	_move_thumb(event.position)
	get_viewport().set_input_as_handled()


## Activation area in GLOBAL canvas coordinates, which is the space touch events arrive in.
func _activation_rect() -> Rect2:
	return get_global_rect().grow(activation_padding)


func _move_thumb(global_pos: Vector2) -> void:
	var local := global_pos - global_position
	var offset := local - _centre
	# Clamp to the base so the thumb never leaves the ring and the magnitude never
	# exceeds 1.0. This is also what stops a diagonal from being longer than a cardinal:
	# limit_length is a circular clamp, not a per-axis one.
	_thumb_offset = offset.limit_length(base_radius)
	# Screen y grows downward; the stick convention is y-up. Flip here, once.
	_publish(Vector2(_thumb_offset.x, -_thumb_offset.y) / base_radius)


func _release() -> void:
	_touch_index = -1
	_thumb_offset = Vector2.ZERO
	# Snap home immediately. No return animation - a stick that eases back keeps
	# reporting movement after the player has stopped asking for it.
	_publish(Vector2.ZERO)


func _publish(vector: Vector2) -> void:
	_vector = vector
	queue_redraw()
	vector_changed.emit(_vector, is_active())


## True while a finger owns the stick.
func is_active() -> bool:
	return _touch_index != -1


## Current value, y-up, length 0..1. Handy for tests and debug readouts.
func value() -> Vector2:
	return _vector


## Which finger owns the stick, or -1. Exposed so an automated run can assert ownership.
func touch_index() -> int:
	return _touch_index


func _draw() -> void:
	draw_circle(_centre, base_radius, base_fill)
	draw_arc(_centre, base_radius, 0.0, TAU, 48, base_ring, 3.0, true)
	var thumb := _centre + _thumb_offset
	draw_circle(thumb, thumb_radius, thumb_fill)
	draw_arc(thumb, thumb_radius, 0.0, TAU, 32, thumb_ring, 2.0, true)

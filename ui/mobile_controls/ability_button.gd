class_name AbilityButton
extends Control

## A round spell button for the right thumb.
##
## Same deal as TouchStick: it reports a press and draws a state. It never casts anything,
## never touches a cooldown, and never decides whether a cast is allowed - it emits
## `pressed_slot` and the level turns that into a request. If this script ever calls
## `try_cast`, the input pipeline has been bypassed and touch has stopped behaving like the
## keyboard.
##
## It DOES read the spellbook, but only to draw: which colour, and how much cooldown is
## left. That is the normal direction for UI (a view reads its model); what would be wrong
## is holding gameplay state here, or writing to it.
##
## TOUCH OWNERSHIP works exactly as it does on the stick - one claimed index, foreign fingers
## ignored and never consumed. That is what lets a thumb hold the stick while another taps
## this, which is the entire point of building them the same way.

## Emitted the moment a finger lands on the button. Press, not release: in a game where a
## dodge is a third of a second, waiting for the lift adds latency the player feels and
## cannot explain.
signal pressed_slot(slot: int)

## Which slot in the AbilityComponent this button drives.
@export var slot: int = 0

@export var radius := 72.0:
	set(value):
		radius = value
		custom_minimum_size = Vector2.ONE * value * 2.0
		size = custom_minimum_size
		queue_redraw()

## Extra grab room, same idea as the stick's. Keep it small enough that it never reaches
## across the screen into the stick's activation area.
@export var activation_padding := 16.0

@export_group("Appearance")
@export var idle_ring := Color(1, 1, 1, 0.45)
@export var cooldown_veil := Color(0, 0, 0, 0.55)
@export var press_flash := Color(1, 1, 1, 0.22)

## Read-only view of the caster's spellbook, assigned by the level. Null is fine - the
## button then draws itself as an empty slot rather than crashing.
var source: AbilityComponent = null:
	set(value):
		source = value
		queue_redraw()

var _touch_index := -1
var _centre := Vector2.ZERO
var _last_fraction := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ONE * radius * 2.0
	size = custom_minimum_size
	_recentre()
	resized.connect(_recentre)


func _recentre() -> void:
	_centre = size * 0.5
	queue_redraw()


func _process(_delta: float) -> void:
	# Redraw only when the sweep actually moves. A radial cooldown redrawn every frame for
	# no reason is exactly the kind of idle cost a mid-range phone cannot spare.
	var f := _fraction()
	if not is_equal_approx(f, _last_fraction):
		_last_fraction = f
		queue_redraw()


func _fraction() -> float:
	return source.cooldown_fraction(slot) if source != null else 0.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		# Own the drag so a finger sliding off the button is not handed to anything else,
		# but there is nothing to update - this is a button, not a stick.
		get_viewport().set_input_as_handled()


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _activation_rect().has_point(event.position):
			_touch_index = event.index
			pressed_slot.emit(slot)
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event.index == _touch_index:
		_touch_index = -1
		queue_redraw()
		get_viewport().set_input_as_handled()


func _activation_rect() -> Rect2:
	return get_global_rect().grow(activation_padding)


func is_held() -> bool:
	return _touch_index != -1


func touch_index() -> int:
	return _touch_index


func _draw() -> void:
	var ability: Ability = source.ability_in(slot) if source != null else null
	var tint := ability.colour if ability != null else Color(0.5, 0.5, 0.5)

	draw_circle(_centre, radius, Color(tint.r, tint.g, tint.b, 0.30))
	if _touch_index != -1:
		draw_circle(_centre, radius, press_flash)
	draw_arc(_centre, radius, 0.0, TAU, 40, idle_ring, 3.0, true)

	var fraction := _fraction()
	if fraction > 0.0:
		_draw_cooldown_wedge(fraction)


## Darkens the slice of the button still on cooldown, unwinding clockwise from the top.
## A wedge rather than a shrinking ring because a wedge reads as "how much time is left"
## at a glance, which is the only thing this needs to communicate mid-fight.
##
## Drawn as one very thick arc rather than a triangle fan: an arc of radius r/2 with a width
## of r covers the disc from centre to rim in a single call, with no polygon to build and no
## triangulation to think about.
##
## Verified by measuring pixels, not by eye - `--cast-at:1.0` with shots at +0.05s, +0.45s
## and +0.85s gives 94%, 50% and 5% of the disc darkened, against a 0.9s cooldown.
func _draw_cooldown_wedge(fraction: float) -> void:
	var start := -PI * 0.5
	var end_angle := start + TAU * fraction
	var segments := maxi(6, int(48.0 * fraction))
	draw_arc(_centre, radius * 0.5, start, end_angle, segments, cooldown_veil, radius, false)

class_name AbilityButton
extends Control

## A round spell button for the right thumb. Press it, drag to aim, lift to cast.
##
## Same deal as TouchStick: it reports where a finger is and draws a state. It never casts
## anything, never touches a cooldown, and never decides whether a cast is allowed - it emits
## what the thumb did and the level turns that into a request. If this script ever calls
## `try_cast`, the input pipeline has been bypassed and touch has stopped behaving like the
## keyboard.
##
## It DOES read the spellbook, but only to draw: which colour, and how much cooldown is
## left. That is the normal direction for UI (a view reads its model); what would be wrong
## is holding gameplay state here, or writing to it.
##
## TOUCH OWNERSHIP works exactly as it does on the stick - one claimed index, foreign fingers
## ignored and never consumed. That is what lets a thumb hold the stick while another drags
## this one, which is the entire point of building them the same way.
##
## The AIM DEADZONE is not here. It lives in PlayerInputController, for the reason written on
## TouchStick: this widget reports honestly where the thumb went, and the gameplay layer
## decides how much of that it believes. So the nub below can sit slightly off-centre while
## the cast is still going to come out as a tap - exactly as the stick's thumb leaves its
## centre before the wizard starts moving.

## A finger landed. The player is now aiming this slot; nothing has been cast.
signal aim_started(slot: int)

## The finger moved. `vector` is measured from where the finger LANDED, in canvas units, with
## y pointing UP the screen - the TouchStick convention, so both controls speak one language.
## Not normalised and not clamped: the length is real, and downstream decides what counts.
signal aim_moved(slot: int, vector: Vector2)

## The finger lifted. THIS is the cast. See PlayerInputController.begin_aim for why the cast
## moved off the press and onto the lift.
signal cast_released(slot: int)

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
## The dark plate under a button, so the world behind it cannot be read through it.
##
## Deliberately not black, like everything else on this screen: a black disc reads as a hole
## punched in the picture. This is the same deep blue-violet the scene's background clears to.
@export var backdrop := Color(0.07, 0.06, 0.13, 0.62)

@export var idle_ring := Color(1, 1, 1, 0.45)
@export var cooldown_veil := Color(0, 0, 0, 0.55)
@export var press_flash := Color(1, 1, 1, 0.22)
## The little marker that follows the drag, so the player can see the aim they are giving
## without looking away from their wizard.
@export var aim_nub := Color(1, 1, 1, 0.85)

## How much of the button's radius the spell's glyph takes up. Small enough that the cooldown
## wedge sweeping over it still reads, large enough to tell apart under a thumb.
@export_range(0.2, 0.9, 0.01) var glyph_scale := 0.52

## The key that casts this slot, printed small in the corner. Empty on a device with no
## keyboard. Set by the level, which is the only thing that knows which kind of device this is.
var key_label := "":
	set(value):
		key_label = value
		queue_redraw()

## True while this slot is the one waiting for a place to go.
##
## On a desk this is the ONLY feedback a key press gives. A thumb sees its own finger on the
## button; a keyboard shows nothing at all, and Q/W/E felt like keys that did not work at all
## until the button they belong to lit up.
var armed := false:
	set(value):
		armed = value
		queue_redraw()

## Read-only view of the caster's spellbook, assigned by the level. Null is fine - the
## button then draws itself as an empty slot rather than crashing.
var source: AbilityComponent = null:
	set(value):
		source = value
		queue_redraw()

var _touch_index := -1

## Where the claiming finger first touched, in global canvas space. The aim is measured from
## HERE and not from the button's centre: a thumb lands wherever it lands, and measuring from
## the centre would fold that landing error into every shot.
var _press_at := Vector2.ZERO

## Live drag offset, y-up, in canvas units. Zero until the finger moves.
var _drag := Vector2.ZERO

var _centre := Vector2.ZERO
var _last_fraction := -1.0

## The spell this button drew last time. Watched because a loadout can be applied to the SAME
## AbilityComponent - the `source` setter never fires - and the button only redraws when its
## cooldown moves. Without this it keeps showing the previous spell's glyph until the player
## casts something, which reads as a button that did not take the choice they just made.
var _last_ability: Ability = null


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
	var showing := source.ability_in(slot) if source != null else null
	if not is_equal_approx(f, _last_fraction) or showing != _last_ability:
		_last_fraction = f
		_last_ability = showing
		queue_redraw()


func _fraction() -> float:
	return source.cooldown_fraction(slot) if source != null else 0.0


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _touch_index == -1 and _claims(event.position):
			_touch_index = event.index
			_press_at = event.position
			_drag = Vector2.ZERO
			aim_started.emit(slot)
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event.index == _touch_index:
		# A lift carries a position of its own, and on a real device it usually differs from
		# the last drag. Use it, so a fast flick that ends between drag events still aims
		# where it actually ended.
		_track(event.position)
		cast_released.emit(slot)
		_touch_index = -1
		_drag = Vector2.ZERO
		queue_redraw()
		get_viewport().set_input_as_handled()


## Own the drag: a finger that slid off the button is still aiming this spell, and must not
## be handed to anything underneath. The button deliberately does NOT let go when the finger
## leaves its disc - dragging away is the gesture, not a mistake.
func _handle_drag(event: InputEventScreenDrag) -> void:
	_track(event.position)
	get_viewport().set_input_as_handled()


func _track(global_pos: Vector2) -> void:
	var offset := global_pos - _press_at
	# Screen y grows downward; both touch controls report y-up. Flip here, once.
	_drag = Vector2(offset.x, -offset.y)
	aim_moved.emit(slot, _drag)
	queue_redraw()


## True if `point` lands on this button.
##
## A DISC, not the bounding box. The button is drawn as a circle, so a square hit area claims
## the corners of a square nobody can see - and with four buttons in a cluster those invisible
## corners overlap, which turns "tap Teleport" into "cast whichever button sits earlier in the
## scene tree". Matching the hit area to the drawing is what lets the cluster be tight enough
## to reach with one thumb.
func _claims(point: Vector2) -> bool:
	return get_global_rect().get_center().distance_to(point) <= radius + activation_padding


## The square that contains the hit area. Used by the layout assertions, which only need to
## know that one finger cannot reach two controls, and for which a conservative box is the
## right shape to compare.
func _activation_rect() -> Rect2:
	return get_global_rect().grow(activation_padding)


func is_held() -> bool:
	return _touch_index != -1


func touch_index() -> int:
	return _touch_index


## The live drag, y-up, in canvas units. For the harness.
func aim_drag() -> Vector2:
	return _drag


func _draw() -> void:
	var ability: Ability = source.ability_in(slot) if source != null else null
	var tint := ability.colour if ability != null else Color(0.5, 0.5, 0.5)

	# Two discs, not one: a dark plate first, then the spell's colour over it.
	#
	# The single 30%-alpha disc that used to be here was fine over a flat orange background and
	# stopped being fine the moment the lava had a TEXTURE in it - the crust pattern read
	# straight through the button and the glyph sat in the middle of it. A button has to be a
	# button whatever happens to be behind it, and what was behind it was always going to
	# change. The plate is the fix; the tint on top is what still says which spell this is.
	draw_circle(_centre, radius, backdrop)
	draw_circle(_centre, radius, Color(tint.r, tint.g, tint.b, 0.34))
	if _touch_index != -1:
		draw_circle(_centre, radius, press_flash)
	draw_arc(_centre, radius, 0.0, TAU, 40, idle_ring, 3.0, true)
	if armed:
		# A bright ring in the spell's own colour, drawn OUTSIDE the rim so the cooldown veil
		# cannot cover it. "Held, waiting for a click" has to read from the corner of an eye.
		draw_arc(_centre, radius + 5.0, 0.0, TAU, 44, Color(tint.r, tint.g, tint.b, 0.95),
			4.0, true)

	# Before the wedge, deliberately: a recharging spell should have its own icon greyed out
	# by the veil rather than sitting bright on top of it, so "not yet" is one reading and not
	# two. Lifted well clear of the disc's own 30% tint, or the shape disappears into it.
	if ability != null:
		SpellGlyph.draw_into(self, ability.glyph, _centre, radius * glyph_scale,
			tint.lightened(0.35), maxf(radius * 0.055, 2.5))
		# Only where there are keys to name. On a phone these buttons ARE the input and a
		# letter over them would be a reminder of a keyboard nobody is holding.
		if key_label != "":
			# Placed against the BUTTON's rim rather than the glyph's corner. At the glyph's
			# size it landed on top of the drawing - the E sat inside Teleport's own dot - and a
			# reminder that obscures the thing it is reminding you of is worth less than
			# nothing.
			SpellGlyph.draw_key(self, key_label, _centre, radius * 0.74,
				tint.lightened(0.5))

	var fraction := _fraction()
	if fraction > 0.0:
		_draw_cooldown_wedge(fraction)

	if _touch_index != -1 and _drag.length_squared() > 1.0:
		_draw_aim_nub()


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


## A short line and a dot showing which way the thumb is dragging.
##
## Small, and kept inside the button on purpose. The REAL aim feedback is the indicator on
## the ground, which is where the player is already looking; this is here only so the finger
## doing the aiming can be seen doing it, under a thumb that is covering the button anyway.
func _draw_aim_nub() -> void:
	# Screen space again: the drag is y-up, the canvas is y-down.
	var dir := Vector2(_drag.x, -_drag.y).normalized()
	var tip := _centre + dir * (radius * 0.72)
	draw_line(_centre, tip, aim_nub, 4.0, true)
	draw_circle(tip, 9.0, aim_nub)

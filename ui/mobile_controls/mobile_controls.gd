class_name MobileControls
extends CanvasLayer

## Holds the touch controls and decides where they sit and whether they are shown.
##
## Separate from TouchStick on purpose: the stick is a reusable widget that knows only about
## thumbs, and this layer knows about *screens* — margins, safe areas, and whether this device
## has a touchscreen at all. The four spell buttons are children here for the same reason, and
## adding a fifth would be a scene edit and a layout angle, not a rewrite.
##
## RESOLUTION INDEPENDENCE: the stretch mode is `canvas_items` with aspect `expand`, so the
## canvas is always 720 units tall and grows *wider* on taller-aspect phones. Anchoring the
## stick to the bottom-left corner and offsetting it in canvas units therefore puts it at
## the same physical spot on the glass on every device — a 16:9 and a 20:9 phone differ in
## how much void is visible at the sides, not in where your thumb rests. That is why these
## margins are plain canvas units and not a fraction of the viewport width, which would
## drift the stick inward as the screen got wider.

enum Visibility {
	## Show when the device has a touchscreen, or when mouse-to-touch emulation is on so
	## the controls can be inspected on a desktop dev build. This is the shipping value.
	AUTO,
	## Always draw them, whatever the device. Useful for screenshots.
	ALWAYS,
	## Never draw them.
	HIDDEN,
}

@export var visibility_mode: Visibility = Visibility.AUTO:
	set(value):
		visibility_mode = value
		_apply_visibility()

## Distance from the bottom-left corner of the screen to the stick's bounding box, in
## canvas units. Large enough that the stick is not under the heel of the thumb and not
## in the system gesture strip along the very edge.
@export var joystick_margin := Vector2(96.0, 76.0):
	set(value):
		joystick_margin = value
		_layout()

## Distance from the bottom-RIGHT corner to the PRIMARY spell button. Kept clear of the
## stick's activation area on the far side of the screen, so the two can never claim one
## finger.
@export var button_margin := Vector2(110.0, 96.0):
	set(value):
		button_margin = value
		_layout()

## How far the three secondary buttons sit from the primary's centre, in canvas units.
##
## Wide enough that no two hit areas touch — with the primary at radius 72 and a secondary at
## 52, plus 16 units of grab room each, 140 is where they would start to share a finger. The
## rest is thumb comfort: this is roughly the arc a right thumb sweeps without the hand moving.
@export var satellite_radius := 170.0:
	set(value):
		satellite_radius = value
		_layout()

## Where each secondary button sits on that arc, in degrees, screen-space (y down, so
## negative is up). They fan up and to the LEFT of the primary because that is the direction
## a right thumb travels; mirroring for left-handed play is a settings screen away and there
## is no settings screen yet.
@export var satellite_angles := PackedFloat32Array([-75.0, -130.0, -185.0])

## The movement stick. Public so the level can connect its signal to the input
## controller - this layer deliberately does not do that wiring itself, because it has no
## business knowing what the stick's output is for.
@onready var joystick: TouchStick = $TouchStick

## The spell buttons, in slot order. Public for the same reason: the level wires them to the
## input controller, because this layer has no business knowing what a press is FOR.
var buttons: Array[AbilityButton] = []


func _ready() -> void:
	_collect_buttons()
	_apply_visibility()
	_layout()
	# Rotating the device or resizing the window moves the corner the stick is pinned to.
	get_viewport().size_changed.connect(_layout)
	joystick.resized.connect(_layout)
	for button in buttons:
		button.resized.connect(_layout)


## Gathers the buttons from the scene and puts them in slot order.
##
## Read out of the tree rather than listed here, so adding a spell button is adding a node.
## Sorted by `slot` rather than trusting tree order, because the two disagreeing would place
## Blink where the player expects Fireball, and nothing about the screen would look wrong.
func _collect_buttons() -> void:
	buttons.clear()
	for child in get_children():
		var button := child as AbilityButton
		if button != null:
			buttons.append(button)
	buttons.sort_custom(func(a: AbilityButton, b: AbilityButton) -> bool: return a.slot < b.slot)


func _apply_visibility() -> void:
	visible = _should_show()


func _should_show() -> bool:
	match visibility_mode:
		Visibility.ALWAYS:
			return true
		Visibility.HIDDEN:
			return false
		_:
			return DisplayServer.is_touchscreen_available() \
				or Input.is_emulating_touch_from_mouse()


func _layout() -> void:
	if joystick == null or buttons.is_empty():
		return
	var inset := _safe_area_inset()
	var stick_size := joystick.size
	# Anchor to the viewport's bottom-left corner, then offset up and right from it.
	joystick.anchor_left = 0.0
	joystick.anchor_right = 0.0
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = joystick_margin.x + inset.x
	joystick.offset_right = joystick.offset_left + stick_size.x
	joystick.offset_bottom = -(joystick_margin.y + inset.w)
	joystick.offset_top = joystick.offset_bottom - stick_size.y

	# The spells hang off the opposite corner, so the two thumbs never share space. The
	# primary keeps the exact spot the single button used to have; the rest fan off it.
	var primary := buttons[0]
	var anchor := Vector2(
		-(button_margin.x + inset.z) - primary.size.x * 0.5,
		-(button_margin.y + inset.w) - primary.size.y * 0.5)
	_place(primary, anchor)
	for i in range(1, buttons.size()):
		var degrees := 0.0
		if i - 1 < satellite_angles.size():
			degrees = satellite_angles[i - 1]
		var radians := deg_to_rad(degrees)
		_place(buttons[i], anchor + Vector2(cos(radians), sin(radians)) * satellite_radius)


## Pins a button to the bottom-right corner and puts its CENTRE at `centre`, measured from
## that corner. Centres rather than edges because the cluster is described as angles on an
## arc, and an arc is a statement about centres.
func _place(button: AbilityButton, centre: Vector2) -> void:
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.anchor_top = 1.0
	button.anchor_bottom = 1.0
	var half := button.size * 0.5
	button.offset_left = centre.x - half.x
	button.offset_right = centre.x + half.x
	button.offset_top = centre.y - half.y
	button.offset_bottom = centre.y + half.y


## Extra margin needed to clear a notch, rounded corner or home indicator, converted from
## native screen pixels into canvas units.
##
## Only consulted on mobile. On desktop `get_display_safe_area()` reports the whole monitor
## while the window is usually smaller, so the two are not comparable and the arithmetic
## would produce a meaningless inset. Guarding on the feature flag keeps this honest rather
## than clever — this is the whole of the device-specific handling, deliberately.
## Returned as (left, top, right, bottom) so each edge gets its own number. An earlier
## version returned only two and the right-hand button was offset by the BOTTOM inset,
## which happens to look fine on a device with no notch and wrong on every device with one.
func _safe_area_inset() -> Vector4:
	if not OS.has_feature("mobile"):
		return Vector4.ZERO
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var scale := get_viewport().get_visible_rect().size / window
	return Vector4(
		maxf(float(safe.position.x) * scale.x, 0.0),
		maxf(float(safe.position.y) * scale.y, 0.0),
		maxf((window.x - float(safe.position.x + safe.size.x)) * scale.x, 0.0),
		maxf((window.y - float(safe.position.y + safe.size.y)) * scale.y, 0.0))

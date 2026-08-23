class_name MobileControls
extends CanvasLayer

## Holds the touch controls and decides where they sit and whether they are shown.
##
## Separate from VirtualJoystick on purpose: the stick is a reusable widget that knows only
## about thumbs, and this layer knows about *screens* — margins, safe areas, and whether
## this device has a touchscreen at all. When the four ability buttons arrive they become
## children here and inherit the same placement rules without the stick changing.
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

## The movement stick. Public so the level can connect its signal to the input
## controller - this layer deliberately does not do that wiring itself, because it has no
## business knowing what the stick's output is for.
@onready var joystick: TouchStick = $TouchStick


func _ready() -> void:
	_apply_visibility()
	_layout()
	# Rotating the device or resizing the window moves the corner the stick is pinned to.
	get_viewport().size_changed.connect(_layout)
	joystick.resized.connect(_layout)


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
	if joystick == null:
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
	joystick.offset_bottom = -(joystick_margin.y + inset.y)
	joystick.offset_top = joystick.offset_bottom - stick_size.y


## Extra margin needed to clear a notch, rounded corner or home indicator, converted from
## native screen pixels into canvas units.
##
## Only consulted on mobile. On desktop `get_display_safe_area()` reports the whole monitor
## while the window is usually smaller, so the two are not comparable and the arithmetic
## would produce a meaningless inset. Guarding on the feature flag keeps this honest rather
## than clever — this is the whole of the device-specific handling, deliberately.
func _safe_area_inset() -> Vector2:
	if not OS.has_feature("mobile"):
		return Vector2.ZERO
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return Vector2.ZERO
	var safe := DisplayServer.get_display_safe_area()
	var scale := get_viewport().get_visible_rect().size / window
	var left := float(safe.position.x) * scale.x
	var bottom := (window.y - float(safe.position.y + safe.size.y)) * scale.y
	return Vector2(maxf(left, 0.0), maxf(bottom, 0.0))

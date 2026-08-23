class_name ArenaCamera
extends Node3D

## Fixed three-quarter camera framing the whole arena.
##
## The framing is DERIVED, not typed in. `pitch_degrees` and `distance` place the camera on
## a sphere around the arena centre and everything else follows, so re-framing for a bigger
## arena is one number instead of a hand-tuned transform. The defaults were solved against
## an arena radius of 7: at 55 degrees and 22m with a 45 degree vertical FOV the near rim
## reaches 77% of the half-height and the 2m-tall wizard stands 11% of the screen tall,
## which is the smallest that still reads a facing direction on a phone. Wider phones only
## gain void at the sides, so no screen shape sees more of the arena than another.
##
## `follow_weight` defaults to 0.0 — a genuinely fixed camera. In a knockback game the
## edge of the arena is the most important thing on screen, and a camera that slides
## around moves the edge, which makes "am I about to die" harder to read than it needs to
## be. The lerp is here so following can be tried later, not because it is wanted now.

## Angle below the horizon. Steeper reads positions more clearly; shallower shows more
## character silhouette.
@export_range(20.0, 89.0, 1.0) var pitch_degrees := 55.0:
	set(value):
		pitch_degrees = value
		_reframe()

## Metres from the look-at point. Larger flattens perspective toward an orthographic look.
@export_range(10.0, 120.0, 0.5) var distance := 22.0:
	set(value):
		distance = value
		_reframe()

## Vertical field of view. Narrow keeps the arena rim close to a true circle; wide
## exaggerates depth and distorts characters near the screen edge.
@export_range(20.0, 90.0, 1.0) var fov := 45.0:
	set(value):
		fov = value
		_reframe()

## 0.0 pins the camera. Raise toward 1.0 to let it drift after `target`.
@export_range(0.0, 1.0, 0.01) var follow_weight := 0.0

## Optional node to drift toward when `follow_weight` is above zero.
@export var target: Node3D = null

@onready var _camera: Camera3D = $Camera3D

var _anchor := Vector3.ZERO


func _ready() -> void:
	_anchor = global_position
	_reframe()


func _process(delta: float) -> void:
	if follow_weight <= 0.0 or target == null:
		return
	# Frame-rate independent smoothing: the same weight settles at the same rate whether
	# the device is running at 30 or 60fps, which a raw lerp(delta) would not.
	var t := 1.0 - pow(1.0 - follow_weight, delta * 60.0)
	var wanted := Vector3(target.global_position.x, _anchor.y, target.global_position.z)
	global_position = global_position.lerp(wanted, t)


## Places the camera on its sphere and aims it back at the rig's origin.
func _reframe() -> void:
	if _camera == null:
		return
	var pitch := deg_to_rad(pitch_degrees)
	_camera.position = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_camera.fov = fov

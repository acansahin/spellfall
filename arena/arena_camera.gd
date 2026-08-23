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

@export_group("Shake")
## How far the camera may be thrown at full shake, in metres, measured in its OWN plane -
## so this is screen-space jitter, not a wobble in the world.
##
## Small on purpose. The arena rim is the most important thing on screen and shake moves it;
## enough to feel the hit, not enough to make you misjudge an edge you are standing on.
@export var shake_offset := 0.42

## How fast a shake dies, in units of shake per second. At 6.0 a full-strength jolt is over
## in under a fifth of a second, which is roughly the length of the hit that caused it.
@export var shake_decay := 6.0

@onready var _camera: Camera3D = $Camera3D

var _anchor := Vector3.ZERO

## Current shake, 0..1. The offset applied is this SQUARED, which is what makes a shake feel
## like it snaps back: a linear fade spends most of its life at a wobble the player can still
## see, and the eye reads that as the camera being loose rather than as an impact.
var _shake := 0.0

## Where `_reframe()` put the camera. The shake is added on top of this each frame rather
## than accumulated into it - reading the shaken position back as "where the camera lives" is
## how a shake turns into a slow drift nothing ever recovers from.
var _framed := Vector3.ZERO


func _ready() -> void:
	_anchor = global_position
	_reframe()


func _process(delta: float) -> void:
	_tick_shake(delta)
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
	_framed = Vector3(0.0, sin(pitch), cos(pitch)) * distance
	_camera.position = _framed
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_camera.fov = fov


## Jolts the camera. `amount` is 0..1 and ADDS to whatever is still shaking, clamped - two
## hits landing together should feel like more, but never like the camera came loose.
func shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


## Current shake level, for the harness.
func shake_level() -> float:
	return _shake


func _tick_shake(delta: float) -> void:
	if _shake <= 0.0:
		if _camera != null and _camera.position != _framed:
			_camera.position = _framed
		return
	_shake = maxf(0.0, _shake - shake_decay * delta)
	if _camera == null:
		return
	# Offset in the camera's own x/y, so the jitter is across the screen rather than into it.
	# A new random point every frame rather than a smooth curve: at 60Hz that is the
	# difference between an impact and a seasick float.
	var jolt := shake_offset * _shake * _shake
	_camera.position = _framed + Vector3(
		randf_range(-jolt, jolt), randf_range(-jolt, jolt), 0.0)

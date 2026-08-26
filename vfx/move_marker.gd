class_name MoveMarker
extends MeshInstance3D

## The green mark a right click leaves on the ground.
##
## Click-to-move has one weakness a keyboard does not: you cannot tell whether the game HEARD
## you. A key you are holding is its own feedback - the wizard is walking or it is not - but a
## click is a single instant, and a click the game missed and a click that landed on a spot you
## misjudged look exactly the same. This is the difference.
##
## Four arrows closing on a point, pulsing once and fading, the way the arena map this game
## follows draws it. Inward, because four arrows closing on a spot NAME the spot; outward would
## read as something going off.
##
## A WORLD-space node owned by the level, like `GroundStreak` and for the same reason: it marks
## a place, and a place does not move when the wizard does.

## Seconds the mark takes to fade. Long enough to catch out of the corner of an eye, short
## enough that it is gone before the wizard arrives - it answers "did that register?", which is
## a question with a very short shelf life.
@export var duration := 0.55

## Radius the arrows sit at, in metres, at rest.
@export var radius := 0.85

## How much of that radius each arrow takes up.
@export_range(0.1, 1.0, 0.05) var arrow_size := 0.5

@export var tint := Color(0.36, 1.0, 0.46)

## Metres above the floor. Enough to clear the arena's own surface without floating.
@export var lift := 0.06

var _life := 0.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	mesh = GroundShapes.arrows(radius, radius * arrow_size)
	_material = GroundShapes.flat_material(tint, 1.0)
	material_override = _material
	visible = false
	set_process(false)


## Puts the mark on the ground at `point` and starts it fading.
func show_at(point: Vector3) -> void:
	global_position = Vector3(point.x, lift, point.z)
	_life = duration
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		visible = false
		set_process(false)
		return
	var left := _life / duration
	# Shrinking rather than growing. A mark that expands reads as something arriving; one that
	# closes reads as something being pointed at, which is what a walk order is.
	scale = Vector3.ONE * lerpf(0.72, 1.3, left)
	_material.albedo_color = Color(tint.r, tint.g, tint.b, left)


## True while the mark is on screen. For the harness.
func is_showing() -> bool:
	return _life > 0.0

class_name SpellFlash
extends MeshInstance3D

## A flat fan of light on the ground, for a spell that happens instantly.
##
## Force Wave hits everything in its cone on the frame it is cast. With nothing drawn there
## is no way to connect "I tapped" to "they flew", and an instant spell you cannot see is one
## nobody can learn to dodge. Readability beats spectacle - see GAME_DESIGN.md - so this is a
## flat translucent fan and nothing else. The game-feel pass can make it beautiful.
##
## It is a CHILD of the fighter that casts, which is why nothing has to pool it or place it:
## there is exactly one per wizard, it is already where the caster is, and the fighter's body
## never rotates - only its Visual does - so a local yaw here is a world yaw.

## Seconds the fan stays on screen. Long enough to be seen at 30fps, short enough that it
## cannot be mistaken for a lingering area of effect, which it is not.
@export var duration := 0.22

## Alpha at full brightness, before the fade.
@export var peak_alpha := 0.55

var _life := 0.0
var _built_reach := -1.0
var _built_angle := -1.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	# Unshaded, two-sided and translucent, for the reasons written on GroundShapes itself.
	_material = GroundShapes.flat_material(Color(1, 1, 1), peak_alpha)
	material_override = _material
	visible = false
	set_process(false)


## Shows the fan for `duration`, pointing along `aim`.
##
## `reach` and `half_angle_deg` come straight off the Ability, so the drawing is the same
## shape as the hit test by construction rather than by a number copied into two places.
func play(reach: float, half_angle_deg: float, tint: Color, aim: Vector3) -> void:
	_rebuild(reach, half_angle_deg)
	_material.albedo_color = Color(tint.r, tint.g, tint.b, peak_alpha)
	var flat := Vector2(aim.x, aim.z)
	if flat.length_squared() > 0.0001:
		# Same convention as player.gd: yaw 0 looks down -Z, and the fan is built around -Z.
		rotation.y = atan2(-flat.x, -flat.y)
	_life = duration
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		visible = false
		set_process(false)
		return
	var fade := _life / maxf(duration, 0.0001)
	_material.albedo_color.a = peak_alpha * fade


## Builds the fan mesh, and only when its shape actually changed. A spell's numbers do not
## move at runtime, so in practice this runs once per wizard per spell shape and never again
## - which is the point, because building an ArrayMesh mid-fight is an allocation.
##
## The fan itself comes from GroundShapes, which is the SAME builder the aim indicator uses.
## What you sighted down and what went off are one shape by construction, not by two pieces
## of trigonometry that happen to agree today.
func _rebuild(reach: float, half_angle_deg: float) -> void:
	if is_equal_approx(reach, _built_reach) and is_equal_approx(half_angle_deg, _built_angle):
		return
	_built_reach = reach
	_built_angle = half_angle_deg
	mesh = GroundShapes.fan(reach, half_angle_deg)

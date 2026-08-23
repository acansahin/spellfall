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

## Straightness of the arc. Sixteen segments is smooth at this size and costs nothing.
const SEGMENTS := 16

var _life := 0.0
var _built_reach := -1.0
var _built_angle := -1.0
var _material: StandardMaterial3D = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	# Unshaded: this is light, not a surface, and it must read the same wherever the key
	# light happens to be pointing.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
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
func _rebuild(reach: float, half_angle_deg: float) -> void:
	if is_equal_approx(reach, _built_reach) and is_equal_approx(half_angle_deg, _built_angle):
		return
	_built_reach = reach
	_built_angle = half_angle_deg
	var half := deg_to_rad(half_angle_deg)

	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in SEGMENTS + 1:
		var a := lerpf(-half, half, float(i) / float(SEGMENTS))
		verts.append(Vector3(-sin(a), 0.0, -cos(a)) * reach)

	var indices := PackedInt32Array()
	for i in SEGMENTS:
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = built

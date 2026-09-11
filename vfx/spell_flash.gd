class_name SpellFlash
extends MeshInstance3D

## A flat fan of light on the ground, for a spell that happens instantly.
##
## Scourge hits everything in its cone on the frame it is cast. With nothing drawn there
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
var _style: StringName = &"force_wave"
var _rings: Array[MeshInstance3D] = []
var _ring_materials: Array[StandardMaterial3D] = []
var _motes: CPUParticles3D = null
var _reach := 1.0
var _active_alpha := 0.55


func _ready() -> void:
	# Unshaded, two-sided and translucent, for the reasons written on GroundShapes itself.
	_material = GroundShapes.flat_material(Color(1, 1, 1), peak_alpha)
	material_override = _material
	for i in 3:
		var ring := MeshInstance3D.new()
		ring.mesh = GroundShapes.ring(1.0, 0.10 + i * 0.025)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring_mat := GroundShapes.flat_material(Color.WHITE, 0.0)
		ring.material_override = ring_mat
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
		_ring_materials.append(ring_mat)
	_motes = CPUParticles3D.new()
	_motes.emitting = false
	_motes.one_shot = true
	_motes.explosiveness = 1.0
	_motes.amount = 24
	_motes.lifetime = 0.48
	_motes.direction = Vector3.UP
	_motes.spread = 78.0
	_motes.initial_velocity_min = 1.0
	_motes.initial_velocity_max = 3.4
	_motes.gravity = Vector3(0.0, -3.0, 0.0)
	var spark := BoxMesh.new()
	spark.size = Vector3(0.055, 0.18, 0.055)
	var spark_mat := StandardMaterial3D.new()
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mat.vertex_color_use_as_albedo = true
	spark.material = spark_mat
	_motes.mesh = spark
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	visible = false
	set_process(false)


## Shows the fan for `duration`, pointing along `aim`.
##
## `reach` and `half_angle_deg` come straight off the Ability, so the drawing is the same
## shape as the hit test by construction rather than by a number copied into two places.
func play(reach: float, half_angle_deg: float, tint: Color, aim: Vector3,
		style: StringName = &"force_wave") -> void:
	_rebuild(reach, half_angle_deg)
	_style = style
	_reach = reach
	scale = Vector3.ONE
	_active_alpha = 0.20 if style in [&"cataclysm", &"pious"] else peak_alpha
	_material.albedo_color = Color(tint.r, tint.g, tint.b, _active_alpha)
	var flat := Vector2(aim.x, aim.z)
	if flat.length_squared() > 0.0001:
		# Same convention as player.gd: yaw 0 looks down -Z, and the fan is built around -Z.
		rotation.y = atan2(-flat.x, -flat.y)
	_life = duration
	for i in _rings.size():
		var radial := style in [&"cataclysm", &"pious"]
		_rings[i].visible = radial
		_ring_materials[i].albedo_color = Color(tint.r, tint.g, tint.b,
			0.65 - i * 0.14)
		_rings[i].scale = Vector3.ONE * reach * (0.12 + i * 0.07)
	if style in [&"cataclysm", &"pious"]:
		_motes.color = tint
		_motes.initial_velocity_min = reach * 0.45
		_motes.initial_velocity_max = reach * 1.05
		_motes.restart()
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		visible = false
		set_process(false)
		return
	var fade := _life / maxf(duration, 0.0001)
	_material.albedo_color.a = _active_alpha * fade
	var spent := 1.0 - fade
	if _style in [&"cataclysm", &"pious"]:
		# Three differently paced fronts keep the burst from reading as one flat painted disc.
		for i in _rings.size():
			var progress := clampf(spent * (1.35 - i * 0.16), 0.0, 1.0)
			var radius := _reach * lerpf(0.12 + i * 0.06, 1.0, progress)
			_rings[i].scale = Vector3.ONE * radius
			_ring_materials[i].albedo_color.a = (0.65 - i * 0.14) * (1.0 - progress)
		rotation.y += delta * (2.6 if _style == &"pious" else -1.8)
	else:
		# Scourge pushes as a travelling wave: the light rolls from the caster to the rim.
		scale = Vector3(lerpf(0.72, 1.0, spent), 1.0, lerpf(0.24, 1.0, spent))


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
	scale = Vector3.ONE

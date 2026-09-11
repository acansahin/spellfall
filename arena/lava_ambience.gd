class_name LavaAmbience
extends Node3D

## Sparse activity over the visible lava near the glacier. Purely decorative and CPU-cheap.
var _flickers: CPUParticles3D
var _embers: CPUParticles3D


func _ready() -> void:
	position.y = 0.02
	_flickers = _build_flickers()
	_embers = _build_embers()
	_flickers.emitting = true
	_embers.emitting = true


func _build_flickers() -> CPUParticles3D:
	var particles := _ring_particles(14, 0.78)
	particles.direction = Vector3.UP
	particles.spread = 12.0
	particles.initial_velocity_min = 0.18
	particles.initial_velocity_max = 0.48
	particles.gravity = Vector3(0.0, 0.15, 0.0)
	particles.scale_amount_min = 0.58
	particles.scale_amount_max = 1.05
	var size := Curve.new()
	size.add_point(Vector2(0.0, 0.15))
	size.add_point(Vector2(0.22, 1.0))
	size.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = size
	var quad := QuadMesh.new()
	quad.size = Vector2(0.30, 0.62)
	var material := ShaderMaterial.new()
	material.shader = preload("res://vfx/hem_flame.gdshader")
	quad.material = material
	particles.mesh = quad
	particles.color = Color(1.0, 0.36, 0.035, 0.72)
	add_child(particles)
	return particles


func _build_embers() -> CPUParticles3D:
	var particles := _ring_particles(30, 1.45)
	particles.direction = Vector3.UP
	particles.spread = 38.0
	particles.initial_velocity_min = 0.35
	particles.initial_velocity_max = 1.15
	particles.gravity = Vector3(0.0, -0.22, 0.0)
	particles.scale_amount_min = 0.65
	particles.scale_amount_max = 1.2
	var mote := SphereMesh.new()
	mote.radius = 0.027
	mote.height = 0.06
	mote.radial_segments = 4
	mote.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mote.material = material
	particles.mesh = mote
	var colours := Gradient.new()
	colours.set_color(0, Color(1.0, 0.82, 0.20, 0.95))
	colours.set_color(1, Color(1.0, 0.08, 0.005, 0.0))
	particles.color_ramp = colours
	var size := Curve.new()
	size.add_point(Vector2(0.0, 1.0))
	size.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = size
	add_child(particles)
	return particles


func _ring_particles(amount: int, lifetime: float) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.88
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_height = 0.02
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


## Keeps the active band just outside the glacier as the playable circle closes.
func set_arena_radius(radius: float) -> void:
	var inner := maxf(radius + 0.28, 0.28)
	var outer := inner + 3.4
	for particles in [_flickers, _embers]:
		if particles == null:
			continue
		particles.emission_ring_inner_radius = inner
		particles.emission_ring_radius = outer
		particles.visibility_aabb = AABB(
			Vector3(-outer, -0.5, -outer), Vector3(outer * 2.0, 3.0, outer * 2.0))

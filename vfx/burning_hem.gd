class_name BurningHem
extends Node3D

## A restrained fire line around the robe hem while its owner stands in lava.
var _burning := false
var _flames: CPUParticles3D
var _embers: CPUParticles3D


func _ready() -> void:
	position.y = -0.62
	_flames = _build_flames()
	_embers = _build_embers()
	# Off until the lava says otherwise, set here rather than through `set_burning(false)`:
	# that call would see `_burning` already false and return without touching anything, and
	# a CPUParticles3D emits by default - which lit every fighter the moment they spawned.
	hide()


func _build_flames() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = 11
	particles.lifetime = 0.46
	particles.randomness = 0.72
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = 0.34
	particles.emission_ring_inner_radius = 0.18
	particles.direction = Vector3.UP
	particles.spread = 15.0
	particles.initial_velocity_min = 0.32
	particles.initial_velocity_max = 0.72
	particles.gravity = Vector3(0.0, 0.32, 0.0)
	particles.scale_amount_min = 0.72
	particles.scale_amount_max = 1.18
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.55))
	shrink.add_point(Vector2(0.18, 1.0))
	shrink.add_point(Vector2(1.0, 0.18))
	particles.scale_amount_curve = shrink
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.52)
	var material := ShaderMaterial.new()
	material.shader = preload("res://vfx/hem_flame.gdshader")
	quad.material = material
	particles.mesh = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.emitting = false
	add_child(particles)
	return particles


func _build_embers() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.amount = 8
	particles.lifetime = 0.58
	particles.randomness = 0.9
	particles.local_coords = true
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	particles.emission_ring_axis = Vector3.UP
	particles.emission_ring_radius = 0.38
	particles.emission_ring_inner_radius = 0.22
	particles.direction = Vector3.UP
	particles.spread = 34.0
	particles.initial_velocity_min = 0.40
	particles.initial_velocity_max = 1.05
	particles.gravity = Vector3(0.0, -0.45, 0.0)
	var mote := SphereMesh.new()
	mote.radius = 0.025
	mote.height = 0.055
	mote.radial_segments = 4
	mote.rings = 2
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mote.material = material
	particles.mesh = mote
	particles.color = Color(1.0, 0.42, 0.04)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = fade
	particles.emitting = false
	add_child(particles)
	return particles


func set_burning(active: bool) -> void:
	if _burning == active:
		return
	_burning = active
	if active:
		show()
		_flames.restart()
		_embers.restart()
		_flames.emitting = true
		_embers.emitting = true
	else:
		_flames.emitting = false
		_embers.emitting = false
		hide()


func is_burning() -> bool:
	return _burning

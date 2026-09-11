class_name SpellAura
extends Node3D

## Render-only identity for self-cast spells. The fighter owns it, so it follows movement.
var _kind: StringName = &""
var _life := 0.0
var _duration := 1.0
var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _motes: CPUParticles3D


func _ready() -> void:
	for i in 3:
		var ring := MeshInstance3D.new()
		var hoop := TorusMesh.new()
		hoop.inner_radius = 0.82 + i * 0.14
		hoop.outer_radius = hoop.inner_radius + 0.065
		hoop.rings = 24
		hoop.ring_segments = 6
		ring.mesh = hoop
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.0)
		ring.material_override = mat
		add_child(ring)
		_rings.append(ring)
		_materials.append(mat)
	_motes = CPUParticles3D.new()
	_motes.emitting = false
	_motes.amount = 24
	_motes.lifetime = 0.85
	_motes.local_coords = true
	_motes.direction = Vector3.UP
	_motes.spread = 28.0
	_motes.initial_velocity_min = 0.25
	_motes.initial_velocity_max = 0.75
	_motes.gravity = Vector3(0.0, 0.12, 0.0)
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_motes.emission_ring_radius = 0.72
	_motes.emission_ring_inner_radius = 0.55
	var mote := SphereMesh.new()
	mote.radius = 0.055
	mote.height = 0.12
	mote.radial_segments = 5
	mote.rings = 2
	var mote_mat := StandardMaterial3D.new()
	mote_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote_mat.vertex_color_use_as_albedo = true
	mote.material = mote_mat
	_motes.mesh = mote
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_motes)
	hide()
	set_process(false)


func play(ability: Ability) -> void:
	_kind = ability.id
	_duration = maxf(ability.duration, 0.2)
	_life = _duration
	var tint := ability.colour
	for i in _rings.size():
		_materials[i].albedo_color = Color(tint.r, tint.g, tint.b, 0.78 - i * 0.12)
		_rings[i].position.y = -0.78 + i * 0.72
		_rings[i].rotation = Vector3(0.12 * i, 0.0, -0.16 * i)
	_motes.color = tint
	_motes.restart()
	_motes.emitting = true
	show()
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		_motes.emitting = false
		hide()
		set_process(false)
		return
	var age := _duration - _life
	var end_fade := clampf(_life / 0.35, 0.0, 1.0)
	for i in _rings.size():
		var ring := _rings[i]
		var hand := -1.0 if i == 1 else 1.0
		ring.rotation.y = age * (1.8 + i * 0.7) * hand
		if _kind == &"momentum":
			ring.scale = Vector3.ONE * (1.0 + 0.07 * sin(age * 8.0 + i))
			ring.rotation.z = 0.45 + i * 0.34
		elif _kind == &"rewind":
			ring.scale = Vector3.ONE * (0.82 + 0.12 * sin(age * 3.2 + i * 1.7))
			ring.rotation.x = PI * 0.5 if i == 1 else 0.22 * i
		else:
			ring.scale = Vector3.ONE * (0.96 + 0.035 * sin(age * 5.0 + i))
		_materials[i].albedo_color.a = (0.78 - i * 0.12) * end_fade

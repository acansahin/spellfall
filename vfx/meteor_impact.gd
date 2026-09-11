extends Node3D

## Four reusable, short-lived impacts; entirely visual and independent of damage resolution.
const COUNT := 4
var _slots: Array[Node3D] = []
var _shards: Array[CPUParticles3D] = []
var _steam: Array[CPUParticles3D] = []
var _flashes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _ages: Array[float] = []
var _sizes: Array[float] = []
var _next := 0


func _ready() -> void:
	var shard_mesh := PrismMesh.new()
	shard_mesh.size = Vector3(0.10, 0.28, 0.08)
	var ice := StandardMaterial3D.new()
	ice.albedo_color = Color(0.40, 0.78, 0.91)
	ice.vertex_color_use_as_albedo = true
	ice.roughness = 0.27
	shard_mesh.material = ice
	var steam_mesh := QuadMesh.new()
	steam_mesh.size = Vector2.ONE
	var steam_material := ShaderMaterial.new()
	steam_material.shader = preload("res://vfx/soft_puff.gdshader")
	steam_mesh.material = steam_material
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 1.0
	flash_mesh.height = 2.0
	flash_mesh.radial_segments = 12
	flash_mesh.rings = 4
	var ring_mesh := GroundShapes.ring(1.0, 0.12)
	for i in COUNT:
		var slot := Node3D.new()
		add_child(slot)
		_slots.append(slot)
		_shards.append(_emitter(slot, shard_mesh, false))
		_steam.append(_emitter(slot, steam_mesh, true))
		var flash := MeshInstance3D.new()
		flash.mesh = flash_mesh
		flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := StandardMaterial3D.new()
		light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		light.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		light.albedo_color = Color(1.0, 0.67, 0.22, 0.8)
		flash.material_override = light
		slot.add_child(flash)
		_flashes.append(flash)
		var ring := MeshInstance3D.new()
		ring.mesh = ring_mesh
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring_material := GroundShapes.flat_material(Color(1.0, 0.32, 0.035), 0.85)
		ring.material_override = ring_material
		ring.position.y = 0.03
		slot.add_child(ring)
		_rings.append(ring)
		_ages.append(1.0)
		_sizes.append(1.0)
		slot.hide()
	set_process(false)


func _emitter(parent: Node3D, mesh: Mesh, vapour: bool) -> CPUParticles3D:
	var emitter := CPUParticles3D.new()
	emitter.emitting = false
	emitter.one_shot = true
	emitter.explosiveness = 1.0
	emitter.local_coords = false
	emitter.amount = 8 if vapour else 16
	emitter.lifetime = 0.65 if vapour else 0.58
	emitter.mesh = mesh
	emitter.direction = Vector3.UP
	emitter.spread = 55.0 if vapour else 70.0
	emitter.gravity = Vector3(0.0, 0.8 if vapour else -9.0, 0.0)
	emitter.initial_velocity_min = 0.5 if vapour else 2.0
	emitter.initial_velocity_max = 1.4 if vapour else 4.4
	emitter.scale_amount_min = 0.4 if vapour else 0.7
	emitter.scale_amount_max = 0.9 if vapour else 1.4
	emitter.angular_velocity_min = -120.0
	emitter.angular_velocity_max = 120.0
	emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.25 if vapour else 1.0))
	curve.add_point(Vector2(0.5, 0.85))
	curve.add_point(Vector2(1.0, 1.2 if vapour else 0.0))
	emitter.scale_amount_curve = curve
	if vapour:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(0.76, 0.85, 0.89, 0.8))
		gradient.set_color(1, Color(0.85, 0.89, 0.90, 0.0))
		emitter.color_ramp = gradient
	parent.add_child(emitter)
	return emitter


func play(at: Vector3, radius: float, on_ice: bool = true) -> void:
	var i := _next
	_next = (_next + 1) % COUNT
	_slots[i].global_position = at
	_slots[i].show()
	_ages[i] = 0.0
	_sizes[i] = clampf(radius / 3.2, 0.4, 1.3)
	_shards[i].color = Color.WHITE if on_ice else Color(0.65, 0.25, 0.08)
	_shards[i].restart()
	_shards[i].emitting = true
	_steam[i].restart()
	_steam[i].emitting = true
	_update_flash(i)
	set_process(true)


func _process(delta: float) -> void:
	var active := false
	for i in COUNT:
		if _ages[i] >= 0.75:
			continue
		_ages[i] += delta
		_update_flash(i)
		if _ages[i] >= 0.75:
			_slots[i].hide()
		else:
			active = true
	set_process(active)


func _update_flash(i: int) -> void:
	var t := clampf(_ages[i] / 0.16, 0.0, 1.0)
	_flashes[i].visible = t < 1.0
	_flashes[i].scale = Vector3(1.0, 0.25, 1.0) * lerpf(0.18, 0.95, t) * _sizes[i]
	(_flashes[i].material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - t)
	var ring_t := clampf(_ages[i] / 0.34, 0.0, 1.0)
	_rings[i].visible = ring_t < 1.0
	_rings[i].scale = Vector3.ONE * lerpf(0.35, 3.2 * _sizes[i], ring_t)
	(_rings[i].material_override as StandardMaterial3D).albedo_color.a = 0.78 * (1.0 - ring_t)

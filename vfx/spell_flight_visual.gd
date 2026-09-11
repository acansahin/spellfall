extends Node3D

## Bounded render-only companions for the two hero projectiles. No collision or gameplay.
const Models = preload("res://vfx/spell_models.gd")
const HISTORY := 15

var _kind: StringName = &""
var _radius := 1.0
var _body: MeshInstance3D
var _flame: Node3D
var _embers: CPUParticles3D
var _smoke: CPUParticles3D
var _ribbon: MeshInstance3D
var _ribbon_mesh := ImmediateMesh.new()
var _left: Array[Vector3] = []
var _right: Array[Vector3] = []
var _centre: Array[Vector3] = []
var _tint := Color.WHITE
var _extras: Array[MeshInstance3D] = []
var _extra_materials: Array[StandardMaterial3D] = []
var _magic: CPUParticles3D

static var _ring_mesh: TorusMesh
static var _orb_mesh: SphereMesh
static var _shard_mesh: CylinderMesh


func _ready() -> void:
	_flame = Node3D.new()
	add_child(_flame)
	var flame_material := ShaderMaterial.new()
	flame_material.shader = preload("res://vfx/meteor_flame.gdshader")
	for angle in [0.0, PI * 0.5]:
		var sheet := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.5, 3.5)
		sheet.mesh = quad
		sheet.material_override = flame_material
		sheet.position.y = 1.75
		sheet.rotation.y = angle
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flame.add_child(sheet)
	# A small emissive volume keeps the tail readable when the translucent sheets are viewed
	# almost end-on by the arena camera.
	for layer in 2:
		var core := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 0.44 if layer == 0 else 0.24
		cone.height = 2.5 if layer == 0 else 1.65
		cone.radial_segments = 8
		cone.rings = 1
		core.mesh = cone
		core.position.y = cone.height * 0.5
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.albedo_color = Color(1.0, 0.16, 0.01, 0.58) if layer == 0 \
			else Color(1.0, 0.82, 0.18, 0.82)
		core.material_override = glow
		_flame.add_child(core)
	_embers = _particles(false)
	_smoke = _particles(true)
	_build_extras()
	_magic = _magic_particles()
	_ribbon = MeshInstance3D.new()
	_ribbon.mesh = _ribbon_mesh
	_ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ribbon_material := StandardMaterial3D.new()
	ribbon_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ribbon_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ribbon_material.vertex_color_use_as_albedo = true
	ribbon_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon_material.albedo_color = Color.WHITE
	_ribbon.material_override = ribbon_material
	add_child(_ribbon)
	_ribbon.top_level = true
	_ribbon.global_transform = Transform3D.IDENTITY
	stop()


func _build_extras() -> void:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.67
		_ring_mesh.outer_radius = 0.82
		_ring_mesh.rings = 18
		_ring_mesh.ring_segments = 6
		_orb_mesh = SphereMesh.new()
		_orb_mesh.radius = 0.34
		_orb_mesh.height = 0.68
		_orb_mesh.radial_segments = 8
		_orb_mesh.rings = 4
		_shard_mesh = CylinderMesh.new()
		_shard_mesh.top_radius = 0.03
		_shard_mesh.bottom_radius = 0.20
		_shard_mesh.height = 0.92
		_shard_mesh.radial_segments = 5
	for i in 3:
		var extra := MeshInstance3D.new()
		extra.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color.WHITE
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.35
		extra.material_override = mat
		add_child(extra)
		_extras.append(extra)
		_extra_materials.append(mat)


func _magic_particles() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.local_coords = false
	particles.amount = 13
	particles.lifetime = 0.34
	particles.direction = Vector3.ZERO
	particles.spread = 0.0
	particles.initial_velocity_min = 0.0
	particles.initial_velocity_max = 0.0
	particles.gravity = Vector3.ZERO
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shard := SphereMesh.new()
	shard.radius = 0.055
	shard.height = 0.11
	shard.radial_segments = 5
	shard.rings = 2
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	shard.material = mat
	particles.mesh = shard
	var fade := Curve.new()
	fade.add_point(Vector2(0.0, 1.0))
	fade.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = fade
	add_child(particles)
	return particles


func _particles(smoke: bool) -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.local_coords = false
	particles.amount = 7 if smoke else 14
	particles.lifetime = 0.48 if smoke else 0.34
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.gravity = Vector3(0.0, 0.7, 0.0)
	particles.spread = 17.0
	particles.initial_velocity_min = 0.4
	particles.initial_velocity_max = 1.2
	if smoke:
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		var material := ShaderMaterial.new()
		material.shader = preload("res://vfx/soft_puff.gdshader")
		quad.material = material
		particles.mesh = quad
	else:
		var spark := SphereMesh.new()
		spark.radius = 0.065
		spark.height = 0.13
		spark.radial_segments = 4
		spark.rings = 2
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		spark.material = material
		particles.mesh = spark
	var colours := Gradient.new()
	colours.set_color(0, Color(0.16, 0.13, 0.12, 0.60) if smoke else Color(1.0, 0.67, 0.10))
	colours.set_color(1, Color(0.25, 0.22, 0.20, 0.0) if smoke else Color(1.0, 0.08, 0.0, 0.0))
	particles.color_ramp = colours
	var size_curve := Curve.new()
	size_curve.add_point(Vector2(0.0, 0.35 if smoke else 1.0))
	size_curve.add_point(Vector2(1.0, 1.0 if smoke else 0.0))
	particles.scale_amount_curve = size_curve
	add_child(particles)
	return particles


func configure(ability: Ability, body: MeshInstance3D) -> bool:
	stop()
	_kind = ability.id
	_radius = ability.projectile_radius
	_tint = ability.colour
	_body = body
	if _kind == &"meteor":
		_radius *= 1.22
		body.mesh = Models.meteor()
		body.material_override = Models.meteor_material()
		_flame.visible = true
		_flame.scale = Vector3.ONE * _radius
		for emitter in [_embers, _smoke]:
			emitter.visible = true
			emitter.restart()
			emitter.emitting = true
		_smoke.scale_amount_min = _radius * 0.8
		_smoke.scale_amount_max = _radius * 1.6
		_embers.scale_amount_min = 0.8
		_embers.scale_amount_max = 1.35
		_ribbon.show()
	elif _kind == &"loopshot":
		_radius *= 1.55
		body.mesh = Models.boomerang()
		body.material_override = Models.metal_material()
		_ribbon.show()
	else:
		if _kind == &"arc_lance":
			body.mesh = Models.lightning()
		_configure_extras()
		_magic.color = _tint
		_magic.scale_amount_min = _radius * 0.32
		_magic.scale_amount_max = _radius * (0.95 if _kind in [&"fireball", &"fire_spray", &"splinter"] else 0.62)
		_magic.show()
		_magic.restart()
		_magic.emitting = true
		_ribbon.show()
	show()
	return true


func _configure_extras() -> void:
	for extra in _extras:
		extra.hide()
	var meshes: Array[Mesh] = []
	match _kind:
		&"fireball": meshes = [_ring_mesh, _ring_mesh]
		&"arc_lance": meshes = [_shard_mesh, _shard_mesh]
		&"seeker": meshes = [_ring_mesh, _orb_mesh]
		&"splitter": meshes = [_shard_mesh, _shard_mesh, _shard_mesh]
		&"fire_spray", &"splinter": meshes = [_orb_mesh, _orb_mesh]
		&"bouncer": meshes = [_orb_mesh, _orb_mesh, _orb_mesh]
		&"warp_bolt": meshes = [_ring_mesh, _ring_mesh, _orb_mesh]
		&"entangle": meshes = [_ring_mesh, _ring_mesh, _ring_mesh]
		&"gravity": meshes = [_ring_mesh, _ring_mesh, _orb_mesh]
		&"link": meshes = [_ring_mesh, _ring_mesh]
		&"drain": meshes = [_ring_mesh, _ring_mesh, _orb_mesh]
		_: meshes = [_ring_mesh]
	for i in meshes.size():
		var extra := _extras[i]
		extra.mesh = meshes[i]
		extra.show()
		var colour := _tint
		if _kind == &"gravity" and i == 2:
			colour = Color(0.035, 0.02, 0.08)
		_extra_materials[i].albedo_color = Color(colour.r, colour.g, colour.b, 0.78)
		_extra_materials[i].emission = colour


func update_flight(age: float, velocity: Vector3) -> void:
	if _kind == &"meteor":
		# Only the drawing tumbles. The projectile continues its original flight exactly.
		_body.basis = Basis.from_euler(Vector3(age * 1.7, age * 0.9, age * 0.6)).scaled(Vector3.ONE * _radius)
		var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
		var backwards := -horizontal_velocity.normalized() if horizontal_velocity.length_squared() > 0.001 \
			else Vector3.BACK
		backwards = (backwards + Vector3.UP * 0.18).normalized()
		_flame.basis = Basis(Quaternion(Vector3.UP, backwards)).scaled(Vector3.ONE * _radius)
		_embers.direction = backwards
		_smoke.direction = backwards
		_smoke.position = backwards * _radius * 1.6
		_centre.push_front(_body.global_position)
		if _centre.size() > HISTORY:
			_centre.pop_back()
		_draw_meteor_tail()
	elif _kind == &"loopshot":
		_left.push_front(_body.global_transform * Vector3(-1.50, 0.1, -0.82))
		_right.push_front(_body.global_transform * Vector3(1.50, 0.1, -0.82))
		if _left.size() > HISTORY:
			_left.pop_back()
			_right.pop_back()
		_draw_ribbons()
	elif _kind != &"":
		_centre.push_front(_body.global_position)
		if _centre.size() > HISTORY:
			_centre.pop_back()
		_animate_extras(age)
		_draw_spell_tail(age)


func _animate_extras(age: float) -> void:
	for i in _extras.size():
		var extra := _extras[i]
		if not extra.visible:
			continue
		var hand := -1.0 if i == 1 else 1.0
		var angle := age * (5.0 + i * 1.7) * hand + i * TAU / 3.0
		if extra.mesh == _ring_mesh:
			extra.position = Vector3.ZERO
			extra.rotation = Vector3(angle * 0.52, angle, angle * 0.28)
			extra.scale = Vector3.ONE * _radius * (1.12 + i * 0.19)
		else:
			var orbit := _radius * (0.62 + i * 0.18)
			extra.position = Vector3(cos(angle) * orbit, sin(angle * 1.3) * orbit * 0.35,
				sin(angle) * orbit)
			extra.rotation = Vector3(angle, angle * 0.7, -angle * 0.4)
			extra.scale = Vector3.ONE * _radius
	if _kind == &"seeker" and _extras[1].visible:
		_extras[1].position = Vector3.ZERO
		_extras[1].scale = Vector3(_radius * 0.55, _radius * 0.22, _radius * 0.55)
	if _kind == &"link":
		_extras[0].position.x = -_radius * 0.55
		_extras[1].position.x = _radius * 0.55
	if _kind == &"gravity" and _extras[2].visible:
		_extras[2].position = Vector3.ZERO
		_extras[2].scale = Vector3.ONE * _radius * 1.15


func _draw_spell_tail(age: float) -> void:
	_ribbon_mesh.clear_surfaces()
	if _centre.size() < 2:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _centre.size() - 1:
		var a := _centre[i]
		var b := _centre[i + 1]
		var travel := b - a
		var across := travel.cross(Vector3.UP).normalized()
		if across.length_squared() < 0.001:
			across = Vector3.RIGHT
		var t := float(i) / float(HISTORY)
		var wobble := 0.0
		if _kind in [&"arc_lance", &"seeker", &"gravity", &"drain"]:
			wobble = sin(age * 18.0 - i * 1.8) * _radius * (0.20 if _kind == &"arc_lance" else 0.11)
		var aa := a + across * wobble
		var bb := b - across * wobble * 0.55
		var width := _radius * lerpf(0.28, 0.035, t)
		if _kind in [&"fireball", &"fire_spray", &"splinter"]:
			width *= 1.45
		var opacity := 0.68 * (1.0 - t)
		var colour := Color(_tint.r, _tint.g, _tint.b, opacity)
		for point in [aa - across * width, aa + across * width,
				bb + across * width * 0.72, aa - across * width,
				bb + across * width * 0.72, bb - across * width * 0.72]:
			_ribbon_mesh.surface_set_color(colour)
			_ribbon_mesh.surface_add_vertex(point)
	_ribbon_mesh.surface_end()


func _draw_ribbons() -> void:
	_ribbon_mesh.clear_surfaces()
	if _left.size() < 2:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for points in [_left, _right]:
		for i in points.size() - 1:
			var a: Vector3 = points[i]
			var b: Vector3 = points[i + 1]
			var across := (b - a).cross(Vector3.UP).normalized() * _radius * 0.20
			var opacity := 0.72 * (1.0 - float(i) / float(HISTORY))
			for point in [a - across, a + across, b + across, a - across, b + across, b - across]:
				_ribbon_mesh.surface_set_color(Color(0.46, 1.0, 0.06, opacity))
				_ribbon_mesh.surface_add_vertex(point)
	_ribbon_mesh.surface_end()


func _draw_meteor_tail() -> void:
	_ribbon_mesh.clear_surfaces()
	if _centre.size() < 2:
		return
	_ribbon_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _centre.size() - 1:
		var a := _centre[i]
		var b := _centre[i + 1]
		var horizontal := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var across := Vector3.RIGHT
		if horizontal.length_squared() > 0.0001:
			across = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
		var start_width := _radius * lerpf(0.36, 0.08, float(i) / float(HISTORY))
		var end_width := _radius * lerpf(0.31, 0.025, float(i + 1) / float(HISTORY))
		var opacity := 0.86 * (1.0 - float(i) / float(HISTORY))
		var colour := Color(1.0, 0.22 + 0.32 * (1.0 - float(i) / float(HISTORY)), 0.01, opacity)
		for point in [a - across * start_width, a + across * start_width,
				b + across * end_width, a - across * start_width,
				b + across * end_width, b - across * end_width]:
			_ribbon_mesh.surface_set_color(colour)
			_ribbon_mesh.surface_add_vertex(point)
	_ribbon_mesh.surface_end()


func stop() -> void:
	_kind = &""
	hide()
	if _flame != null:
		_flame.hide()
	if _embers != null:
		_embers.emitting = false
		_embers.hide()
	if _smoke != null:
		_smoke.emitting = false
		_smoke.hide()
	if _magic != null:
		_magic.emitting = false
		_magic.hide()
	for extra in _extras:
		extra.hide()
	if _ribbon != null:
		_ribbon.hide()
	_ribbon_mesh.clear_surfaces()
	_left.clear()
	_right.clear()
	_centre.clear()

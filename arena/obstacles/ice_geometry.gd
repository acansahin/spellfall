extends RefCounted

## Clustered, fractured ice blocks. Collision remains in the obstacle scenes.
static func build(parent: Node3D, height: float, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := 4 if height > 2.0 else 3
	for i in count:
		var main := i == 0
		var shard_height := height * (rng.randf_range(0.78, 1.0) if main else rng.randf_range(0.28, 0.58))
		var shard_radius := radius * (rng.randf_range(0.82, 1.05) if main else rng.randf_range(0.34, 0.60))
		var angle := rng.randf_range(0.0, TAU)
		var reach := 0.0 if main else radius * rng.randf_range(0.62, 0.92)
		var node := MeshInstance3D.new()
		node.mesh = _fractured_block(shard_height, shard_radius, rng)
		node.material_override = _ice_material(i, rng)
		node.position = Vector3(cos(angle) * reach, 0.01, sin(angle) * reach)
		node.rotation = Vector3(rng.randf_range(-0.07, 0.07), angle, rng.randf_range(-0.08, 0.08))
		parent.add_child(node)


static func _fractured_block(height: float, radius: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var point_count := 7
	var bottom: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	var top: Array[Vector3] = []
	var top_offset := Vector2(rng.randf_range(-0.20, 0.20), rng.randf_range(-0.20, 0.20)) * radius
	for i in point_count:
		var angle := TAU * float(i) / float(point_count)
		var uneven := radius * rng.randf_range(0.78, 1.14)
		bottom.append(Vector3(cos(angle) * uneven, 0.0, sin(angle) * uneven))
		shoulder.append(Vector3(cos(angle) * uneven * rng.randf_range(0.74, 0.94), height * 0.68, sin(angle) * uneven * rng.randf_range(0.74, 0.94)))
		top.append(Vector3(cos(angle) * uneven * rng.randf_range(0.43, 0.69) + top_offset.x, height * rng.randf_range(0.91, 1.04), sin(angle) * uneven * rng.randf_range(0.43, 0.69) + top_offset.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in point_count:
		var next := (i + 1) % point_count
		_add_quad(surface, bottom[i], bottom[next], shoulder[next], shoulder[i])
		_add_quad(surface, shoulder[i], shoulder[next], top[next], top[i])
	var centre := Vector3(top_offset.x, height * 0.97, top_offset.y)
	for i in point_count:
		_add_triangle(surface, centre, top[i], top[(i + 1) % point_count])
	return surface.commit()


static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise front faces; the outward normal follows the reverse cross product.
	var normal := (c - a).cross(b - a).normalized()
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)


static func _ice_material(index: int, rng: RandomNumberGenerator) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var variation := rng.randf_range(-0.035, 0.035)
	material.albedo_color = Color(0.28 + variation, 0.58 + variation, 0.67 + variation)
	material.roughness = 0.34 + float(index) * 0.035
	material.metallic_specular = 0.68
	return material

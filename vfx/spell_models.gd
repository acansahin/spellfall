extends RefCounted

## Shared render-only meshes. Never used to derive collision or spell timing.
static var _boomerang: ArrayMesh
static var _meteor: ArrayMesh
static var _lightning: ArrayMesh
static var _metal: ShaderMaterial
static var _basalt: ShaderMaterial


static func boomerang() -> ArrayMesh:
	if _boomerang != null:
		return _boomerang
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Two bevelled arms, joined at the elbow. The opening stays visible while spinning.
	for hand in [-1.0, 1.0]:
		var elbow := Vector3(0.0, 0.0, 0.65)
		var tip := Vector3(hand * 1.55, 0.0, -0.85)
		var along := (tip - elbow).normalized()
		var across := Vector3(-along.z, 0.0, along.x)
		var base := [elbow - across * 0.26, tip - across * 0.14,
			tip + across * 0.14, elbow + across * 0.26]
		var upper: Array[Vector3] = []
		var lower: Array[Vector3] = []
		for v: Vector3 in base:
			lower.append(v - Vector3.UP * 0.10)
			upper.append(v + Vector3.UP * 0.06)
		var ridge_a := elbow + Vector3.UP * 0.17
		var ridge_b := tip + Vector3.UP * 0.13
		_face(surface, upper[0], upper[1], ridge_b, Color(0.28, 0.40, 0.48))
		_face(surface, upper[0], ridge_b, ridge_a, Color(0.28, 0.40, 0.48))
		_face(surface, ridge_a, ridge_b, upper[2], Color(0.63, 0.75, 0.79))
		_face(surface, ridge_a, upper[2], upper[3], Color(0.63, 0.75, 0.79))
		_face(surface, upper[0], ridge_a, upper[3], Color(0.42, 0.55, 0.60))
		_face(surface, upper[1], upper[2], ridge_b, Color(0.62, 0.80, 0.35))
		for i in 4:
			var j := (i + 1) % 4
			_face(surface, lower[i], lower[j], upper[j], Color(0.12, 0.20, 0.25))
			_face(surface, lower[i], upper[j], upper[i], Color(0.12, 0.20, 0.25))
		_face(surface, lower[0], lower[2], lower[1], Color(0.25, 0.34, 0.38))
		_face(surface, lower[0], lower[3], lower[2], Color(0.25, 0.34, 0.38))
		# Narrow green inlay on each ridge; most of the body remains shaded metal.
		var a := elbow.lerp(tip, 0.30) + Vector3.UP * 0.19
		var b := elbow.lerp(tip, 0.96) + Vector3.UP * 0.16
		_face(surface, a - across * 0.045, b - across * 0.035,
			b + across * 0.035, Color(0.48, 1.0, 0.06))
		_face(surface, a - across * 0.045, b + across * 0.035,
			a + across * 0.045, Color(0.48, 1.0, 0.06))
	_boomerang = surface.commit()
	return _boomerang


static func meteor() -> ArrayMesh:
	if _meteor != null:
		return _meteor
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 9:
		for col in 16:
			var a := _rock_point(row, col)
			var b := _rock_point(row, col + 1)
			var c := _rock_point(row + 1, col + 1)
			var d := _rock_point(row + 1, col)
			if row > 0:
				_face(surface, a, b, c, Color.WHITE)
			if row < 8:
				_face(surface, a, c, d, Color.WHITE)
	_meteor = surface.commit()
	return _meteor


static func lightning() -> ArrayMesh:
	if _lightning != null:
		return _lightning
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [
		Vector3(-0.10, -3.0, 0.0), Vector3(0.34, -1.72, 0.0),
		Vector3(-0.28, -0.66, 0.0), Vector3(0.30, 0.30, 0.0),
		Vector3(-0.20, 1.36, 0.0), Vector3(0.08, 3.0, 0.0),
	]
	for i in points.size() - 1:
		var a: Vector3 = points[i]
		var b: Vector3 = points[i + 1]
		var along := (b - a).normalized()
		var side := Vector3(-along.y, along.x, 0.0) * (0.24 if i < 2 else 0.18)
		var depth := Vector3(0.0, 0.0, 0.12)
		var a0 := a - side - depth
		var a1 := a + side - depth
		var a2 := a + side + depth
		var a3 := a - side + depth
		var b0 := b - side - depth
		var b1 := b + side - depth
		var b2 := b + side + depth
		var b3 := b - side + depth
		for face in [[a0, b0, b1], [a0, b1, a1], [a3, a2, b2], [a3, b2, b3],
				[a1, b1, b2], [a1, b2, a2], [a0, a3, b3], [a0, b3, b0]]:
			_face(surface, face[0], face[1], face[2], Color.WHITE)
	_lightning = surface.commit()
	return _lightning


static func _rock_point(row: int, col: int) -> Vector3:
	var latitude := PI * float(row) / 9.0
	var longitude := TAU * float(col % 16) / 16.0
	var p := Vector3(sin(latitude) * cos(longitude), cos(latitude),
		sin(latitude) * sin(longitude))
	var radius := 0.91 + 0.05 * sin(p.x * 11.0 + p.y * 7.0) + 0.04 * cos(p.z * 13.0 - p.x * 8.0)
	return p * radius


static func _face(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, tint: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	# Faces are authored in either hand; orient outward from the model's centre.
	if normal.dot((a + b + c) / 3.0) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	for point in [a, b, c]:
		surface.set_normal(normal)
		surface.set_color(tint)
		surface.add_vertex(point)


static func metal_material() -> ShaderMaterial:
	if _metal == null:
		_metal = ShaderMaterial.new()
		_metal.shader = preload("res://vfx/boomerang_metal.gdshader")
	return _metal


static func meteor_material() -> ShaderMaterial:
	if _basalt == null:
		_basalt = ShaderMaterial.new()
		_basalt.shader = preload("res://vfx/meteor_rock.gdshader")
	return _basalt

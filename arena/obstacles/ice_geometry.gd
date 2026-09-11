extends RefCounted

## The shared builder behind both pieces of cover: a cluster of fractured ice blocks.
##
## One file rather than two, because the rock and the tree stopped being different things when
## the arena became a glacier. What separates them now is a HEIGHT and a RADIUS - a low chunk
## you shoot over the top of, a tall shard you do not - and that is two arguments, not two
## builders. The scenes and their scripts stay separate for the reason written on each.
##
## What it does NOT touch is collision. Every shape stays in the obstacle scene, untouched,
## because what a piece of cover BLOCKS is a gameplay number that four suites measure - and it
## must not drift because the art changed. Same rule the old rock and tree kept.

## Points around each block. Seven, and odd on purpose: an even count puts a vertex opposite
## every other vertex, which reads as a symmetry the eye picks out immediately.
const POINTS := 7

## Where a cluster stops adding shards. A tall shard gets a fourth; a low chunk does not need
## one, and a mid-range Android is the target.
const TALL_ENOUGH := 2.0


## Builds one cluster under `parent`. `height` and `radius` describe the MAIN shard; the rest
## are smaller and lean off it.
##
## `seed_value` is what makes a cluster the same cluster every run. Taken from where the
## obstacle stands, so two shards are two shards and neither changes shape between launches - a
## screenshot taken twice has to be the same screenshot, or nothing can be compared to anything.
static func build(parent: Node3D, height: float, radius: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var count := 4 if height > TALL_ENOUGH else 3
	for i in count:
		var main := i == 0
		var shard_height := height * (
			rng.randf_range(0.78, 1.0) if main else rng.randf_range(0.28, 0.58))
		var shard_radius := radius * (
			rng.randf_range(0.82, 1.05) if main else rng.randf_range(0.34, 0.60))
		var angle := rng.randf_range(0.0, TAU)
		# The main shard stands at the centre; the others lean out from it, so the footprint is
		# not a circle and the silhouette is not a lump.
		var reach := 0.0 if main else radius * rng.randf_range(0.62, 0.92)
		var node := MeshInstance3D.new()
		node.mesh = _fractured_block(shard_height, shard_radius, rng)
		node.material_override = _ice_material(i, rng)
		node.position = Vector3(cos(angle) * reach, 0.01, sin(angle) * reach)
		node.rotation = Vector3(
			rng.randf_range(-0.07, 0.07), angle, rng.randf_range(-0.08, 0.08))
		parent.add_child(node)


## One block: an uneven base, a shoulder that pulls in, and a top that pulls in further and
## sits off-centre.
##
## Three rings rather than two is the whole of why it reads as fractured ice rather than as a
## cone. The shoulder is where the break is, and a shape with no shoulder has nothing to catch
## the light at an angle different from its own sides.
static func _fractured_block(height: float, radius: float,
		rng: RandomNumberGenerator) -> ArrayMesh:
	var bottom: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	var top: Array[Vector3] = []
	# The top is pushed off the vertical axis, so the block leans without being rotated - which
	# keeps its base flat on the ground while its mass is not over its own centre.
	var lean := Vector2(rng.randf_range(-0.20, 0.20), rng.randf_range(-0.20, 0.20)) * radius
	for i in POINTS:
		var angle := TAU * float(i) / float(POINTS)
		# Each point at its OWN distance, so no two faces are the same width.
		var uneven := radius * rng.randf_range(0.78, 1.14)
		bottom.append(Vector3(cos(angle) * uneven, 0.0, sin(angle) * uneven))
		# x and z are drawn SEPARATELY here and on the crown below, so a point is not on
		# its own radial line. That is what keeps the block from reading as a lathed
		# shape: pull both axes by the same factor and every face is a clean taper.
		shoulder.append(Vector3(
			cos(angle) * uneven * rng.randf_range(0.74, 0.94),
			height * 0.68,
			sin(angle) * uneven * rng.randf_range(0.74, 0.94)))
		top.append(Vector3(
			cos(angle) * uneven * rng.randf_range(0.43, 0.69) + lean.x,
			height * rng.randf_range(0.91, 1.04),
			sin(angle) * uneven * rng.randf_range(0.43, 0.69) + lean.y))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in POINTS:
		var next := (i + 1) % POINTS
		_add_quad(surface, bottom[i], bottom[next], shoulder[next], shoulder[i])
		_add_quad(surface, shoulder[i], shoulder[next], top[next], top[i])
	# Capped from a single apex rather than left open. The camera looks down at this arena, so
	# the top of a shard is the face most often on screen.
	var apex := Vector3(lean.x, height * 0.97, lean.y)
	for i in POINTS:
		_add_triangle(surface, apex, top[i], top[(i + 1) % POINTS])
	return surface.commit()


static func _add_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3) -> void:
	_add_triangle(surface, a, b, c)
	_add_triangle(surface, a, c, d)


## One flat-shaded triangle. FLAT is the point - a normal per face rather than per vertex is
## what makes the facets read as broken planes instead of a smooth blob.
static func _add_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# Godot uses clockwise front faces; the outward normal follows the reverse cross product.
	var normal := (c - a).cross(b - a).normalized()
	for vertex in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(vertex)


## A shade of ice per shard, varied a little so a cluster is not one flat colour.
##
## Roughness climbs with the index: the main shard is the wettest-looking and the chips around
## it are duller, which is what stops the cluster reading as one object cut into pieces.
static func _ice_material(index: int, rng: RandomNumberGenerator) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	var variation := rng.randf_range(-0.035, 0.035)
	material.albedo_color = Color(0.28 + variation, 0.58 + variation, 0.67 + variation)
	material.roughness = 0.34 + float(index) * 0.035
	material.metallic_specular = 0.68
	return material

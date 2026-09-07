class_name RockObstacle
extends StaticBody3D

## A boulder, built out of angular lumps.
##
## It was one seven-sided cylinder, which is a barrel. Texturing it produced a textured barrel:
## a silhouette is not something a texture can fix, and the wizard rig had just finished
## demonstrating that from the other direction.
##
## Three lumps rather than one, at different sizes and angles, and every sphere is cut with
## SIX segments and THREE rings on purpose. That is few enough that the facets read as the
## flat planes of broken stone - the same trick the hand-painted highlight in a Warcraft III
## texture is doing - and it costs about sixty triangles for a thing that is thirty pixels
## tall.
##
## The collision shape is untouched and stays in the scene: what a rock BLOCKS is a gameplay
## number that four suites measure, and it must not drift because the art changed.

## Rough radius of the main lump, in metres. The collision cylinder is 0.7, so the art is a
## little wider than what it stops - which is what you want, or a wizard slides along an
## invisible wall a hand's width outside the rock.
@export var size := 0.86

## Different every instance, and STABLE for each one: seeded from where the rock stands, so
## two boulders are two boulders and neither changes shape between runs. A screenshot taken
## twice has to be the same screenshot, or nothing can be compared to anything.
@export var seed_offset := 0

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(Vector2(position.x, position.z)) + seed_offset
	_build()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/materials/rock.png")
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	mat.uv1_scale = Vector3(0.6, 0.6, 0.6)
	mat.uv1_triplanar = true

	# The main mass, squashed and leaning. A boulder is wider than it is tall and it never sits
	# level - both of those are what stop it reading as a barrel stood on end.
	_lump(Vector3(0.0, size * 0.86, 0.0), size,
		Vector3(1.0, 0.80, 0.88), _rng.randf_range(-0.16, 0.16), mat)
	# A shoulder, part-buried, on a random side.
	var angle := _rng.randf_range(0.0, TAU)
	_lump(Vector3(cos(angle) * size * 0.62, size * 0.44, sin(angle) * size * 0.62),
		size * 0.58, Vector3(1.0, 0.74, 0.92), _rng.randf_range(-0.3, 0.3), mat)
	# A chip at the foot, opposite it, so the base is not a circle.
	var other := angle + PI + _rng.randf_range(-0.9, 0.9)
	_lump(Vector3(cos(other) * size * 0.72, size * 0.22, sin(other) * size * 0.72),
		size * 0.38, Vector3(1.0, 0.66, 1.0), _rng.randf_range(-0.4, 0.4), mat)


## One angular mass. `squash` is applied on top of the radius, `tilt` leans it off vertical.
func _lump(at: Vector3, radius: float, squash: Vector3, tilt: float,
		mat: StandardMaterial3D) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	# Six and three. Any smoother and it is a pebble; any coarser and the triplanar mapping
	# has too little surface to read a facet on.
	mesh.radial_segments = 6
	mesh.rings = 3
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.set_surface_override_material(0, mat)
	node.position = at
	node.scale = squash
	node.rotation = Vector3(tilt, _rng.randf_range(0.0, TAU), tilt * 0.6)
	add_child(node)

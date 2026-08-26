class_name GroundShapes
extends Object

## Flat meshes that lie on the ground plane, built from a spell's own numbers.
##
## Every one of these is a shape the player is told something with: the fan Force Wave will
## hit, the lane a Fireball will fly down, the spot a Blink will put you on. They live in one
## file because the SAME shape is drawn twice - once while you are aiming and once when the
## spell goes off - and a fan that was aimed differently from the fan that hit would teach the
## player something untrue. One builder, two callers, no second copy of the trigonometry.
##
## Everything is built around -Z, which is where a yaw of 0 looks in Godot, so a caller
## orients a shape by setting `rotation.y` and nothing here needs to know about aim.
##
## An Object with static functions and no state: this is a workshop, not a node.

## Straightness of an arc. Sixteen segments is smooth at arena scale and costs nothing.
const SEGMENTS := 16


## A pie slice: `reach` metres long, `half_angle_deg` either side of -Z.
##
## `half_angle_deg` is the HALF angle, matching `Ability.cone_angle`, so 55 gives a 110
## degree fan. Feeding it the full angle draws a fan twice as wide as the one that hits.
static func fan(reach: float, half_angle_deg: float) -> ArrayMesh:
	var half := deg_to_rad(half_angle_deg)
	var verts := PackedVector3Array()
	verts.append(Vector3.ZERO)
	for i in SEGMENTS + 1:
		var a := lerpf(-half, half, float(i) / float(SEGMENTS))
		verts.append(Vector3(-sin(a), 0.0, -cos(a)) * reach)
	var indices := PackedInt32Array()
	for i in SEGMENTS:
		indices.append(0)
		indices.append(i + 1)
		indices.append(i + 2)
	return _mesh(verts, indices)


## A rectangle lying along -Z, from `start` to `length`, `width` metres across.
##
## `start` exists so a projectile's lane can begin where the projectile is actually born
## rather than inside the caster, which is the difference between a lane you can sight down
## and a smear across your own wizard.
static func strip(length: float, width: float, start: float = 0.0) -> ArrayMesh:
	var half := maxf(width, 0.01) * 0.5
	var near := -maxf(start, 0.0)
	var far := -maxf(length, start + 0.01)
	var verts := PackedVector3Array([
		Vector3(-half, 0.0, near),
		Vector3(half, 0.0, near),
		Vector3(half, 0.0, far),
		Vector3(-half, 0.0, far),
	])
	var indices := PackedInt32Array([0, 1, 2, 0, 2, 3])
	return _mesh(verts, indices)


## An annulus centred on the origin: a ring `thickness` metres wide at `radius`.
##
## Used for the spot a Blink lands on and for the "this one affects you" circle a buff draws.
## A ring rather than a disc because a filled circle under a wizard reads as ground the
## wizard is standing on, and this is a place the wizard is not standing yet.
static func ring(radius: float, thickness: float) -> ArrayMesh:
	var inner := maxf(radius - thickness * 0.5, 0.01)
	var outer := radius + thickness * 0.5
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var steps := SEGMENTS * 2
	for i in steps:
		var a := TAU * float(i) / float(steps)
		var dir := Vector3(sin(a), 0.0, cos(a))
		verts.append(dir * inner)
		verts.append(dir * outer)
	for i in steps:
		var a0 := i * 2
		var b0 := ((i + 1) % steps) * 2
		indices.append(a0)
		indices.append(a0 + 1)
		indices.append(b0 + 1)
		indices.append(a0)
		indices.append(b0 + 1)
		indices.append(b0)
	return _mesh(verts, indices)


## Four flat triangles pointing INWARD at a point - the mark a right click leaves on the
## ground, drawn the way the arena map this game follows draws it.
##
## Inward and not outward, which is the whole of why it reads as "here" rather than as an
## explosion: four arrows closing on a spot name the spot.
static func arrows(radius: float, size: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	for step in 4:
		var angle := TAU * float(step) / 4.0
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var base := out * radius
		var start := verts.size()
		verts.append(out * maxf(radius - size, 0.0))
		verts.append(base + side * size * 0.5)
		verts.append(base - side * size * 0.5)
		indices.append_array(PackedInt32Array([start, start + 1, start + 2]))
	return _mesh(verts, indices)


static func _mesh(verts: PackedVector3Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return built


## The unshaded, two-sided, translucent material every ground shape wants.
##
## Unshaded because these are light rather than surfaces: an aim line that dims when the key
## light is behind you is an aim line you cannot trust. Two-sided because a flat mesh seen
## from underneath - which happens the moment a wizard is knocked below the rim - would
## otherwise vanish.
static func flat_material(tint: Color, alpha: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
	return mat

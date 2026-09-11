class_name BlastRing
extends Node3D

## The ring that opens on the ground where a blast went off, at exactly the blast's own radius.
##
## A blast used to be invisible when it caught nobody. That is the one case where seeing it
## matters most: `_burst` resolves at the SPOT a projectile died rather than on what it
## touched, so "a meteor that lands on empty ground has still landed" was true in the code and
## unreadable on screen. Standing just outside one and standing just inside one produced the
## same picture.
##
## Sized from `Ability.area` and nothing else, which is the same rule `SpellFlash` keeps for a
## cone and `AimIndicator` for a lane: a shape drawn from the ability's own numbers cannot
## promise a different reach from the one that hits. The reference map does this too - it
## scales its explosion model to the blast radius on the frame it plays, `SetUnitScale(F[PN],
## .006*EY, ...)`. See docs/warlock-reference.md section 9a.
##
## Pooled like `ImpactBurst` and for the same reason: two blasts can overlap, and building a
## mesh mid-fight is the allocation the projectile pool exists to avoid.

## How many rings may be open at once. Two blasts in the same second is already unusual.
const POOL := 4

## Seconds a ring takes to open and fade. Short: it is the record of an instant, and a circle
## that lingers reads as an area that is still dangerous - which is the one thing it is not.
@export var duration := 0.32

@export_range(0.0, 1.0, 0.01) var peak_alpha := 0.5

## Fraction of the final radius the ring starts at. Not zero - a ring that opens from nothing
## spends its first frames as a dot, which reads as a spark rather than as a shockwave.
@export_range(0.0, 1.0, 0.01) var from_fraction := 0.35

## Width of the band, as a fraction of the radius, so a big blast gets a bold ring and a small
## one a fine ring rather than both getting the same hairline.
@export_range(0.01, 0.5, 0.01) var band := 0.09

var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
## Seconds left on each ring, and the radius each is opening to. Parallel to `_rings`.
var _life: PackedFloat32Array = PackedFloat32Array()
var _radius: PackedFloat32Array = PackedFloat32Array()
var _next := 0

## The band is authored at radius 1 and scaled by the node, exactly like a projectile's bolt
## mesh and a glyph's unit box: one drawing, any size.
static var _unit_ring: ArrayMesh = null


func _ready() -> void:
	if _unit_ring == null:
		_unit_ring = GroundShapes.ring(1.0, band)
	for i in POOL:
		var ring := MeshInstance3D.new()
		ring.mesh = _unit_ring
		# The lesson the sparks taught: a flat translucent thing that casts a shadow puts a
		# dark smear on the arena instead of light. See ARCHITECTURE.md.
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := GroundShapes.flat_material(Color(1, 1, 1), peak_alpha)
		ring.material_override = mat
		ring.visible = false
		add_child(ring)
		_rings.append(ring)
		_materials.append(mat)
		_life.append(0.0)
		_radius.append(1.0)
	set_process(false)


func _process(delta: float) -> void:
	var busy := false
	for i in _rings.size():
		if _life[i] <= 0.0:
			continue
		_life[i] -= delta
		if _life[i] <= 0.0:
			_rings[i].visible = false
			continue
		busy = true
		var spent := 1.0 - _life[i] / maxf(duration, 0.0001)
		# Opens toward the radius and fades while it does, so the last thing the eye sees is
		# the ring AT the reach of the damage rather than somewhere short of it.
		var wide := _radius[i] * lerpf(from_fraction, 1.0, spent)
		_rings[i].transform.basis = Basis().scaled(Vector3(wide, 1.0, wide))
		_materials[i].albedo_color.a = peak_alpha * (1.0 - spent)
	if not busy:
		set_process(false)


## Opens a ring `radius` metres across, centred on `at`, in the spell's own colour.
##
## `at` is the spot the blast resolved at, which for a falling spell is the height it was
## thrown from rather than the floor. Dropped to ground level here rather than at the call
## site, because the call site is the combat layer and the floor is a drawing concern.
func play(at: Vector3, tint: Color, radius: float, ground_drop: float = 0.92) -> void:
	if radius <= 0.0:
		return
	var index := _next
	_next = (_next + 1) % _rings.size()
	var ring := _rings[index]
	ring.global_position = Vector3(at.x, at.y - ground_drop, at.z)
	ring.transform.basis = Basis().scaled(
		Vector3(radius * from_fraction, 1.0, radius * from_fraction))
	ring.visible = true
	_materials[index].albedo_color = Color(tint.r, tint.g, tint.b, peak_alpha)
	_life[index] = duration
	_radius[index] = radius
	set_process(true)


## How many rings are open. For the harness.
func active_count() -> int:
	var n := 0
	for i in _rings.size():
		if _life[i] > 0.0:
			n += 1
	return n

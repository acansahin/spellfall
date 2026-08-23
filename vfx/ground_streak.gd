class_name GroundStreak
extends MeshInstance3D

## The smear a Blink leaves between where you were and where you are.
##
## Blink was the one spell with no visual at all: the wizard simply appeared elsewhere. It
## read, in the sense that you could tell what had happened - but only afterwards, and never
## from the other side of the arena, where an opponent vanishing is indistinguishable from a
## dropped frame. This draws the line they took.
##
## Ground-level, flat, and built by `GroundShapes` like everything else drawn on the floor,
## so a dash reads as the same kind of object as the fan and the aim lane. It is a WORLD-space
## node owned by the level rather than a child of the fighter: the fighter is at the far end
## by the time this is drawn, and a child would draw the streak from the wrong place.

## Seconds the streak takes to fade out. Short - it is the record of a movement, and a trail
## that outlives the movement turns into scenery.
@export var duration := 0.28

@export var peak_alpha := 0.45

## Width of the smear, in metres.
@export var width := 0.55

## Metres from a fighter's origin down to the floor, so the streak lies on the ground rather
## than through the wizard's waist. Matches the offset the SpellFlash node carries in
## player.tscn.
@export var ground_drop := 0.92

var _life := 0.0
var _material: StandardMaterial3D = null
var _built_length := -1.0


func _ready() -> void:
	_material = GroundShapes.flat_material(Color(1, 1, 1), peak_alpha)
	material_override = _material
	visible = false
	set_process(false)


## Draws the smear from `from` to `to`, in the spell's own colour.
func play(from: Vector3, to: Vector3, tint: Color) -> void:
	var travel := to - from
	var flat := Vector2(travel.x, travel.z)
	var length := flat.length()
	if length < 0.05:
		return
	_rebuild(length)
	global_position = Vector3(from.x, from.y - ground_drop, from.z)
	# Same convention as everything else on the ground: meshes are built around -Z, and a yaw
	# of `a` looks along (-sin a, -cos a).
	rotation.y = atan2(-flat.x, -flat.y)
	_material.albedo_color = Color(tint.r, tint.g, tint.b, peak_alpha)
	_life = duration
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		visible = false
		set_process(false)
		return
	_material.albedo_color.a = peak_alpha * (_life / maxf(duration, 0.0001))


## Rebuilt only when the distance changes, which for a clamped Blink is most casts - but a
## strip is four vertices, so this is cheap in a way the fan is not.
func _rebuild(length: float) -> void:
	if is_equal_approx(length, _built_length):
		return
	_built_length = length
	mesh = GroundShapes.strip(length, width, 0.0)


## True while the streak is on screen. For the harness.
func is_showing() -> bool:
	return visible and _life > 0.0

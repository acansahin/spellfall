class_name GroundStreak
extends MeshInstance3D

## The smear a Teleport leaves between where you were and where you are.
##
## Teleport was the one spell with no visual at all: the wizard simply appeared elsewhere. It
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
var _style: StringName = &"blink"
var _active_alpha := 0.45
var _accents: Array[MeshInstance3D] = []
var _accent_materials: Array[StandardMaterial3D] = []
var _start_ring: MeshInstance3D
var _end_ring: MeshInstance3D
var _ring_materials: Array[StandardMaterial3D] = []
var _burst: CPUParticles3D


func _ready() -> void:
	_material = GroundShapes.flat_material(Color(1, 1, 1), peak_alpha)
	material_override = _material
	for i in 3:
		var accent := MeshInstance3D.new()
		accent.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := GroundShapes.flat_material(Color.WHITE, 0.0)
		accent.material_override = mat
		add_child(accent)
		_accents.append(accent)
		_accent_materials.append(mat)
	for endpoint in 2:
		var ring := MeshInstance3D.new()
		ring.mesh = GroundShapes.ring(0.62, 0.10)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ring_mat := GroundShapes.flat_material(Color.WHITE, 0.0)
		ring.material_override = ring_mat
		add_child(ring)
		_ring_materials.append(ring_mat)
		if endpoint == 0:
			_start_ring = ring
		else:
			_end_ring = ring
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.explosiveness = 1.0
	_burst.local_coords = false
	_burst.amount = 18
	_burst.lifetime = 0.38
	_burst.direction = Vector3.UP
	_burst.spread = 58.0
	_burst.initial_velocity_min = 0.8
	_burst.initial_velocity_max = 2.6
	_burst.gravity = Vector3(0.0, -2.6, 0.0)
	var fleck := BoxMesh.new()
	fleck.size = Vector3(0.045, 0.15, 0.045)
	var fleck_mat := StandardMaterial3D.new()
	fleck_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fleck_mat.vertex_color_use_as_albedo = true
	fleck.material = fleck_mat
	_burst.mesh = fleck
	_burst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_burst)
	visible = false
	set_process(false)


## Draws the smear from `from` to `to`, in the spell's own colour.
func play(from: Vector3, to: Vector3, tint: Color, style: StringName = &"blink") -> void:
	var travel := to - from
	var flat := Vector2(travel.x, travel.z)
	var length := flat.length()
	if length < 0.05:
		return
	_rebuild(length)
	_style = style
	var draw_tint := tint
	if style == &"wind_walk":
		draw_tint = Color(0.18, 0.82, 1.0)
	elif style == &"lunge":
		draw_tint = Color(1.0, 0.55, 0.08)
	global_position = Vector3(from.x, from.y - ground_drop, from.z)
	# Same convention as everything else on the ground: meshes are built around -Z, and a yaw
	# of `a` looks along (-sin a, -cos a).
	rotation.y = atan2(-flat.x, -flat.y)
	_active_alpha = 0.62 if style == &"wind_walk" else peak_alpha
	_material.albedo_color = Color(draw_tint.r, draw_tint.g, draw_tint.b, _active_alpha)
	var spacing := width * (0.62 if style == &"wind_walk" else 0.46)
	for i in _accents.size():
		_accents[i].position.x = (i - 1) * spacing
		_accents[i].visible = style != &"lunge" or i == 1
		_accent_materials[i].albedo_color = Color(draw_tint.r, draw_tint.g, draw_tint.b,
			0.76 if i == 1 else 0.56)
	_start_ring.position = Vector3.ZERO
	_end_ring.position = Vector3(0.0, 0.0, -length)
	_start_ring.visible = style in [&"blink", &"warp_bolt"]
	_end_ring.visible = true
	_end_ring.scale = Vector3.ONE
	for ring_mat in _ring_materials:
		ring_mat.albedo_color = Color(draw_tint.r, draw_tint.g, draw_tint.b, 0.82)
	_burst.global_position = Vector3(to.x, to.y - ground_drop + 0.08, to.z)
	_burst.color = draw_tint
	_burst.restart()
	_life = duration
	visible = true
	set_process(true)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		visible = false
		set_process(false)
		return
	_material.albedo_color.a = _active_alpha * (_life / maxf(duration, 0.0001))
	var fade := _life / maxf(duration, 0.0001)
	for i in _accent_materials.size():
		_accent_materials[i].albedo_color.a = (0.76 if i == 1 else 0.56) * fade
	for ring_mat in _ring_materials:
		ring_mat.albedo_color.a = 0.72 * fade
	var pulse := 1.0 + (1.0 - fade) * 0.7
	_end_ring.scale = Vector3.ONE * pulse
	if _style == &"wind_walk":
		for i in _accents.size():
			_accents[i].position.x += sin((1.0 - fade) * 11.0 + i * 2.1) * delta * 0.7


## Rebuilt only when the distance changes, which for a clamped Teleport is most casts - but a
## strip is four vertices, so this is cheap in a way the fan is not.
func _rebuild(length: float) -> void:
	if is_equal_approx(length, _built_length):
		return
	_built_length = length
	mesh = GroundShapes.strip(length, width, 0.0)
	for i in _accents.size():
		var line_width := width * (0.12 if i != 1 else 0.18)
		_accents[i].mesh = GroundShapes.strip(length, line_width, 0.0)


## True while the streak is on screen. For the harness.
func is_showing() -> bool:
	return visible and _life > 0.0

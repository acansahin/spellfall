class_name AimIndicator
extends Node3D

## What a spell is about to do, drawn on the ground before it happens.
##
## Nothing in the game showed the player where a spell would land. On a keyboard that is
## survivable - you cast where you are walking and you find out. Under a thumb it is not: the
## finger is doing the aiming and the finger is also covering part of the screen, so a spell
## with no preview is a spell you learn by missing.
##
## Every shape here is built from the ability's OWN numbers - reach, cone angle, projectile
## radius - through the same GroundShapes builder the hit tests and the cast flash use. That
## is the rule this file exists to keep: an indicator that promises a different shape from the
## one that lands is worse than no indicator at all, because the player believes it.
##
## It is a CHILD of the fighter, like SpellFlash, so it needs no placement and no pooling: it
## is already where the caster is, and the fighter's body never rotates - only its Visual
## does - so a local yaw here is a world yaw.
##
## The bot's wizard inherits one of these and never shows it. Nothing calls `show_for` on the
## bot, which is the whole of "only the human sees their own aim".

## Which drawing is up. Read by the harness, which asserts that a cone draws a fan and a
## projectile does not.
enum Shape {
	## Nothing shown.
	NONE,
	## A lane down which a projectile will fly.
	LANE,
	## The fan a cone will catch.
	FAN,
	## A line to the spot a dash lands on, with that spot marked.
	DASH,
	## A ring around the caster: this one affects you and needs no aim.
	SELF,
}

## Transparency of the shape. Low enough to see the arena and the opponent through it - this
## is a hint, not a wall - and high enough to read on a phone in daylight.
@export_range(0.0, 1.0, 0.01) var shape_alpha := 0.30

## The marker on a dash landing spot sits brighter than its line: the line is the route, the
## ring is the answer to the only question being asked.
@export_range(0.0, 1.0, 0.01) var marker_alpha := 0.55

## Narrowest a projectile lane may be drawn, in metres. A Fireball is 0.35 across, and a lane
## that honest is a hairline at this camera distance - it would be accurate and useless.
@export var min_lane_width := 0.45

## Width of the line drawn along a dash.
@export var dash_line_width := 0.30

## Radius of the ring drawn where a dash lands, and of the one drawn around the caster for a
## self-cast. Roughly a wizard's own footprint, so it reads as "you, there".
@export var marker_radius := 0.70

@onready var _shape: MeshInstance3D = $Shape
@onready var _marker: MeshInstance3D = $Marker

var _shape_mat: StandardMaterial3D = null
var _marker_mat: StandardMaterial3D = null

var _kind := Shape.NONE
var _reach := 0.0
var _half_angle := 0.0
## Key of the mesh currently built, so an unchanged shape is not rebuilt every frame. A
## String because the key is a mixture of an enum and three floats, and this runs once per
## aim rather than once per vertex.
var _built := ""


func _ready() -> void:
	_shape_mat = GroundShapes.flat_material(Color(1, 1, 1), shape_alpha)
	_marker_mat = GroundShapes.flat_material(Color(1, 1, 1), marker_alpha)
	_shape.material_override = _shape_mat
	_marker.material_override = _marker_mat
	clear()


## Draws `ability` pointing along `aim`, reaching `reach` metres.
##
## `reach` is passed in rather than read off the ability because a dash is clamped to the
## arena, and the arena's size belongs to the level. Handing the number in keeps the one
## clamp in the one place that owns it - the drawn line stops exactly where `_cast_dash`
## would put you, because both ask the same function.
func show_for(ability: Ability, aim: Vector3, reach: float) -> void:
	if ability == null:
		clear()
		return
	var flat := Vector2(aim.x, aim.z)
	if flat.length_squared() > 0.0001:
		# Same convention as player.gd and SpellFlash: yaw 0 looks down -Z, and every
		# GroundShapes mesh is built around -Z.
		rotation.y = atan2(-flat.x, -flat.y)
	_reach = maxf(reach, 0.0)
	_half_angle = ability.cone_angle
	_kind = _shape_for(ability.cast_type)
	_rebuild(ability)
	var tint := ability.colour
	_shape_mat.albedo_color = Color(tint.r, tint.g, tint.b, shape_alpha)
	_marker_mat.albedo_color = Color(tint.r, tint.g, tint.b, marker_alpha)
	visible = true
	_marker.visible = _kind == Shape.DASH


func clear() -> void:
	_kind = Shape.NONE
	visible = false


func _shape_for(cast_type: Ability.CastType) -> Shape:
	match cast_type:
		Ability.CastType.PROJECTILE:
			return Shape.LANE
		Ability.CastType.CONE:
			return Shape.FAN
		Ability.CastType.DASH:
			return Shape.DASH
		_:
			return Shape.SELF


func _rebuild(ability: Ability) -> void:
	var key := "%d|%.3f|%.3f|%.3f" % [_kind, _reach, _half_angle, ability.projectile_radius]
	if key == _built:
		return
	_built = key
	match _kind:
		Shape.LANE:
			# Starts where the projectile is born, not inside the wizard.
			var width := maxf(ability.projectile_radius * 2.0, min_lane_width)
			_shape.mesh = GroundShapes.strip(_reach, width, ability.spawn_offset)
		Shape.FAN:
			_shape.mesh = GroundShapes.fan(_reach, _half_angle)
		Shape.DASH:
			_shape.mesh = GroundShapes.strip(_reach, dash_line_width, 0.0)
			_marker.mesh = GroundShapes.ring(marker_radius, 0.12)
			_marker.position = Vector3(0.0, 0.0, -_reach)
		_:
			_shape.mesh = GroundShapes.ring(marker_radius * 1.6, 0.16)


## True while something is drawn. For the harness and for anything that wants to know the
## player is mid-aim without asking the input layer.
func is_showing() -> bool:
	return _kind != Shape.NONE and visible


func shape() -> Shape:
	return _kind


func reach() -> float:
	return _reach


func half_angle() -> float:
	return _half_angle

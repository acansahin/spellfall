class_name HealthBar
extends Node3D

## The burn bar over a wizard's head.
##
## The HUD row already carries the number, and the number is the precise one - but it lives in
## a corner, and the corner is not where anybody is looking while they are on fire and walking
## for the stone. This is the same value where the eye already is: over the fighter it belongs
## to, next to the thing you are steering.
##
## It shows the LAVA burn and nothing else. There is no combat health in this game - hits
## raise instability - so a bar that filled and emptied during a normal exchange would be
## telling a lie about what the fight is made of. It only ever moves when someone is out of
## the ring, which is exactly when it should be the loudest thing on screen.
##
## Two quads and no textures: a dark backing and a fill that shrinks from the right. The fill
## keeps its left edge pinned, because a bar that shrinks toward its centre reads as a bar
## that is being squeezed rather than one that is running out.

## Width and height of the bar in metres.
##
## Sized against the SCREEN, not the wizard, and photographed rather than guessed. A bar a
## little wider than the 1m body sounds right and comes out 35 pixels by 4 at the camera's
## furthest zoom - a stray dash rather than a gauge. 2.2 by 0.3 reads at the widest zoom and
## grows with the camera as the ring closes, which is when it matters most.
@export var width := 2.4
@export var height := 0.38

## Metres above the fighter's origin. Clear of a 2m capsule's head with room for the bar not
## to sit ON the skull.
@export var lift := 1.75

@export_group("Colour")
## Full, half, and nearly gone. Green would vanish into the arena floor, and orange would read
## as the lava rather than as a warning about it - so full is a pale, almost white green, and
## the danger end is the one red nothing else on screen uses.
@export var full_tint := Color(0.85, 0.98, 0.86)
@export var half_tint := Color(1.0, 0.78, 0.25)
@export var low_tint := Color(1.0, 0.27, 0.18)
@export var backing_tint := Color(0.05, 0.04, 0.06, 0.72)

@onready var _back: MeshInstance3D = $Back
@onready var _fill: MeshInstance3D = $Fill

var _source: HealthComponent = null
var _fill_material: StandardMaterial3D = null


func _ready() -> void:
	position.y = lift
	_shape(_back, backing_tint, width, height)
	_fill_material = _shape(_fill, full_tint, width, height * 0.72)
	# The fill sits a hair in front of the backing. Coplanar quads z-fight, and at this camera
	# distance that shows up as the bar flickering rather than as anything obviously wrong.
	_fill.position.z = 0.01
	visible = false


## Builds one quad and returns its material, so the fill can keep hold of its own.
##
## Billboarded, so the bar faces the camera whatever the pitch is - and `billboard_keep_scale`
## with it, because billboarding otherwise throws away the node scale that the fill uses to
## show the value.
func _shape(target: MeshInstance3D, tint: Color, w: float, h: float) -> StandardMaterial3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(w, h)
	target.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.albedo_color = tint
	target.material_override = mat
	# A bar behind a tree is a bar nobody can read, and this one only appears at the moment it
	# matters most. It draws through the world on purpose.
	mat.no_depth_test = true
	target.sorting_offset = 1.0
	return mat


## Points the bar at a fighter's burn. Called by the fighter itself - it is the one thing that
## certainly knows which HealthComponent is its own.
func bind(source: HealthComponent) -> void:
	if _source != null and _source.changed.is_connected(_on_changed):
		_source.changed.disconnect(_on_changed)
	_source = source
	if _source != null:
		_source.changed.connect(_on_changed)
	_refresh()


func _on_changed(_current: float, _previous: float) -> void:
	_refresh()


func _refresh() -> void:
	if _source == null:
		visible = false
		return
	var fraction := clampf(_source.fraction(), 0.0, 1.0)
	# Hidden while untouched. Two full bars sitting over two wizards for the whole opening of
	# every round is furniture, and furniture is what the eye stops seeing - including on the
	# one occasion it moves.
	visible = fraction < 0.999
	if not visible:
		return
	_fill.scale.x = maxf(fraction, 0.001)
	# Pinned at the left edge: shrink about the centre and the quad would eat both ends.
	_fill.position.x = -width * (1.0 - fraction) * 0.5
	_fill_material.albedo_color = _tint(fraction)


## Pale at full, amber through the middle, red at the end.
func _tint(fraction: float) -> Color:
	if fraction > 0.5:
		return half_tint.lerp(full_tint, (fraction - 0.5) * 2.0)
	return low_tint.lerp(half_tint, fraction * 2.0)


## What the bar is currently showing, 0..1. For the harness.
func shown_fraction() -> float:
	return _fill.scale.x if _fill != null else 0.0

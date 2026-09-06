class_name Arena
extends Node3D

## The stone ring, and the only thing that knows how big it is right now.
##
## The radius used to be a number typed into a collision shape, read once at startup and
## copied to whoever needed it. It is a moving value now - the ring closes during a round -
## so it lives here and everything else asks. Teleport clamps against it, the bot keeps clear of
## it, the aim lane stops at it, the lava burns whoever is outside it, and the camera frames
## it; five readers, one source.
##
## **It closes DURING a round, not between rounds.** The map this game takes after shrinks its
## arena one step per round, which bounds a match but leaves a single round able to run
## forever - and a round that can stall is exactly the problem, because nobody is knocked out
## by accident any more now that the lava gives a way back. A ring that closes on a clock ends
## every round on its own, and turns "hold your ground" into a decision with a deadline.
##
## Nothing here knows what a fighter is. It moves geometry and emits a number.

## Emitted whenever the ring changes size. The level re-points the camera, the bot and its own
## cached edge at it.
signal radius_changed(radius: float)

## Where a round starts. The reference map's 1408 units, at 128 units to the metre - see
## docs/warlock-reference.md.
##
## It was already 12.0, which is within a metre of the map's own ring, so this barely moves.
## Worth saying out loud because it is the half of the "too fast" problem that was NOT wrong:
## the arena was the right size all along and the wizard was crossing it 2.4x too quickly. At
## 1.641 m/s an eleven-metre ring takes 13.4 seconds to cross, which is the map's number.
@export var start_radius := 11.0

## How small it is allowed to get. At 4.5m a Scourge reaches most of the way across, which
## is the point: by the end of a round, standing still is not an option anyone has.
@export var min_radius := 4.5

## Seconds at full size before it begins to close. The opening exchange happens on the whole
## board; the squeeze is what breaks a stalemate, so it should not arrive before there is one.
@export var grace_seconds := 12.0

## Metres of radius lost per second once it starts. At 0.3 the ring takes 25 seconds to go
## from 12m to 4.5m, so a round that nobody wins outright resolves in well under a minute.
@export var shrink_per_second := 0.3

## Fraction of the radius the rim ring sits at, and how wide it and the molten shore are.
@export var rim_width := 1.0
@export var shore_gap := 0.15
@export var shore_width := 0.85

## Off while a suite is measuring. Fourth in the family after the bot, the game feel and the
## cover: every one of those suites picks distances by hand and would have the ground move
## under it mid-measurement.
var shrinking := true

var radius: float = 0.0

@onready var _platform_mesh: MeshInstance3D = $Platform/Mesh
@onready var _platform_shape: CollisionShape3D = $Platform/Collision
@onready var _rim: MeshInstance3D = $Rim
@onready var _shore: MeshInstance3D = $Lava/Shore
@onready var _obstacles: Node3D = $Obstacles

var _elapsed := 0.0

## Where each obstacle stands, as a FRACTION of the radius, captured once from the scene. The
## cover shrinks with the ring rather than being swallowed by it - a ring that closes over its
## own cover would spend the second half of every round as a bare plate.
var _obstacle_spots: Array = []


func _ready() -> void:
	# Sub-resources are shared by every instance of a scene, and these get written to every
	# frame the ring is closing. Duplicating is the same precaution projectile.gd takes with
	# its mesh and shape, and for the same reason: one arena editing another's geometry would
	# be a very confusing bug to meet later.
	_platform_mesh.mesh = _platform_mesh.mesh.duplicate()
	_platform_shape.shape = _platform_shape.shape.duplicate()
	_rim.mesh = _rim.mesh.duplicate()
	_shore.mesh = _shore.mesh.duplicate()
	var base: float = (_platform_shape.shape as CylinderShape3D).radius
	for child in _obstacles.get_children():
		var body := child as Node3D
		if body != null:
			_obstacle_spots.append([body, body.position / maxf(base, 0.001)])
	reset()


## Back to full size, and the clock back to zero. The round system calls this.
func reset() -> void:
	_elapsed = 0.0
	_set_radius(start_radius)


## One tick of the round. The level calls this only while the round is live: a ring that
## closed through the countdown would take the interlude with it.
func tick(delta: float) -> void:
	if not shrinking or radius <= min_radius:
		return
	_elapsed += delta
	if _elapsed < grace_seconds:
		return
	_set_radius(maxf(radius - shrink_per_second * delta, min_radius))


## Seconds until it starts closing, or 0 once it has.
func grace_left() -> float:
	return maxf(grace_seconds - _elapsed, 0.0)


func is_closing() -> bool:
	return shrinking and _elapsed >= grace_seconds and radius > min_radius


func _set_radius(value: float) -> void:
	if is_equal_approx(value, radius):
		return
	radius = value
	_apply()
	radius_changed.emit(radius)


## Moves every piece of geometry that describes the ring.
func _apply() -> void:
	var mesh := _platform_mesh.mesh as CylinderMesh
	if mesh != null:
		mesh.top_radius = radius
		# The taper is a fraction, so the platform keeps its shape as it closes.
		mesh.bottom_radius = radius * 0.9
	var shape := _platform_shape.shape as CylinderShape3D
	if shape != null:
		shape.radius = radius
	var rim := _rim.mesh as TorusMesh
	if rim != null:
		rim.inner_radius = maxf(radius - rim_width * 0.5, 0.05)
		rim.outer_radius = radius + rim_width * 0.5
	var shore := _shore.mesh as TorusMesh
	if shore != null:
		shore.inner_radius = radius + shore_gap
		shore.outer_radius = radius + shore_gap + shore_width
	for spot in _obstacle_spots:
		var body: Node3D = spot[0]
		var fraction: Vector3 = spot[1]
		body.position = fraction * radius

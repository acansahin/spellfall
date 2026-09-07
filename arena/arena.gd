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
## **It closes DURING a round, in whole-metre steps, and it does not stop.** That is the
## reference map's own behaviour, read out of `PY()` and `WY()` in its script - see
## docs/warlock-reference.md section 7c. This file used to say the map shrank between rounds
## and that a continuous close was this port's own idea; both were wrong, and wrong because
## nobody had looked.
##
## Three properties come with it and each is the point rather than a detail:
##
## - **It steps.** A whole ring of ground becomes lava at one moment. That is a different kind
##   of pressure from a rim creeping inward: you can be standing somewhere safe and be standing
##   in lava a moment later without having moved.
## - **It speeds up as fighters die**, because the interval is `10 * sqrt(alive)` and `alive`
##   is recomputed on every step. The closing ring is the loser's punishment and the winner's
##   reward in one number.
## - **It goes to zero.** There is no minimum, so a round always ends - which is the job the
##   old continuous close was invented to do, and the map was already doing it.
##
## Nothing here knows what a fighter is. It moves geometry and emits a number.

## Emitted whenever the ring changes size. The level re-points the camera, the bot and its own
## cached edge at it.
signal radius_changed(radius: float)

## Metres of radius a round starts at, if nobody says otherwise.
##
## The map sizes its ring off the ROSTER - `9 + players/2` tiles, and a tile is one metre here
## - so this is only the fallback for a scene opened with nobody in it. `size_for()` below is
## what actually decides, and the level calls it once the squad exists.
@export var start_radius := 11.0

## The map's `9 +` term, in metres.
@export var base_radius := 9.0

## Seconds per step at ONE fighter alive. The map's `NN`, and the interval is this times the
## square root of how many are still standing.
@export var seconds_per_step := 10.0

## Metres the ring loses per step. The map moves one terrain tile at a time and a Warcraft III
## tile is 128 units, which is exactly one metre on this port's scale.
@export var step_metres := 1.0

## THERE IS NO `grace_seconds` AND NO `shrink_per_second` ANY MORE, and no `min_radius`.
##
## The first two were one number each doing what `step_delay()` now does with the map's own
## arithmetic: the ring waits a full interval before its first step, which IS the grace, and
## it moves a whole metre at once rather than a fraction of one per second. The third was a
## floor at 4.5m that the map does not have - it closes to nothing, which is what guarantees
## a round ends rather than merely gets uncomfortable.

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

## Seconds since the last step, or since the round began.
var _elapsed := 0.0

## The size THIS match's rounds start at, from `size_to()`. Zero until the level says.
var _round_start_radius := 0.0

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
## The radius a round starts at for a given number of fighters. The map's `9 + players/2`
## tiles, in metres, with the integer division it uses - so two and three fighters both start
## at ten and four at eleven.
func size_for(fighters: int) -> float:
	return base_radius + float(int(maxi(fighters, 1) / 2))


## Seconds until the next step, given how many are still standing. The map's `NN * sqrt(UH)`.
##
## Recomputed on every step rather than once at the start, which is the whole of why the ring
## speeds up as a fight thins out.
func step_delay(alive: int) -> float:
	return seconds_per_step * sqrt(float(maxi(alive, 1)))


func reset() -> void:
	_elapsed = 0.0
	_set_radius(_round_start_radius if _round_start_radius > 0.0 else start_radius)


## Sets the size this and every following round begins at. The level calls it once the squad
## is formed, because the arena does not know how many wizards there are and should not.
func size_to(fighters: int) -> void:
	_round_start_radius = size_for(fighters)
	_set_radius(_round_start_radius)


## One tick of the round. The level calls this only while the round is live: a ring that
## closed through the countdown would take the interlude with it.
## One tick of the round. The level calls this only while the round is live: a ring that
## closed through the countdown would take the interlude with it.
##
## `alive` is handed in rather than looked up. The arena still knows nothing about fighters -
## it takes a count, the same way it takes a delta.
func tick(delta: float, alive: int = 2) -> void:
	if not shrinking or radius <= 0.0:
		return
	_elapsed += delta
	# The first step lands a full interval in, which is the map's grace: it has no separate
	# grace period, it simply has not stepped yet.
	if _elapsed < step_delay(alive):
		return
	_elapsed = 0.0
	_set_radius(maxf(radius - step_metres, 0.0))


## Seconds until the NEXT step. Named `grace_left` still because that is what it is before the
## first one, and the HUD and three suites already ask for it by that name.
func grace_left(alive: int = 2) -> float:
	return maxf(step_delay(alive) - _elapsed, 0.0)


func is_closing() -> bool:
	return shrinking and radius > 0.0


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

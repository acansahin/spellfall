class_name ImpactBurst
extends Node3D

## The spray of sparks where something got hit.
##
## A hit already had three ways of being noticed - the number on the HUD moved, the body
## slid, and a line of print appeared in a console no player will ever see. None of those is
## AT the point of contact, which is the one place the eye is looking. This puts something
## there for a fifth of a second.
##
## Pooled for the same reason projectiles are: a four-player fight throws a lot of spells,
## and `instantiate()` mid-fight is the classic mobile stutter. Six emitters is more than a
## busy moment needs; past that the oldest is restarted, which costs a tail nobody notices.
##
## CPUParticles3D rather than GPUParticles3D. Fourteen particles is far below the point
## where the GPU path wins anything, and the CPU one has no compatibility caveats on the
## low-end Android hardware this game is aimed at.

## How many emitters may overlap.
const POOL := 6

## Particles per burst. Enough to read as a spray, few enough to cost nothing.
@export var count := 14

@export var lifetime := 0.42

## Metres per second at the slowest and fastest, before the hit's own strength scales them.
@export var speed_min := 1.6
@export var speed_max := 4.2

## Size of one spark, in metres.
##
## Photographed, not guessed. At 0.07 - a physically sensible spark - one particle is four
## pixels on a 720p screen at this camera distance, and the burst reads as dirt on the lens.
## The arena is 14m across and drawn 600px wide; anything meant to be SEEN in it has to be
## sized against the screen rather than against the world.
@export var spark_size := 0.13

## Degrees off vertical the spray covers, for a hit and for a blast.
##
## A hit is a spray from a point of contact and leans upward; a blast went off ON the ground
## and belongs to a circle, so it is thrown almost flat. The two spreads are what keep a
## meteor landing from reading as a very large punch.
const HIT_SPREAD := 75.0
const BLAST_SPREAD := 86.0

var _emitters: Array[CPUParticles3D] = []
var _next := 0
var _mesh: SphereMesh = null


func _ready() -> void:
	_mesh = SphereMesh.new()
	_mesh.radius = spark_size
	_mesh.height = spark_size * 2.0
	_mesh.radial_segments = 6
	_mesh.rings = 3
	var mat := StandardMaterial3D.new()
	# Unshaded, and reading the particle's own colour: sparks are light, and a spark that
	# needs the key light to be visible is a spark you miss in the half of the arena the
	# light is behind you.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	_mesh.material = mat
	for i in POOL:
		_emitters.append(_build())


func _build() -> CPUParticles3D:
	var particles := CPUParticles3D.new()
	particles.emitting = false
	particles.one_shot = true
	# All at once. A burst that trickles reads as a fire, not as an impact.
	particles.explosiveness = 1.0
	particles.amount = count
	particles.lifetime = lifetime
	particles.mesh = _mesh
	# Sparks must not cast shadows. They did, and a dozen tiny shadows on a dark board is a
	# handful of BLACK specks around the hit - which reads as the impact having smudged the
	# arena rather than as light coming off it. Caught in a screenshot; invisible in the code.
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.direction = Vector3.UP
	# Set per burst as well, because `blast` widens it. Left here so a fresh emitter is never
	# waiting on its first call to be given a shape.
	particles.spread = HIT_SPREAD
	particles.gravity = Vector3(0.0, -7.0, 0.0)
	particles.initial_velocity_min = speed_min
	particles.initial_velocity_max = speed_max
	particles.scale_amount_min = 0.7
	particles.scale_amount_max = 1.3
	# Shrink to nothing rather than blink out.
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	particles.scale_amount_curve = curve
	add_child(particles)
	return particles


## Sparks at `at`, tinted `tint`, sized by `strength` in metres per second of knockback.
##
## Strength scales the SPREAD of the spray rather than the count. A heavier hit throwing more
## sparks would be the obvious choice and it reads worse: the count is what the eye uses to
## judge "did something happen", and it should be the same every time so that a light hit
## still registers. How far they go is what says how hard it was.
func burst(at: Vector3, tint: Color, strength: float) -> void:
	var particles := _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	particles.global_position = at
	particles.color = tint
	var scale := clampf(strength / 8.0, 0.5, 2.0)
	particles.initial_velocity_min = speed_min * scale
	particles.initial_velocity_max = speed_max * scale
	particles.spread = HIT_SPREAD
	# Restart rather than merely enable: an emitter still finishing a previous burst ignores
	# `emitting = true` and the hit is silently not drawn.
	particles.restart()


## The spray for an AREA effect: thrown to the rim of `radius` rather than by a fixed strength.
##
## The difference from `burst` above is the whole point. A hit's spray says how HARD; a blast's
## says how FAR, because the only question a player has about a blast is whether they were
## inside it. Sizing the picture to `Ability.area` is the same rule the aim indicator and the
## cast flash keep, and it is what the reference map does - it scales its explosion model to
## the blast radius on the frame it plays. See docs/warlock-reference.md section 8a.
func blast(at: Vector3, tint: Color, radius: float) -> void:
	var particles := _emitters[_next]
	_next = (_next + 1) % _emitters.size()
	particles.global_position = at
	particles.color = tint
	# Metres per second that puts a spark at the rim as its life runs out. The slower half
	# fills the middle, so the shape reads as a disc rather than as a hollow shell.
	var rim := maxf(radius, 0.3) / maxf(lifetime, 0.01)
	particles.initial_velocity_min = rim * 0.5
	particles.initial_velocity_max = rim * 1.05
	particles.spread = BLAST_SPREAD
	particles.restart()


## How many bursts are still on screen. For the harness.
func active_count() -> int:
	var n := 0
	for particles in _emitters:
		if particles.emitting:
			n += 1
	return n

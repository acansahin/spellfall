class_name Projectile
extends Area3D

## A skillshot in flight. One generic scene; what it is comes from the Ability it carries.
##
## An Area3D moved by hand rather than a RigidBody3D or CharacterBody3D, for the same reason
## the wizard is hand-integrated (see player.gd): this is trivially cheap to re-simulate, and
## a projectile has no business being pushed around by a physics solver. That is also how the
## reference map does it - every one of its spells is a dummy unit moved by the same tick that
## moves the wizards, and its object editor carries a missile art for three abilities out of
## fifty. See docs/warlock-reference.md section 9.
##
## The model is a VELOCITY and an ACCELERATION, integrated once a tick, and it stops when it
## touches something. It used to be a direction and a speed, which is the same thing for
## anything flying straight and cannot express a spell that curves at all.
##
## It does NOT decide what a hit means. It emits `hit` and lets the combat layer apply
## instability and knockback (Session 4). A projectile that knew about knockback would be a
## second place the formula lived.
##
## Four spells bend the straight line, and all four are FIELDS on the Ability rather than
## subclasses: a seeker turns toward whoever is nearest, a boomerang loops out and home under
## a constant acceleration, a meteor is born overhead and falls, and a piercing spell keeps
## going through what it caught. Each is a handful of lines here because the flight is still
## "move, then look at what you touched" - the control flow the class doc describes never
## changed. A spell that genuinely needed different control flow would earn its own runtime;
## none of these did.

## Emitted when this touches a valid target. `direction` is the travel direction, which is
## what a knockback system wants - you get thrown the way the spell was going, not away from
## wherever its centre happened to be.
##
## `shooter` rides along because one spell's whole payload is about the caster: a warp bolt
## trades the two of them over. Passing it here rather than having the level remember who fired
## last is the difference between a rule and a guess - two bolts can be in the air at once.
signal hit(body: Node3D, direction: Vector3, ability: Ability, shooter: Node3D)

## Emitted when this is done, for any reason, BEFORE it is reclaimed - so the combat layer
## still has the position it died at.
##
## Two spells are about that spot rather than about what was touched: a blast damages
## everything standing around it, and a splitter breaks into fragments from it. Both must fire
## when nothing was hit at all, which is why this is "done" and not "hit" - a meteor that
## lands on empty ground has still landed.
signal spent(at: Vector3, direction: Vector3, ability: Ability, shooter: Node3D)

## Emitted when this is done, for any reason. The pool listens to reclaim it.
signal finished(projectile: Projectile)

## Where parked projectiles wait. Far enough below the arena that a pooled projectile can
## never overlap anything while it is off duty.
const PARKED_POSITION := Vector3(0.0, -1000.0, 0.0)

## Which leg of a returning spell's flight is running. A spell that does not curve is always
## on the first one and never leaves it.
enum Leg {
	## Out: forward speed falling to zero at `curve_reach`, bowing to one side.
	OUT,
	## Home: the same parabola run backwards with the lateral term mirrored, so it comes down
	## the other side.
	BACK,
	## Steering at the caster, wherever they have walked to. Also where a hit sends it.
	HOME,
}

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape

var _ability: Ability = null
## Metres per second, and the whole of the horizontal flight. The vertical is `_fall` below,
## kept apart from this for the reason written there.
var _velocity := Vector3.ZERO
## Metres per second squared, constant for the duration of a leg. Zero for everything that
## flies straight, which is every spell but one.
var _accel := Vector3.ZERO
## The acceleration the return leg switches to: the same term along the throw, the lateral one
## mirrored. Computed at launch rather than at the turn, so the turn is one assignment and
## cannot re-read a direction that has since changed.
var _accel_back := Vector3.ZERO
## Which leg is running. See `Leg`.
var _leg := Leg.OUT
## Age at which the current leg ends.
var _leg_ends := INF
## How long the outward leg lasts, in seconds. The return leg is this less `TURN_TRIM`.
var _out_seconds := 0.0
## Metres per second downward. A SEPARATE term from `_velocity` rather than its y component,
## which is how the map states it too - a falling spell's descent has nothing to do with its
## drag, its homing or the pull of a gravity well, and folding it into the velocity vector
## would hand it to all three.
var _fall := 0.0
## The height this was launched from, and the height a falling spell lands at.
var _ground_y := 0.0
## The travel direction, flattened. Kept rather than derived at each reader because it is what
## `hit` carries and what the drawing is aimed along, and both want the same answer.
var _direction := Vector3.ZERO
var _age := 0.0
## Guards against a second hit, and against ticking while parked in the pool. A pooled node
## is still in the tree, so without this it would keep flying after being reclaimed.
var _active := false
## The caster is ignored, otherwise a spell detonates inside the wizard that cast it - both
## are on the players layer.
var _shooter: Node3D = null
var _material: StandardMaterial3D = null

## Fighters already caught on this leg of the flight. Only a piercing spell ever has more than
## one entry, and a returning spell empties it when it turns - so a boomerang is allowed to
## catch the same wizard going out and coming back, and is not allowed to catch them twice on
## the way out because it happened to overlap for two ticks.
var _caught: Array[Node3D] = []

## How much the shared mesh is scaled up, in metres per authored unit - which is just the
## ability's `projectile_radius`. Kept rather than read back off the node: `_aim_mesh` writes a
## basis that carries both the rotation and the scale, and recovering the scale from a basis it
## wrote last frame is a round trip that can only lose precision.
var _draw_scale := 1.0

## Radians a spinning shape has turned through. Only BLADE reads it - a thrown bar that did not
## spin would read as a stick sliding through the air sideways.
var _spin := 0.0

## The ring drawn on the ground under a falling spell. Built here rather than in the scene so
## that a projectile which never leaves the ground plane costs one hidden node and nothing else.
var _shadow: MeshInstance3D = null
var _shadow_material: StandardMaterial3D = null

## The specks left behind in flight. See `_build_trail`.
var _trail: CPUParticles3D = null

const FlightVisual = preload("res://vfx/spell_flight_visual.gd")
var _flight_visual: FlightVisual

## Mask value for the "players" physics layer, matching ConeCast and KillZone. Homing looks for
## bodies on it and for nothing else - a seeker that locked onto a rock would be a seeker that
## never reached anybody.
const PLAYERS_MASK := 2

## Ceiling on a homing query. Nobody is expected to have eight fighters inside a seeker's
## look-ahead; this is a bound, not a budget.
const MAX_SEEK := 8

## Metres from the caster at which a returning spell is considered caught. The map's own
## number: 75 units. Roughly a body's width, so it lands in the hand rather than flying through
## and expiring behind them.
const CATCH_DISTANCE := 0.59

## Metres per second a returning spell wants while it is steering home, and the metres per
## second squared it may correct by. Both the map's: 1000 u/s wanted, 30 u per tick of
## correction, which is 1000 u/s².
##
## A correction RATE and not an assignment, so the spell arcs into the caster's hand rather
## than snapping onto the line to it - and so a wizard who sprints sideways makes their own
## boomerang take the long way home.
const HOME_SPEED := 7.81
const HOME_ACCEL := 7.81

## Seconds trimmed off the return leg, so the parabola stops just short and the homing leg
## covers the last stretch. The map trims five of its own ticks; this is those five ticks.
##
## It matters more than it looks: the parabola returns the spell to where the caster STOOD
## when they threw it, and everything between there and where they are now is walking the
## homing leg has to make up.
const TURN_TRIM := 0.15

## Metres of daylight left between a recoiling spell and the body it just bounced off.
##
## Sized past a fighter's own collision radius (0.5), because the point is to leave contact
## entirely: Godot reports `body_entered` on the frame contact BEGINS, so a spell that turned
## around while still overlapping would never be reported again and would silently pass back
## through.
const RECOIL_CLEARANCE := 0.75

## Radians per second a BLADE turns about the vertical. Fast enough to read as a spin from the
## camera's height, slow enough that it does not strobe against a 60Hz tick.
const SPIN_RATE := 14.0

## How wide the ring under a falling spell is drawn, as a fraction of its radius, and how
## solid it is at the top of the drop and at the bottom.
##
## It fades IN as the spell comes down. The map gets this for free - Warcraft III draws a real
## shadow under a flying unit - and it is not decoration here either: a spell that comes from
## outside the frame is the one case where the thing about to hit you is not on screen, and
## the ring is the only warning there is. `GAME_DESIGN.md`'s rule is that readability beats
## spectacle, and this is the readability half of a falling rock.
const SHADOW_THICKNESS := 0.16
const SHADOW_ALPHA_FAR := 0.10
const SHADOW_ALPHA_NEAR := 0.45

## The trail: how many specks are alive behind a spell at once, how long each lasts, and how
## big it is as a fraction of the spell's own radius.
##
## Cheap on purpose. Ten CPU particles per projectile at eight pooled projectiles is eighty at
## the very worst, which is a fifth of what one impact burst already costs, and the target is
## a mid-range Android. What it buys is the thing a still frame cannot show: which way a spell
## came from, and how fast - and for the boomerang, that its path is a curve at all.
const TRAIL_COUNT := 10
const TRAIL_LIFE := 0.26
const TRAIL_SIZE := 0.55

## One mesh per shape, built on first use and shared by every projectile that ever flies with
## it. Authored at RADIUS 1 and scaled by the node, so `projectile_radius` is the only number
## that decides how big a spell looks - the same contract `SpellGlyph`'s unit box gives the
## icons.
static var _bolt_meshes: Dictionary = {}

## The shadow ring, authored at radius 1 like everything else and scaled by the node.
static var _shadow_mesh: ArrayMesh = null

## The speck the trail is made of, authored at radius 1 and sized per spell by the emitter's
## own scale, so one mesh serves a fireball and a mote alike.
static var _trail_mesh: SphereMesh = null

## Which way the next curving spell bows. Flipped on every launch, so two boomerangs in a row
## loop opposite ways and the same spell does not look identical twice.
##
## The map keeps this PER CASTER. One shared toggle is a departure and a deliberate one: with
## a sixteen-second cooldown, the case where it reads differently - two casters alternating
## inside one cooldown - is a case where the two loops are at opposite ends of the arena.
static var _curve_hand := 1.0

# Reused, exactly as ConeCast reuses its own. Building a shape per tick per seeker is an
# allocation in the middle of a fight, which is the stutter the pool exists to avoid.
static var _seek_probe := SphereShape3D.new()
static var _seek_query := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	# These OVERRIDE whatever projectile.tscn carries. The scene sets the same values and the
	# script wins, so a mask edited only in the scene does nothing at all - which cost a run
	# to find, because the file said 3 and the flying projectile said 2. If these ever move,
	# move them here.
	collision_layer = 4   # projectiles
	# 3 = players + world. World is the layer cover stands on, so a Fireball dies against a
	# rock instead of flying through it. `_apply_hit` then finds the body is not a Player and
	# does nothing, which is exactly what hitting a rock should do. The arena platform is on
	# that layer too and is never touched: its top is at y=0 and a projectile flies at chest
	# height - including a falling one, which is born above the caster and comes to rest at
	# the height it was thrown from.
	collision_mask = 3    # players + world
	monitoring = true
	# monitorable MUST stay true. Its documented job is "other monitoring areas can detect
	# this area", which sounds free to switch off for a projectile that nothing else looks
	# for - but in Godot 4.7 setting it false also silently kills body_entered and
	# get_overlapping_bodies() on this area. Isolated with a minimal repro: two identical
	# areas flown through the same StaticBody3D, and only the monitorable one detected it.
	monitorable = true
	# The collision shape comes from the PackedScene and is SHARED between every instance it
	# spawns, so resizing one would resize them all. Two abilities with different radii would
	# silently fight over it. Give each projectile its own copy.
	#
	# The MESH deliberately does not get the same treatment any more. It is never mutated now:
	# `launch` picks one of five shared shapes and sizes it with the node's own scale, so a
	# hundred fireballs are one SphereMesh. Duplicating it per projectile would be a hundred
	# meshes for no difference on screen.
	_shape.shape = _shape.shape.duplicate()
	# Likewise one material per instance, so tinting a Fireball cannot recolour a Scourge.
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	# Was 2.2, which blew every tint toward white. That was survivable while all five spells
	# were identical spheres and glow was the only thing making them visible against the grass;
	# with five SHAPES carrying the identity, a lime bar and a gold spike reading as the same
	# white is a straight loss. Low enough that the albedo shows through, high enough that a
	# spell still lifts off the field.
	_material.emission_energy_multiplier = 1.15
	_mesh.material_override = _material
	_build_shadow()
	_build_trail()
	_flight_visual = FlightVisual.new()
	add_child(_flight_visual)
	body_entered.connect(_on_body_entered)
	_park()


## The ground ring, made once per projectile and hidden until a spell that falls needs it.
func _build_shadow() -> void:
	if _shadow_mesh == null:
		_shadow_mesh = GroundShapes.ring(1.0, SHADOW_THICKNESS)
	_shadow = MeshInstance3D.new()
	_shadow.mesh = _shadow_mesh
	# Sparks taught this one: a flat translucent thing that casts a shadow puts a dark smear
	# on the arena rather than light. See ARCHITECTURE.md.
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shadow_material = GroundShapes.flat_material(Color(1, 1, 1), SHADOW_ALPHA_FAR)
	_shadow.material_override = _shadow_material
	_shadow.visible = false
	add_child(_shadow)


## The specks a spell leaves behind it.
##
## `local_coords = false` is the whole of it: the particles are emitted into WORLD space and
## stay where they were dropped, so the trail marks the path rather than riding along with the
## thing that made it. With it left true the specks travel with the projectile and the effect
## is a slightly fatter projectile.
##
## No velocity, no gravity, no spread. A trail that drifted would be smoke, and smoke behind a
## fireball is a second moving thing to read on a board the size of a phone screen.
func _build_trail() -> void:
	if _trail_mesh == null:
		_trail_mesh = SphereMesh.new()
		_trail_mesh.radius = 1.0
		_trail_mesh.height = 2.0
		_trail_mesh.radial_segments = 6
		_trail_mesh.rings = 3
		var mat := StandardMaterial3D.new()
		# Unshaded and reading the particle's own colour, for the reason ImpactBurst gives:
		# these are light, and light that needs the key lamp is light you lose on half the
		# board.
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		_trail_mesh.material = mat
	_trail = CPUParticles3D.new()
	_trail.emitting = false
	_trail.local_coords = false
	_trail.amount = TRAIL_COUNT
	_trail.lifetime = TRAIL_LIFE
	_trail.mesh = _trail_mesh
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trail.direction = Vector3.ZERO
	_trail.spread = 0.0
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.0
	_trail.gravity = Vector3.ZERO
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_trail.scale_amount_curve = curve
	add_child(_trail)


func _physics_process(delta: float) -> void:
	if not _active:
		return
	# Steering happens BEFORE the step, so a spell that turns this tick also moves along the
	# direction it turned to. Moving first would leave every seeker one tick behind its own aim,
	# which reads as a spell that consistently trails its target.
	_steer(delta)
	_pull(delta)
	_velocity += _accel * delta
	global_position += _velocity * delta
	# The vertical is its own term and is applied after the horizontal, never through it. A
	# falling spell descends at a constant rate to the height it was thrown from, arriving
	# exactly as its lifetime runs out - which is what makes its flight TIME the thing a
	# player can count rather than its speed.
	if _fall > 0.0:
		global_position.y = maxf(global_position.y - _fall * delta, _ground_y)
	# Framerate-independent decay: `drag` is stated per SECOND, so a 30fps phone and a 144fps
	# desktop agree on where the spell lands. Multiplying by the raw factor once per tick would
	# make the same spell travel twice as far on a machine running at half the rate.
	if _ability.projectile_drag < 1.0:
		_velocity *= pow(_ability.projectile_drag, delta)
	_age += delta
	# After the step, so the drawing points where the spell is now going rather than where it
	# was going. A seeker turns every tick and a boomerang turns continuously; both would
	# otherwise fly one frame's worth of sideways.
	_sync_heading()
	_spin += delta * SPIN_RATE
	_aim_mesh()
	_drop_shadow()
	_flight_visual.update_flight(_age, _velocity - Vector3.UP * _fall)
	if _leg == Leg.HOME and _reached_caster():
		_finish()
		return
	if _age >= _ability.lifetime:
		_finish()


## Re-reads the travel direction off the velocity.
##
## Flattened, because `hit` carries this as the push direction and knockback is a thing that
## happens in the plane: a meteor that threw people downward would push them through the floor.
func _sync_heading() -> void:
	var flat := Vector3(_velocity.x, 0.0, _velocity.z)
	if flat.length_squared() > 0.000001:
		_direction = flat.normalized()


## Bends the flight: run the boomerang's legs, or lean toward whoever is nearest.
##
## The two are exclusive on purpose. A spell that both homed and looped would chase its target
## on the way back as well, and there is no reading of "it comes back to you" under which it
## should first go somewhere else.
func _steer(delta: float) -> void:
	if _ability.curve_speed > 0.0:
		_curve(delta)
		return
	if _ability.homing_turn > 0.0:
		_home(delta)


## Advances a boomerang through its three legs.
##
## Nothing here computes a path. The path is entirely in the constant `_accel` set at launch,
## which is the whole trick the reference map is worth reading for: a deceleration that brings
## the forward speed to zero after exactly `curve_reach` metres, and a lateral term in fixed
## ratio to it that bows the flight out and brings it back to the line at the same instant. The
## turn is one assignment, not a decision.
func _curve(delta: float) -> void:
	if _leg == Leg.HOME:
		_steer_home(delta)
		return
	if _age < _leg_ends:
		return
	if _leg == Leg.OUT:
		_leg = Leg.BACK
		# A fresh leg, so whoever was caught on the way out may be caught on the way home.
		_caught.clear()
		# The lateral term mirrored and the forward one unchanged, so the spell comes down the
		# OTHER side. Out and back cross at two places and only two: here, and the caster.
		_accel = _accel_back
		_leg_ends += maxf(_out_seconds - TURN_TRIM, 0.05)
		return
	_caught.clear()
	_begin_homing()


## Hands the flight over to the steering leg: no more acceleration, just a pull toward whoever
## threw it. Also where a hit sends it - see `_recoil_from`.
func _begin_homing() -> void:
	_leg = Leg.HOME
	_accel = Vector3.ZERO


## Steers the spell at its caster, wherever they have walked to.
##
## A correction toward the velocity it WANTS, capped per tick, rather than an assignment of
## that velocity - which is what makes the last stretch an arc into the hand instead of a
## right-angle snap onto the line home.
func _steer_home(delta: float) -> void:
	if not is_instance_valid(_shooter):
		return
	var home := _shooter.global_position - global_position
	home.y = 0.0
	if home.length_squared() < 0.0001:
		return
	var correction := home.normalized() * HOME_SPEED - _velocity
	var step := HOME_ACCEL * delta
	if correction.length() > step:
		correction = correction.normalized() * step
	_velocity += correction


## Leans the flight toward the nearest fighter, at most `homing_turn` degrees this tick.
##
## Capped by a turn RATE, so the spell can be lost by moving across it. The cap is what makes
## this dodgeable, and removing it turns the seeker into a guaranteed hit with a delay.
##
## The velocity is ROTATED rather than rebuilt, which keeps the spell's speed - and therefore
## its drag history - out of the steering entirely.
func _home(delta: float) -> void:
	var prey := _nearest_target()
	if prey == null:
		return
	var wanted := prey.global_position - global_position
	wanted.y = 0.0
	if wanted.length_squared() < 0.0001:
		return
	var here := Vector2(_velocity.x, _velocity.z)
	if here.length_squared() < 0.0001:
		return
	var there := Vector2(wanted.x, wanted.z).normalized()
	var turned := here.rotated(
		clampf(here.angle_to(there), -deg_to_rad(_ability.homing_turn) * delta,
			deg_to_rad(_ability.homing_turn) * delta))
	_velocity = Vector3(turned.x, 0.0, turned.y)


## The closest fighter inside the look-ahead, or null. The caster is never it.
func _nearest_target() -> Node3D:
	var space := get_world_3d().direct_space_state
	if space == null:
		return null
	_seek_probe.radius = maxf(_ability.homing_radius, 0.01)
	_seek_query.shape = _seek_probe
	_seek_query.transform = Transform3D(Basis.IDENTITY, global_position)
	_seek_query.collision_mask = PLAYERS_MASK
	_seek_query.collide_with_bodies = true
	_seek_query.collide_with_areas = false
	var best: Node3D = null
	var best_gap := INF
	for found in space.intersect_shape(_seek_query, MAX_SEEK):
		var body := found.get("collider") as Node3D
		if body == null or body == _shooter:
			continue
		# A seeker that locked onto a teammate would curve away from the fight and then fly
		# straight through them, which looks exactly like a broken spell.
		var thrower := _shooter as Player
		if thrower != null and thrower.is_ally_of(body):
			continue
		var gap := global_position.distance_squared_to(body.global_position)
		if gap < best_gap:
			best_gap = gap
			best = body
	return best


## Points the drawing along the flight, and spins it if the shape wants spinning.
##
## Only the MESH is turned, never the Area3D. Rotating the node would rotate its collision
## shape with it - and the hitbox is a sphere on purpose, so turning it would be work that
## changes nothing except the chance of a subtle bug the day somebody swaps the shape. It
## would also take the ground shadow with it, which is a flat thing that must stay flat.
func _aim_mesh() -> void:
	if _ability == null:
		return
	# A ball has no direction, and a hoop is left lying FLAT on purpose. Stood across the flight
	# path - which is what "aim it" would do - the camera looks down its edge and a ring becomes
	# a vertical sliver indistinguishable from a small capsule. Flat, it reads as a ring from
	# the only angle this game is ever seen from.
	# A lump and a speck have no direction either, for the same reason a ball does not: aiming
	# a shape whose silhouette is the same from every side is work that changes nothing.
	if _ability.bolt in [Ability.Bolt.ORB, Ability.Bolt.RING, Ability.Bolt.STONE,
			Ability.Bolt.MOTE]:
		return
	if _ability.bolt == Ability.Bolt.BLADE:
		# Flat and spinning about the vertical, the way a thrown bar actually flies. It does
		# not point anywhere, so the direction of travel is not read at all.
		var blade_scale := _draw_scale * (1.55 if _ability.id == &"loopshot" else 1.0)
		_mesh.transform.basis = Basis(Vector3.UP, _spin).scaled(Vector3.ONE * blade_scale)
		return
	if _direction.length_squared() < 0.0001:
		return
	# Every pointed shape is authored along +Y, so aligning +Y with the travel aims all of them
	# with one line. The direction is always horizontal here, so the degenerate case that would
	# make this quaternion ambiguous - travelling straight down - cannot arise.
	_mesh.transform.basis = Basis(Quaternion(Vector3.UP, _direction.normalized())) \
		.scaled(Vector3.ONE * _draw_scale)


## Keeps the ring under a falling spell on the ground, and brings it up as the spell comes down.
##
## Placed in LOCAL space, which is only legal because `_aim_mesh` above turns the mesh and
## never the node: this projectile's basis is the identity, so straight down is -Y here too.
func _drop_shadow() -> void:
	if _fall <= 0.0:
		return
	var height := maxf(global_position.y - _ground_y, 0.0)
	_shadow.position = Vector3(0.0, -height, 0.0)
	var closing := 1.0 - clampf(height / maxf(_ability.drop_height, 0.01), 0.0, 1.0)
	_shadow_material.albedo_color.a = lerpf(SHADOW_ALPHA_FAR, SHADOW_ALPHA_NEAR, closing)


## The shape for `bolt`, built once and then handed out.
##
## Authored under one rule: the CROSS-SECTION matches the hitbox and only the LENGTH along the
## flight is free. So every shape is about 1 unit across - which becomes `projectile_radius`
## once scaled - and stretches only in the direction it is travelling.
##
## That rule is what keeps the drawing honest. A shape drawn wider than the sphere that catches
## people produces "that missed me and hit anyway"; drawn narrower, it produces near misses that
## land. Stretching along the flight is different in kind: nobody judges the exact extent of a
## thing crossing the screen at 30 m/s, and the length reads as SPEED rather than as reach.
static func _bolt_mesh(bolt: Ability.Bolt) -> Mesh:
	if _bolt_meshes.has(bolt):
		return _bolt_meshes[bolt]
	var mesh: Mesh = null
	match bolt:
		Ability.Bolt.SHARD:
			var spike := CapsuleMesh.new()
			spike.radius = 1.0
			spike.height = 6.0
			spike.radial_segments = 8
			spike.rings = 2
			mesh = spike
		Ability.Bolt.DART:
			# A cone. CylinderMesh's top is +Y, so a zero top radius puts the point forward.
			var cone := CylinderMesh.new()
			cone.top_radius = 0.02
			cone.bottom_radius = 1.0
			cone.height = 2.6
			cone.radial_segments = 10
			mesh = cone
		Ability.Bolt.BLADE:
			var bar := BoxMesh.new()
			bar.size = Vector3(3.4, 0.5, 2.0)
			mesh = bar
		Ability.Bolt.RING:
			var hoop := TorusMesh.new()
			hoop.inner_radius = 0.35
			hoop.outer_radius = 1.0
			hoop.rings = 12
			hoop.ring_segments = 8
			mesh = hoop
		Ability.Bolt.STONE:
			# A ball with almost no subdivision, so its facets read as a lump rather than as a
			# low-quality sphere. Four segments is the fewest that still has a silhouette.
			var lump := SphereMesh.new()
			lump.radius = 1.0
			lump.height = 1.7
			lump.radial_segments = 5
			lump.rings = 3
			mesh = lump
		Ability.Bolt.MOTE:
			# Small and round. It is the only shape whose job is to look like there are several
			# of it, so it must not have an orientation the eye can read.
			var speck := SphereMesh.new()
			speck.radius = 0.62
			speck.height = 1.24
			speck.radial_segments = 8
			speck.rings = 4
			mesh = speck
		Ability.Bolt.FUNNEL:
			# DART's cone the other way up, so the two read as opposites rather than as the
			# same shape at two sizes: this one arrives mouth first.
			var mouth := CylinderMesh.new()
			mouth.top_radius = 1.0
			mouth.bottom_radius = 0.04
			mouth.height = 2.2
			mouth.radial_segments = 10
			mesh = mouth
		Ability.Bolt.PRISM:
			# A four-sided sliver along the flight. A cylinder with four segments, not a box:
			# the box is already BLADE's, and two rectangles in the air are not two shapes.
			var sliver := CylinderMesh.new()
			sliver.top_radius = 0.45
			sliver.bottom_radius = 0.45
			sliver.height = 3.0
			sliver.radial_segments = 4
			mesh = sliver
		_:
			var ball := SphereMesh.new()
			ball.radius = 1.0
			ball.height = 2.0
			ball.radial_segments = 12
			ball.rings = 6
			mesh = ball
	_bolt_meshes[bolt] = mesh
	return mesh


func _reached_caster() -> bool:
	if not is_instance_valid(_shooter):
		return false
	var gap := _shooter.global_position - global_position
	gap.y = 0.0
	return gap.length() <= CATCH_DISTANCE


## Sends this projectile on its way. `direction` is normalised here, so callers may pass a
## rough aim without worrying about its length.
func launch(ability: Ability, from: Vector3, direction: Vector3, shooter: Node3D) -> void:
	_ability = ability
	_shooter = shooter
	_direction = direction.normalized()
	_velocity = _direction * ability.projectile_speed
	_accel = Vector3.ZERO
	_accel_back = Vector3.ZERO
	_leg = Leg.OUT
	_leg_ends = INF
	_out_seconds = 0.0
	_age = 0.0
	_caught.clear()
	global_position = from
	_ground_y = from.y
	_fall = 0.0
	_shadow.visible = false
	if ability.curve_speed > 0.0:
		_arm_curve(ability)
	if ability.drop_height > 0.0 and ability.lifetime > 0.0:
		_arm_drop(ability)
	var radius := ability.projectile_radius
	(_shape.shape as SphereShape3D).radius = radius
	_mesh.mesh = _bolt_mesh(ability.bolt)
	_mesh.material_override = _material
	# Every shape is authored at radius 1 and sized here, the same trick `SpellGlyph` uses for
	# the icons: one drawing, any size, and a retuned `projectile_radius` cannot leave the mesh
	# behind at the old one.
	_draw_scale = radius
	# The whole basis, not `scale`. Setting the scale alone KEEPS the rotation, so a pooled
	# projectile that was last a shard would come back as a hoop still lying at the shard's
	# angle - and only for spells that do not re-aim themselves, which is the kind of bug that
	# shows up in one screenshot out of ten.
	_mesh.transform.basis = Basis().scaled(Vector3.ONE * radius)
	_spin = 0.0
	_aim_mesh()
	_material.albedo_color = ability.colour
	_material.emission = ability.colour
	_trail.color = ability.colour
	# Sized off the spell, not off the mesh, so a mote's trail is a mote's and a meteor's is a
	# meteor's without a second mesh existing.
	_trail.scale_amount_min = radius * TRAIL_SIZE * 0.7
	_trail.scale_amount_max = radius * TRAIL_SIZE
	_trail.restart()
	_trail.emitting = true
	if _flight_visual.configure(ability, _mesh):
		_trail.emitting = false
	_flight_visual.update_flight(0.0, _velocity - Vector3.UP * _fall)
	_active = true
	visible = true


## Solves the boomerang's parabola, once, at launch.
##
## The whole flight is two numbers off the Ability and four lines of algebra, taken from the
## reference map rather than invented:
##
##     along  = -speed² / (2 * reach)      forward speed reaches zero after `reach` metres
##     across = -speed * curve_speed / reach   in fixed ratio, so the bow closes at the same instant
##     out    = 2 * reach / speed          which is how long that takes
##
## Both accelerations are constant for a leg, so nothing per-tick has to know what shape the
## path is. See docs/warlock-reference.md section 9b for the map's own version.
func _arm_curve(ability: Ability) -> void:
	var forward := _direction
	var reach := maxf(ability.curve_reach, 0.5)
	var speed := maxf(ability.projectile_speed, 0.1)
	# Alternating, so the same spell cast twice does not draw the same loop twice.
	var side := Vector3(-forward.z, 0.0, forward.x) * _curve_hand
	_curve_hand = -_curve_hand
	var along := -speed * speed / (2.0 * reach)
	var across := -speed * ability.curve_speed / reach
	_velocity = forward * speed + side * ability.curve_speed
	_accel = forward * along + side * across
	_accel_back = forward * along - side * across
	_out_seconds = 2.0 * reach / speed
	_leg_ends = _out_seconds


## Lifts a falling spell to its starting height and works out how fast it has to come down.
##
## The rate is DERIVED from the height and the lifetime rather than stated, so the rock cannot
## land early or late when either is retuned. The map states both and they agree; deriving is
## what keeps them agreeing here.
func _arm_drop(ability: Ability) -> void:
	global_position.y += ability.drop_height
	_fall = ability.drop_height / ability.lifetime
	# The ring is the size of what the spell will DO, not the size of the rock: a blast if it
	# has one, otherwise its own width. Same rule the aim indicator and the cast flash keep -
	# a shape drawn from the ability's own numbers cannot promise something else.
	var mark := maxf(ability.area, ability.projectile_radius * 2.0)
	_shadow.transform.basis = Basis().scaled(Vector3(mark, 1.0, mark))
	var warning_colour := Color(1.0, 0.28, 0.035) if ability.id == &"meteor" else ability.colour
	_shadow_material.albedo_color = Color(
		warning_colour.r, warning_colour.g, warning_colour.b, SHADOW_ALPHA_FAR)
	_shadow.visible = true


## Anything solid stops it; only a fighter takes a hit from it. See the mask in `_ready`.
##
## Two spells are exceptions and they are different in kind. A PIERCING spell carries on
## through a fighter it caught. A RETURNING one does the opposite - it is knocked clear and
## sent straight home, which is the map's own behaviour and the only thing the mirrored return
## path leaves room for: out and back cross at just two points, so "catch them twice" was a
## promise a straight out-and-back could keep and a real loop cannot.
##
## Cover still stops both dead: a rock that swallows a fireball and lets a boomerang through
## would teach the player a rule and then break it, which is the same argument ConeCast makes
## about line of sight.
func _on_body_entered(body: Node3D) -> void:
	if not _active or body == _shooter:
		return
	# An ally is not merely unhurt, they are not IN THE WAY. Stopping here and doing no damage
	# would turn every teammate into a moving wall, and a teammate you have to walk around is
	# worse than no teammate at all.
	var shooter := _shooter as Player
	if shooter != null and shooter.is_ally_of(body):
		return
	var fighter := body as Player
	if fighter != null and _caught.has(body):
		return
	hit.emit(body, _direction, _ability, _shooter)
	if _ability.curve_speed > 0.0 and _leg != Leg.HOME:
		_recoil_from(body)
		return
	if _ability.pierces and fighter != null:
		_caught.append(body)
		return
	_finish()


## Bounces a returning spell off what it hit and points it home.
##
## The reposition is not cosmetic. Godot reports `body_entered` on the frame contact BEGINS,
## so a spell left overlapping the body it just hit would never be reported against it again -
## and would drift back out through it in silence. Putting it clear of the body settles that,
## and `_caught` keeps it from re-reporting the same victim if the arc home brushes them.
func _recoil_from(body: Node3D) -> void:
	var away := global_position - body.global_position
	away.y = 0.0
	if away.length_squared() < 0.0001:
		away = -_direction
	away = away.normalized()
	global_position = Vector3(body.global_position.x, global_position.y,
		body.global_position.z) + away * (_ability.projectile_radius + RECOIL_CLEARANCE)
	_velocity = away * HOME_SPEED
	_caught.append(body)
	_begin_homing()


func _finish() -> void:
	if not _active:
		return
	_active = false
	# `spent` goes out BEFORE `_park()` moves the node a thousand metres under the arena.
	# Emitting it after would put every blast in the same spot far below the world, where it
	# would hit nothing and read as a field that does not work.
	spent.emit(global_position, _direction, _ability, _shooter)
	_park()
	finished.emit(self)


## Drags nearby fighters toward this projectile. Gravity, and nothing else.
##
## An ACCELERATION added to the knockback channel, not a position set: caught in one, you can
## still walk out if you start early, which is the difference between a field and a stun. The
## knockback channel rather than the steering one because that is the half a fighter cannot
## cancel by letting go.
##
## It reuses the seeker's shape query rather than a group, because a group would be a second
## register of who is fighting and this file already has a way to ask.
func _pull(delta: float) -> void:
	if _ability.pull_force <= 0.0:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	_seek_probe.radius = maxf(_ability.pull_radius, 0.01)
	_seek_query.shape = _seek_probe
	_seek_query.transform = Transform3D(Basis.IDENTITY, global_position)
	_seek_query.collision_mask = PLAYERS_MASK
	_seek_query.collide_with_bodies = true
	_seek_query.collide_with_areas = false
	for found in space.intersect_shape(_seek_query, MAX_SEEK):
		var fighter := found.get("collider") as Player
		if fighter == null or not is_instance_valid(fighter):
			continue
		var gap := global_position - fighter.global_position
		gap.y = 0.0
		var distance := gap.length()
		# Inside the eye it stops pulling. Without the floor the normalised direction flips
		# sign every tick as the field passes over somebody, and they judder in place.
		if distance < 0.3:
			continue
		fighter.apply_pull(gap.normalized() * _ability.pull_force * delta)


## Makes the node inert without freeing it, so the pool can hand it out again.
##
## Note what this does NOT do: toggle `monitoring`. A pooled node that flips monitoring off
## and on through set_deferred has more states than it needs, and `_active` already makes a
## parked projectile inert. Monitoring is switched on once in _ready() and left alone;
## parking the node far below the world keeps it from touching anything meanwhile.
func _park() -> void:
	visible = false
	if _flight_visual != null:
		_flight_visual.stop()
	_velocity = Vector3.ZERO
	_accel = Vector3.ZERO
	_fall = 0.0
	_direction = Vector3.ZERO
	if _shadow != null:
		_shadow.visible = false
	# The trail goes out WITH the projectile, not after it.
	#
	# Measured, not assumed: a fireball photographed 0.1s after it expired has no tail at all,
	# though a speck lives 0.26s. The emitter is a child of this node and `visible = false`
	# above hides every descendant with it, so parking takes the specks already dropped as
	# well as the ones still to come.
	#
	# Left that way on purpose rather than worked around. Freeing the tail from the projectile
	# means a second pool of world-space emitters owned by the level, and the moment it would
	# buy is the one moment already covered - an impact burst goes off in the same place on the
	# same frame. The reference map does the same thing for the same reason: `KillUnit` takes
	# the missile's model and its attached effect together.
	if _trail != null:
		_trail.emitting = false
	global_position = PARKED_POSITION


## True while in flight. The pool uses this to decide what is available.
func is_active() -> bool:
	return _active


## The ability currently in flight, or null. Handy for tests and debug readouts.
## The way it is travelling, for the harness: an aim test that only checks the cast happened
## has not checked that the spell went where the thumb pointed.
func direction() -> Vector3:
	return _direction


func ability() -> Ability:
	return _ability

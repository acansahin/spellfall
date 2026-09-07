class_name Projectile
extends Area3D

## A skillshot in flight. One generic scene; what it is comes from the Ability it carries.
##
## An Area3D moved by hand rather than a RigidBody3D or CharacterBody3D, for the same reason
## the wizard is hand-integrated (see player.gd): this is trivially cheap to re-simulate, and
## a projectile has no business being pushed around by a physics solver. It travels in a
## straight line at a constant speed and stops when it touches something. That is the whole
## model, and it is the model a server can re-run cheaply.
##
## It does NOT decide what a hit means. It emits `hit` and lets the combat layer apply
## instability and knockback (Session 4). A projectile that knew about knockback would be a
## second place the formula lived.
##
## Three spells bend the straight line, and all three are FIELDS on the Ability rather than
## subclasses: a seeker turns toward whoever is nearest, a boomerang turns around and comes
## home, and a piercing spell keeps going through what it caught. Each is a handful of lines
## here because the flight is still "move, then look at what you touched" - the control flow
## the class doc describes never changed. A spell that genuinely needed different control flow
## would earn its own runtime; none of these did.

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

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape

var _ability: Ability = null
var _direction := Vector3.ZERO
## Current speed in m/s. Held rather than read off the ability because it decays in flight.
var _speed := 0.0
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

## True once a returning spell has turned for home. Held rather than re-derived from `_age`,
## because the turn also re-aims and re-speeds the spell and must happen exactly once.
var _returned := false

## Mask value for the "players" physics layer, matching ConeCast and KillZone. Homing looks for
## bodies on it and for nothing else - a seeker that locked onto a rock would be a seeker that
## never reached anybody.
const PLAYERS_MASK := 2

## Ceiling on a homing query. Nobody is expected to have eight fighters inside a seeker's
## look-ahead; this is a bound, not a budget.
const MAX_SEEK := 8

## Metres from the caster at which a returning spell is considered caught. Roughly a body's
## width, so it lands in the hand rather than flying through and expiring behind them.
const CATCH_DISTANCE := 0.9

## Radians per second a BLADE turns about the vertical. Fast enough to read as a spin from the
## camera's height, slow enough that it does not strobe against a 60Hz tick.
const SPIN_RATE := 14.0

## One mesh per shape, built on first use and shared by every projectile that ever flies with
## it. Authored at RADIUS 1 and scaled by the node, so `projectile_radius` is the only number
## that decides how big a spell looks - the same contract `SpellGlyph`'s unit box gives the
## icons.
static var _bolt_meshes: Dictionary = {}

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
	# height.
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
	body_entered.connect(_on_body_entered)
	_park()


func _physics_process(delta: float) -> void:
	if not _active:
		return
	# Steering happens BEFORE the step, so a spell that turns this tick also moves along the
	# direction it turned to. Moving first would leave every seeker one tick behind its own aim,
	# which reads as a spell that consistently trails its target.
	_steer(delta)
	_pull(delta)
	global_position += _direction * _speed * delta
	# Framerate-independent decay: `drag` is stated per SECOND, so a 30fps phone and a 144fps
	# desktop agree on where the spell lands. Multiplying by the raw factor once per tick would
	# make the same spell travel twice as far on a machine running at half the rate.
	if _ability.projectile_drag < 1.0:
		_speed *= pow(_ability.projectile_drag, delta)
	_age += delta
	# After the step, so the drawing points where the spell is now going rather than where it
	# was going. A seeker turns every tick and a boomerang turns once; both would otherwise
	# fly one frame's worth of sideways.
	_spin += delta * SPIN_RATE
	_aim_mesh()
	if _returned and _reached_caster():
		_finish()
		return
	if _age >= _ability.lifetime:
		_finish()


## Bends the flight: turn for home if it is time, otherwise lean toward whoever is nearest.
##
## The two are exclusive on purpose. A spell that both homed and returned would chase its
## target on the way back as well, and there is no reading of "it comes back to you" under
## which it should first go somewhere else.
func _steer(delta: float) -> void:
	if _ability.returns_after > 0.0:
		if not _returned and _age >= _ability.lifetime * _ability.returns_after:
			_turn_for_home()
		return
	if _ability.homing_turn > 0.0:
		_home(delta)


## Turns a returning spell around and re-aims it at wherever its caster is NOW.
##
## At the caster and not back down its own line: the wizard has been walking since they threw
## it, and a boomerang that returns to a patch of empty ground is a boomerang whose second
## half is decoration. Re-speeding it matters for the same reason - a spell with drag on it
## arrives home at a crawl otherwise, long after the fight has moved.
func _turn_for_home() -> void:
	_returned = true
	_caught.clear()
	_speed = _ability.projectile_speed
	if not is_instance_valid(_shooter):
		_direction = -_direction
		return
	var home := _shooter.global_position - global_position
	home.y = 0.0
	if home.length_squared() < 0.0001:
		_direction = -_direction
		return
	_direction = home.normalized()


## Leans the flight toward the nearest fighter, at most `homing_turn` degrees this tick.
##
## Capped by a turn RATE, so the spell can be lost by moving across it. The cap is what makes
## this dodgeable, and removing it turns the seeker into a guaranteed hit with a delay.
func _home(delta: float) -> void:
	var prey := _nearest_target()
	if prey == null:
		return
	var wanted := prey.global_position - global_position
	wanted.y = 0.0
	if wanted.length_squared() < 0.0001:
		return
	var here := Vector2(_direction.x, _direction.z)
	var there := Vector2(wanted.x, wanted.z).normalized()
	if here.length_squared() < 0.0001:
		return
	var turned := here.normalized().rotated(
		clampf(here.angle_to(there), -deg_to_rad(_ability.homing_turn) * delta,
			deg_to_rad(_ability.homing_turn) * delta))
	_direction = Vector3(turned.x, 0.0, turned.y).normalized()


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
## changes nothing except the chance of a subtle bug the day somebody swaps the shape.
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
		_mesh.transform.basis = Basis(Vector3.UP, _spin).scaled(Vector3.ONE * _draw_scale)
		return
	if _direction.length_squared() < 0.0001:
		return
	# Every pointed shape is authored along +Y, so aligning +Y with the travel aims all of them
	# with one line. The direction is always horizontal here, so the degenerate case that would
	# make this quaternion ambiguous - travelling straight down - cannot arise.
	_mesh.transform.basis = Basis(Quaternion(Vector3.UP, _direction.normalized())) 		.scaled(Vector3.ONE * _draw_scale)


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
	_speed = ability.projectile_speed
	_age = 0.0
	_returned = false
	_caught.clear()
	global_position = from
	var radius := ability.projectile_radius
	(_shape.shape as SphereShape3D).radius = radius
	_mesh.mesh = _bolt_mesh(ability.bolt)
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
	_active = true
	visible = true


## Anything solid stops it; only a fighter takes a hit from it. See the mask in `_ready`.
##
## A PIERCING spell is the one exception, and only for fighters. Cover still stops it dead:
## a rock that swallows a fireball and lets a boomerang through would teach the player a rule
## and then break it, which is the same argument ConeCast makes about line of sight.
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
	if _ability.pierces and fighter != null:
		_caught.append(body)
		return
	_finish()


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
	_direction = Vector3.ZERO
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

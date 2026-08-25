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
	# The mesh and shape come from the PackedScene and are SHARED between every instance it
	# spawns, so resizing one would resize them all. Two abilities with different radii would
	# silently fight over it. Give each projectile its own copies.
	_mesh.mesh = _mesh.mesh.duplicate()
	_shape.shape = _shape.shape.duplicate()
	# Likewise one material per instance, so tinting a Fireball cannot recolour a Force Wave.
	_material = StandardMaterial3D.new()
	_material.emission_enabled = true
	_material.emission_energy_multiplier = 2.2
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
	global_position += _direction * _speed * delta
	# Framerate-independent decay: `drag` is stated per SECOND, so a 30fps phone and a 144fps
	# desktop agree on where the spell lands. Multiplying by the raw factor once per tick would
	# make the same spell travel twice as far on a machine running at half the rate.
	if _ability.projectile_drag < 1.0:
		_speed *= pow(_ability.projectile_drag, delta)
	_age += delta
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
		var gap := global_position.distance_squared_to(body.global_position)
		if gap < best_gap:
			best_gap = gap
			best = body
	return best


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
	_mesh.mesh.radius = radius
	_mesh.mesh.height = radius * 2.0
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
	_park()
	finished.emit(self)


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

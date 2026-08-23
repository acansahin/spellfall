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

## Emitted when this touches a valid target. `direction` is the travel direction, which is
## what a knockback system wants - you get thrown the way the spell was going, not away from
## wherever its centre happened to be.
signal hit(body: Node3D, direction: Vector3, ability: Ability)

## Emitted when this is done, for any reason. The pool listens to reclaim it.
signal finished(projectile: Projectile)

## Where parked projectiles wait. Far enough below the arena that a pooled projectile can
## never overlap anything while it is off duty.
const PARKED_POSITION := Vector3(0.0, -1000.0, 0.0)

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _shape: CollisionShape3D = $Shape

var _ability: Ability = null
var _direction := Vector3.ZERO
var _age := 0.0
## Guards against a second hit, and against ticking while parked in the pool. A pooled node
## is still in the tree, so without this it would keep flying after being reclaimed.
var _active := false
## The caster is ignored, otherwise a spell detonates inside the wizard that cast it - both
## are on the players layer.
var _shooter: Node3D = null
var _material: StandardMaterial3D = null


func _ready() -> void:
	collision_layer = 4   # projectiles
	collision_mask = 2    # players
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
	global_position += _direction * _ability.projectile_speed * delta
	_age += delta
	if _age >= _ability.lifetime:
		_finish()


## Sends this projectile on its way. `direction` is normalised here, so callers may pass a
## rough aim without worrying about its length.
func launch(ability: Ability, from: Vector3, direction: Vector3, shooter: Node3D) -> void:
	_ability = ability
	_shooter = shooter
	_direction = direction.normalized()
	_age = 0.0
	global_position = from
	var radius := ability.projectile_radius
	(_shape.shape as SphereShape3D).radius = radius
	_mesh.mesh.radius = radius
	_mesh.mesh.height = radius * 2.0
	_material.albedo_color = ability.colour
	_material.emission = ability.colour
	_active = true
	visible = true


func _on_body_entered(body: Node3D) -> void:
	if not _active or body == _shooter:
		return
	hit.emit(body, _direction, _ability)
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

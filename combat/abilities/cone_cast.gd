class_name ConeCast
extends RefCounted

## Who a fan-shaped instant spell catches.
##
## A physics query rather than a walk over a list of known fighters, for the same reason
## KillZone is an Area3D rather than a height check: it finds anything on the players layer,
## including a fighter nobody has written code for yet - which is exactly what 2v2 and a
## free-for-all will create.
##
## It decides who was in the fan and nothing else. What a hit MEANS - instability, knockback,
## a sound - belongs to the level, which applies it through the same door a projectile hit
## goes through. A cone that knew about knockback would be a second place the formula lived.
##
## The query objects are static and reused. Building a SphereShape3D per cast would allocate
## in the middle of a fight, which is the stutter the projectile pool exists to avoid.

## Mask value for the "players" physics layer (layer 2), matching KillZone and Projectile.
const PLAYERS_MASK := 2

## Mask value for the "world" layer (layer 1), which is what cover stands on. The sight line
## is drawn between two fighters' ORIGINS, which sit at chest height on a 2m capsule - so an
## obstacle has to be about that tall to be cover, and both the rock and the tree are.
const WORLD_MASK := 1

## Nobody is expected to be in a 4m fan on a 14m arena with four fighters, so this is a
## ceiling and not a budget.
const MAX_TARGETS := 8

static var _probe := SphereShape3D.new()
static var _query := PhysicsShapeQueryParameters3D.new()


## Bodies standing inside `ability`'s fan, centred on `aim` and anchored at `from`.
##
## The test is done on the GROUND PLANE. A fan that also had to be aimed vertically would
## make a spell miss because the target was mid-knockback and half a metre in the air, which
## is not a skill anyone wants to practise.
static func targets(space: PhysicsDirectSpaceState3D, from: Vector3, aim: Vector3,
		ability: Ability, caster: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if space == null or ability == null:
		return found
	var flat_aim := Vector2(aim.x, aim.z)
	if flat_aim.length_squared() < 0.0001:
		return found
	flat_aim = flat_aim.normalized()

	_probe.radius = maxf(ability.area, 0.01)
	_query.shape = _probe
	_query.transform = Transform3D(Basis.IDENTITY, from)
	_query.collision_mask = PLAYERS_MASK
	_query.collide_with_bodies = true
	_query.collide_with_areas = false

	var half := deg_to_rad(ability.cone_angle)
	for hit in space.intersect_shape(_query, MAX_TARGETS):
		var body := hit.get("collider") as Node3D
		if body == null or body == caster or found.has(body):
			continue
		var offset := Vector2(body.global_position.x - from.x, body.global_position.z - from.z)
		if offset.length_squared() < 0.0001:
			# Standing inside the caster. There is no angle to test and no reading of the
			# rule under which that should miss.
			found.append(body)
			continue
		if absf(flat_aim.angle_to(offset.normalized())) <= half:
			if _in_sight(space, from, body):
				found.append(body)
	return found


## True if nothing solid stands between the caster and `body`.
##
## Cover has to mean ONE thing. A rock that stops a Fireball and not a Force Wave teaches the
## player a rule and then breaks it, and "I was behind a rock and it hit me anyway" reads as a
## bug whatever the physics of an imaginary shockwave might argue.
##
## Cast against the WORLD layer only, so a second fighter standing in the way is not cover -
## a wave catches everyone in the fan, and bodies do not shield each other.
static func _in_sight(space: PhysicsDirectSpaceState3D, from: Vector3, body: Node3D) -> bool:
	var ray := PhysicsRayQueryParameters3D.create(from, body.global_position)
	ray.collision_mask = WORLD_MASK
	ray.collide_with_bodies = true
	ray.collide_with_areas = false
	return space.intersect_ray(ray).is_empty()

class_name AbilityComponent
extends Node

## The spellbook a character carries: which abilities it has, and whether they are ready.
##
## A component the wizard OWNS rather than a base class it inherits, so a bot, a dummy or a
## second character type gets spells by gaining this node - no shared ancestor required.
##
## It does not spawn anything. It decides *whether* a cast may happen and emits
## `cast_requested`; the level connects that to whatever produces the effect. Two reasons:
## the component stays free of scene-tree knowledge (it cannot know where the projectile pool
## lives), and when the server becomes authoritative this signal is the natural place to
## intercept - validate there, and the client's own component becomes a prediction rather
## than a decision.
##
## Cooldowns tick in _physics_process, on the fixed 60Hz gameplay tick, so a phone running at
## 30fps and a desktop at 144fps agree on how long a spell takes to come back.

## A cast passed its checks. The level turns this into a projectile, cone, dash or buff.
signal cast_requested(ability: Ability, origin: Vector3, direction: Vector3, caster: Node3D)

## A cast happened, for UI and audio. Separate from `cast_requested` because a listener that
## only wants to flash a button should not have to care about origins and directions.
signal cast_performed(slot: int, ability: Ability)

## A slot came off cooldown.
signal cooldown_finished(slot: int)

## The spells this character has, in slot order. Slot 0 is the primary. Authored in the
## inspector or assigned at runtime; either way they are shared Resources, so never mutate
## one at runtime - that would edit the spell for everybody holding it.
@export var abilities: Array[Ability] = []:
	set(value):
		abilities = value
		# Keep the cooldown array in step here rather than only in _ready(), so a slot can
		# be queried before the node enters the tree and so assigning a spellbook at
		# runtime (a bot being armed, a round handing out an upgrade) cannot desync the two.
		_resize_cooldowns()

## Seconds remaining per slot, parallel to `abilities`.
var _cooldowns: PackedFloat32Array = PackedFloat32Array()

## The body that casts. A component attached to a character takes that character as its
## caster; nothing else would make sense for a node parented to it.
@onready var _caster: Node3D = get_parent() as Node3D


func _ready() -> void:
	_resize_cooldowns()


func _resize_cooldowns() -> void:
	_cooldowns.resize(abilities.size())
	_cooldowns.fill(0.0)


func _physics_process(delta: float) -> void:
	for slot in _cooldowns.size():
		if _cooldowns[slot] <= 0.0:
			continue
		_cooldowns[slot] = maxf(0.0, _cooldowns[slot] - delta)
		if _cooldowns[slot] == 0.0:
			cooldown_finished.emit(slot)


## Attempts a cast. Returns true if it happened.
##
## `direction` is a world-space aim on the ground plane; a zero vector means "no aim given",
## and the caller's own facing is used instead. Casting into a random direction because the
## player had not moved yet would be worse than casting where they are looking.
func try_cast(slot: int, direction: Vector3 = Vector3.ZERO) -> bool:
	if not is_ready(slot):
		return false
	var ability := abilities[slot]
	var aim := direction
	if aim.length_squared() < 0.0001:
		aim = caster_facing()
	aim = aim.normalized()

	_cooldowns[slot] = ability.cooldown
	var origin: Vector3 = _caster.global_position + aim * ability.spawn_offset
	cast_requested.emit(ability, origin, aim, _caster)
	cast_performed.emit(slot, ability)
	return true


## Where the caster is looking, on the ground plane. Falls back to world -Z so a cast can
## never produce a zero-length direction.
##
## Public because the aim indicator has to draw the direction an un-aimed cast would take,
## and the only honest way to draw it is to ask the thing that decides it. A second copy of
## this in the drawing code would put a line on the ground that the spell did not follow.
func caster_facing() -> Vector3:
	var visual := _caster.get_node_or_null(^"Visual") as Node3D
	var yaw: float = visual.rotation.y if visual != null else _caster.rotation.y
	# Godot yaw 0 faces -Z, and yaw `a` faces (-sin a, 0, -cos a). Same convention as
	# player.gd's _face_travel; getting this wrong aims spells out of the wizard's back.
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## True if the slot exists and is off cooldown.
func is_ready(slot: int) -> bool:
	if not _valid_slot(slot):
		return false
	return _cooldowns[slot] <= 0.0


## Seconds left on a slot, or 0.0.
func cooldown_remaining(slot: int) -> float:
	if not _valid_slot(slot):
		return 0.0
	return _cooldowns[slot]


## 0.0 when ready, 1.0 the instant it was cast. This is what a radial sweep draws.
func cooldown_fraction(slot: int) -> float:
	if not _valid_slot(slot):
		return 0.0
	var total := abilities[slot].cooldown
	if total <= 0.0:
		return 0.0
	return clampf(_cooldowns[slot] / total, 0.0, 1.0)


func ability_in(slot: int) -> Ability:
	return abilities[slot] if _valid_slot(slot) else null


func slot_count() -> int:
	return abilities.size()


## Guards BOTH arrays. Checking only `abilities` and then indexing `_cooldowns` is exactly
## how this crashed once: the bounds that were tested were not the bounds that were used.
func _valid_slot(slot: int) -> bool:
	if slot < 0 or slot >= abilities.size() or slot >= _cooldowns.size():
		return false
	return abilities[slot] != null


## Clears every cooldown. The round system will call this on reset so a new round does not
## start with spells still recovering from the last one.
func reset() -> void:
	_cooldowns.fill(0.0)

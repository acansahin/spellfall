class_name ProjectilePool
extends Node3D

## Hands out projectiles without allocating during a fight.
##
## Spawning and freeing nodes mid-combat is the classic mobile stutter: each `instantiate()`
## allocates, each `queue_free()` gives the collector something to do, and a four-player
## fight throws a lot of spells. Projectiles are reused instead - parked invisible and
## inert, then relaunched.
##
## This is a POOL, not an object-pool framework. It handles one scene, it grows if it runs
## dry, and it has no eviction policy. If a second pooled type ever appears, generalise it
## then; today that would be building for an imagined problem.

## Emitted when any projectile from this pool hits something. Re-broadcast here so the
## combat layer connects once, rather than to every projectile as it is launched.
signal projectile_hit(body: Node3D, direction: Vector3, ability: Ability)

@export var projectile_scene: PackedScene = null

## How many to build up front. Eight covers a busy moment for one caster; the pool grows
## past this if it has to, it just allocates when it does.
@export var prewarm: int = 8

var _all: Array[Projectile] = []
var _idle: Array[Projectile] = []


func _ready() -> void:
	for i in prewarm:
		_build()


func _build() -> Projectile:
	var p: Projectile = projectile_scene.instantiate()
	add_child(p)
	p.finished.connect(_reclaim)
	p.hit.connect(_relay_hit)
	_all.append(p)
	_idle.append(p)
	return p


## Fires one projectile. Returns it so a caller can watch it; ignore the result freely.
func fire(ability: Ability, from: Vector3, direction: Vector3, shooter: Node3D) -> Projectile:
	var p: Projectile = _idle.pop_back() if not _idle.is_empty() else _build()
	# _build() appends to _idle as well, so take it back out in that path too.
	_idle.erase(p)
	p.launch(ability, from, direction, shooter)
	return p


func _reclaim(p: Projectile) -> void:
	if not _idle.has(p):
		_idle.append(p)


func _relay_hit(body: Node3D, direction: Vector3, ability: Ability) -> void:
	projectile_hit.emit(body, direction, ability)


## Number currently in flight. Used by the harness to prove reuse rather than growth.
func active_count() -> int:
	var n := 0
	for p in _all:
		if p.is_active():
			n += 1
	return n


## Total instances ever built. If this stays at `prewarm` across many casts, reuse works.
func total_count() -> int:
	return _all.size()

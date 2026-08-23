class_name KillZone
extends Area3D

## The volume under the arena. Enter it and you are out of the round.
##
## Replaces the `y < fall_limit` check that stood in for this during the prototype. A real
## Area3D matters for more than tidiness: a threshold test only runs for bodies something
## thought to poll, so every new fighter had to be remembered and added to a list. This
## detects anything on the players layer, including a fighter nobody wrote code for yet.
##
## It reports and nothing else. Whether falling means elimination, a life lost or a respawn
## is the round system's business - this only knows that someone left the world.

## Emitted once per body that falls in.
signal fighter_fell(fighter: Node3D)

## Bodies already counted, so a body that clips the boundary twice on the way down cannot
## be eliminated twice.
var _seen: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 8   # killzone
	collision_mask = 2    # players
	monitoring = true
	# Must stay true. See ARCHITECTURE.md "Traps already hit" - monitorable=false silently
	# disables body detection on the area itself, not just detection OF it.
	monitorable = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if _seen.has(body):
		return
	_seen.append(body)
	fighter_fell.emit(body)


## Called by the round system when a round resets, so fallers can fall again next round.
func clear() -> void:
	_seen.clear()

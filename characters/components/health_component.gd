class_name HealthComponent
extends Node

## How much longer a fighter can take.
##
## This used to be lava-only, on the rule that no spell may ever touch it - keeping combat
## entirely in instability and knockback, so the fight stayed a positioning game and not a
## damage race. That rule is gone: Fireball now drains it directly (see `Ability.health_damage`
## and `_apply_hit()` in main.gd), on top of everything instability still does. Two ways to
## lose are live at once - destabilise someone into the lava, or simply outshoot them - and the
## level decides which spells get to use the second one.
##
## What has NOT changed is that standing on stone no longer heals it. A trip into the lava, or
## a Fireball taken to the face, costs something for the rest of the round - `reset()` between
## rounds is the only way back to full. So the total is a budget as much as a health bar: how
## many hits, and how many seconds in the lava, before this fighter is out.
##
## Like instability, it knows nothing about knockback, the arena, or who is standing where. The
## level decides who is burning and who got hit; this only counts.

## Emitted whenever the value moves. The HUD listens.
signal changed(current: float, previous: float)

## Emitted the moment it reaches zero. The level turns this into an elimination, through the
## same door a fall goes through.
signal emptied()

@export var maximum: float = 100.0

## Points per second lost while standing in the lava. At 22 a fighter has about four and a
## half seconds out there, which is two to three seconds of walking back plus a margin for
## being knocked out again on the way.
@export var burn_per_second: float = 22.0

var current: float = 0.0


func _ready() -> void:
	current = maximum


## Burns for one tick's worth. Emits `emptied` exactly once on the crossing, not every frame
## afterwards - the level would otherwise report the same elimination sixty times a second.
func burn(delta: float) -> void:
	if current <= 0.0:
		return
	var previous := current
	current = maxf(current - burn_per_second * delta, 0.0)
	if current != previous:
		changed.emit(current, previous)
	if current <= 0.0:
		emptied.emit()


## Removes a fixed amount outright - a spell hit, not the lava's per-second burn. Kept as a
## separate entry point rather than folded into `burn()`: a hit is instantaneous and a burn is
## a rate, and merging them would mean either scaling a spell's damage by delta (wrong - a
## Fireball's bite must not depend on the frame it landed on) or scaling the lava by nothing.
func damage(amount: float) -> void:
	if amount <= 0.0 or current <= 0.0:
		return
	var previous := current
	current = maxf(current - amount, 0.0)
	if current != previous:
		changed.emit(current, previous)
	if current <= 0.0:
		emptied.emit()


func fraction() -> float:
	return current / maxf(maximum, 0.001)


## True while there is anything left to burn.
func is_alive() -> bool:
	return current > 0.0


## Back to full. The round system calls this between rounds.
func reset() -> void:
	var previous := current
	current = maximum
	if current != previous:
		changed.emit(current, previous)

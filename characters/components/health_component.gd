class_name HealthComponent
extends Node

## How much longer a fighter can take.
##
## This used to be lava-only, on the rule that no spell may ever touch it - keeping combat
## entirely in instability and knockback, so the fight stayed a positioning game and not a
## damage race. Then five spells were allowed to chip it. Now MOST of the roster does, because
## the reference map has one number per spell that drains health, raises damage points and
## sets the push all at once - see `Ability.damage` and docs/warlock-reference.md.
##
## The rule behind the original decision survives all of that, and is the one to defend:
## **THIS BAR IS THE LAVA'S CURRENCY.**
##
## A trip into the lava empties a full bar in about four and a half seconds. The fastest spell
## in the game needs nine seconds of PERFECT uptime - every cast landing, nobody dodging, nobody
## walking away - to do the same, and a real fight is nothing like that. So a spell hit is worth
## a fraction of a second in the lava, which is exactly what it should be worth: a mark left
## between exchanges, never a way to win without ever using the edge.
##
## Fireball spent a session at five hits to a full bar, and at five it was a damage race with a
## knockback theme - the ring stopped mattering. `--loadout-test` now asserts both halves: ten
## clean hits minimum for any spell, and the lava faster than all of them.
##
## The map agrees with the ten, which is the pleasant part: its own heaviest single hit is
## Scourge at 10 out of 100, exactly ten hits, and its Fireball at 7 needs fifteen. The floor
## only comes under pressure at the shop levels this port does not build.
##
## What has NOT changed is that standing on stone no longer heals it. A trip into the lava, or
## a spell taken to the face, costs something for the rest of the round - `reset()` between
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


## Puts the bar back to a value it held earlier, for a spell that rewinds its caster.
##
## Deliberately not `damage(-n)`: healing and un-doing are different claims. Nothing in this
## game heals - stone does not mend a burn, and a Fireball taken stays taken - but one spell
## restores the reading a fighter had a few seconds ago, and it has to be able to say so
## without opening a door that lets any negative number through `damage()`.
##
## Clamped to the maximum, so a rewind taken while full cannot bank spare health.
func restore_to(value: float) -> void:
	var previous := current
	current = clampf(value, 0.0, maximum)
	if current != previous:
		changed.emit(current, previous)


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

class_name HealthComponent
extends Node

## How much longer a fighter can stand in the lava.
##
## Read the name carefully: this is NOT a combat health bar, and no spell may ever touch it.
## Hits raise `InstabilityComponent` and nothing else - that is the whole design, and a spell
## that could chip this number would quietly turn the game into a damage race. The only thing
## that burns it is the lava, and the only thing that mends it is standing on stone.
##
## What it buys is a second chance. Being knocked out of the ring used to be instant: you
## touched the void and the round was over, which makes one mistake the whole story of a round
## and makes a comeback impossible. Burning gives a window - long enough to turn around and
## walk back, short enough that being out there is genuinely bad.
##
## Like instability, it knows nothing about knockback, the arena, or who is standing where.
## The level decides who is in the lava; this only counts.

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

## Points per second recovered while on the stone. Deliberately less than half the burn rate:
## a dunk should cost something that lasts, or the lava is a nuisance rather than a threat.
@export var mend_per_second: float = 10.0

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


## Recovers for one tick's worth, up to the maximum. A fighter already at zero stays there:
## they are out of the round, and the round system is what puts them back.
func mend(delta: float) -> void:
	if current <= 0.0 or current >= maximum:
		return
	var previous := current
	current = minf(current + mend_per_second * delta, maximum)
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

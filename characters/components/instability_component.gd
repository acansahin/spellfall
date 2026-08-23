class_name InstabilityComponent
extends Node

## How destabilised a fighter is. One number, and nothing else.
##
## This replaces health. It starts at 0 and only rises within a round; higher instability
## means a hit throws you further, which is what makes a round get more dangerous the longer
## it runs without a shrinking arena or a timer forcing it.
##
## It deliberately does NOT know what knockback is. It cannot compute how far a hit throws
## you, and it must never learn - that formula lives once, in combat/knockback/. Keeping them
## apart is what lets the HUD show instability without touching combat, and lets knockback be
## rebalanced without touching either.

## Emitted whenever the value moves. The HUD listens; nothing in combat does.
signal changed(current: float, previous: float)

## Where a round begins.
@export var starting: float = 0.0

## A ceiling, so a long round cannot produce absurd numbers. Well above the ~150% the design
## calls "extremely dangerous", so it should never be reached in practice.
@export var maximum: float = 400.0

var current: float = 0.0


func _ready() -> void:
	current = starting


## Raises instability. Negative amounts are ignored rather than clamped, because "a spell that
## heals instability" is a design decision nobody has made yet, and silently allowing it here
## would let one land by accident.
func add(amount: float) -> void:
	if amount <= 0.0:
		return
	var previous := current
	current = minf(current + amount, maximum)
	if current != previous:
		changed.emit(current, previous)


## Back to the starting value. The round system calls this between rounds.
func reset() -> void:
	var previous := current
	current = starting
	if current != previous:
		changed.emit(current, previous)

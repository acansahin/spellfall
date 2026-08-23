class_name Knockback
extends RefCounted

## The one place knockback is computed.
##
## GAME_DESIGN.md states the formula as
##     final = ability_base_knockback * instability_multiplier * situational_modifiers
## and this is it. No ability script computes its own knockback; no projectile does; the
## receiving body does not either. One function, so there is one thing to read when a hit
## sends someone the wrong distance, and one thing for a server to agree with.
##
## Pure functions on purpose - no nodes, no state, no side effects. That makes it trivially
## testable and trivially re-runnable, which is what reconciliation will need.


## How much the target's instability amplifies a hit.
static func multiplier(instability: float, rules: KnockbackRules) -> float:
	var raw := rules.base_multiplier + (instability / 100.0) * rules.per_100_instability
	return clampf(raw, 0.0, rules.max_multiplier)


## The velocity a hit imparts, in m/s.
##
## `direction` is normalised here and flattened onto the ground plane: you are thrown the way
## the spell was travelling, not away from wherever its centre happened to be. That keeps a
## skillshot's angle meaningful - clipping someone on the edge of a Fireball should still push
## them along its line, which is what makes aiming at the arena edge a real tactic.
static func velocity(base: float, direction: Vector3, instability: float,
		rules: KnockbackRules) -> Vector3:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() < 0.0001:
		return Vector3.ZERO
	var speed := base * multiplier(instability, rules)
	return flat.normalized() * speed + Vector3.UP * rules.lift


## How far a hit of this speed will carry, given the receiver's friction. Closed form, because
## the decay is linear: v^2 / 2f. Used by the harness to check that the measured slide matches
## the intended one, and useful for answering "how much knockback clears a 7m arena?" without
## playing it.
static func slide_distance(speed: float, friction: float) -> float:
	if friction <= 0.0:
		return INF
	return (speed * speed) / (2.0 * friction)

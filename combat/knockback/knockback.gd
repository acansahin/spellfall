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


## Warcraft III units to one metre. The reference map's terrain cell is 128 units, and this
## port lays everything out on that one scale - the arena, the ranges, the walk speed and the
## line below. It appears HERE and nowhere else; see docs/warlock-reference.md.
const UNITS_PER_METRE := 128.0


## The impulse a spell of this damage imparts to a target at zero instability, in m/s.
##
## The map has no separate knockback stat. One number is the damage, the instability gained
## and the push, and its hit function reads
##
##     dv = (100 + damage_points) * damage * push_mult * 0.03      [units per 0.03s tick]
##
## Divide out the tick and you have units per second; divide by 128 and you have this. The
## leading 100 is the map's own base, and `(100 + points)/100` is exactly the multiplier
## below - which is why `KnockbackRules` ships at base 1.0 and per_100 1.0 and needs no
## change: that curve was arrived at independently and it is the map's own curve.
static func base_impulse(damage: float, push_mult: float) -> float:
	return damage * push_mult * 100.0 / UNITS_PER_METRE


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


## How far a hit of this speed will carry, given the receiver's drag. Still a closed form,
## which is the part worth protecting: "how much knockback clears an 11m arena?" has an
## answer instead of a playtest.
##
## The decay is EXPONENTIAL now - the reference map multiplies a velocity by 0.98 every 0.03s
## tick and does nothing else - so the integral is `v / -ln(drag)` where it used to be the
## `v^2 / 2f` of linear friction. Two consequences to know before reading a number out of it:
## the carry is now LINEAR in the impulse rather than quadratic, so doubling the instability
## doubles the distance instead of quadrupling it; and the tail never formally reaches zero,
## so this is total travel, not distance to a full stop.
static func slide_distance(speed: float, drag_per_second: float) -> float:
	if drag_per_second <= 0.0 or drag_per_second >= 1.0:
		return INF
	return speed / -log(drag_per_second)

class_name KnockbackRules
extends Resource

## How a hit is turned into speed. The tuning knobs for the game's central mechanic.
##
## These describe the HIT, not the body receiving it. How quickly you slide to a stop, and how
## long you lose control for, are properties of the fighter and live on player.gd - a heavier
## character would slide less from the identical hit.
##
## Nothing here is balanced. These are starting shapes, to be moved in playtesting, which is
## exactly why they are a Resource and not constants in a script.

## Multiplier at 0% instability. 1.0 means an ability's `knockback` is its speed in m/s when
## the target is perfectly stable.
@export var base_multiplier: float = 1.0

## Extra multiplier per 100% instability. At 1.0 the curve is 1x at 0%, 2x at 100%, 2.5x at
## 150% - a straight line. Linear on purpose: a player has to be able to look at a number and
## predict what the next hit does, and an exponential curve makes that guesswork.
@export var per_100_instability: float = 1.0

## Ceiling, so a very long round cannot produce a hit that crosses the arena instantly.
@export var max_multiplier: float = 6.0

## Upward speed added to every hit, in m/s. A little lift makes a knockback read as a hit
## rather than a shove, and helps a victim clear the arena lip instead of grinding along it.
@export var lift: float = 2.5

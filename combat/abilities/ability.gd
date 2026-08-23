class_name Ability
extends Resource

## One spell, as data.
##
## Adding a spell should mean authoring a `.tres` file in `data/abilities/`, not writing a
## script. That is the whole point of this class: the four starting spells differ in numbers
## and in which *behaviour* they select, not in bespoke code. A fifth spell that is "Fireball
## but wider and slower" must cost a file, not a class.
##
## Not every field applies to every cast type - `projectile_speed` means nothing to a buff.
## Unused fields are simply left at their defaults; a runtime reads only what its cast type
## needs. The alternative, a subclass per cast type, buys nothing until a spell needs genuinely
## different CONTROL FLOW rather than different numbers.
##
## Balance note: nothing here is tuned. These are starting shapes, to be moved in playtesting.

enum CastType {
	## Travels from the caster in a straight line until it hits something or expires.
	PROJECTILE,
	## Instant, fan-shaped, centred on the aim direction. (not implemented yet)
	CONE,
	## Moves the caster. (not implemented yet)
	DASH,
	## Applies a timed effect to the caster. (not implemented yet)
	BUFF,
}

@export_group("Identity")
## Stable key used in code and save data. Never shown to a player.
@export var id: StringName = &""
## Shown in the UI.
@export var display_name: String = ""
## Placeholder tint until real art exists - the button and the projectile both read it, so a
## spell is recognisable by colour alone while everything is untextured primitives.
@export var colour: Color = Color(1, 1, 1)

@export_group("Casting")
@export var cast_type: CastType = CastType.PROJECTILE
## Seconds before this can be cast again.
@export var cooldown: float = 1.0
## How many casts are banked. 1 means a plain cooldown. (>1 not implemented yet)
@export var charges: int = 1

@export_group("Combat")
## Instability added to whatever this hits. Read by the instability system, not by this
## class - see ARCHITECTURE.md. Session 4.
@export var instability: float = 0.0
## Base knockback, before the target's instability multiplier is applied. Session 4.
@export var knockback: float = 0.0

@export_group("Projectile")
## Metres per second.
@export var projectile_speed: float = 18.0
## Collision radius, in metres. Also the drawn size.
@export var projectile_radius: float = 0.35
## Seconds before it expires on its own. Combined with speed this is the real range:
## 18 m/s for 1.2s reaches 21.6m, comfortably across a 14m arena.
@export var lifetime: float = 1.2
## Metres from the caster's centre that the projectile is born, so it does not spawn
## inside the caster's own collision shape.
@export var spawn_offset: float = 0.8

@export_group("Area")
## Radius of the effect on impact. 0 means a single-target hit. (splash not implemented yet)
@export var area: float = 0.0
## Cone half-angle in degrees, for CONE casts. (not implemented yet)
@export var cone_angle: float = 45.0

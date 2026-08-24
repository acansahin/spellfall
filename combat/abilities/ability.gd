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
	## Instant, fan-shaped, centred on the aim direction. Everything inside the fan is hit on
	## the frame it is cast, and thrown away from the caster rather than along the aim.
	CONE,
	## Moves the caster along the aim, and never off the arena.
	DASH,
	## Applies a timed effect to the caster.
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

## Health points this drains outright, bypassing instability and knockback entirely. 0.0 for
## every spell but Fireball - most of the game's violence still routes through instability and
## a fall into the lava, not a bar ticking down on its own. See HealthComponent for why this
## field exists at all despite that rule.
@export var health_damage: float = 0.0

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

## What fraction of its speed a projectile still has one second later. 1.0 flies flat forever;
## 0.3 keeps under a third of it.
##
## A spell that leaves fast and arrives slow says something a constant-speed one cannot: point
## blank is lethal, the far end of the range is a lob you can walk out of. It also limits the
## range with physics rather than with a lifetime cut off in mid-air.
##
## `effective_range()` below accounts for it, so the aim indicator and the bot's own reach
## check both stay honest without knowing this field exists.
@export_range(0.05, 1.0, 0.01) var projectile_drag: float = 1.0

@export_group("Area")
## How far the effect reaches, in metres. For a CONE this is the length of the fan. For a
## PROJECTILE it would be the splash radius on impact, and 0 means a single-target hit
## (splash is not implemented yet).
@export var area: float = 0.0
## Cone HALF-angle in degrees, so 55 is a 110-degree fan. Read by CONE casts only.
@export var cone_angle: float = 45.0

@export_group("Dash")
## Metres the caster is moved by a DASH cast. The landing point is clamped to the arena by
## the level, which is the only thing that knows where the edge is - a spell that could put
## you in the void would be a spell nobody ever casts.
@export var dash_distance: float = 5.0

@export_group("Buff")
## Seconds a BUFF cast lasts.
@export var duration: float = 1.0
## What incoming knockback is multiplied by while the buff is up. 1.0 changes nothing, 0.35
## takes just over a third of the hit. Reduction rather than blocking: it is one number
## folded into the existing formula, where blocking needs projectile ownership and hit
## cancellation and a visual language of its own. See GAME_DESIGN.md.
@export var knockback_resist: float = 1.0


## How far this spell reaches, in metres, whatever kind of spell it is.
##
## Range is stated differently by every cast type - a projectile's is speed times lifetime, a
## cone's is its area, a dash's is its distance - and the aim indicator has to draw all four.
## Answering it here keeps that arithmetic beside the numbers it reads, so a spell whose
## reach changes cannot leave the line drawn for it stale.
##
## A BUFF has no reach at all, and says so with 0.0 rather than with a number nobody should
## draw.
func effective_range() -> float:
	match cast_type:
		CastType.PROJECTILE:
			if projectile_drag >= 1.0:
				return projectile_speed * lifetime
			# Distance under exponential drag: the integral of v0 * drag^t from 0 to lifetime.
			# Both the numerator and log() are negative, so this comes out positive.
			var decay := log(projectile_drag)
			return projectile_speed * (pow(projectile_drag, lifetime) - 1.0) / decay
		CastType.CONE:
			return area
		CastType.DASH:
			return dash_distance
		_:
			return 0.0

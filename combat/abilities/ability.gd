class_name Ability
extends Resource

## One spell, as data.
##
## Adding a spell should mean authoring a `.tres` file in `data/abilities/`, not writing a
## script. That is the whole point of this class: the eleven spells differ in numbers and in
## which *behaviour* they select, not in bespoke code. A twelfth that is "Fireball but wider
## and slower" must cost a file, not a class.
##
## Seven of the eleven were added at once and only two of them needed a line of runtime: the
## rest are this file's fields in new combinations. Where a field DID have to be added it says
## what the spell is - `returns_after` is the whole of a boomerang - rather than naming the
## spell, so the next one that wants to come back gets it free.
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

## The little drawing on the spell button, so eleven spells are eleven SHAPES and not eleven
## tints. Named for what each looks like rather than for the spell that uses it - two spells
## may share one, and a new spell should reach for the closest fit before anybody draws a
## twelfth. `SpellGlyph` in `vfx/` is where they are actually drawn.
enum Glyph {
	## A teardrop. Fireball.
	FLAME,
	## Arcs spreading from a point. Force Wave.
	FAN,
	## A lightning zigzag. Arc Lance.
	BOLT,
	## A curl tightening inward, with a head. Seeker.
	SPIRAL,
	## A bent, thrown thing. Loopshot.
	BOOMERANG,
	## Two feet and a dashed hop. Blink.
	JUMP,
	## Three forward chevrons. Lunge.
	CHEVRON,
	## Two arrows passing each other. Warp Bolt.
	SWAP,
	## A heraldic shield. Arcane Shield.
	SHIELD,
	## A clock with its hands set back. Rewind.
	CLOCK,
	## A wall, and lines leaving it faster. Momentum.
	SURGE,
}

@export_group("Identity")
## Stable key used in code and save data. Never shown to a player.
@export var id: StringName = &""
## Shown in the UI.
@export var display_name: String = ""
## One line the loadout screen shows under the name, saying what the spell IS.
##
## Lives on the spell and not in the UI because a menu that described the roster from its own
## table would be a second place the roster lived - and the two drift the first time a spell is
## retuned. Keep it to what a player needs before their first cast, not to numbers: the
## cooldown is drawn beside it and the rest is learned by pressing the button.
@export_multiline var blurb: String = ""

## Placeholder tint until real art exists - the button and the projectile both read it, so a
## spell is recognisable by colour alone while everything is untextured primitives.
@export var colour: Color = Color(1, 1, 1)

## Which shape the button and the menu draw for this spell.
##
## Sits beside `colour` because it is the same kind of fact and answers the same question -
## "which spell is this?" - and because colour on its own stopped answering it at eleven
## spells, three of which are some shade of blue.
@export var glyph: Glyph = Glyph.FLAME

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

## Degrees per second the projectile may turn toward the nearest fighter. 0 flies straight.
##
## A TURN RATE and not a target lock, which is the whole difference between a spell you dodge
## and a spell you cannot. A seeker corrects a near miss and still loses someone who walks
## across its nose, so the counter is movement - which is what this game is about.
@export var homing_turn: float = 0.0

## How far ahead a homing projectile looks for something to steer at, in metres. Outside this
## it flies straight, which is what keeps a seeker aimed rather than fired.
@export var homing_radius: float = 8.0

## Fraction of the lifetime spent flying out before the spell turns and comes back to its
## caster. 0 never turns.
##
## Stated as a FRACTION and not in seconds, so the turn cannot drift out of the lifetime when
## the spell is retuned: 0.5 is always "halfway", whatever the flight now lasts.
## `effective_range()` reads it, so the aim lane and the bot's own reach shorten with it.
@export_range(0.0, 1.0, 0.01) var returns_after: float = 0.0

## Keeps flying after catching a fighter instead of expiring. Each fighter is caught at most
## once per leg, and a returning spell gets a clean list when it turns - so it can hit the
## same target going out and coming back.
##
## Cover is NOT pierced. A rock stops every spell in the game and that rule outranks this one;
## see ARCHITECTURE.md on why cover has to mean exactly one thing.
@export var pierces: bool = false

## Trades places with whoever it hits: the caster lands where the target stood, and the target
## lands where the caster was.
##
## The one spell whose payload is not damage at all. It rides on a field rather than on its
## own cast type because the CONTROL FLOW is identical - fly, hit the first body, resolve -
## and only the resolution differs.
@export var swaps_places: bool = false

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

## Whether a DASH catches whoever stands in its way. False makes it a pure escape.
##
## The hit uses the same `instability` / `knockback` / `health_damage` the projectiles use and
## goes through the same `_apply_hit` door, so a charge is not a second damage rule - it is a
## second way of reaching the one that already exists.
@export var dash_hits: bool = false

## Half-width of the corridor a hitting DASH sweeps, in metres. Roughly a body's width: wide
## enough that a charge down someone's centre line connects, narrow enough that it is aimed.
@export var dash_width: float = 0.9

@export_group("Buff")
## Seconds a BUFF cast lasts.
@export var duration: float = 1.0
## What incoming knockback is multiplied by while the buff is up. 1.0 changes nothing, 0.35
## takes just over a third of the hit. Reduction rather than blocking: it is one number
## folded into the existing formula, where blocking needs projectile ownership and hit
## cancellation and a visual language of its own. See GAME_DESIGN.md.
@export var knockback_resist: float = 1.0

## Metres per second of walking speed gained for every m/s of knockback the buff took off an
## incoming hit. 0 converts nothing, which is every buff but one.
##
## This is what turns a defensive number into an offensive one: the harder you are hit while
## it is up, the faster you move afterwards, so it rewards standing in a fight rather than
## leaving one. It reads the knockback the buff ABSORBED - the difference between what was
## thrown and what landed - so it cannot pay out without `knockback_resist` below 1.0.
@export var speed_per_absorbed: float = 0.0

## Ceiling on that bonus, in m/s. Without one, a fighter who takes three hits under the buff
## outruns the arena.
@export var speed_cap: float = 0.0

## Restores the position and the health the caster had when the buff was cast, `duration`
## seconds later.
##
## Instability is deliberately NOT restored: the round still remembers what you took. So this
## undoes where a fight put you, never how dangerous the fight has become - which keeps the
## escalation curve intact and makes the spell a retreat rather than a reset.
@export var rewind: bool = false


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
			# A returning spell only threatens as far as its TURN. Measuring the whole flight
			# would draw an aim lane twice the length of the one the boomerang actually
			# reaches, and would have the bot hold a range from which it cannot connect.
			var flight := lifetime
			if returns_after > 0.0:
				flight = lifetime * returns_after
			return _travel(flight)
		CastType.CONE:
			return area
		CastType.DASH:
			return dash_distance
		_:
			return 0.0


## Metres a projectile covers in `seconds`, accounting for drag.
##
## Split out of `effective_range()` because a returning spell asks the same question about a
## shorter flight, and two copies of an integral is two chances to retune only one of them.
func _travel(seconds: float) -> float:
	if seconds <= 0.0:
		return 0.0
	if projectile_drag >= 1.0:
		return projectile_speed * seconds
	# Distance under exponential drag: the integral of v0 * drag^t from 0 to `seconds`.
	# Both the numerator and log() are negative, so this comes out positive.
	var decay := log(projectile_drag)
	return projectile_speed * (pow(projectile_drag, seconds) - 1.0) / decay

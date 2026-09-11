class_name Ability
extends Resource

## One spell, as data.
##
## Adding a spell should mean authoring a `.tres` file in `data/abilities/`, not writing a
## script. That is the whole point of this class: the twenty-two spells differ in numbers and
## in which *behaviour* they select, not in bespoke code. A twenty-third that is "Fireball but
## wider and slower" must cost a file, not a class.
##
## The claim has been tested twice now. Seven spells were added at once and only two needed a
## line of runtime; eleven more were added after that and eight mechanics covered all of them.
## Where a field DID have to be added it says what the spell DOES - `curve_speed` is the
## whole of a boomerang, `drop_height` the whole of a meteor - rather than naming the spell,
## so the next one that wants to loop or fall gets it free.
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
	## Arcs spreading from a point. Scourge.
	FAN,
	## A lightning zigzag. Lightning.
	BOLT,
	## A curl tightening inward, with a head. Homing.
	SPIRAL,
	## A bent, thrown thing. Boomerang.
	BOOMERANG,
	## Two feet and a dashed hop. Teleport.
	JUMP,
	## Three forward chevrons. Thrust.
	CHEVRON,
	## Two arrows passing each other. Swap.
	SWAP,
	## A heraldic shield. Shield.
	SHIELD,
	## A clock with its hands set back. Time Shift.
	CLOCK,
	## A wall, and lines leaving it faster. Rush.
	SURGE,
	## A lump with a streak behind it. Meteor.
	ROCK,
	## A core with short rays leaving it. Splitter.
	BURST,
	## Three dots growing along a line. Fire Spray.
	STREAM,
	## A zigzag with a mark at each corner. Bouncer.
	BOUNCE,
	## A droplet with an arrow running into it. Drain.
	DROP,
	## A ring with spokes closing on its centre. Entangle.
	WEB,
	## Arcs winding inward. Gravity.
	VORTEX,
	## Two rings joined by a line. Link.
	CHAIN,
	## A shape and its two trailing copies. WindWalk.
	GHOST,
	## An eight-pointed burst from the centre out. Cataclysm.
	STAR,
	## A cross under an arc. Pious.
	CROSS,
}

## What a projectile LOOKS like in flight. The icon says which spell it is before you cast it;
## this says which spell is coming at you while it is in the air.
##
## Named for the form and not for the spell, like `Glyph` above, and for the same reason.
## Drawn by `Projectile`; every shape but ORB is oriented along the direction of travel.
enum Bolt {
	## A ball. Fireball, and the default for anything that has not thought about it.
	ORB,
	## A long thin spike along the line of flight. Lightning.
	SHARD,
	## A cone with its point forward. Homing.
	DART,
	## A flat bar, spinning as it goes. Boomerang.
	BLADE,
	## A hoop, lying flat. Swap.
	RING,
	## A lump. Meteor, and anything else that is a thrown thing rather than a spell.
	STONE,
	## A small bright ball. The fragments of a splitter, and the drops of a stream.
	MOTE,
	## A four-sided sliver, longer than it is wide. Splitter.
	PRISM,
	## A cone with its WIDE end forward - a mouth rather than a point. Drain.
	FUNNEL,
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

## How many projectiles ONE cast sends, spaced `stream_interval` apart. Fire Spray, at six.
##
## A stream and not a volley: they leave one at a time along the aim held at the moment of the
## cast, so walking sideways while one is in the air is what makes it dodgeable and what makes
## it worth aiming ahead of somebody.
@export var stream_count: int = 1

## Seconds between the projectiles of a stream.
@export var stream_interval: float = 0.15

@export_group("Combat")
## What this spell does, as ONE number, out of a hundred points of health.
##
## There used to be three fields here - `instability`, `knockback` and `health_damage` - set
## independently, and that separation was invented in this repo. The reference map has one
## number, and its hit function reads
##
##     dv = (100 + damage_points) * damage * push_mult * 0.03
##
## so the same `damage` drains health, raises the target's damage points AND decides how far
## they fly. A spell therefore cannot be "heavy but harmless" or "deadly but gentle" by fiat.
## The only lever between those is `push_mult` below, and that is the design space the map
## actually has. See docs/warlock-reference.md sections 4 and 5.
##
## Zero for a spell not meant to threaten at all - Teleport, Swap, and all three guards.
## Everything else chips, which IS a change: five spells drained health before, most of the
## roster does now.
##
## The floor under it is still a rule rather than a taste: **no spell may empty a full bar in
## under ten clean hits.** It survives the port because the map's own heaviest single hit is
## Scourge, at 10 out of 100 - exactly ten. `--loadout-test` asserts it.
@export var damage: float = 0.0

## How hard this pushes, per point of damage. 1.0 is Fireball; the map's real range is 0.1
## to 1.4.
##
## The whole per-spell design space, and it is deliberately NOT correlated with damage: the
## map's Gravity does 3 damage at 0.1 push, and another of its calls does the same 3 at 1.4.
## So a spell can threaten your health, your position, or both, and the two are separable
## without needing separate damage numbers.
@export var push_mult: float = 1.0

## Whether the push follows the PROJECTILE's travel, or points from the caster to the victim.
##
## The map has both doors and they belong to different spells: `SW()` shoves along the
## missile's line, `WW()` shoves away from whoever cast it. Along-travel keeps a skillshot's
## angle meaningful - clipping someone with the edge of a Fireball still throws them along
## its line, which is what makes aiming at the rim a tactic. Away-from-caster is what a burst
## around your own feet wants, where there is no travel to speak of.
@export var push_along_travel: bool = true

## Seconds the target cannot walk for. Entangle.
##
## It roots, it does not freeze: knockback still moves you and the round still burns you. A
## spell that stopped a body outright would also stop the lava from mattering, which is the
## one thing in this game that must never stop mattering.
@export var root_seconds: float = 0.0

## Fraction of the damage dealt that comes back to the caster as health. Drain, at 1.0.
##
## Capped by the caster's own maximum like any other heal, so it is a way to undo a trip into
## the lava rather than a way to bank health you never had.
@export_range(0.0, 2.0, 0.05) var heal_caster: float = 0.0

## Health given to every ALLY the burst catches, including the caster. Pious.
##
## Separate from `damage` rather than a negative one, because the two land on different
## people: the same cast hurts an enemy and mends a friend, which is what the map's own
## version does and what makes it the odd spell in its column.
@export var ally_heal: float = 0.0

## Seconds a tether keeps draining whoever this hit. Link.
@export var tether_seconds: float = 0.0

## Health per second that tether takes. The map's Link is 0.2 a tick, which is a slow bleed
## rather than a threat - the spell is a commitment you make early and forget about.
@export var tether_dps: float = 0.0

@export_group("Projectile")
## Metres per second.
@export var projectile_speed: float = 18.0
## Collision radius, in metres, and the size the drawing is scaled to.
##
## The HITBOX IS ALWAYS A SPHERE of this radius, whatever shape is drawn. A lance that is
## drawn a metre long is still caught by a ball a tenth of that: what a spell hits has to be
## the thing the player learned from Fireball, and a per-shape collider would make "did that
## graze me?" a different question for every spell in the game.
@export var projectile_radius: float = 0.35

## Which shape is drawn in flight. See `Bolt`.
@export var bolt: Bolt = Bolt.ORB
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

## Metres per second SIDEWAYS at launch. Above zero, the spell stops flying straight and
## becomes a boomerang: out along one side, home down the other.
##
## This replaced a `returns_after` fraction that turned the spell around at a point in its
## lifetime, and the replacement is the reference map's own model rather than a nicer version
## of ours. There, a boomerang is a projectile under CONSTANT ACCELERATION in the plane: a
## deceleration along the throw that brings its forward speed to zero after exactly
## `curve_reach` metres and then pulls it back, and a lateral acceleration in fixed ratio to
## it that bows the flight out and returns it to the line at the same instant. The return leg
## mirrors the lateral term, so the path is a leaf rather than a line - and the two legs cross
## at only two places, the caster and the turn.
##
## `Projectile` does the algebra; the two numbers here are all a spell states.
## See docs/warlock-reference.md section 8b.
@export var curve_speed: float = 0.0

## Metres out the curve reaches before it turns, for a spell with `curve_speed` above zero.
##
## A DISTANCE and not a time, because it is the distance that the flight is solved for: the
## deceleration is derived as `-speed² / (2 * reach)`, so retuning either number keeps the
## turn exactly here. It is also what `effective_range()` returns, so the aim lane and the
## bot's reach check are the outward leg rather than the whole loop.
##
## The map takes this from where the caster aimed, clamped to 2.34-6.25m. This port's aim
## carries a direction and no distance, so it is fixed per spell.
@export var curve_reach: float = 6.25

## Metres above the launch point the projectile is BORN, falling to the launch height over
## exactly its lifetime. 0 flies flat, which is every spell but one.
##
## The whole of a meteor, and the only thing in the game that leaves the ground plane. The
## fall rate is derived rather than stated - `drop_height / lifetime` - because the two are
## one fact in the map as well: it spawns its meteor 1000 units up and drops it at 740.741
## units a second, and 1000 / 740.741 is the 1.35 second lifetime it also states. Deriving
## keeps a retuned height or lifetime from landing the rock early or late.
##
## Note what this makes true: the flight TIME is fixed and the horizontal speed is what
## varies with range. That is a telegraph a player can count, and it is the opposite of every
## other projectile here. See docs/warlock-reference.md section 8a.
@export var drop_height: float = 0.0

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

## How many children this breaks into when its flight ends. Splitter.
##
## They are fired from wherever it died, fanned across `split_spread` degrees around the
## direction it was travelling, and each one is `split_child` - a whole Ability of its own, so
## the fragments have their own damage, speed, colour and shape rather than inheriting a
## fraction of their parent's.
@export var splits_into: int = 0

## The spell each fragment IS. Null with `splits_into` above zero simply splits into nothing.
@export var split_child: Resource = null

## Degrees the fan of fragments covers, centred on the parent's heading.
@export var split_spread: float = 90.0

## How many times this looks for another target after a hit. Bouncer.
##
## It searches within `bounce_range` for a fighter it has not already caught, so a bouncer in
## a 1v1 is a single-target spell with a long cooldown and in a 2v2 is the best spell in the
## column. That asymmetry is the map's and is kept.
@export var bounces: int = 0

## Fraction of the damage each bounce loses.
@export_range(0.0, 1.0, 0.05) var bounce_falloff: float = 0.2

## How far a bounce will look for its next target, in metres.
@export var bounce_range: float = 7.0

@export_group("Area")
## How far the effect reaches, in metres. For a CONE this is the length of the fan; for a
## PROJECTILE it is the blast radius on impact, and 0 means a single-target hit.
@export var area: float = 0.0
## Cone HALF-angle in degrees, so 55 is a 110-degree fan. Read by CONE casts only.
@export var cone_angle: float = 45.0

## Metres over which a burst's damage falls to nothing, measured from its centre. 0 means the
## whole area hits equally hard.
##
## The map states this the other way round - Meteor is "7-14 depending on range" - and the
## direction matters: standing at the centre of a meteor is the WORST place to be, not a safe
## one. Falloff is applied to `damage`, so it scales the push and the damage points with it,
## because those are the same number.
@export var falloff_over: float = 0.0

## Whether a burst catches the caster too. Scourge, Cataclysm and Pious.
##
## This is the map's own balance for a spell that hits in every direction on a three-second
## cooldown, and it is why those three are not simply better than an aimed spell: you pay for
## every cast. Note it also pushes you, which is a use rather than a cost - a self-hit near
## the rim is a way to travel.
@export var hits_caster: bool = false

## How hard a projectile drags nearby fighters toward itself, in m/s per second. Gravity.
##
## An acceleration and not a teleport, so walking out of it is possible and being caught in
## the open by one is a position problem rather than a stun.
@export var pull_force: float = 0.0

## Radius of that pull, in metres.
@export var pull_radius: float = 4.0

@export_group("Dash")
## Metres the caster is moved by a DASH cast. The landing point is clamped to the arena by
## the level, which is the only thing that knows where the edge is - a spell that could put
## you in the void would be a spell nobody ever casts.
@export var dash_distance: float = 5.0

## Whether a DASH catches whoever stands in its way. False makes it a pure escape.
##
## The hit uses the same `damage` / `push_mult` the projectiles use and goes through the same
## `_apply_hit` door, so a charge is not a second damage rule - it is a second way of reaching
## the one that already exists.
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

## Metres per second added to the caster's walking speed for `duration`. WindWalk's charge is
## a dash; this is the other half of the map's own speed buffs, and Pious hands it to allies.
@export var move_bonus: float = 0.0


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
			# A returning spell only threatens as far as its TURN, and its turn is a stated
			# distance rather than something to integrate. Measuring the whole flight would
			# draw an aim lane twice the length of the one the boomerang actually reaches, and
			# would have the bot hold a range from which it cannot connect.
			if curve_speed > 0.0:
				return curve_reach
			return _travel(lifetime)
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

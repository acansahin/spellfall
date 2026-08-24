class_name BotController
extends PlayerInputController

## An opponent that plays through the controller, not around it.
##
## It extends PlayerInputController and fills the same InputCommand a thumb fills, so the
## fighter it drives cannot tell it apart from a human: same move_dir, same aim_dir, same
## latched cast, same 60Hz consumption. That is the whole design. A bot that called
## try_cast() and wrote velocity directly could do things no player can, and every bug found
## while fighting it would live in a code path the real game never runs.
##
## Extending the player's controller rather than inventing a shared base class is the same
## trade `Player` already makes by meaning "a fighter": the parent owns the InputCommand and
## the cast latch, which is exactly what a bot needs, and renaming the type to something
## device-neutral would churn every scene, script and test for no behavioural gain. What the
## bot does NOT inherit is the device polling - `_process` is overridden to nothing, so no
## key and no finger can ever steer it.
##
## Thinking happens in _physics_process, on the fixed 60Hz tick, not in _process like the
## human's controller. A bot's reaction time is a gameplay number: it must not get sharper on
## a 144Hz desktop and duller on a 30fps phone.

## How much of Force Wave's reach the target must be inside before the bot throws one.
## Firing at the very tip of the fan is how a cone misses a target that took one step.
const CONE_TRIGGER := 0.9

## Metres past the safe line at which the bot abandons the fight and runs for the centre.
const RETURN_SPAN := 0.8

## How much of a circling drift is mixed into an approach or a retreat. Straight lines make a
## bot that reads as a machine walking a tape measure.
const STRAFE_BLEND := 0.35

## How well it plays.
##
## Difficulty is four numbers and not one of them is a stat bonus: the bot moves at the same
## speed, casts the same Fireball, takes the same knockback. It gets better by NOTICING
## sooner, aiming truer, shooting more often, and respecting the edge more. A bot that
## cheated on speed or damage would teach the player nothing about the game they are playing.
enum Skill { CALM, STEADY, SHARP }

## Per-skill numbers, in one table so the three difficulties can be compared at a glance
## instead of reconstructed from scattered branches.
##
##   reaction    seconds between glances at the target. Everything the bot knows is this
##               stale, so a slow bot genuinely mis-tracks a moving player.
##   aim_error   maximum degrees of error, re-rolled once per glance.
##   cast_gap    seconds it dawdles after the spell is ready before using it.
##   edge_margin metres from the rim it refuses to cross. A careless bot stands nearer the
##               edge, which is exactly what makes it easier to remove.
##   lead        how much of the target's velocity it aims ahead of. 0 shoots at where you
##               were, 1 at where you are going.
const PROFILES: Dictionary = {
	Skill.CALM: {"reaction": 0.50, "aim_error": 14.0, "cast_gap": 1.10, "edge_margin": 0.70, "lead": 0.0},
	Skill.STEADY: {"reaction": 0.28, "aim_error": 7.0, "cast_gap": 0.45, "edge_margin": 1.10, "lead": 0.6},
	Skill.SHARP: {"reaction": 0.12, "aim_error": 2.5, "cast_gap": 0.05, "edge_margin": 1.60, "lead": 1.0},
}

@export var skill: Skill = Skill.STEADY

## Set false to park the bot without unwiring it. The harness uses this so a suite measuring
## knockback or projectile flight has a target that stands still.
@export var enabled := true

@export_group("Positioning")
## Metres it tries to keep between itself and the target. Close enough that a 1.2s Fireball
## arrives before the player can walk out of it, far enough that the player sees it coming.
## Never further out than it can actually hit from - see `_holding_range()`.
@export var preferred_range := 5.5

## How far either side of `preferred_range` counts as close enough. Inside this band the bot
## stops closing and circles, which is what stops it oscillating on the spot.
@export var range_slack := 1.5

## Radius of the platform. Handed to the bot by the level, which reads it off the arena's own
## collision shape - a number typed in here would go stale the first time the arena resized.
@export var arena_radius := 10.0

@export_group("Movement texture")
## Seconds between reversals of the circling direction, randomised in this range.
@export var strafe_min := 0.9
@export var strafe_max := 1.8

## 0 randomises. Set it to anything else and the bot plays the same match twice, which is
## what makes a scripted run repeatable.
@export var rng_seed := 0

@export_group("Spells")
## Own instability, in percent, above which it spends Arcane Shield. Below this a shield is
## wasted on a hit that was not going to remove it anyway.
@export var shield_above := 70.0

## The fighter this drives. Set by the level, like everything else here - the controller
## never reaches into the scene to find its own body or its own enemy.
var body: Player = null

## Who it is fighting.
var target: Player = null

var _rng := RandomNumberGenerator.new()

## Everything the bot knows about the target, and how long ago it learned it.
var _seen_pos := Vector3.ZERO
var _seen_vel := Vector3.ZERO
var _has_seen := false
var _look_timer := 0.0

## Aim error in radians, re-rolled once per glance. See `_perceive` for why not per frame.
var _aim_error := 0.0

var _strafe_sign := 1.0
var _strafe_timer := 0.0
var _cast_timer := 0.0


func _ready() -> void:
	reseed(rng_seed)
	_cast_timer = _num("cast_gap")


## Restarts the random stream. The harness calls this so a scripted fight replays exactly;
## nothing in the game does. A function rather than a setter because the export is read once
## in _ready, and a test that has to work out which of the two ran has been made harder than
## it needs to be.
func reseed(value: int) -> void:
	rng_seed = value
	if value == 0:
		_rng.randomize()
	else:
		_rng.seed = value
	_strafe_sign = 1.0 if _rng.randf() < 0.5 else -1.0


## The parent polls the keyboard and the stick here. A bot must never be steered by either,
## so this override is deliberately empty. It thinks in _physics_process instead.
func _process(_delta: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(body) or not is_instance_valid(target):
		_stand_still()
		return
	# Frozen by the round system: a countdown, or a round that is already decided. Think
	# about nothing, and drop any latched cast - a request made during the countdown would
	# otherwise fire on the first live tick, before the bot had looked at anything.
	if not body.accepts_input or body.is_eliminated() or target.is_eliminated():
		_stand_still()
		consume_ability()
		_cast_timer = _num("cast_gap")
		_has_seen = false
		return

	_perceive(delta)
	var wish := _keep_inside(_steer(delta))
	# The spell is chosen BEFORE the aim, because the two are not independent: Blink is aimed
	# at safety and everything else is aimed at the enemy.
	var slot := _choose_slot()
	var aim := _aim_for(slot)
	_consider_cast(delta, slot, aim)
	_publish(wish, aim)


## Takes a fresh look at the target, at most once per `reaction` seconds. Everything below
## reads the remembered position, never the live one, so reaction time is a real handicap
## rather than a cosmetic delay.
func _perceive(delta: float) -> void:
	_look_timer -= delta
	if _has_seen and _look_timer > 0.0:
		return
	_look_timer = _num("reaction")
	_has_seen = true
	_seen_pos = target.global_position
	_seen_vel = target.velocity
	# Re-rolled on the same clock as the glance, deliberately. A fresh error every frame
	# would twitch the wizard's head, and would average out to a perfect shot over the flight
	# of a projectile. One error per glance is an aim that is WRONG, not merely noisy.
	_aim_error = deg_to_rad(_rng.randf_range(-1.0, 1.0) * _num("aim_error"))


## Where it wants to walk: hold the preferred range, and circle rather than stand.
func _steer(delta: float) -> Vector2:
	var here := _flat(body.global_position)
	var offset := _flat(_seen_pos) - here
	var gap := offset.length()
	if gap < 0.001:
		return Vector2.ZERO
	var towards := offset / gap

	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = _rng.randf_range(strafe_min, strafe_max)
		_strafe_sign = -_strafe_sign
	# Perpendicular to the line between the two of them. Circling holds the range while
	# keeping the bot a moving target, which is the difference between a sparring partner and
	# a practice cone.
	var strafe := Vector2(-towards.y, towards.x) * _strafe_sign

	var want := holding_range()
	if gap > want + range_slack:
		return (towards + strafe * STRAFE_BLEND).normalized()
	if gap < want - range_slack:
		return (-towards + strafe * STRAFE_BLEND).normalized()
	return strafe


## The rule that stops the bot beating itself. Two parts, in order.
func _keep_inside(wish: Vector2) -> Vector2:
	var here := _flat(body.global_position)
	var dist := here.length()
	var safe := safe_radius()
	if dist <= safe or dist < 0.001:
		return wish
	var outward := here / dist
	# One: never ASK to move further out. Knockback can still throw it off the arena - that
	# is the game - but it will never walk off under its own steam. Only the outward
	# component is removed, so it keeps sliding along the circle instead of stopping dead.
	var radial := wish.dot(outward)
	if radial > 0.0:
		wish -= outward * radial
	# Two: the further past the line it is, the more of its attention goes to getting back.
	# At RETURN_SPAN metres out it gives up on the fight entirely and runs for the centre.
	var urgency := clampf((dist - safe) / RETURN_SPAN, 0.0, 1.0)
	return wish.lerp(-outward, urgency).limit_length(1.0)


## Where it wants to shoot. Separate from where it wants to walk, which is the first real use
## of InputCommand's two-field aim: the bot strafes sideways while shooting at you.
func _aim() -> Vector2:
	var here := _flat(body.global_position)
	var there := _flat(_seen_pos)
	var lead := Vector2.ZERO
	var ability := _primary()
	if ability != null and ability.projectile_speed > 0.0:
		# Aim where the target is going, not where it was seen. This is the single biggest
		# difference between a bot that misses a moving player and one that does not, which
		# is why it sits on the difficulty table instead of being always on.
		var flight := here.distance_to(there) / ability.projectile_speed
		lead = _flat(_seen_vel) * flight * _num("lead")
	var to_target := (there + lead) - here
	if to_target.length_squared() < 0.0001:
		return Vector2.ZERO
	return to_target.normalized().rotated(_aim_error)


## Which button to press: a short priority list, in the order a person would think of them.
## Get back on the arena, shove off whoever is in my face, brace if I am nearly gone,
## otherwise throw a Fireball.
##
## Slots are found BY CAST TYPE rather than by index. The bot reads the spellbook it was
## given, so a wizard with a different loadout - or with only two spells - is playable by the
## same bot without a line changing here.
func _choose_slot() -> int:
	var book := body.abilities()
	if book == null:
		return -1
	var here := _flat(body.global_position)

	var dash := _slot_of(book, Ability.CastType.DASH)
	if dash >= 0 and book.is_ready(dash) and here.length() > safe_radius():
		return dash

	var cone := _slot_of(book, Ability.CastType.CONE)
	if cone >= 0 and book.is_ready(cone):
		if here.distance_to(_flat(_seen_pos)) <= book.ability_in(cone).area * CONE_TRIGGER:
			return cone

	var buff := _slot_of(book, Ability.CastType.BUFF)
	if buff >= 0 and book.is_ready(buff) and _own_instability() >= shield_above:
		return buff

	return _slot_of(book, Ability.CastType.PROJECTILE)


## Where to aim for a given spell. Blink goes towards the middle of the arena, because it is
## the escape; everything else goes at the enemy. The wizard faces its aim, so a bot that is
## running for the centre also looks like it.
func _aim_for(slot: int) -> Vector2:
	var book := body.abilities()
	if book != null and slot >= 0 and book.ability_in(slot) != null 			and book.ability_in(slot).cast_type == Ability.CastType.DASH:
		var here := _flat(body.global_position)
		if here.length() > 0.001:
			return -here.normalized()
	return _aim()


## Decides whether to press it. It presses the same latch the touch button does; whether that
## becomes a cast is still AbilityComponent's call, exactly as for a human.
func _consider_cast(delta: float, slot: int, aim: Vector2) -> void:
	var book := body.abilities()
	if book == null or slot < 0 or not book.is_ready(slot):
		return
	var ability := book.ability_in(slot)
	# A buff is cast on yourself and needs no direction. Everything else does.
	if ability.cast_type != Ability.CastType.BUFF and aim == Vector2.ZERO:
		return
	# The clock only runs while a spell is actually available, so `cast_gap` reads as "how
	# long it dawdles once it could act" rather than as a second, hidden cooldown.
	_cast_timer -= delta
	if _cast_timer > 0.0:
		return
	if ability.cast_type == Ability.CastType.PROJECTILE:
		# Do not throw a spell that expires before it arrives. Same number `holding_range()`
		# clamps against, so the bot never stands where it refuses to shoot from.
		if _flat(body.global_position).distance_to(_flat(_seen_pos)) > cast_reach():
			return
	request_ability(slot)
	_cast_timer = _num("cast_gap")


## How far out the bot actually tries to stand: its preference, clamped so that even at the
## FAR edge of its comfort band it can still land a shot.
##
## The preference and the spell's reach were independent numbers, and they drifted the moment
## the spell was retuned: the preference said 5.5m, the shot reached 4.86m, and the bot
## dutifully held a distance from which its own guard refused to fire. It stood there for a
## whole round doing nothing, and nothing in the code looked wrong.
##
## Subtracting `range_slack` is the part that took a second try. Clamping to the reach alone
## is not enough - the bot stops closing as soon as it is anywhere inside the band, which can
## still be a metre outside the range it can shoot from.
func holding_range() -> float:
	var reach := cast_reach()
	if reach <= 0.0:
		return preferred_range
	return maxf(minf(preferred_range, reach - range_slack), 1.0)


## How far a shot from this bot is allowed to be taken. The 0.9 keeps it clear of the very
## end of the projectile's life, where a target that steps back is missed by a whisker.
##
## Read by the cast guard AND by the range it holds, so the distance it stands at and the
## distance it will shoot from cannot disagree.
func cast_reach() -> float:
	var book := body.abilities() if body != null else null
	if book == null:
		return 0.0
	var slot := _slot_of(book, Ability.CastType.PROJECTILE)
	if slot < 0:
		return 0.0
	# effective_range(), not speed times lifetime: a spell with drag on it does not travel the
	# product of its two numbers, and the bot would hold a range it cannot reach.
	return book.ability_in(slot).effective_range() * 0.9


## First slot holding a spell of this type, or -1.
func _slot_of(book: AbilityComponent, cast_type: Ability.CastType) -> int:
	for slot in book.slot_count():
		var ability := book.ability_in(slot)
		if ability != null and ability.cast_type == cast_type:
			return slot
	return -1


func _own_instability() -> float:
	var inst := body.instability()
	return inst.current if inst != null else 0.0


func _publish(wish: Vector2, aim: Vector2) -> void:
	command.move_dir = wish.limit_length(1.0)
	command.has_move_input = command.move_dir.length_squared() > 0.0
	command.aim_dir = aim
	command.has_aim = aim != Vector2.ZERO
	# Mirrors the parent's own line in _process. The underscore means "not for outsiders",
	# and a subclass filling the same command is not an outsider.
	command.ability_pressed = _pending_ability
	command_updated.emit(command)


func _stand_still() -> void:
	command.move_dir = Vector2.ZERO
	command.has_move_input = false
	command.aim_dir = Vector2.ZERO
	command.has_aim = false
	command.ability_pressed = _pending_ability


## The spell it leads its aim with. The projectile's speed is what turns "where is the target
## going" into "how far ahead do I point", so a bot with no projectile simply does not lead.
func _primary() -> Ability:
	var book := body.abilities()
	if book == null:
		return null
	var slot := _slot_of(book, Ability.CastType.PROJECTILE)
	return book.ability_in(slot) if slot >= 0 else null


## One difficulty number, by name. Kept as a lookup rather than copied into fields on _ready,
## so that changing `skill` at runtime - which the harness does - takes effect immediately.
func _num(key: String) -> float:
	return float(PROFILES[skill][key])


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## The radius it will not walk past. Derived, never stored, so it cannot disagree with the
## rule `_keep_inside` actually applies.
func safe_radius() -> float:
	return maxf(1.0, arena_radius - _num("edge_margin"))


## Where it currently thinks the target is. Exposed for the harness, which has to be able to
## tell "the bot is wrong about the world" apart from "the bot is broken".
func believed_target_position() -> Vector3:
	return _seen_pos

class_name Player
extends CharacterBody3D

## A fighter. Usually the wizard the player steers.
##
## Not necessarily the human's character: the bot is this same script with a BotController
## in `input_controller` instead of a PlayerInputController, and a null controller simply
## means nobody is driving. The class is still called Player because renaming it would churn
## every scene for no behavioural gain; read it as "fighter".
##
## Movement is integrated by hand on a CharacterBody3D rather than handed to a RigidBody3D.
##
## The reason is NOT determinism. Godot's physics is floating-point and is not guaranteed to
## produce identical results across different machines, so nothing here may depend on that.
## The plan is an authoritative server with client prediction and reconciliation, which
## assumes divergence and corrects it - see ARCHITECTURE.md.
##
## The reason is that hand-integrated movement is cheap to RE-SIMULATE, which is exactly what
## reconciliation does, many times a second. Replaying a few ticks of "add to velocity, then
## move_and_slide()" is trivial. Replaying a rigid-body solver is not: its result depends on
## the whole contact island and the order bodies were processed, so rewinding one body means
## rewinding everything it touched. It also keeps the knockback rule readable in one place
## instead of buried in a solver.
##
## Everything here runs in _physics_process at the fixed 60Hz tick set in project.godot, so
## behaviour does not change with rendered framerate.

## Top ground speed in metres per second. The reference map's 210 units/s, at 128 units to
## the metre. See docs/warlock-reference.md.
##
## It was 4.0, and 6.5 before that, and both came from mapping the map's numbers across at a
## scale that was never written down - speed at 52.5 units/m while the arena was laid out at
## 140. That is the whole of "the game feels too fast": the wizard walked its ring 2.4x
## faster than the map's does. One scale now, stated in the reference doc and applied to the
## arena, the projectiles, the ranges and this.
##
## 1.641 m/s crosses the 11m arena in 13.4 seconds, which is what the map takes.
@export var move_speed := 1.641

## Metres per second per second, while under `move_speed` along the direction being asked for.
##
## The map accelerates by `IA/20` per 0.03s tick, where IA is its top speed per tick - so top
## speed arrives in twenty ticks, 0.6 seconds. It scales that by the fighter's own top speed
## over the base one, and so does this: a buffed wizard should get going in the same 0.6s,
## not spend longer ramping to a bigger number.
@export var acceleration := 2.734

## What fraction of a velocity survives one second. The map multiplies by 0.98 every 0.03s
## tick; `0.98 ^ (1/0.03)` is this.
##
## THERE IS NO BRAKING TERM. Releasing the stick does not stop the wizard - only drag does,
## and it halves the speed about once a second. That coast is the map's signature feel, and
## its own Time Shift restores your "momentum" alongside your position and health, which is
## the map saying out loud that the slide is part of the state of a fight.
##
## It governs knockback too, and that is not a shortcut: in the map a hit is added into the
## same velocity a walk is, and bleeds off the same way. One number, so a hit and a step can
## never disagree about how slippery the floor is.
##
## The closed form for "how far does this hit carry?" survives the change from the linear
## friction this used to have - it is `speed / -log(drag)` now instead of `v^2 / 2f`. See
## `Knockback.slide_distance()`, which is what --knockback-test asserts against.
@export_range(0.05, 0.99, 0.01) var drag_per_second := 0.51

## How much steering authority remains while airborne. Knocked off the edge you should
## feel committed, not able to fly back — but 0.0 removes all recovery skill.
@export_range(0.0, 1.0, 0.05) var air_control := 0.25

## Radians per second the visual turns to face its aim. Purely cosmetic; it never gates
## movement, so turning can never eat an input.
@export var turn_speed := 14.0

@export_group("Knockback")
## Seconds of reduced control per m/s of incoming knockback. A harder hit takes you out of
## the fight for longer, which is what stops a player simply walking out of every knockback
## and makes positioning matter.
@export var hitstun_per_speed := 0.030

## How much steering authority remains during hitstun. 0.0 removes all agency and feels
## terrible; this leaves enough to angle a recovery without cancelling the hit.
@export_range(0.0, 1.0, 0.05) var hitstun_control := 0.2

## Which side this fighter is on. Everyone is on their own side in a 1v1, where the numbers
## are simply 0 and 1 and nothing ever compares them.
##
## An int on the FIGHTER rather than a physics layer per team, which was the other candidate.
## A layer would let the engine filter allies for free - and would break the one thing every
## query in this project relies on: that "players" is one layer. `KillZone` masks it, `ConeCast`
## masks it, a seeker's look-ahead masks it. Four of those would have to learn about teams to
## save one comparison.
@export var team: int = 0

## Set by the level once, so the character does not reach out and find its own input.
var input_controller: PlayerInputController = null

## While false the fighter ignores steering and casting, but still falls and still takes
## knockback. That is what a countdown wants: everyone stands still, nobody is frozen in
## mid-air, and a hit landed on the last frame of the previous round still resolves.
var accepts_input := true

## Horizontal velocity the player is ASKING for, before knockback is added.
##
## Held separately rather than read back off `velocity`, because `move_and_slide()` writes
## its own result there. Reading that back as "what I was doing" folds last frame's knockback
## into this frame's input, and any reduced-authority path (hitstun, airborne) then retains a
## fraction of it and adds the knockback again on top - the hit compounds with itself and a
## single Fireball launches someone across the arena. Two accumulators, summed once, at the
## end.
var _input_velocity := Vector3.ZERO

## Velocity from being hit, kept SEPARATE from the velocity the player asks for.
##
## The reference map keeps ONE velocity and adds a hit straight into it. This port keeps two
## and sums them at the end, which is not a disagreement: both accumulators now carry the
## same drag, so the total behaves exactly as one would. What the split buys is that the
## steering path can never assign over a hit - it did once, with an instant ramp, and a
## knockback folded into `velocity` was erased on the very next frame.
##
## The one place the two must meet is the acceleration gate in `_apply_horizontal()`, which
## reads the COMBINED speed along the wished direction. That is what the map tests, and it
## is what makes steering out of a slide work.
var _knockback := Vector3.ZERO

## Seconds left of reduced control after being hit.
var _hitstun := 0.0

## Seconds left rooted. Entangle.
var _root_timer := 0.0

## Set on the frame a spell leaves and consumed by the rig on the same tick. A flag rather
## than a signal because exactly one thing reads it and it must not survive to a second frame.
var _cast_tell := false

## A flat walking-speed bonus with its own clock, separate from the one Rush banks.
##
## Two of them, because they expire differently: Rush's is tied to the shield that earned
## it and dies with it, and this one is a spell's whole payload with a duration of its own. One
## variable would make casting Pious cancel a Rush somebody was still holding.
var _move_bonus := 0.0
var _move_bonus_timer := 0.0

## What fraction of an incoming knockback gets through. 1.0 is unprotected; Shield
## drops it for a moment. Held on the fighter and not in the knockback formula because the
## formula answers "how hard was that hit" and this answers "how much of it landed on ME".
var _shield_factor := 1.0
var _shield_timer := 0.0

## Extra walking speed earned by taking hits under a converting buff, in m/s, and the two
## numbers that produced it.
##
## Held on the fighter rather than on the buff because it is a property of THIS body: the
## same spell on a heavier character would pay out the same absorbed metres per second and
## they would carry it differently. It survives the buff dropping and bleeds off with it -
## see `_drop_shield`, which is the one place a buff ends.
var _speed_bonus := 0.0
var _speed_per_absorbed := 0.0
var _speed_cap := 0.0

## A rewind in progress: where to put this fighter back, what to put the bar back to, and how
## long until it happens. Recorded at cast time, so what comes back is the state that was true
## when the button was pressed and not the state at the moment it resolves.
var _rewind_timer := 0.0
var _rewind_position := Vector3.ZERO
var _rewind_health := 0.0

var _eliminated := false

@onready var _visual: Node3D = $Visual
@onready var _rig: WizardRig = get_node_or_null(^"Visual/Body") as WizardRig

## Optional, like the spellbook. A fighter without these simply shows nothing.
@onready var _shield_visual: Node3D = get_node_or_null(^"Visual/Shield") as Node3D
@onready var _flash: SpellFlash = get_node_or_null(^"SpellFlash") as SpellFlash
@onready var _aim: AimIndicator = get_node_or_null(^"AimIndicator") as AimIndicator
@onready var _bar: HealthBar = get_node_or_null(^"HealthBar") as HealthBar

## Optional: a wizard without a spellbook simply never casts, which is what a training
## dummy or a not-yet-armed character wants.
@onready var _abilities: AbilityComponent = get_node_or_null(^"Abilities") as AbilityComponent

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _ready() -> void:
	# The fighter points its own bar at its own burn. This is internal wiring, not the class
	# reaching upward: it is the only thing that certainly knows which HealthComponent is its,
	# and doing it here means a third fighter gets a working bar by existing.
	if _bar != null:
		_bar.bind(health())


func _physics_process(delta: float) -> void:
	var wish := Vector2.ZERO
	if input_controller != null and accepts_input:
		wish = input_controller.command.move_dir

	if _hitstun > 0.0:
		_hitstun = maxf(0.0, _hitstun - delta)
	if _root_timer > 0.0:
		_root_timer = maxf(0.0, _root_timer - delta)
	if _move_bonus_timer > 0.0:
		_move_bonus_timer = maxf(0.0, _move_bonus_timer - delta)
		if _move_bonus_timer == 0.0:
			_move_bonus = 0.0
	if _shield_timer > 0.0:
		_shield_timer = maxf(0.0, _shield_timer - delta)
		if _shield_timer == 0.0:
			_drop_shield()
	if _rewind_timer > 0.0:
		_rewind_timer = maxf(0.0, _rewind_timer - delta)
		if _rewind_timer == 0.0:
			_finish_rewind()

	_apply_horizontal(wish, delta)
	# The single place the two accumulators meet. Assigned, never accumulated, so nothing
	# `move_and_slide()` left in `velocity` can leak into the next tick.
	velocity.x = _input_velocity.x + _knockback.x
	velocity.z = _input_velocity.z + _knockback.z
	velocity.y += _knockback.y
	_apply_gravity(delta)
	move_and_slide()
	_decay_knockback(delta)
	_face(delta)
	_animate_rig(delta)
	_service_casting()


## Drives `_input_velocity` toward the requested direction. Touches only the steering
## accumulator - knockback is summed in afterwards, in _physics_process.
func _apply_horizontal(wish: Vector2, delta: float) -> void:
	# One local, read three times below. `move_speed` is the fighter's own top speed and a
	# converting buff adds to it; reading the export directly in the ramp - as this did before
	# the buff existed - would accelerate toward a speed the target no longer states, and the
	# bonus would show up as a longer ramp instead of a faster walk.
	var top := move_speed + _speed_bonus + _move_bonus

	var authority := 1.0 if is_on_floor() else air_control
	if _hitstun > 0.0:
		authority = minf(authority, hitstun_control)
	# A root takes the legs, not the body. Knockback still lands, the lava still burns, and the
	# drag below still runs - so being rooted in the lava is exactly as bad as it sounds, and
	# being rooted mid-slide does not freeze you in mid-air.
	if _root_timer > 0.0:
		authority = 0.0

	if wish != Vector2.ZERO and authority > 0.0:
		var dir := Vector3(wish.x, 0.0, wish.y).normalized()
		# The map tests the speed the body ALREADY carries along the wished direction, and it
		# tests the WHOLE velocity - knockback included. That is why steering out of a slide
		# works at all: flying backwards at 10 m/s, the component along "forward" is negative,
		# so you are under the cap and you accelerate. Reading only the steering accumulator
		# here would let a wizard mid-launch accelerate as though standing still, and the hit
		# would compound with the recovery.
		var along := (_input_velocity + Vector3(_knockback.x, 0.0, _knockback.z)).dot(dir)
		if along <= top:
			# `top / move_speed` is the map's own `VE/IA`: a speed buff raises the ceiling and
			# the acceleration together, so the ramp stays 0.6s at any speed.
			var rate := acceleration * (top / move_speed) * authority * minf(wish.length(), 1.0)
			_input_velocity += dir * rate * delta

	# Drag runs whether or not anything was asked for, because there is no other way to stop.
	_input_velocity *= pow(drag_per_second, delta)
	# Exponential decay never reaches zero, and a residual 1e-30 velocity is a wizard that is
	# forever "moving" - it keeps the facing code awake and stops any is-it-still test from
	# ever firing. Snap it once it is well below anything a player could perceive.
	if _input_velocity.length_squared() < 0.0001:
		_input_velocity = Vector3.ZERO


func _apply_gravity(delta: float) -> void:
	# `velocity.y <= 0.0` matters: without it the downward pin would squash the upward lift
	# on a knockback, and every hit would grind the victim along the floor instead of
	# popping them clear of the arena lip.
	if is_on_floor() and velocity.y <= 0.0:
		# Small downward bias keeps the body pinned to the floor across slope seams so
		# is_on_floor() does not flicker, which would flicker air_control with it.
		velocity.y = -0.1
	else:
		velocity.y -= _gravity * delta


## Poses the wizard for this frame.
##
## It is handed the SPEED it is actually travelling at, knockback included, rather than what
## the thumb asked for. A wizard sliding backwards out of a hit should have its legs moving -
## it is going somewhere - and one pressing into a wall it cannot pass should not, because it
## is not. The rig knows nothing about either situation; it only ever sees a number.
func _animate_rig(delta: float) -> void:
	if _rig == null:
		return
	var travel := Vector2(velocity.x, velocity.z).length()
	_rig.animate(delta, travel, move_speed + _speed_bonus + _move_bonus, _cast_tell)
	_cast_tell = false


## Raises the staff. Called by the ability component the moment a spell leaves, so the pose
## and the bolt begin on the same frame.
func tell_cast() -> void:
	_cast_tell = true


## Recolours the wizard's cloth. One door, so the level does not have to know what a rig is
## made of - which it did when the body was a single capsule with a single material.
func set_tint(colour: Color) -> void:
	if _rig != null:
		_rig.set_tint(colour)


func _face(delta: float) -> void:
	var flat := _facing_intent()
	if flat == Vector2.ZERO:
		return
	# Godot yaw 0 faces -Z, and a yaw of `a` faces (-sin a, 0, -cos a). Solving that for the
	# travel direction is where BOTH minus signs come from - dropping them aims the wizard
	# backwards, which a screenshot caught and the position trace never would have.
	var wanted := atan2(-flat.x, -flat.y)
	_visual.rotation.y = rotate_toward(_visual.rotation.y, wanted, turn_speed * delta)


## Which way the wizard should be looking: where it is AIMING if it is aiming, otherwise
## where it is travelling.
##
## Aim wins because facing is how one fighter tells another what is about to happen. A bot
## that circles left while shooting at you must LOOK like it is shooting at you, or its
## strafe reads as a retreat and the spell that follows reads as a cheat. While aim mirrors
## movement - which is all it does for a thumb today - this changes nothing for the human;
## when drag-to-aim lands, their wizard starts reading the same way for free.
func _facing_intent() -> Vector2:
	if input_controller != null and accepts_input and input_controller.command.has_aim:
		var aim: Vector2 = input_controller.command.aim_dir
		if aim.length_squared() > 0.0001:
			return aim
	var travel := Vector2(velocity.x, velocity.z)
	# Below this the body is drifting, not travelling, and facing would jitter.
	return travel if travel.length_squared() >= 0.01 else Vector2.ZERO


## Puts the character back at a spawn point with no residual momentum. The round system
## will call this; for now the R key does, so falling off is testable immediately.
func respawn_at(point: Vector3) -> void:
	velocity = Vector3.ZERO
	_input_velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_hitstun = 0.0
	_root_timer = 0.0
	_move_bonus = 0.0
	_move_bonus_timer = 0.0
	_rewind_timer = 0.0
	_drop_shield()
	global_position = point
	var inst := instability()
	if inst != null:
		inst.reset()
	var hp := health()
	if hp != null:
		hp.reset()


## Turns a latched ability request into a cast. Casting is deliberately AFTER movement and
## facing: a spell fired on the same tick you changed direction should come out of where the
## wizard now is and where they now point, not where they were.
##
## The aim is read BEFORE the slot is consumed, not after. Consuming releases the aim that
## was latched with the cast, and reading the two in the wrong order would work today only
## because of exactly how the controller happens to clear it.
func _service_casting() -> void:
	if input_controller == null or _abilities == null:
		return
	if not accepts_input:
		# Drop anything latched while nobody may act. A press during the countdown - or a
		# click on the FIGHT button, now that the left mouse button casts - would otherwise
		# sit in the latch and come out on the first live tick, as a spell the player never
		# aimed. BotController has always done this; the human's fighter had not needed to
		# until a mouse button existed that also means "confirm".
		input_controller.consume_ability()
		return
	var command := input_controller.command
	var aim := Vector3.ZERO
	if command.has_aim:
		aim = Vector3(command.aim_dir.x, 0.0, command.aim_dir.y)
	var slot := input_controller.consume_ability()
	if slot < 0:
		return
	# A zero aim means "no direction given"; AbilityComponent falls back to facing.
	_abilities.try_cast(slot, aim)


## True if `other` fights on the same side. False for null, and false for THIS fighter - you
## are not your own ally, which is what lets a caster be excluded by one rule instead of two.
##
## Asked at hit time by the level, by the cone and by a projectile deciding whether to stop.
## Friendly fire is off, so an ally is not merely unhurt: a spell passes through them as if
## they were not standing there. Anything less makes a teammate into cover, and a teammate you
## have to walk around is worse than no teammate at all.
func is_ally_of(other: Node3D) -> bool:
	var them := other as Player
	if them == null or them == self:
		return false
	return them.team == team


## The wizard's spellbook, or null. Exposed so the level can wire casts to the projectile
## pool and the HUD can read cooldowns.
func abilities() -> AbilityComponent:
	return _abilities


## Takes a hit. `impulse` is a velocity in m/s, already scaled by the target's instability -
## see combat/knockback/knockback.gd, which is the only thing allowed to compute it.
##
## Knockback REPLACES rather than accumulates. Two hits landing a frame apart should not stack
## into a launch neither of them earned; the harder one wins, which keeps "what does this hit
## do" answerable without knowing the history of the last few frames.
func apply_knockback(impulse: Vector3) -> void:
	# The shield is applied HERE and not inside Knockback.velocity() because it belongs to
	# whoever is being hit, not to the hit. Hitstun then falls out of the reduced speed for
	# free, which is the behaviour you want: a hit you shrugged off should not pin you either.
	var arriving := impulse * _shield_factor
	_bank_absorbed(impulse, arriving)
	var flat := Vector3(arriving.x, 0.0, arriving.z)
	if flat.length() >= Vector3(_knockback.x, 0.0, _knockback.z).length():
		_knockback = arriving
	_hitstun = maxf(_hitstun, flat.length() * hitstun_per_speed)


## Takes the legs for `seconds`. Recasting keeps whichever root lasts longer.
func apply_root(seconds: float) -> void:
	_root_timer = maxf(_root_timer, seconds)


## True while rooted. For the HUD, the bot and the harness.
func is_rooted() -> bool:
	return _root_timer > 0.0


## Adds `bonus` m/s of walking speed for `seconds`. Recasting keeps the better of the two
## rather than stacking, the same rule shields and knockback use.
func grant_speed(bonus: float, seconds: float) -> void:
	if bonus <= 0.0 or seconds <= 0.0:
		return
	_move_bonus = maxf(_move_bonus, bonus)
	_move_bonus_timer = maxf(_move_bonus_timer, seconds)


## Adds an impulse to the knockback channel without replacing what is already there.
##
## `apply_knockback` REPLACES, which is right for a hit: two hits a frame apart must not
## combine into a launch neither earned. A gravity field is the opposite case - a small nudge
## applied sixty times a second - and replacing on each one would leave a fighter carrying a
## single tick's worth of pull and no accumulation at all.
func apply_pull(impulse: Vector3) -> void:
	_knockback.x += impulse.x
	_knockback.z += impulse.z


## Raises a shield: `factor` of an incoming knockback gets through, for `seconds`.
##
## Recasting REPLACES rather than stacks, keeping the stronger of the two - the same rule
## knockback itself uses, and for the same reason. Two shields multiplying into near
## invulnerability is not a mechanic anybody designed.
func apply_shield(seconds: float, factor: float,
		speed_per_absorbed: float = 0.0, speed_cap: float = 0.0) -> void:
	if _shield_timer > 0.0:
		_shield_factor = minf(_shield_factor, factor)
	else:
		_shield_factor = factor
		# A fresh buff starts the conversion from nothing. Keeping the bonus across a recast
		# would let two casts of a 3 m/s buff stack to 6, which is the same "two shields
		# multiplying into invulnerability" the paragraph above refuses.
		_speed_bonus = 0.0
	_speed_per_absorbed = speed_per_absorbed
	_speed_cap = speed_cap
	_shield_timer = maxf(_shield_timer, seconds)
	if _shield_visual != null:
		_shield_visual.visible = true


## Turns the knockback a buff just swallowed into walking speed.
##
## Reads the DIFFERENCE between what was thrown and what landed, so it is impossible for this
## to pay out without the buff actually having reduced something - and a buff with no
## conversion set simply multiplies by zero. The bonus does not decay on its own; it is what
## the fighter carries until the buff drops.
func _bank_absorbed(thrown: Vector3, landed: Vector3) -> void:
	if _speed_per_absorbed <= 0.0 or _shield_timer <= 0.0:
		return
	var absorbed := Vector2(thrown.x, thrown.z).length() - Vector2(landed.x, landed.z).length()
	if absorbed <= 0.0:
		return
	_speed_bonus = minf(_speed_bonus + absorbed * _speed_per_absorbed, _speed_cap)


func _drop_shield() -> void:
	_shield_timer = 0.0
	_shield_factor = 1.0
	_speed_bonus = 0.0
	_speed_per_absorbed = 0.0
	_speed_cap = 0.0
	if _shield_visual != null:
		_shield_visual.visible = false


## Extra walking speed currently earned, in m/s. For the HUD, the harness, and a bot deciding
## whether the buff it is holding has paid for itself.
func speed_bonus() -> float:
	return _speed_bonus


## True while a shield is up. For the HUD, for tests, and for a bot deciding whether the hit
## it is about to land is worth spending.
func is_shielded() -> bool:
	return _shield_timer > 0.0


## Moves the fighter instantly, for a DASH cast. The level decides WHERE - it is the only
## thing that knows where the arena ends.
##
## Knockback is cleared and hitstun deliberately is NOT. That is the shape of the escape: a
## Teleport cancels the slide you are in, so it can genuinely save you at an edge, but you land
## with the same reduced control the hit gave you, so it is not a free reset. If it plays too
## strong, the cooldown is the first dial to turn.
func blink_to(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	_input_velocity = Vector3.ZERO
	_knockback = Vector3.ZERO


## Starts a rewind: `seconds` from now this fighter returns to where it is standing and to
## the health it has right now.
##
## Recording at CAST time and not at resolve time is the spell. The player presses it, keeps
## fighting - or keeps running - and gets pulled back to the moment they pressed it, which is
## what makes it a decision made in advance rather than an escape pressed after the fact.
##
## Instability is not recorded and not restored. What the round has taken out of you stays
## taken; see `Ability.rewind`.
func begin_rewind(seconds: float) -> void:
	_rewind_position = global_position
	var hp := health()
	_rewind_health = hp.current if hp != null else 0.0
	_rewind_timer = maxf(seconds, 0.0)


func _finish_rewind() -> void:
	var hp := health()
	if hp != null:
		hp.restore_to(_rewind_health)
	# Through blink_to, so a rewind lands under the same rule a dash does: momentum cleared,
	# hitstun kept. A second way of moving a body without touching its velocity is a second
	# place for a fighter to arrive somewhere still carrying the slide that put them there.
	blink_to(_rewind_position)


## True while a rewind is pending. For the HUD, the harness, and a bot that should not spend
## a second escape on top of one already in flight.
func is_rewinding() -> bool:
	return _rewind_timer > 0.0


## The fighter's instant-spell flash, or null. The level plays it, because the fighter has no
## business knowing which spells exist.
func spell_flash() -> SpellFlash:
	return _flash


## The fighter's aim indicator, or null. Driven by the level for the same reason as the flash,
## and for one more: a dash's preview stops at the arena rim, and only the level knows where
## that is. Every fighter carries one; only the human's is ever shown.
func aim_indicator() -> AimIndicator:
	return _aim


func _decay_knockback(delta: float) -> void:
	if _knockback == Vector3.ZERO:
		return
	# The vertical part is handed to gravity on the frame it is applied, so only the ground
	# plane decays here. Bleeding Y as well would fight gravity and make falls float.
	_knockback.y = 0.0
	# The same drag a walk gets, because in the map it is the same velocity. See
	# `drag_per_second`.
	_knockback *= pow(drag_per_second, delta)
	if _knockback.length_squared() < 0.0001:
		_knockback = Vector3.ZERO


## True while recovering from a hit. The HUD and future VFX can read it.
func is_in_hitstun() -> bool:
	return _hitstun > 0.0


## Current knockback velocity, for tests and debug readouts.
func knockback_velocity() -> Vector3:
	return _knockback


## The fighter's instability tracker, or null if it has none.
func instability() -> InstabilityComponent:
	return get_node_or_null(^"Instability") as InstabilityComponent


## How much longer this fighter can stand in the lava, or null. Nothing in combat may touch
## it - see health_component.gd.
func health() -> HealthComponent:
	return get_node_or_null(^"Health") as HealthComponent


## Takes the fighter out of the round: no input, no physics, no collision, not drawn.
##
## Physics processing stops rather than merely being ignored, so an eliminated body cannot
## keep falling forever and cannot be hit on its way down by a spell already in flight.
func eliminate() -> void:
	if _eliminated:
		return
	_eliminated = true
	accepts_input = false
	velocity = Vector3.ZERO
	_input_velocity = Vector3.ZERO
	_knockback = Vector3.ZERO
	_hitstun = 0.0
	# A pending rewind would otherwise resolve on a body that is out of the round - and since
	# physics processing stops here, it would resolve on the NEXT round instead, teleporting a
	# fighter to where they died in the last one.
	_rewind_timer = 0.0
	visible = false
	set_physics_process(false)
	# Stop being a valid target while out. Deferred because this can be reached from inside
	# a physics callback (an Area3D body_entered), where changing collision state directly
	# is not allowed.
	set_deferred("collision_layer", 0)


## Puts the fighter back in play at `point`, fully reset.
func revive_at(point: Vector3) -> void:
	_eliminated = false
	set_physics_process(true)
	visible = true
	set_deferred("collision_layer", 2)
	accepts_input = true
	respawn_at(point)
	if _abilities != null:
		_abilities.reset()


func is_eliminated() -> bool:
	return _eliminated

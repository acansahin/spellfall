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

## Top ground speed in metres per second. The arena is 14m across, so 6.5 crosses it in
## about 2.2s — fast enough to dodge a skillshot, slow enough that position is a commitment.
@export var move_speed := 6.5

## Seconds to reach top speed from a standstill. 0.0 means instant, which is what a
## competitive brawler wants — direction changes must not feel like steering a truck.
## Raise it slightly if movement ever feels twitchy; the ramp is here so that is a tuning
## change and not a rewrite.
@export_range(0.0, 0.5, 0.01) var accel_time := 0.0

## Seconds to stop from top speed. Also 0.0 for immediate, predictable stops.
@export_range(0.0, 0.5, 0.01) var decel_time := 0.0

## How much steering authority remains while airborne. Knocked off the edge you should
## feel committed, not able to fly back — but 0.0 removes all recovery skill.
@export_range(0.0, 1.0, 0.05) var air_control := 0.25

## Radians per second the visual turns to face its aim. Purely cosmetic; it never gates
## movement, so turning can never eat an input.
@export var turn_speed := 14.0

@export_group("Knockback")
## How fast an incoming knockback bleeds off, in m/s per second.
##
## LINEAR, not exponential, and that is the important part. Linear drag means the distance a
## hit carries you has a closed form - v squared over 2f - so "how much knockback throws
## someone off a 7m arena?" is a question with an answer instead of a playtest. An
## exponential decay never quite stops, and makes the same question guesswork.
##
## This lives on the fighter, not on KnockbackRules, because it describes how THIS body
## slides. A heavier character would take the identical hit and travel less far.
@export var knockback_friction := 14.0

## Seconds of reduced control per m/s of incoming knockback. A harder hit takes you out of
## the fight for longer, which is what stops a player simply walking out of every knockback
## and makes positioning matter.
@export var hitstun_per_speed := 0.030

## How much steering authority remains during hitstun. 0.0 removes all agency and feels
## terrible; this leaves enough to angle a recovery without cancelling the hit.
@export_range(0.0, 1.0, 0.05) var hitstun_control := 0.2

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
## This is not optional bookkeeping. With accel_time at 0 the input path assigns
## `velocity.x` outright every tick, so a knockback folded into `velocity` would be erased on
## the very next frame. Holding it apart and summing at the end is what lets movement stay
## instant - which the game needs - while a hit still carries.
var _knockback := Vector3.ZERO

## Seconds left of reduced control after being hit.
var _hitstun := 0.0

## What fraction of an incoming knockback gets through. 1.0 is unprotected; Arcane Shield
## drops it for a moment. Held on the fighter and not in the knockback formula because the
## formula answers "how hard was that hit" and this answers "how much of it landed on ME".
var _shield_factor := 1.0
var _shield_timer := 0.0

var _eliminated := false

@onready var _visual: Node3D = $Visual

## Optional, like the spellbook. A fighter without these simply shows nothing.
@onready var _shield_visual: Node3D = get_node_or_null(^"Visual/Shield") as Node3D
@onready var _flash: SpellFlash = get_node_or_null(^"SpellFlash") as SpellFlash
@onready var _aim: AimIndicator = get_node_or_null(^"AimIndicator") as AimIndicator

## Optional: a wizard without a spellbook simply never casts, which is what a training
## dummy or a not-yet-armed character wants.
@onready var _abilities: AbilityComponent = get_node_or_null(^"Abilities") as AbilityComponent

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _physics_process(delta: float) -> void:
	var wish := Vector2.ZERO
	if input_controller != null and accepts_input:
		wish = input_controller.command.move_dir

	if _hitstun > 0.0:
		_hitstun = maxf(0.0, _hitstun - delta)
	if _shield_timer > 0.0:
		_shield_timer = maxf(0.0, _shield_timer - delta)
		if _shield_timer == 0.0:
			_drop_shield()

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
	_service_casting()


## Drives `_input_velocity` toward the requested direction. Touches only the steering
## accumulator - knockback is summed in afterwards, in _physics_process.
func _apply_horizontal(wish: Vector2, delta: float) -> void:
	var target := Vector3(wish.x, 0.0, wish.y) * move_speed

	var authority := 1.0 if is_on_floor() else air_control
	if _hitstun > 0.0:
		authority = minf(authority, hitstun_control)

	# Scaling the TARGET rather than blending toward the previous value keeps this
	# stateless: no authority setting can leave a residue that outlives the hitstun.
	target *= authority

	var ramp := accel_time if target.length_squared() > 0.0 else decel_time
	if ramp <= 0.0:
		_input_velocity = target
	else:
		_input_velocity = _input_velocity.move_toward(target, (move_speed / ramp) * delta)


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
	_drop_shield()
	global_position = point
	var inst := instability()
	if inst != null:
		inst.reset()


## Turns a latched ability request into a cast. Casting is deliberately AFTER movement and
## facing: a spell fired on the same tick you changed direction should come out of where the
## wizard now is and where they now point, not where they were.
##
## The aim is read BEFORE the slot is consumed, not after. Consuming releases the aim that
## was latched with the cast, and reading the two in the wrong order would work today only
## because of exactly how the controller happens to clear it.
func _service_casting() -> void:
	if input_controller == null or _abilities == null or not accepts_input:
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
	var flat := Vector3(arriving.x, 0.0, arriving.z)
	if flat.length() >= Vector3(_knockback.x, 0.0, _knockback.z).length():
		_knockback = arriving
	_hitstun = maxf(_hitstun, flat.length() * hitstun_per_speed)


## Raises a shield: `factor` of an incoming knockback gets through, for `seconds`.
##
## Recasting REPLACES rather than stacks, keeping the stronger of the two - the same rule
## knockback itself uses, and for the same reason. Two shields multiplying into near
## invulnerability is not a mechanic anybody designed.
func apply_shield(seconds: float, factor: float) -> void:
	if _shield_timer > 0.0:
		_shield_factor = minf(_shield_factor, factor)
	else:
		_shield_factor = factor
	_shield_timer = maxf(_shield_timer, seconds)
	if _shield_visual != null:
		_shield_visual.visible = true


func _drop_shield() -> void:
	_shield_timer = 0.0
	_shield_factor = 1.0
	if _shield_visual != null:
		_shield_visual.visible = false


## True while a shield is up. For the HUD, for tests, and for a bot deciding whether the hit
## it is about to land is worth spending.
func is_shielded() -> bool:
	return _shield_timer > 0.0


## Moves the fighter instantly, for a DASH cast. The level decides WHERE - it is the only
## thing that knows where the arena ends.
##
## Knockback is cleared and hitstun deliberately is NOT. That is the shape of the escape: a
## Blink cancels the slide you are in, so it can genuinely save you at an edge, but you land
## with the same reduced control the hit gave you, so it is not a free reset. If it plays too
## strong, the cooldown is the first dial to turn.
func blink_to(point: Vector3) -> void:
	global_position = point
	velocity = Vector3.ZERO
	_input_velocity = Vector3.ZERO
	_knockback = Vector3.ZERO


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
	_knockback = _knockback.move_toward(Vector3.ZERO, knockback_friction * delta)


## True while recovering from a hit. The HUD and future VFX can read it.
func is_in_hitstun() -> bool:
	return _hitstun > 0.0


## Current knockback velocity, for tests and debug readouts.
func knockback_velocity() -> Vector3:
	return _knockback


## The fighter's instability tracker, or null if it has none.
func instability() -> InstabilityComponent:
	return get_node_or_null(^"Instability") as InstabilityComponent


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

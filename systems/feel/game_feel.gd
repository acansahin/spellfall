class_name GameFeel
extends Node

## Everything the game does that is not the game: hitstop, shake, sparks, sound, haptics.
##
## One node, because these are one decision. "That hit was heavy" has to mean the same thing
## to the camera, the speaker, the phone's motor and the frame clock, and five systems each
## reading `knockback` separately is five places to disagree about what heavy is. They are
## handed a single strength here and scale off it.
##
## It is not a manager. It owns no gameplay state, decides nothing about the fight, and
## nothing reads back out of it. Every call is one-way and every one of them can be skipped
## with no consequence beyond a duller game - which is precisely what `enabled` does.
##
## `enabled = false` is not a debug leftover. Six suites measure distances and durations, and
## hitstop moves both: it scales `Engine.time_scale`, so a slide measured over a fixed number
## of ticks comes out short, and a cooldown read after a fixed wait comes out long. They turn
## the feel off in their setup, exactly as they park the bot, and `--feel-test` is where the
## feel gets to run.

## Master switch. Off means every entry point below returns immediately, and time scale is
## restored on the way out.
@export var enabled := true:
	set(value):
		enabled = value
		if not enabled:
			_end_hitstop()

@export_group("Hitstop")
## How slow the world runs during a hit. Not zero: a full freeze reads as a dropped frame,
## and on a phone that is a complaint rather than a compliment. A tenth speed still moves,
## which is what makes it read as the hit landing rather than as the game stopping.
@export_range(0.0, 1.0, 0.01) var stop_scale := 0.12

## Seconds of hitstop for the lightest hit that gets any, and for the heaviest.
##
## Both short. Hitstop is spent from the player's control: for as long as it lasts, their
## thumb does less than it should, and in a game about dodging that is a real cost. These are
## the numbers to pull DOWN first if the game ever feels sticky.
@export var stop_min := 0.035
@export var stop_max := 0.085

## Knockback speed, in m/s, at which a hit is "heavy" - full stop, full shake, the heavier
## sound. Fireball at 0% instability lands around 6.7 m/s, so this sits just above a clean
## opening hit and is reached by Force Wave, or by anything landing on a destabilised target.
@export var heavy_speed := 9.0

@export_group("Shake")
## Shake for a hit at `heavy_speed`, 0..1.
@export_range(0.0, 1.0, 0.05) var shake_on_hit := 0.55

## What a hit on someone ELSE is worth, as a fraction of a hit on you.
##
## Not zero and not one. The camera is the room, so an impact anywhere in it should register;
## but the shake is also the game flinching on your behalf, and it should say plainly which
## of you got hit.
@export_range(0.0, 1.0, 0.05) var shake_on_others := 0.55

@export_group("Haptics")
## Milliseconds of vibration for a light and a heavy hit.
@export var buzz_light := 18
@export var buzz_heavy := 45

## Handed over by the level, all optional. A missing one is simply a thing that does not
## happen - the feel layer must never be the reason a scene fails to run.
var camera: ArenaCamera = null
var sounds: SoundBank = null
var sparks: ImpactBurst = null
var streak: GroundStreak = null

## When the hitstop ends, in engine milliseconds.
##
## A deadline in REAL time, not a countdown in delta. `_process`'s delta is itself scaled by
## `Engine.time_scale`, so counting a hitstop down with it means the hitstop is timing itself
## with the clock it slowed - which stretches by exactly the factor it applied and comes out
## eight times too long.
var _resume_at := 0


func _process(_delta: float) -> void:
	if _resume_at > 0 and Time.get_ticks_msec() >= _resume_at:
		_end_hitstop()


func _exit_tree() -> void:
	# Leaving a scene mid-hitstop must not leave the engine slowed for whatever loads next.
	_end_hitstop()


# ---------------------------------------------------------------------------------------
# What happened
#
# Each of these is one event in the fight, translated into every channel at once. The level
# calls them from the same places it already prints its log lines, which is deliberate: those
# lines mark the moments the game considers worth reporting, and this is that list made
# audible.
# ---------------------------------------------------------------------------------------

## Somebody got hit. `speed` is the knockback in m/s, which is the game's own measure of how
## hard - already scaled by instability and already reduced by a shield, so a shrugged-off hit
## correctly feels like one.
func hit(at: Vector3, tint: Color, speed: float, on_player: bool) -> void:
	if not enabled:
		return
	var weight := clampf(speed / maxf(heavy_speed, 0.01), 0.0, 1.0)
	var heavy := weight >= 0.999
	if sparks != null:
		sparks.burst(at, tint, speed)
	if sounds != null:
		sounds.play(&"heavy" if heavy else &"hit")
	if camera != null:
		var strength := shake_on_hit * weight
		if not on_player:
			strength *= shake_on_others
		camera.shake(strength)
	_hitstop(lerpf(stop_min, stop_max, weight))
	if on_player:
		_buzz(buzz_heavy if heavy else buzz_light)


## A spell went off. Sound only: the cast already has a fan, a lane or a projectile to look
## at, and a screen shake on something you did every 0.9 seconds is noise.
func cast(ability: Ability, by_player: bool) -> void:
	if not enabled or sounds == null:
		return
	match ability.cast_type:
		Ability.CastType.DASH:
			sounds.play(&"blink")
		Ability.CastType.BUFF:
			sounds.play(&"shield")
		_:
			sounds.play(&"cast")
	if by_player and ability.cast_type == Ability.CastType.DASH:
		_buzz(12)


## A dash happened: draw the line it took.
func dashed(from: Vector3, to: Vector3, tint: Color) -> void:
	if not enabled or streak == null:
		return
	streak.play(from, to, tint)


## Somebody went over the edge.
func eliminated(at: Vector3, was_player: bool) -> void:
	if not enabled:
		return
	if sounds != null:
		sounds.play(&"fall", 0.03)
	if sparks != null:
		sparks.burst(at, Color(0.75, 0.8, 1.0), 6.0)
	if camera != null:
		camera.shake(0.4)
	if was_player:
		_buzz(70)


## The countdown ticked. `remaining` of 0 is "GO".
func countdown(remaining: int) -> void:
	if not enabled or sounds == null:
		return
	if remaining <= 0:
		sounds.play(&"go", 0.0)
	else:
		sounds.play(&"tick", 0.0)


## A round or a match ended.
func round_over(player_won: bool) -> void:
	if not enabled or sounds == null:
		return
	sounds.play(&"win" if player_won else &"lose", 0.0)


# ---------------------------------------------------------------------------------------
# Channels
# ---------------------------------------------------------------------------------------

## Slows the whole engine for a moment.
##
## `Engine.time_scale` rather than a per-node pause, because a hit that stops the victim but
## not the projectile that caused it looks broken. Everything stops together, briefly, and
## nothing in the game has to know it happened.
func _hitstop(seconds: float) -> void:
	if seconds <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	# A second hit inside a hitstop extends it rather than restarting it, so a combo lands as
	# one long beat rather than as a stutter.
	_resume_at = maxi(_resume_at, until)
	Engine.time_scale = stop_scale


func _end_hitstop() -> void:
	_resume_at = 0
	Engine.time_scale = 1.0


## Buzzes the handset. Guarded on the feature rather than on the platform name, and a no-op
## everywhere else - `vibrate_handheld` does nothing on desktop, but the guard says out loud
## that this is a phone-only channel rather than leaving it to be discovered.
func _buzz(milliseconds: int) -> void:
	if not OS.has_feature("mobile"):
		return
	Input.vibrate_handheld(milliseconds)


## True while the world is slowed. For the harness.
func is_stopped() -> bool:
	return _resume_at > 0

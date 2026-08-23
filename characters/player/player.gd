class_name Player
extends CharacterBody3D

## The wizard the player steers.
##
## Movement is integrated by hand on a CharacterBody3D rather than handed to a RigidBody3D.
## That is deliberate and load-bearing: knockback is the centrepiece mechanic of this game
## and it has to be reproducible frame-for-frame on a server that never rendered anything.
## Rigid-body solvers are tuned for plausible-looking contacts, not for "the same hit always
## sends you the same distance", and they resolve differently depending on how many bodies
## are touching. Everything here runs in _physics_process at the fixed 60Hz tick set in
## project.godot, so behaviour does not change with rendered framerate.

## Top ground speed in metres per second. The arena is 14m across, so 6.5 crosses it in
## about 2.2s — fast enough to dodge a skillshot, slow enough that position is a commitment.
@export var move_speed := 6.5

## Seconds to reach top speed from a standstill. 0.0 means instant, which is what a
## competitive brawler wants â€” direction changes must not feel like steering a truck.
## Raise it slightly if movement ever feels twitchy; the ramp is here so that is a tuning
## change and not a rewrite.
@export_range(0.0, 0.5, 0.01) var accel_time := 0.0

## Seconds to stop from top speed. Also 0.0 for immediate, predictable stops.
@export_range(0.0, 0.5, 0.01) var decel_time := 0.0

## How much steering authority remains while airborne. Knocked off the edge you should
## feel committed, not able to fly back â€” but 0.0 removes all recovery skill.
@export_range(0.0, 1.0, 0.05) var air_control := 0.25

## Radians per second the visual turns to face travel. Purely cosmetic; it never gates
## movement, so turning can never eat an input.
@export var turn_speed := 14.0

## Set by the level once, so the character does not reach out and find its own input.
var input_controller: PlayerInputController = null

@onready var _visual: Node3D = $Visual

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)


func _physics_process(delta: float) -> void:
	var wish := Vector2.ZERO
	if input_controller != null:
		wish = input_controller.command.move_dir

	_apply_horizontal(wish, delta)
	_apply_gravity(delta)
	move_and_slide()
	_face_travel(delta)


## Drives the XZ plane toward the requested direction. Knockback will later add its own
## velocity here before this runs, which is why the target is computed and blended rather
## than assigned straight onto `velocity`.
func _apply_horizontal(wish: Vector2, delta: float) -> void:
	var target := Vector3(wish.x, 0.0, wish.y) * move_speed
	var current := Vector3(velocity.x, 0.0, velocity.z)

	var authority := 1.0 if is_on_floor() else air_control
	if authority <= 0.0:
		return

	var ramp := accel_time if target.length_squared() > 0.0 else decel_time
	var next: Vector3
	if ramp <= 0.0:
		next = target
	else:
		next = current.move_toward(target, (move_speed / ramp) * delta)

	if authority < 1.0:
		next = current.lerp(next, authority)

	velocity.x = next.x
	velocity.z = next.z


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		# Small downward bias keeps the body pinned to the floor across slope seams so
		# is_on_floor() does not flicker, which would flicker air_control with it.
		velocity.y = -0.1
	else:
		velocity.y -= _gravity * delta


func _face_travel(delta: float) -> void:
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length_squared() < 0.01:
		return
	# Godot yaw 0 faces -Z, and a yaw of `a` faces (-sin a, 0, -cos a). Solving that for the
	# travel direction is where BOTH minus signs come from - dropping them aims the wizard
	# backwards, which a screenshot caught and the position trace never would have.
	var wanted := atan2(-flat.x, -flat.y)
	_visual.rotation.y = rotate_toward(_visual.rotation.y, wanted, turn_speed * delta)


## Puts the character back at a spawn point with no residual momentum. The round system
## will call this; for now the R key does, so falling off is testable immediately.
func respawn_at(point: Vector3) -> void:
	velocity = Vector3.ZERO
	global_position = point

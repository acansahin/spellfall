class_name InputCommand
extends RefCounted

## One frame of player intent, in WORLD space.
##
## This is the contract between "how the player touched the device" and "what the
## character does". The keyboard, the virtual joystick and (later) a replayed network
## input stream all fill this same object, so no gameplay code ever branches on input
## device. Keep it plain data — no logic, no node references.

## Desired movement direction on the ground plane, already rotated out of screen space
## into world space by PlayerInputController. Length is 0.0 to 1.0, where 1.0 means
## "full speed"; an analogue joystick pushed halfway gives 0.5.
## x maps to world +X, y maps to world +Z.
var move_dir := Vector2.ZERO

## True while the player is actively steering. Lets a character distinguish
## "deliberately standing still" from "no input at all" (e.g. bot handoff, disconnect).
var has_move_input := false

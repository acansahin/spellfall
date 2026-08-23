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

## Where the player wants to aim, same world-space convention as `move_dir`.
##
## Today this simply mirrors `move_dir` - you cast where you are heading. Drag-to-aim will
## fill it from a second thumb instead, and NOTHING downstream changes when it does: the
## character already reads this field rather than asking how it was produced. That is the
## entire reason it exists as a separate field instead of the caster reading `move_dir`.
var aim_dir := Vector2.ZERO

## False when no aim was given, in which case a caster should use its own facing rather than
## firing at whatever direction happened to be left over.
var has_aim := false

## Ability slot the player asked for, or -1.
##
## LATCHED, not sampled. Input is read in _process (render rate) while characters act in
## _physics_process (fixed 60Hz), so a press read as "just happened" can be missed entirely
## if two render frames land between ticks, or acted on twice if two ticks land between
## frames. The controller holds the request until someone calls `consume_ability()`, which
## makes a tap exactly one cast. Read this field freely for UI; consuming is what casts.
var ability_pressed := -1

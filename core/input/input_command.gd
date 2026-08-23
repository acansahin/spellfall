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
## Filled by whichever of three things is currently speaking: a finger dragging off a spell
## button, the latched aim of a cast that has been released but not yet consumed, or - when
## neither is happening - `move_dir`, so you still cast where you are heading. The character
## reads this field and never asks which of the three produced it, which is why drag-to-aim
## landed without a single line changing downstream of here.
var aim_dir := Vector2.ZERO

## False when no aim was given, in which case a caster should use its own facing rather than
## firing at whatever direction happened to be left over.
var has_aim := false

## Slot the player is currently AIMING - a finger is down on its button and has not lifted -
## or -1. Distinct from `ability_pressed`, which is a cast that has already been asked for:
## this one is "a spell is being pointed", which is what the aim indicator draws and what
## the button draws its nub for. Nothing casts from this field.
var aiming_slot := -1

## Ability slot the player asked for, or -1.
##
## LATCHED, not sampled. Input is read in _process (render rate) while characters act in
## _physics_process (fixed 60Hz), so a press read as "just happened" can be missed entirely
## if two render frames land between ticks, or acted on twice if two ticks land between
## frames. The controller holds the request until someone calls `consume_ability()`, which
## makes a tap exactly one cast. Read this field freely for UI; consuming is what casts.
var ability_pressed := -1

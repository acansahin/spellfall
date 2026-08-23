extends Node3D

## Level wiring for the movement prototype, plus the scripted-run harness.
##
## Nothing here is a "GameManager". It connects the input controller to the character and
## nothing else; the round system, spawning and combat get their own nodes when they land.
##
## HARNESS (everything after a bare `--` on the command line):
##   --shot            save one drawn frame to user://shot.png and print the path
##   --shot:N          same, but N seconds in, landing in user://shot_N.png (repeatable)
##   --move=X,Y        steer the player with a constant stick vector, no input events
##   --trace           print the player's position once a second
## Screenshots need real rendering, so DO NOT pass --headless with --shot.

## Where the player is put on start and after falling off.
@export var spawn_point := Vector3(0.0, 1.2, 3.5)

## Falling below this counts as off the arena. The real elimination system replaces this.
@export var fall_limit := -10.0

@onready var _player: Player = $Player
@onready var _input: PlayerInputController = $PlayerInputController

var _trace := false


func _ready() -> void:
	# The character is handed its input source rather than reaching out for one, so a bot
	# or a network replay can be substituted without the character noticing.
	_player.input_controller = _input
	_player.respawn_at(spawn_point)
	_parse_harness_args()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("debug_respawn"):
		_player.respawn_at(spawn_point)
	if _player.global_position.y < fall_limit:
		print("[fall] player left the arena at %.1f,%.1f" % [
			_player.global_position.x, _player.global_position.z
		])
		_player.respawn_at(spawn_point)


func _parse_harness_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--move="):
			var parts := arg.substr(7).split(",")
			if parts.size() == 2:
				var v := Vector2(float(parts[0]), float(parts[1]))
				_input.set_override_vector(v, true)
				print("[harness] steering override %s" % v)
		elif arg == "--trace":
			_trace = true
			_run_trace()
		elif arg == "--shot":
			_shoot("user://shot.png", 0.0)
		elif arg.begins_with("--shot:"):
			var secs := float(arg.substr(7))
			_shoot("user://shot_%d.png" % int(secs), secs)


func _run_trace() -> void:
	while _trace and is_inside_tree():
		await get_tree().create_timer(1.0).timeout
		if not is_instance_valid(_player):
			return
		print("[trace] pos=(%.2f, %.2f, %.2f) vel=(%.2f, %.2f, %.2f)" % [
			_player.global_position.x, _player.global_position.y, _player.global_position.z,
			_player.velocity.x, _player.velocity.y, _player.velocity.z,
		])


func _shoot(path: String, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# The viewport texture only holds a complete frame after the draw pass, so grabbing it
	# any earlier returns the previous frame or an empty image.
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err != OK:
		push_error("screenshot failed: %s" % err)
		return
	print("[shot] %s -> %s" % [path, ProjectSettings.globalize_path(path)])

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
##   --touch-ui:on|off force the mobile controls visible or hidden, whatever the device
##   --touch-test      inject a scripted multi-touch sequence and assert the results
##   --key-test        inject key presses and assert the keyboard path still drives movement
##   --cast-test       assert the full cast round-trip: cooldown, pooling, flight, impact
##   --twothumb-test   hold the stick and the cast button at once, on separate fingers
##   --knockback-test  assert the instability curve and the distance a hit carries
##   --round-test      assert a full round cycle: countdown, elimination, score, reset
##   --bot-test        assert the bot: range, aim, facing, edge safety, difficulty, fairness
##   --bot:off         park the bot, for a screenshot or a suite measuring something else
##   --bot-skill:S     play against calm|steady|sharp instead of the scene's setting
##   --spells-test     assert Scourge, Teleport and Shield do what they claim
##   --loadout-test    assert the catalogue, the picks, the screen, and each added spell's rule
##   --2v2             two a side: you and a bot ally against two bots
##   --pc-test         assert the desk controls: right click to walk, Q W E R to arm, left
##                     click to send, and a ward that needs no click. Needs a real window
##   --team-test       assert the sides, friendly fire, re-targeting, and what ends a round
##                     (implies --2v2; it has nothing to measure in a duel)
##   --loadout:on      open the spell-picking screen even though other harness args were given
##   --loadout:off     skip it (the default whenever ANY user arg is passed)
##   --loadout:a,b,c   arm the player with these spell ids
##   --wipe-loadout    forget the stored picks, so the next PLAIN launch opens with nothing set
## Any user argument at all puts the run on the DEFAULT loadout - the stored one belongs to
## the player, and a suite inheriting it measures a different wizard every day.
##   --button-test     assert a finger on button N casts spell N and nothing else
##   --aim-test        assert drag-to-aim: the indicator, the direction, and the latch
##   --aim-hold:S,X,Y  hold a drag on button S toward X,Y and never lift, for a screenshot
##   --lava-test       assert the lava burns, stone stops it, ends a round, and is survivable
##   --shrink-test     assert the ring holds, closes, stops, drags cover and camera with it
##   --burn-pose       park the player in the lava, so a shot catches the bar draining
##   --bolt-pose       fan every projectile spell out from the centre, again and again, so a
##                     delayed --shot photographs all five shapes at once
##   --cover-test      assert the obstacles block spells, block walking, and are fair
##                     (every OTHER suite clears the obstacles first - see _clear_cover)
##   --feel-test       assert hitstop, shake, sparks, sound and the dash streak all fire
##   --feel:off        park the game feel, for a suite that measures distance or duration
##   --cast-at:N[,S]   cast spell S (default 0) N seconds in, so a delayed shot catches it
## Screenshots need real rendering, so DO NOT pass --headless with --shot.
## The two input tests ALSO need a real window: the headless display driver does not
## route injected InputEventScreenTouch/Key to _input(), so every assertion silently
## reads zero and the run reports failures that say nothing about the code.

## Where the player is put on start. Half the arena's STARTING radius out, so the opening gap
## is wider than Fireball's reach - which is what makes the first move of a round a decision
## rather than a race to click.
@export var spawn_point := Vector3(0.0, 1.2, 6.0)

## Where the bot stands. Directly opposite the player, so neither side opens the round
## nearer the edge than the other.
@export var bot_spawn := Vector3(0.0, 1.2, -6.0)

## How a hit is turned into speed. A Resource so the central mechanic is tuned by editing
## data, never by editing logic - see combat/knockback/knockback_rules.gd.
@export var knockback_rules: KnockbackRules = null

## Every spell in the game, and the choice the player is offered before a match. Null simply
## means "leave the wizards with whatever their scenes gave them", which is what keeps this
## level runnable with the catalogue unassigned.
@export var catalogue: SpellCatalogue = null

## The wizard a team match spawns for the ally and the second opponent. The scene's own
## BotWizard is not reused as a template: instancing a PackedScene is the one way to get a
## fighter with its own components, and duplicating a live node copies its current state too.
@export var bot_scene: PackedScene = null

@onready var _player: Player = $Player
@onready var _input: PlayerInputController = $PlayerInputController
@onready var _mobile: MobileControls = $MobileControls
@onready var _pool: ProjectilePool = $ProjectilePool
@onready var _bot: Player = $BotWizard
@onready var _brain: BotController = $BotController
@onready var _hud: Hud = $Hud
@onready var _rounds: RoundManager = $Rounds
@onready var _arena: Arena = $Arena
@onready var _kill_zone: KillZone = $Arena/KillZone
@onready var _obstacles: Node3D = $Arena/Obstacles
@onready var _camera_rig: ArenaCamera = $CameraRig
@onready var _feel: GameFeel = $Feel
@onready var _loadout: LoadoutScreen = $LoadoutScreen
@onready var _move_marker: MoveMarker = $MoveMarker

var _trace := false

## What the player picked, one index per column. Held so a rematch, the save and the harness
## all read one answer rather than each asking the screen again.
var _picks := PackedInt32Array()

## Whether this run opens the spell-picking screen. False for every harness run: a dozen suites
## begin by awaiting a live round, and a menu waiting on a human would hang all of them.
var _show_loadout := false

## Two a side instead of one. Chosen on the loadout screen, or forced with `--2v2`.
var _team_match := false

## True once the roster has been registered. The screen can be driven a second time by a suite,
## and a second registration is silent, permanent and fatal to the round loop.
var _squad_formed := false

## Every wizard on the stone, in registration order: the player first, then their ally if
## there is one, then the opposition. Built by `_form_squad` and read by everything that used
## to say `[_player, _bot]` - the lava, the combat wiring, the round roster.
var _fighters: Array[Player] = []

## Live tethers: one entry per victim, `{caster, ability, left}`. Link, and nothing else yet.
##
## Keyed by the VICTIM rather than by the caster, because the rule is about them: a second
## link landing on somebody already tethered refreshes the one they are carrying instead of
## bleeding them twice. Two casters can each tether a different wizard; neither can stack.
var _tethers: Dictionary = {}

## One per bot fighter, parallel to the bots in `_fighters`. The scene's own `_brain` is the
## first of them; the rest are made at runtime.
var _brains: Array[BotController] = []

## Where each fighter starts and what the HUD calls them, keyed by the fighter. Dictionaries
## rather than two more parallel arrays: every reader here already holds the Player and wants
## one fact about it, and a parallel array is a second list to keep in step.
var _spawns: Dictionary = {}
var _titles: Dictionary = {}

## Metres either side of a spawn point that teammates stand, in a team match. Wide enough that
## a Scourge aimed at one does not automatically catch the other on the opening exchange.
const TEAM_SPREAD := 2.6

## Metres from a walk order at which it counts as reached. Roughly a body's width: closer than
## this and the wizard shuffles on the spot, because the ramp cannot stop it that precisely.
const ARRIVAL_RADIUS := 0.45

## Where a right click sent the wizard, and whether one stands.
var _move_target := Vector3.ZERO
var _move_target_set := false

## Body colours, so four wizards are two readable sides. The player keeps `player.tscn`'s blue
## and the scene bot keeps its pink; these are the two that are made at runtime.
## COOL IS A FRIEND, WARM IS A FOE - the whole rule, and it has to survive a glance at four
## capsules from this camera's height.
##
## The ally is a green-teal and NOT the cyan that was tried second. Cyan is the same family as
## the player's blue, which is exactly what the rule asks for and exactly one step too far: the
## screenshot came back with two blue wizards and no way to tell which one was me. Reading your
## own side matters, and finding yourself matters more.
const ALLY_TINT := Color(0.36, 0.82, 0.62)
const SECOND_FOE_TINT := Color(0.95, 0.42, 0.20)

## The platform's radius, measured once in _ready. Teleport clamps against it and the bot is
## handed it; nothing else in the level needs to know the arena has a size.
var _arena_edge := 7.0

## How far inside the rim a Teleport is allowed to land. Enough that you arrive ON the platform
## rather than on its lip, where the next breath of knockback removes you anyway.
const BLINK_EDGE_MARGIN := 0.6

## The direction the last cast actually went out with, and which spell it was.
##
## Recorded for the harness alone. "Did it cast?" is easy to assert and answers half the
## question; drag-to-aim needs the other half - that the spell left along the line the thumb
## drew - and this is the one place every cast type passes through on its way to happening.
var _last_cast_dir := Vector3.ZERO
var _last_cast_id: StringName = &""


func _ready() -> void:
	# The character is handed its input source rather than reaching out for one, so a bot
	# or a network replay can be substituted without the character noticing.
	_player.input_controller = _input
	# ...and here is that substitution made good. The bot's fighter takes a BotController
	# where the human's takes a PlayerInputController, and player.gd holds not one line that
	# knows which of the two it got.
	_bot.input_controller = _brain
	_brain.body = _bot
	_brain.target = _player
	_wire_feel()
	_arena.radius_changed.connect(_on_arena_resized)
	_on_arena_resized(_arena.radius)
	# The stick is a dumb widget that reports where a thumb is; this single line is what
	# gives its output a meaning. Wiring it here rather than inside either node keeps the
	# stick reusable and keeps PlayerInputController unaware that a UI exists - the same
	# hand-it-its-dependencies pattern already used for the character above.
	_mobile.joystick.vector_changed.connect(_input.set_touch_vector)
	# A run with ANY user argument starts from the DEFAULT loadout, never the stored one. A suite
	# that inherited whatever the last play session picked would measure a different wizard every
	# day - and it did: `--aim-test` went looking for a cone slot, found a stored loadout that had
	# none, and crashed on a null. The stored picks are for the player, and the player is who
	# launches with no arguments at all.
	_show_loadout = OS.get_cmdline_user_args().is_empty()
	_report_input_mode()
	_picks = LoadoutStore.load_picks(catalogue) if _show_loadout else _default_picks()
	_team_match = LoadoutStore.load_mode() if _show_loadout else false
	_arm_fighters(false)
	_parse_harness_args()
	if _show_loadout:
		# The squad is NOT formed yet. How many wizards stand on the stone is a thing the
		# player is about to choose, and every wiring step below - the spellbooks, the HUD
		# rows, the round system's roster - depends on the answer.
		_open_loadout()
	else:
		_begin_match(_team_match)


func _process(_delta: float) -> void:
	_feed_pointer_aim()
	_update_aim_indicator()


func _physics_process(delta: float) -> void:
	if _rounds.is_live():
		_arena.tick(delta)
	_tick_lava(delta)
	_tick_tethers(delta)


## Bleeds whoever is on the end of a link.
##
## Health only - no push and no damage points. A tether that shoved would be a spell you could
## not walk out of AND could not survive standing still, and the map's own is a slow bleed you
## are supposed to be able to ignore for a while.
func _tick_tethers(delta: float) -> void:
	if _tethers.is_empty():
		return
	for victim in _tethers.keys():
		var entry: Dictionary = _tethers[victim]
		var fighter := victim as Player
		entry["left"] = float(entry["left"]) - delta
		if fighter == null or not is_instance_valid(fighter) or float(entry["left"]) <= 0.0:
			_tethers.erase(victim)
			continue
		var hp := fighter.health()
		if hp == null or not hp.is_alive():
			_tethers.erase(victim)
			continue
		hp.damage(float(entry["dps"]) * delta)


## Burns whoever is off the stone. Standing on it only stops the bleeding - it does not
## reverse it.
##
## A radius test rather than an Area3D. The arena is a circle and every other rule in this
## file already knows it - Teleport clamps against it, the bot keeps clear of it, the aim lane
## stops at it - so a fifth way of asking "am I inside the ring" would be a fifth thing to
## keep in step. It is also two floats of work per fighter per tick.
##
## Only while the round is live. Between rounds the fighters stand where the countdown put
## them, and burning through the interlude would be a fine way to lose a round you have not
## started yet.
func _tick_lava(delta: float) -> void:
	if not _rounds.is_live():
		return
	for fighter in _fighters:
		if fighter == null or fighter.is_eliminated():
			continue
		var hp := fighter.health()
		if hp == null or not hp.is_alive():
			continue
		# Stone no longer mends. A trip into the lava, or a hit that drains health directly,
		# costs something for the rest of the round - reset() between rounds is the only way
		# back to full, which is what makes the total a budget rather than a bar that refills
		# between exchanges.
		if _radius_of(fighter.global_position) > _arena_edge:
			hp.burn(delta)
			_feel.burning(fighter.global_position, fighter == _player, delta)


## How far the camera stands back, as a multiple of the radius. 3.14 is what the framing that
## was solved at radius 7 and distance 22 worked out to, and holding it while the ring closes
## means the fight is framed the same at every size - so the wizard grows on screen exactly as
## the round gets tighter, which is the one moment readability matters most.
const CAMERA_FRAMING := 3.14

## The camera stops coming in once the ring closes past this radius, even though the ring
## itself keeps shrinking to `Arena.min_radius`. Framing the last few metres as tightly as the
## rest would zoom the camera in far enough to crowd the fight rather than clarify it - the
## squeeze is meant to be felt as the RING closing around two wizards who stay a readable size,
## not as the camera lunging at them.
const CAMERA_FLOOR_RADIUS := 6.5

## How much of the ring's shrink the camera actually follows. 0 pins it; 1 frames every size
## identically.
##
## It was effectively 1, and that was too much to look at. From an 11m ring down to the camera
## floor the lens travelled 34.5m to 20.4m - a 41% zoom, which grows the wizard by 69% on
## screen over about twenty seconds. What that reads as is not "the ring is closing"; it reads
## as the character inflating while the island under them shrinks, and the two moving in
## opposite directions is what looks wrong.
##
## At 0.25 the same close moves the lens 34.5m to 31.0m and grows the wizard 11%, which is
## slow enough not to be seen happening. **The ring still shrinks by the same amount** - the
## squeeze is now entirely in the geometry, where it belongs, and the wizard stays the size
## the framing was solved for.
##
## Set it to 0.0 for a lens that never moves at all. `--shrink-test` asserts the travel stays
## under a fifth of the opening distance, so raising this back toward 1 is a decision somebody
## has to make on purpose.
const CAMERA_SHRINK_FOLLOW := 0.25


## Points everything that needs a radius at the radius the arena currently has.
##
## Five things read it and it is now a moving value, so it arrives by signal rather than being
## copied at startup. A stale copy would put the bot's idea of the edge, the lava's idea of it
## and the drawn rim in three different places.
func _on_arena_resized(value: float) -> void:
	_arena_edge = value
	if _brain != null:
		_brain.arena_radius = value
	if _camera_rig != null:
		_camera_rig.distance = _camera_distance_for(value)


## Where the lens stands for a ring of this radius.
##
## Blended between the framing the round OPENED at and the framing this radius would ask for,
## so the camera moves a fraction of the way rather than all of it. See
## `CAMERA_SHRINK_FOLLOW`; the opening distance is read off `start_radius` rather than cached,
## so a retuned arena cannot leave a stale number here.
func _camera_distance_for(value: float) -> float:
	var framed := maxf(value, CAMERA_FLOOR_RADIUS) * CAMERA_FRAMING
	var opening := maxf(_arena.start_radius, CAMERA_FLOOR_RADIUS) * CAMERA_FRAMING
	return lerpf(opening, framed, CAMERA_SHRINK_FOLLOW)


func _parse_harness_args() -> void:
	# `_show_loadout` is already decided in `_ready` - a script is driving whenever there is an
	# argument at all, and a script must never be handed a menu. `--loadout:on` below is how a
	# screenshot run asks for one anyway.
	# Settings first: --touch-test needs the stick already shown and laid out, and a suite
	# that reads a bot number must read the one the run asked for.
	for arg in OS.get_cmdline_user_args():
		if arg == "--touch-ui:on":
			_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
		elif arg == "--touch-ui:off":
			_mobile.visibility_mode = MobileControls.Visibility.HIDDEN
		elif arg == "--bot:off":
			_freeze_bot()
			print("[harness] bot parked")
		elif arg == "--feel:off":
			_quiet_feel()
		elif arg == "--wipe-loadout":
			# Only deletes the file. This run is already on the defaults - see `_ready` - so what
			# this is for is the NEXT plain launch, which must open the menu with nothing chosen.
			LoadoutStore.clear()
			print("[harness] stored loadout forgotten")
		elif arg == "--2v2" or arg == "--team-test":
			# The suite implies the mode. Asked for in the settings pass, which runs BEFORE the
			# suites start, so the squad is already four by the time one awaits a live round.
			_team_match = true
			print("[harness] two a side")
		elif arg == "--loadout:on":
			_show_loadout = true
		elif arg == "--loadout:off":
			_show_loadout = false
		elif arg.begins_with("--loadout:"):
			# The two exact spellings above are tested FIRST, or "--loadout:off" would be read
			# as a request for a spell called "off" and silently leave the loadout at default.
			# Ten characters in the prefix - counted, see ARCHITECTURE.md on --cast-at.
			if catalogue != null:
				_picks = catalogue.picks_from_ids(arg.substr(10).split(","))
				_arm_fighters(false)
				print("[harness] loadout %s" % str(catalogue.ids_from_picks(_picks)))
		elif arg.begins_with("--bot-skill:"):
			# Twelve characters. Counted, not guessed - see ARCHITECTURE.md on --cast-at.
			_set_bot_skill(arg.substr(12))
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
			# Name from the raw argument, not int(seconds): --shot:1.05 and --shot:1.85 both
			# rounded to "shot_1.png" and silently overwrote each other, so a run that asked
			# for three frames quietly produced one.
			var label := arg.substr(7).replace(".", "_")
			_shoot("user://shot_%s.png" % label, float(arg.substr(7)))
		elif arg == "--touch-test":
			_run_touch_tests()
		elif arg == "--key-test":
			_run_key_tests()
		elif arg == "--cast-test":
			_run_cast_tests()
		elif arg == "--twothumb-test":
			_run_two_thumb_tests()
		elif arg == "--knockback-test":
			_run_knockback_tests()
		elif arg == "--round-test":
			_run_round_tests()
		elif arg == "--bot-test":
			_run_bot_tests()
		elif arg == "--spells-test":
			_run_spell_tests()
		elif arg == "--roster-test":
			_run_roster_tests()
		elif arg == "--loadout-test":
			_run_loadout_tests()
		elif arg == "--team-test":
			_run_team_tests()
		elif arg == "--pc-test":
			_run_pc_tests()
		elif arg == "--button-test":
			_run_button_tests()
		elif arg == "--aim-test":
			_run_aim_tests()
		elif arg == "--feel-test":
			_run_feel_tests()
		elif arg == "--cover-test":
			_run_cover_tests()
		elif arg == "--lava-test":
			_run_lava_tests()
		elif arg == "--shrink-test":
			_run_shrink_tests()
		elif arg == "--burn-pose":
			_burn_pose()
		elif arg == "--bolt-pose":
			_bolt_pose()
		elif arg.begins_with("--aim-hold:"):
			# "--aim-hold:0,1,0" aims spell 0 to screen-right. Eleven characters in the
			# prefix, counted rather than guessed - see ARCHITECTURE.md on --cast-at.
			var held := arg.substr(11).split(",")
			if held.size() == 3:
				_hold_aim(int(held[0]), Vector2(float(held[1]), float(held[2])))
		elif arg == "--layout-probe":
			_probe_layout()
		elif arg.begins_with("--cast-at:"):
			# "--cast-at:1.5", or "--cast-at:1.5,1" for a slot other than the first. Ten
			# characters in the prefix; substr(9) yields ":1.5", which float() reads as 0.0
			# without complaining. That cost a session once - see ARCHITECTURE.md.
			var when := arg.substr(10).split(",")
			var slot := 0
			if when.size() > 1:
				slot = int(when[1])
			_cast_at(float(when[0]), slot)
		elif arg.begins_with("--stick-hold="):
			var hp := arg.substr(13).split(",")
			if hp.size() == 2:
				_hold_stick(Vector2(float(hp[0]), float(hp[1])))


## Parks the bot without unwiring it.
##
## Every suite written before the bot existed assumed the second fighter stood still: the
## cast suite fires down the -Z line and expects a hit, the knockback suite measures a slide
## with no steering in it, the round suite expects a body to stay where it was put. An
## opponent that dodges breaks all three for entirely correct reasons, which is the most
## expensive kind of test failure. They park it; --bot-test is where it gets to play.
func _freeze_bot() -> void:
	# The scene's brain first, because it is the one `_add_bot` copies `enabled` from - so a
	# `--bot:off` parsed before the squad exists still reaches the two bots made later. The loop
	# is for the other order: a suite freezing them after the match has begun.
	_brain.enabled = false
	for brain in _brains:
		brain.enabled = false


## Turns the game feel off for a suite that measures.
##
## The same shape as `_freeze_bot()` above and for the same reason: hitstop scales
## `Engine.time_scale`, so a slide measured over a fixed number of ticks comes out short and a
## cooldown read after a fixed wait comes out long. Both would be correct behaviour breaking a
## correct test, which is the most expensive kind of failure to read.
func _quiet_feel() -> void:
	_feel.enabled = false
	print("[harness] game feel parked")


## Takes the obstacles out of the arena for a suite that measures.
##
## Third in the family, after `_freeze_bot()` and `_quiet_feel()`, and for the same reason
## each time: every suite written before cover existed assumes an EMPTY arena and picks the
## spot it measures from by hand. Scourge's "the push goes away from the caster" test
## happened to put its target a metre from a tree, so the victim slid along the trunk and the
## measured push came out 30 degrees off - correct physics, correct test, arena furniture in
## the way. That is the most expensive kind of failure to read, so the furniture goes.
##
## The bodies stay in the tree and simply stop colliding and drawing. `--cover-test` is where
## they get to matter.
## Stops the ring closing, for a suite that measures.
##
## Fourth in the family after the bot, the game feel and the cover. Every suite that places a
## fighter at a distance picks that distance by hand, and several run for longer than the
## grace period - so without this the ground would move under the measurement, and the failure
## would look like a broken spell rather than a moving arena.
func _freeze_arena() -> void:
	_arena.shrinking = false
	_arena.reset()
	print("[harness] arena frozen at %.1fm" % _arena.radius)


func _clear_cover() -> void:
	for child in _obstacles.get_children():
		var body := child as CollisionObject3D
		if body != null:
			body.set_deferred("collision_layer", 0)
			body.visible = false
	print("[harness] cover cleared")


func _set_bot_skill(level: String) -> void:
	match level.to_lower():
		"calm":
			_brain.skill = BotController.Skill.CALM
		"steady":
			_brain.skill = BotController.Skill.STEADY
		"sharp":
			_brain.skill = BotController.Skill.SHARP
		_:
			push_warning("unknown bot skill '%s'; leaving it alone" % level)
			return
	# Every opponent, not merely the one in the scene. `_add_bot` copies this off `_brain`, so
	# ordering is covered either way - but a difficulty that reached one of three bots would be
	# a difficulty setting that quietly did a third of what it said.
	for brain in _brains:
		brain.skill = _brain.skill
	print("[harness] bot skill = %s" % level.to_upper())


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


# ---------------------------------------------------------------------------------------
# Touch harness
#
# Godot cannot be driven by a real finger from an automated session, so these inject
# InputEventScreenTouch/Drag directly. That is the only way to prove the things that
# actually matter about a two-thumb layout: that the stick claims exactly one finger, that
# a second finger cannot disturb it, and that a diagonal is not faster than a cardinal.
#
# Positions are in canvas units, which equal window pixels only at the 1280x720 design
# size, so run the touch tests at that resolution and the stretch transform stays identity.
# ---------------------------------------------------------------------------------------

var _touch_failures := 0


func _emit_touch(index: int, position: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = position
	event.pressed = pressed
	_dispatch(event)


func _emit_drag(index: int, position: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = position
	_dispatch(event)


## Pushes an injected event through immediately.
##
## Godot buffers input by default (`use_accumulated_input`), so parse_input_event() alone
## leaves the event sitting in a queue for an unpredictable number of frames - which shows
## up as a test that passes or fails depending on how many frames it happened to wait, and
## sends you hunting for a bug in the code under test. Flushing makes the dispatch
## deterministic, which is the whole point of a scripted run.
func _dispatch(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()


## Waits for the whole input pipeline to turn over.
##
## An injected event is flushed, read by PlayerInputController in _process, and acted on by
## the character in _physics_process. Two idle frames can straddle the flush and leave the
## command one frame behind the inputs that produced it - which looks exactly like a bug and
## is not one. Awaiting a physics frame between two idle frames covers every ordering.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame


func _expect(label: String, passed: bool, detail: String) -> void:
	if not passed:
		_touch_failures += 1
	print("  [%s] %-44s %s" % ["PASS" if passed else "FAIL", label, detail])


func _run_touch_tests() -> void:
	# This suite is ABOUT the thumb controls, so it asks for them rather than
	# hoping the device shows them. AUTO now means a real touchscreen.
	_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
	await _settle()
	var stick := _mobile.joystick
	var centre := stick.get_global_rect().get_center()
	var radius: float = stick.base_radius
	print("[touch-test] viewport=%s stick centre=%s radius=%.0f" % [
		get_viewport().get_visible_rect().size, centre, radius])

	# --- claiming a finger -------------------------------------------------------------
	_emit_touch(0, centre, true)
	await _settle()
	_expect("press inside claims finger 0", stick.touch_index() == 0,
		"owner=%d" % stick.touch_index())

	# --- full right deflection ---------------------------------------------------------
	_emit_drag(0, centre + Vector2(radius, 0.0))
	await _settle()
	var right_cmd: Vector2 = _input.command.move_dir
	_expect("stick right -> value (1,0)", stick.value().is_equal_approx(Vector2(1.0, 0.0)),
		"value=%s" % stick.value())
	_expect("stick right -> world +X (screen-right)",
		right_cmd.x > 0.9 and absf(right_cmd.y) < 0.05, "move_dir=%s" % right_cmd)

	# --- a second finger must not disturb it -------------------------------------------
	var elsewhere := Vector2(get_viewport().get_visible_rect().size.x - 140.0, centre.y)
	_emit_touch(1, elsewhere, true)
	await _settle()
	_expect("second finger ignored (ownership)", stick.touch_index() == 0,
		"owner=%d" % stick.touch_index())
	_expect("second finger leaves value intact",
		stick.value().is_equal_approx(Vector2(1.0, 0.0)), "value=%s" % stick.value())

	_emit_drag(1, elsewhere + Vector2(0.0, -120.0))
	await _settle()
	_expect("foreign drag leaves value intact",
		stick.value().is_equal_approx(Vector2(1.0, 0.0)), "value=%s" % stick.value())

	_emit_touch(1, elsewhere, false)
	await _settle()
	_expect("foreign release does not free stick", stick.touch_index() == 0,
		"owner=%d value=%s" % [stick.touch_index(), stick.value()])

	# --- screen directions map to screen directions ------------------------------------
	_emit_drag(0, centre + Vector2(0.0, -radius))
	await _settle()
	var up_cmd: Vector2 = _input.command.move_dir
	_expect("stick up -> value (0,1)", stick.value().is_equal_approx(Vector2(0.0, 1.0)),
		"value=%s" % stick.value())
	# Screen-up is world -Z with this camera: the wizard walks away from the viewer.
	_expect("stick up -> world -Z (up the screen)",
		up_cmd.y < -0.9 and absf(up_cmd.x) < 0.05, "move_dir=%s" % up_cmd)

	_emit_drag(0, centre + Vector2(-radius, 0.0))
	await _settle()
	var left_cmd: Vector2 = _input.command.move_dir
	_expect("stick left -> world -X (screen-left)",
		left_cmd.x < -0.9 and absf(left_cmd.y) < 0.05, "move_dir=%s" % left_cmd)

	# --- diagonals must not be faster --------------------------------------------------
	_emit_drag(0, centre + Vector2(radius, -radius))
	await _settle()
	var diag: float = _input.command.move_dir.length()
	var cardinal: float = right_cmd.length()
	_expect("diagonal is not faster than cardinal", absf(diag - cardinal) < 0.02,
		"diagonal=%.4f cardinal=%.4f" % [diag, cardinal])
	_expect("diagonal magnitude clamped to 1.0", diag <= 1.0001, "len=%.4f" % diag)

	# --- deadzone ----------------------------------------------------------------------
	var inside_dead: float = _input.touch_deadzone * radius * 0.5
	_emit_drag(0, centre + Vector2(inside_dead, 0.0))
	await _settle()
	_expect("inside deadzone -> no movement",
		_input.command.move_dir.length() < 0.0001,
		"stick=%.3f move_dir=%.4f" % [stick.value().length(), _input.command.move_dir.length()])

	# Just outside the deadzone the output must ramp up from ~0, not jump to the deadzone
	# value. This is exactly what the rescaling in _shape_stick buys.
	var just_outside: float = (_input.touch_deadzone + 0.02) * radius
	_emit_drag(0, centre + Vector2(just_outside, 0.0))
	await _settle()
	var edge: float = _input.command.move_dir.length()
	_expect("just outside deadzone ramps from ~0", edge > 0.0 and edge < 0.06,
		"len=%.4f (a clipping deadzone would give ~%.2f)" % [edge, _input.touch_deadzone])

	# --- release -----------------------------------------------------------------------
	_emit_touch(0, centre + Vector2(just_outside, 0.0), false)
	await _settle()
	_expect("release frees the stick", stick.touch_index() == -1,
		"owner=%d" % stick.touch_index())
	_expect("release snaps value to centre", stick.value() == Vector2.ZERO,
		"value=%s" % stick.value())
	_expect("release stops the wizard", _input.command.move_dir.length() < 0.0001,
		"move_dir=%s" % _input.command.move_dir)
	_expect("controller reports no move input after release",
		not _input.command.has_move_input, "has_move_input=%s" % _input.command.has_move_input)

	print("[touch-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


func _emit_key(physical_keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	_dispatch(event)


## Proves the desktop path still reaches the character now that a stick shares the pipeline.
## Both feed the same InputCommand, so a regression here would mean the touch branch had
## started swallowing input that no finger was actually producing.
func _run_key_tests() -> void:
	# ARROW keys, not WASD. W, E and R are spell slots since the desk controls became the ones
	# the map this game follows uses, and the arrows are what is left bound to walking.
	# It holds the stick to prove touch outranks a held key, and a hidden stick claims nothing.
	_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
	await _settle()
	print("[key-test] keyboard through the same InputCommand pipeline")

	_emit_key(KEY_RIGHT, true)
	await _settle()
	var right: Vector2 = _input.command.move_dir
	_expect("D -> world +X (screen-right)", right.x > 0.9 and absf(right.y) < 0.05,
		"move_dir=%s" % right)
	_emit_key(KEY_RIGHT, false)
	await _settle()

	_emit_key(KEY_UP, true)
	await _settle()
	var fwd: Vector2 = _input.command.move_dir
	_expect("W -> world -Z (up the screen)", fwd.y < -0.9 and absf(fwd.x) < 0.05,
		"move_dir=%s" % fwd)

	# Diagonal on the keyboard must obey the same circular clamp the stick does.
	_emit_key(KEY_RIGHT, true)
	await _settle()
	var diag: float = _input.command.move_dir.length()
	_expect("W+D diagonal is not faster", absf(diag - right.length()) < 0.02,
		"diagonal=%.4f cardinal=%.4f" % [diag, right.length()])

	_emit_key(KEY_UP, false)
	_emit_key(KEY_RIGHT, false)
	await _settle()
	_expect("releasing keys stops the wizard", _input.command.move_dir.length() < 0.0001,
		"move_dir=%s" % _input.command.move_dir)

	# A finger on the stick must take priority over a held key, not fight it.
	var centre := _mobile.joystick.get_global_rect().get_center()
	_emit_key(KEY_LEFT, true)
	await _settle()
	_emit_touch(0, centre, true)
	_emit_drag(0, centre + Vector2(_mobile.joystick.base_radius, 0.0))
	await _settle()
	var contested: Vector2 = _input.command.move_dir
	_expect("touch wins over a held key", contested.x > 0.9,
		"A held + stick right -> move_dir=%s" % contested)

	_emit_touch(0, centre, false)
	await _settle()
	var after: Vector2 = _input.command.move_dir
	_expect("keyboard resumes when the finger lifts", after.x < -0.9,
		"A still held -> move_dir=%s" % after)
	_emit_key(KEY_LEFT, false)
	await _settle()

	print("[key-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Presses the stick and leaves it deflected, so a screenshot shows a live thumb rather
## than a stick at rest. Purely for looking at the thing; no assertions.
func _hold_stick(normalised: Vector2) -> void:
	await _settle()
	var stick := _mobile.joystick
	var centre := stick.get_global_rect().get_center()
	# Screen y is down, the stick convention is y-up, so flip to place the thumb.
	var offset := Vector2(normalised.x, -normalised.y) * stick.base_radius
	_emit_touch(0, centre, true)
	_emit_drag(0, centre + offset)
	print("[harness] holding stick at %s" % normalised)


## Prints where the stick actually landed, so anchor behaviour across screen shapes is
## measured rather than assumed. The numbers that must stay constant are the distances to
## the bottom-left corner; the viewport width is expected to change and the arena with it.
func _probe_layout() -> void:
	await _settle()
	var view := get_viewport().get_visible_rect().size
	var r := _mobile.joystick.get_global_rect()
	print("[layout] viewport=%.0fx%.0f aspect=%.2f | stick rect=%s | left_gap=%.1f bottom_gap=%.1f | visible=%s" % [
		view.x, view.y, view.x / view.y, r, r.position.x, view.y - r.end.y,
		_mobile.joystick.is_visible_in_tree()])
	get_tree().quit()


# ---------------------------------------------------------------------------------------
# Combat wiring
#
# The spellbook decides a cast MAY happen; this turns that into something in the world. The
# component cannot do it itself without knowing where the projectile pool lives, and the
# pool has no opinion about cooldowns. Joining them is the level's job, exactly like the
# joystick above.
#
# This is also the seam a server slots into: when casts become authoritative, the request is
# validated here (or refused) rather than anywhere inside the character.
# ---------------------------------------------------------------------------------------

func _wire_combat() -> void:
	# Every fighter's spellbook arrives at the same handler, so the bot's Fireball IS the
	# player's Fireball: same pool, same flight, same hit resolution, same knockback. A
	# separate path for the opponent would be a second set of rules to keep in step.
	for fighter in _fighters:
		var spellbook := fighter.abilities()
		if spellbook == null:
			push_warning("%s has no AbilityComponent; it will never cast" % fighter.name)
			continue
		spellbook.cast_requested.connect(_on_cast_requested)
	_pool.projectile_hit.connect(_on_projectile_hit)
	_pool.projectile_spent.connect(_on_projectile_spent)
	# A button reports a press; the controller latches it; the character consumes it on the
	# next tick. Touch therefore takes the same route as the number keys, which is what stops
	# the two drifting apart - and it is why four buttons needed no new plumbing at all.
	for button in _mobile.buttons:
		# Press, drag, lift. The button says what the thumb did; the controller decides what
		# that means and latches the cast, exactly as the stick's vector is given meaning by
		# a single line up here rather than inside either node.
		button.aim_started.connect(_input.begin_aim)
		button.aim_moved.connect(_input.update_aim)
		button.cast_released.connect(_input.end_aim)
		# Read-only, for drawing the cooldown wedge and the spell's colour. The buttons belong
		# to the human, so they watch the human's spellbook.
		button.source = _player.abilities()


# ---------------------------------------------------------------------------------------
# Loadout
#
# Which spells a wizard carries is decided HERE and nowhere else. The screen reports a set of
# picks, the catalogue turns picks into a spellbook, and this level assigns it - the same
# three-step shape the touch buttons already follow, where a widget reports, a rule decides,
# and the level performs.
#
# Nothing downstream learns a spell's name. The buttons read whatever the spellbook holds, the
# bot chooses by cast type, and the aim indicator asks the Ability what its reach is. That is
# what made seven new spells a data change with a handful of runtime lines rather than a pass
# over the whole file.
# ---------------------------------------------------------------------------------------

## The catalogue's own defaults, or nothing if this level was given no catalogue.
func _default_picks() -> PackedInt32Array:
	return catalogue.default_picks() if catalogue != null else PackedInt32Array()


## Forms the squad, wires it, and starts the match.
##
## Everything here used to sit in `_ready`, and moved out for one reason: how many wizards are
## on the stone is chosen on a screen that has not been shown yet. The spellbooks, the HUD rows
## and the round roster all depend on the answer, and wiring them for two and then discovering
## there are four is how a fighter ends up invisible to the round system - standing, unhittable,
## and preventing the round from ever ending.
func _begin_match(team_match: bool) -> void:
	if _squad_formed:
		# A suite drove the loadout screen after the match had already started. Re-arm and
		# restart; registering the same roster twice would give every fighter a second HUD row
		# and the round system two of each body, and the round would never end.
		_arm_fighters(false)
		_rounds.start_match()
		return
	_squad_formed = true
	_team_match = team_match
	_form_squad(team_match)
	_wire_combat()
	# The HUD reads instability and nothing else. It is handed its sources here rather than
	# hunting for them, which is what makes a third and fourth fighter a loop rather than a
	# rewrite - the list it draws was built for exactly this.
	for fighter in _readout_order():
		_hud.add_readout(_title_of(fighter), fighter.instability(), fighter.health())
	_wire_rounds()
	_arm_fighters(_show_loadout)
	_rounds.start_match()


## The fighters grouped by side, the player's own first.
##
## `_fighters` is in the order the squad was BUILT - player, scene bot, then the two made at
## runtime - which puts an opponent between the player and their ally in the readout. Nobody
## reads four interleaved rows as two teams.
func _readout_order() -> Array[Player]:
	var mine: Array[Player] = []
	var theirs: Array[Player] = []
	for fighter in _fighters:
		if fighter.team == _player.team:
			mine.append(fighter)
		else:
			theirs.append(fighter)
	return mine + theirs


## Puts the fighters on the stone: two in a duel, four in a team match.
##
## The scene's own Player and BotWizard are always the first of their sides, whichever mode
## this is. That is not tidiness - a dozen suites hold `_player` and `_bot` and measure them,
## and a mode that rebuilt the pair from scratch would be a mode none of those suites describe.
func _form_squad(team_match: bool) -> void:
	_fighters = [_player, _bot]
	_brains = [_brain]
	_spawns = {_player: spawn_point, _bot: bot_spawn}
	_titles = {_player: "YOU", _bot: "BOT"}
	if not team_match:
		_brain.enemies = [_player]
		return

	# Point-symmetric, so neither side opens nearer an edge and every wizard has an opposite
	# number directly across the ring.
	var side := Vector3(TEAM_SPREAD, 0.0, 0.0)
	_spawns[_player] = spawn_point - side
	_spawns[_bot] = bot_spawn + side
	_titles[_bot] = "RED 1"

	var ally := _add_bot("ALLY", _player.team, spawn_point + side, ALLY_TINT)
	var foe := _add_bot("RED 2", _bot.team, bot_spawn - side, SECOND_FOE_TINT)

	# Handed the whole opposing side rather than one name, so a bot that loses its target
	# turns to the other one instead of standing still for the rest of the round.
	var blue: Array[Player] = [_player, ally]
	var red: Array[Player] = [_bot, foe]
	for brain in _brains:
		brain.enemies = red if brain.body.team == _player.team else blue


## Builds one bot fighter and its controller, and adds both to the scene.
##
## The controller is a sibling node rather than a child of the wizard, matching how the scene
## already does it: a brain that lived inside the body it drives could not be swapped for a
## human's controller, which is the whole point of `Player.input_controller`.
func _add_bot(title: String, team: int, at: Vector3, tint: Color) -> Player:
	var fighter: Player = bot_scene.instantiate()
	fighter.name = title.replace(" ", "")
	fighter.team = team
	add_child(fighter)
	fighter.global_position = at
	_tint_fighter(fighter, tint)

	var brain := BotController.new()
	brain.name = "%sBrain" % fighter.name
	# Copied off the scene's bot so a difficulty picked with `--bot-skill` reaches every
	# opponent, not just the one that happens to be in the .tscn.
	brain.skill = _brain.skill
	brain.arena_radius = _brain.arena_radius
	brain.enabled = _brain.enabled
	add_child(brain)
	brain.body = fighter
	fighter.input_controller = brain

	_fighters.append(fighter)
	_brains.append(brain)
	_spawns[fighter] = at
	_titles[fighter] = title
	return fighter


## Recolours a wizard's body. Four capsules in two shades of the same colour would be a fight
## nobody can read, and the tint is the only thing telling them apart while everything is
## untextured primitives.
func _tint_fighter(fighter: Player, tint: Color) -> void:
	var body := fighter.get_node_or_null(^"Visual/Body") as MeshInstance3D
	if body == null:
		return
	# A fresh material rather than an edit of the scene's, which every instance of
	# `bot_wizard.tscn` shares - recolouring it would recolour the opposition too.
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.roughness = 0.55
	body.set_surface_override_material(0, material)


## What the SCORE calls a side. The player's side is "YOU" in both modes, so a caller that
## only knows that word - and several suites only know that word - gets the right answer
## whether it is one wizard or two.
func _side_name(team: int) -> String:
	if team == _player.team:
		return "YOU"
	return "RED" if _team_match else "BOT"


func _title_of(fighter: Player) -> String:
	return _titles.get(fighter, fighter.name)


func _spawn_of(fighter: Player) -> Vector3:
	return _spawns.get(fighter, Vector3.ZERO)


func _open_loadout() -> void:
	# Guarded because the suite opens the screen too, and a second connection would arm the
	# wizards twice and start two matches off one button.
	if not _loadout.confirmed.is_connected(_on_loadout_confirmed):
		_loadout.confirmed.connect(_on_loadout_confirmed)
	# The HUD reports a fight that has not started. Hidden rather than dimmed: a round counter
	# and two instability bars ghosting through the menu read as a bug, and they are about to be
	# correct again the moment the player presses FIGHT.
	_hud.visible = false
	# The spell buttons live on their own CanvasLayer and claim touches through `_input`, which
	# runs whether or not anything is drawn over them. Hiding them is what stops a thumb landing
	# on the menu and also arming a cast underneath it.
	_mobile.visible = false
	# Nobody fights while the menu is up. The round system has not started yet, and a fighter's
	# default is to accept input - so without this the bot opens fire on a player who is still
	# reading the spell list, and the first screenshot of the screen caught exactly that.
	var waiting: Array[Player] = [_player, _bot]
	for fighter in waiting:
		fighter.accepts_input = false
	_loadout.open(catalogue, _picks, _team_match, _control_hint())


func _on_loadout_confirmed(picks: PackedInt32Array, team_match: bool) -> void:
	_picks = picks
	# Saving BEFORE the match, not after it. A player who chose a loadout and then closed the
	# game mid-round still chose it, and losing the pick because the round did not finish would
	# be the kind of small betrayal nobody reports and everybody notices.
	LoadoutStore.save_picks(catalogue, _picks, team_match)
	_mobile.visible = true
	_hud.visible = true
	_begin_match(team_match)


## Hands both wizards their spellbooks.
##
## The bot's is RANDOM in a real match and fixed in a scripted one. Random because a spell the
## player never has used against them is a spell they never learn to read, and this is the
## cheapest way to put all eleven in front of them; fixed under the harness because a dozen
## suites were written against a bot that carries a cone and a dash, and an opponent whose
## loadout changed per run would fail them for entirely correct reasons.
##
## Seeded from the bot's own generator, so `rng_seed` still replays a whole fight - including
## which spells it brought to it.
func _arm_fighters(randomise_bot: bool) -> void:
	if catalogue == null:
		return
	var mine := _player.abilities()
	if mine != null:
		mine.abilities = catalogue.spellbook(_picks)
	if not randomise_bot:
		return
	var rng := RandomNumberGenerator.new()
	if _brain.rng_seed == 0:
		rng.randomize()
	else:
		rng.seed = _brain.rng_seed
	print("[loadout] you %s" % str(catalogue.ids_from_picks(_picks)))
	for fighter in _fighters:
		if fighter == _player:
			continue
		var theirs := fighter.abilities()
		if theirs == null:
			continue
		# Drawn one after another from the same stream, so a seeded run replays every wizard's
		# loadout and not merely the first one's.
		var picks := catalogue.random_picks(rng)
		theirs.abilities = catalogue.spellbook(picks)
		print("[loadout] %s %s" % [
			_title_of(fighter), str(catalogue.ids_from_picks(picks))])


func _on_cast_requested(ability: Ability, origin: Vector3, direction: Vector3, caster: Node3D) -> void:
	if caster == _player:
		_last_cast_dir = direction
		_last_cast_id = ability.id
	_feel.cast(ability, caster == _player)
	match ability.cast_type:
		Ability.CastType.PROJECTILE:
			if ability.stream_count > 1:
				_fire_stream(ability, origin, direction, caster)
			else:
				_pool.fire(ability, origin, direction, caster)
		Ability.CastType.CONE:
			_cast_cone(ability, direction, caster)
		Ability.CastType.DASH:
			_cast_dash(ability, direction, caster)
		Ability.CastType.BUFF:
			_cast_buff(ability, caster)
		_:
			# Nothing reaches here today. Kept so that a cast type added to the enum and
			# forgotten here is loud rather than silent - which is how the other three spent
			# a session doing nothing at all.
			push_warning("cast type %d has no runtime (%s)" % [ability.cast_type, ability.id])


## Sends one cast as several projectiles, spaced out in time. Fire Spray.
##
## The aim is frozen at the moment of the cast rather than re-read per shot, which is what
## makes a stream a skillshot: you commit to a line and the target gets to walk out of it.
## Re-aiming each shot would turn six missiles into six free hits.
func _fire_stream(ability: Ability, origin: Vector3, direction: Vector3,
		caster: Node3D) -> void:
	for index in ability.stream_count:
		if index > 0:
			await get_tree().create_timer(ability.stream_interval).timeout
		# The caster can die, be eliminated, or leave the round between shots. The origin is
		# re-read from them when they are still around so the stream follows the wizard, and
		# the whole thing stops when they are not.
		if not is_instance_valid(caster):
			return
		var from := origin
		var fighter := caster as Player
		if fighter != null:
			from = fighter.global_position + direction.normalized() * ability.spawn_offset
			from.y = origin.y
		_pool.fire(ability, from, direction, caster)


## The projectile pool reports contact and stops there. Every hit in the game, from any
## source, goes through `_apply_hit` below.
##
## A spell with a BLAST does nothing here: it resolves on `spent` instead, at the spot it
## died, so that the wizard it touched and the wizards standing beside them are caught by one
## rule rather than by two. Handling both would hit the first target twice.
func _on_projectile_hit(body: Node3D, direction: Vector3, ability: Ability,
		shooter: Node3D) -> void:
	if ability.area > 0.0:
		return
	_apply_hit(body, direction, ability, shooter)
	_bounce_onward(body, ability, shooter)


## A projectile ended. Blasts and splits happen here, because both are about the SPOT rather
## than about what was touched - a meteor that lands on empty ground has still landed.
func _on_projectile_spent(at: Vector3, direction: Vector3, ability: Ability,
		shooter: Node3D) -> void:
	if ability.area > 0.0:
		_burst(at, direction, ability, shooter)
	if ability.splits_into > 0 and ability.split_child is Ability:
		_split(at, direction, ability, shooter)


## Everything standing within `area` of a point takes the hit, softened by distance if the
## spell has a falloff.
##
## Walks `_fighters` rather than running a shape query. The list is short, it is already the
## register of who is in the round, and it is the only way to ask that also knows who is
## eliminated - a physics query would happily catch a body that has left the fight.
func _burst(at: Vector3, direction: Vector3, ability: Ability, caster: Node3D) -> void:
	for fighter in _fighters:
		if not is_instance_valid(fighter) or fighter.is_eliminated():
			continue
		if fighter == caster and not ability.hits_caster:
			continue
		var thrower := caster as Player
		var friendly := thrower != null and (fighter == caster or thrower.is_ally_of(fighter))
		var gap := fighter.global_position - at
		gap.y = 0.0
		var distance := gap.length()
		if distance > ability.area:
			continue
		if friendly and ability.ally_heal > 0.0:
			var hp := fighter.health()
			if hp != null:
				hp.heal(ability.ally_heal)
		# An ally is only hurt when the spell says it hurts everybody. Scourge and Cataclysm
		# do; that is their cost and the reason they are allowed a three-second cooldown.
		if friendly and not ability.hits_caster:
			continue
		var push := gap
		if push.length_squared() < 0.0001:
			push = direction
		_apply_hit(fighter, push.normalized(), ability, caster, _falloff(ability, distance))


## What fraction of a burst's damage survives `distance` metres from its centre.
##
## The map states this the other way up - its meteor is "7-14 depending on range" - and the
## direction is the point: the centre of a blast is the worst place to stand, not a safe one.
func _falloff(ability: Ability, distance: float) -> float:
	if ability.falloff_over <= 0.0:
		return 1.0
	return clampf(1.0 - distance / ability.falloff_over, 0.0, 1.0)


## Breaks a spent projectile into fragments, fanned around the way it was travelling.
##
## Each fragment is a whole Ability of its own (`split_child`) rather than a fraction of its
## parent, so the pieces have their own damage, speed, colour and shape - which is what lets a
## splitter be a weak shot that leaves a dangerous cloud rather than one big hit cut into bits.
func _split(at: Vector3, direction: Vector3, ability: Ability, caster: Node3D) -> void:
	var child := ability.split_child as Ability
	var heading := Vector3(direction.x, 0.0, direction.z)
	if heading.length_squared() < 0.0001:
		heading = Vector3.FORWARD
	heading = heading.normalized()
	var spread := deg_to_rad(ability.split_spread)
	for index in ability.splits_into:
		# Evenly across the fan, and centred: a single fragment goes straight on, two straddle
		# the line, and none of them is ever the parent's exact heading by accident.
		var t := 0.5 if ability.splits_into == 1 else float(index) / float(ability.splits_into - 1)
		var angle := (t - 0.5) * spread
		_pool.fire(child, at, heading.rotated(Vector3.UP, angle), caster)


## Looks for another target after a hit, and throws the same spell at it with less behind it.
##
## The bounce is a fresh projectile carrying a DUPLICATED ability, one bounce poorer and one
## falloff weaker. Duplicating rather than tracking a scale on the projectile keeps the hit
## signal's shape - which has already broken two harnesses silently once - and costs one
## Resource per bounce.
func _bounce_onward(body: Node3D, ability: Ability, shooter: Node3D) -> void:
	if ability.bounces <= 0:
		return
	var from := body as Node3D
	if from == null or not is_instance_valid(from):
		return
	var next: Player = null
	var best := INF
	for fighter in _fighters:
		if not is_instance_valid(fighter) or fighter.is_eliminated() or fighter == body:
			continue
		var thrower := shooter as Player
		if thrower != null and (fighter == shooter or thrower.is_ally_of(fighter)):
			continue
		var gap := fighter.global_position.distance_to(from.global_position)
		if gap < best and gap <= ability.bounce_range:
			best = gap
			next = fighter
	if next == null:
		return
	var weaker: Ability = ability.duplicate() as Ability
	weaker.bounces = ability.bounces - 1
	weaker.damage = ability.damage * (1.0 - ability.bounce_falloff)
	var aim := next.global_position - from.global_position
	aim.y = 0.0
	if aim.length_squared() < 0.0001:
		return
	var heading := aim.normalized()
	# Launched CLEAR of the wizard it just bounced off, by the same offset a cast uses. Spawned
	# on top of them, the new projectile overlaps them on its very first frame and hits the
	# same person twice from one cast - and `_caught` cannot help, because this is a different
	# projectile carrying a different (duplicated) ability.
	_pool.fire(weaker, from.global_position + heading * weaker.spawn_offset, heading, shooter)


## Scourge. Everything standing in the fan is hit on this frame, and thrown AWAY FROM THE
## CASTER rather than along the aim.
##
## That difference is the spell. A wave shoves what it touches outward, so catching someone at
## the shoulder of the cone throws them sideways off the rim - which is why it is the finisher
## and why it is worth walking into range for.
func _cast_cone(ability: Ability, direction: Vector3, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter != null:
		var flash := fighter.spell_flash()
		if flash != null:
			# The drawing takes its shape from the same two numbers the hit test uses, so the
			# fan on screen cannot disagree with the fan that hits.
			flash.play(ability.area, ability.cone_angle, ability.colour, direction)
	# A burst that catches its own caster is a BURST, not a fan, and it resolves through the
	# same door a blast does - which is also the only door that knows how to hit the caster and
	# how to mend an ally. A fan keeps the cone query, because a fan has a direction and a
	# burst does not.
	if ability.hits_caster:
		_burst(caster.global_position, direction, ability, caster)
		return
	var space := get_world_3d().direct_space_state
	for body in ConeCast.targets(space, caster.global_position, direction, ability, caster):
		var push := body.global_position - caster.global_position
		push.y = 0.0
		if push.length_squared() < 0.0001:
			push = direction
		var reach := push.length()
		_apply_hit(body, push.normalized(), ability, caster, _falloff(ability, reach))


## Teleport. The landing point is clamped INSIDE the arena here, in the level, because the level
## is the only thing that knows where the edge is - and a spell that could drop you in the
## void is a spell nobody would ever press.
func _cast_dash(ability: Ability, direction: Vector3, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter == null:
		return
	var from := fighter.global_position
	var landing := _blink_landing(fighter, direction, ability)
	# Swept BEFORE the move, while the corridor still runs from where the caster was standing.
	# After the teleport the two endpoints are the same point and the sweep finds nothing - the
	# charge would land silently and read as a spell that simply does not work.
	var caught: Array[Node3D] = []
	if ability.dash_hits:
		caught = _dash_targets(from, landing, ability, fighter)
	fighter.blink_to(landing)
	_feel.dashed(from, landing, ability.colour)
	for body in caught:
		# Thrown along the charge, which is the direction the caster travelled and not the line
		# out from where they ended up. A charge shoves what it ran through forward.
		_apply_hit(body, direction.normalized(), ability, caster)


## Fighters standing in the corridor a charge sweeps from `from` to `to`.
##
## Sampled along the line rather than shape-cast, because a cast reports only the FIRST thing
## it meets and a charge through two bodies has to catch both - a rule that costs nothing today
## with two fighters and is the one that will still be right in a free-for-all.
##
## The step is the corridor's own width, so no body can sit between two samples and be missed.
func _dash_targets(from: Vector3, to: Vector3, ability: Ability,
		caster: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var space := get_world_3d().direct_space_state
	if space == null:
		return found
	var travel := to - from
	travel.y = 0.0
	var span := travel.length()
	var width := maxf(ability.dash_width, 0.1)
	var probe := SphereShape3D.new()
	probe.radius = width
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = ConeCast.PLAYERS_MASK
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var steps := maxi(1, int(ceil(span / width)))
	for step in steps + 1:
		var at := from + travel * (float(step) / float(steps))
		query.transform = Transform3D(Basis.IDENTITY, at)
		for hit in space.intersect_shape(query, ConeCast.MAX_TARGETS):
			var body := hit.get("collider") as Node3D
			if body == null or body == caster or found.has(body):
				continue
			found.append(body)
	return found


## Where a dash from `fighter` along `direction` would put them, clamped to the arena.
##
## Pulled out of the cast so the AIM INDICATOR can ask the same question. A preview that drew
## the unclamped distance would promise a landing spot the cast then refuses to use, and the
## player would learn to distrust the only thing telling them where they are about to be.
func _blink_landing(fighter: Player, direction: Vector3, ability: Ability) -> Vector3:
	var landing := fighter.global_position + direction.normalized() * ability.dash_distance
	var flat := Vector2(landing.x, landing.z)
	var limit := maxf(_arena_edge - BLINK_EDGE_MARGIN, 0.5)
	if flat.length() > limit:
		flat = flat.normalized() * limit
	return Vector3(flat.x, fighter.global_position.y, flat.y)


## Every self-cast spell. Which one it is comes off the Ability, not off a second cast type:
## a ward, a conversion and a rewind all do exactly one thing to the caster and nothing to the
## world, so they share a runtime and differ in which fields are set.
##
## Shield is reduction rather than blocking - see GAME_DESIGN.md for why blocking is the
## better long-term version and still not the one that ships.
func _cast_buff(ability: Ability, caster: Node3D) -> void:
	var fighter := caster as Player
	if fighter == null:
		return
	if ability.rewind:
		fighter.begin_rewind(ability.duration)
		print("[buff] %s -> %s | back to here in %.1fs" % [
			ability.id, fighter.name, ability.duration])
		return
	if ability.move_bonus > 0.0:
		fighter.grant_speed(ability.move_bonus, ability.duration)
	fighter.apply_shield(ability.duration, ability.knockback_resist,
		ability.speed_per_absorbed, ability.speed_cap)
	print("[buff] %s -> %s | %.0f%% of a hit gets through, for %.1fs" % [
		ability.id, fighter.name, ability.knockback_resist * 100.0, ability.duration])


## What a hit MEANS, for every source of one. A projectile arriving and a cone catching
## someone both end up here, so instability is raised in exactly one place and knockback is
## handed out in exactly one place.
##
## `direction` is the way the victim gets thrown: a projectile's travel direction, or the line
## out from the caster for a cone.
##
## `caster` is who threw it, and may be null for a hit with no author. Two rules read it - a
## spell that trades places needs both ends, and a spell that pushes away from its caster needs
## to know where the caster was - but it arrives here rather than being looked up because two
## spells can be in the air at once and "whoever cast last" is a guess.
## `scale` softens the whole hit at once - damage, damage points and push together, because
## they are one number. A blast uses it for distance falloff and nothing else does yet.
func _apply_hit(body: Node3D, direction: Vector3, ability: Ability,
		caster: Node3D = null, scale: float = 1.0) -> void:
	var fighter := body as Player
	if fighter == null:
		return
	var damage := ability.damage * scale
	if damage <= 0.0 and scale <= 0.0:
		return

	if ability.swaps_places:
		_swap_places(caster as Player, fighter, ability)

	# ONE number does all three things - see Ability.damage. Health first, then damage points,
	# then the push that reads them.
	if damage > 0.0:
		var hp := fighter.health()
		if hp != null:
			hp.damage(damage)
		var thief := caster as Player
		if ability.heal_caster > 0.0 and thief != null and is_instance_valid(thief):
			var mine := thief.health()
			if mine != null:
				mine.heal(damage * ability.heal_caster)
	if ability.root_seconds > 0.0:
		fighter.apply_root(ability.root_seconds)
	if ability.tether_seconds > 0.0 and ability.tether_dps > 0.0:
		_tethers[fighter] = {
			"caster": caster,
			"dps": ability.tether_dps,
			"left": ability.tether_seconds,
		}

	# Damage points are raised FIRST, and the push reads the new value. So a hit is amplified
	# by the destabilisation it just caused, which makes a landed combo escalate instead of
	# plateauing. The alternative - reading the value from before the hit - is defensible and
	# duller.
	var inst := fighter.instability()
	if inst != null:
		inst.add(damage)
	var level := inst.current if inst != null else 0.0

	# `push_along_travel` picks between the map's two hit functions. Away-from-caster needs a
	# caster to be away FROM, so a hit with no known origin falls back to the travel line.
	var push_dir := direction
	if not ability.push_along_travel and caster != null:
		var away := fighter.global_position - (caster as Node3D).global_position
		if Vector3(away.x, 0.0, away.z).length_squared() > 0.0001:
			push_dir = away
	var impulse := Knockback.velocity(
		Knockback.base_impulse(damage, ability.push_mult),
		push_dir, level, knockback_rules)
	fighter.apply_knockback(impulse)
	var shielded := " (shielded)" if fighter.is_shielded() else ""
	# What the victim ACTUALLY took, not what was thrown at them: the shield is applied inside
	# apply_knockback, and a hit somebody shrugged off has to feel like one.
	var landed := Vector2(fighter.knockback_velocity().x, fighter.knockback_velocity().z).length()
	_feel.hit(fighter.global_position, ability.colour, landed, fighter == _player)
	print("[hit] %s -> %s | instability %.0f%% | knockback %.1f m/s%s" % [
		ability.id, body.name, level, Vector2(impulse.x, impulse.z).length(), shielded])


## Trades two fighters over. Both go through `blink_to`, so a swap lands under exactly the rule
## a dash lands under: momentum cleared, hitstun kept.
##
## NOT clamped to the arena, and that is the spell. Both ends were somewhere a fighter was
## already standing, so neither can be the void - and if one of them was over the lava, putting
## the caster there is the whole reason to press it.
func _swap_places(caster: Player, victim: Player, ability: Ability) -> void:
	if caster == null or victim == null or caster == victim:
		return
	var theirs := victim.global_position
	var mine := caster.global_position
	caster.blink_to(theirs)
	victim.blink_to(mine)
	_feel.dashed(mine, theirs, ability.colour)
	print("[swap] %s <-> %s" % [caster.name, victim.name])


# ---------------------------------------------------------------------------------------
# Game feel
#
# Handed its channels here rather than finding them, like everything else in this file. Every
# one of them is optional on the other side, so a scene missing the sparks node is a scene
# with no sparks - never a scene that fails to run.
# ---------------------------------------------------------------------------------------

func _wire_feel() -> void:
	_feel.camera = _camera_rig
	_feel.sounds = $Sounds as SoundBank
	_feel.sparks = $Sparks as ImpactBurst
	_feel.streak = $Streak as GroundStreak


# ---------------------------------------------------------------------------------------
# Pointing
#
# On a phone the aim comes from a thumb dragging off a spell button. On a desktop it comes from
# the cursor, and turning a cursor into an aim takes three things the input controller
# deliberately does not know: the camera, the ground plane, and where the wizard is standing.
# So the level works it out and hands over the answer - the same single line of meaning it
# already gives the joystick.
# ---------------------------------------------------------------------------------------

## The one line telling a desk player which keys are theirs, or "" for a thumb.
##
## Read off the same state the aim is: if the thumb controls came up, this is a touch device and
## naming keys at it would be noise. It is deliberately shown on the loadout screen and nowhere
## else - it is needed once, before the first fight, and a permanent key legend over a game is
## clutter the second time you read it.
func _control_hint() -> String:
	if _mobile.is_touch_driving():
		return ""
	var line := "RIGHT CLICK or LEFT CLICK the ground to move  ·  Q W E R arms a spell"
	line += "  ·  LEFT CLICK sends it  ·  wards cast at once"
	var build := _build_id()
	if build != "":
		line += "      build %s" % build
	return line


## Which build this is, on the web, or "" anywhere else.
##
## The page stamps its own commit in (see the Web preset's `html/head_include` and the Pages
## workflow) and the game reads it back out. It exists because a web build is the one build
## nobody working on it can see: three separate reports turned on the question "is that even
## the build you are looking at?", and a browser hands back a cached pack next to a fresh
## shell often enough that guessing was worthless.
func _build_id() -> String:
	if not OS.has_feature("web"):
		return ""
	var stamp := str(JavaScriptBridge.eval("window.SPELLFALL_BUILD", true))
	# Un-substituted means somebody served the page without the workflow, which is worth
	# seeing rather than hiding.
	return stamp if stamp != "" and stamp != "<null>" else "?"


## Prints what the input layer decided, once, at startup.
##
## Because the thing that decides it cannot be seen. A web build renders into a canvas nobody
## here can photograph, so "the mouse does not work" arrives as a sentence rather than as a
## screenshot - and the difference between "the cursor is gated off" and "the cursor is aiming
## at the wrong place" is two minutes with this line and a guess without it.
func _report_input_mode() -> void:
	var tags := PackedStringArray()
	for tag in ["mobile", "web", "web_android", "web_ios", "pc", "android"]:
		if OS.has_feature(tag):
			tags.append(tag)
	print("[input] %s | thumb driving=%s -> %s" % [
		OS.get_name(), _mobile.is_touch_driving(),
		"THUMB DRIVES" if _mobile.is_touch_driving() else "CURSOR AIMS"])
	print("[input] features=[%s] | touchscreen flag=%s (not consulted) | emulating touch=%s" % [
		", ".join(tags), DisplayServer.is_touchscreen_available(),
		Input.is_emulating_touch_from_mouse()])


func _feed_pointer_aim() -> void:
	var live := _pointing_is_live()
	# Only where there is a mouse to describe, and only until the desk controls are confirmed
	# working in a browser. See `Hud.set_probe`.
	_hud.set_probe(_input.probe_text() if live else "")
	_label_spell_bar()
	_input.set_pointer_aim(_cursor_direction(), live)
	if not live:
		_move_target_set = false
		_input.set_click_move(Vector2.ZERO, false)
		return
	_take_move_click()
	_follow_move_target()
	_release_instant_casts()


## Prints each slot's key on its button, or clears them on a device with no keys.
##
## Refreshed every frame rather than set once, because the answer can CHANGE mid-session: a
## phone browser starts with no controls drawn and turns into a touch device the first time a
## finger lands. Only ever assigns a value that differs from the one already there, so the
## button redraws when the answer changes and not sixty times a second.
func _label_spell_bar() -> void:
	var keyed := not _mobile.is_touch_driving()
	var armed := _input.armed_slot()
	for slot in _mobile.buttons.size():
		var button := _mobile.buttons[slot]
		var wanted := PlayerInputController.key_label_for(button.slot) if keyed else ""
		if button.key_label != wanted:
			button.key_label = wanted
		var lit := button.slot == armed
		if button.armed != lit:
			button.armed = lit


## Turns a right click into a patch of ground.
##
## The controller read the button - it is the only thing allowed to know a mouse exists - and
## this works out what was under it, because that needs a camera and a ground plane.
func _take_move_click() -> void:
	if not _input.consume_move_click():
		return
	var spot := _cursor_ground_point()
	if spot == Vector3.INF:
		return
	_move_target = spot
	_move_target_set = true
	# The only feedback a click gets. A key you are holding tells you it worked by the wizard
	# walking; a click is one instant, and a click the game missed looks exactly like a click
	# that landed somewhere you did not mean.
	_move_marker.show_at(spot)


## Walks toward a standing order, and forgets it on arrival.
##
## The direction is recomputed EVERY FRAME rather than stored once, because the wizard is being
## shoved around while it walks: a direction latched at click time would have it marching
## confidently past the place it was sent, having been knocked three metres sideways on the way.
func _follow_move_target() -> void:
	if not _move_target_set:
		_input.set_click_move(Vector2.ZERO, false)
		return
	var here := _player.global_position
	var away := Vector2(_move_target.x - here.x, _move_target.z - here.z)
	if away.length() <= ARRIVAL_RADIUS:
		_move_target_set = false
		_input.set_click_move(Vector2.ZERO, false)
		return
	_input.set_click_move(away.normalized(), true)


## Fires an armed spell that has nowhere to be aimed.
##
## A ward is not pointed at anything, so holding it and waiting for a click would be asking the
## player for information the spell does not use. This is the level's call because a slot's
## cast type is a gameplay fact, and the input layer is not allowed to know one.
##
## Straight out of the map this follows: its own wards - Shield, Time Shift, Rush - are the
## three abilities there that take no target either.
func _release_instant_casts() -> void:
	var slot := _input.armed_slot()
	if slot < 0:
		return
	var book := _player.abilities()
	if book == null:
		return
	var ability := book.ability_in(slot)
	if ability != null and ability.cast_type == Ability.CastType.BUFF:
		_input.disarm()
		_input.request_ability(slot)


## Where the cursor meets the ground, or `Vector3.INF`.
##
## The FLOOR here, not the wizard's chest height the aim uses. A walk order is about a place to
## stand, and standing happens on the floor.
func _cursor_ground_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var ray := cam.project_ray_normal(mouse)
	if absf(ray.y) < 0.0001:
		return Vector3.INF
	var distance := -from.y / ray.y
	if distance <= 0.0:
		return Vector3.INF
	return from + ray * distance


## Whether a cursor should be steering the aim at all.
##
## A REAL touchscreen switches this off, not `Input.is_emulating_touch_from_mouse()`. Emulation
## is on in every desktop build so the thumb controls can be inspected, and keying off it would
## hand a phone-shaped answer to somebody sitting at a keyboard - which is exactly the mistake
## `MobileControls` made until this landed.
##
## It also goes quiet while the menu is up: the cursor is choosing a spell then, and a wizard
## turning to follow it behind the backdrop is motion nobody asked for.
func _pointing_is_live() -> bool:
	# THE THUMB CONTROLS BEING UP IS THE ONLY ANSWER. If a stick and four buttons are drawn,
	# this is a touch run - a phone, or a desktop run that asked for them with `--touch-ui:on` -
	# and a cursor aiming underneath would silently outrank every drag the thumb makes. Four
	# suites found that the hard way: they force the controls visible and then measure
	# drag-to-aim, and the mouse sitting wherever it happened to be was answering instead.
	#
	# This line also read `DisplayServer.is_touchscreen_available()` for one release, which is
	# the trap ARCHITECTURE.md describes and which is documented three files away from here.
	# In a browser that call answers about `ontouchstart in window`, which desktop Chrome
	# defines - so the first published build had a working WASD and a dead mouse. The
	# capability flag is not consulted anywhere any more; `_mobile.visible` already carries
	# the answer, because it is set by a finger actually arriving.
	if _mobile.is_touch_driving():
		return false
	if _loadout != null and _loadout.is_open():
		return false
	return not _player.is_eliminated()


## From the wizard toward the cursor, on the ground plane. Zero when there is no answer.
##
## The ray is intersected with the horizontal plane at the WIZARD'S OWN HEIGHT rather than with
## the floor. Aiming at the floor points slightly past the target - the wizard casts from chest
## height and the camera looks down, so the two planes are a stride apart at the far rim.
func _cursor_direction() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.ZERO
	var mouse := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var ray := cam.project_ray_normal(mouse)
	if absf(ray.y) < 0.0001:
		return Vector2.ZERO
	var distance := (_player.global_position.y - from.y) / ray.y
	if distance <= 0.0:
		return Vector2.ZERO
	var at := from + ray * distance
	var away := Vector2(at.x - _player.global_position.x, at.z - _player.global_position.z)
	# Under the wizard's own feet is not a direction. Below this the cursor is inside the body
	# and the aim would spin with sub-pixel mouse noise.
	if away.length() < 0.35:
		return Vector2.ZERO
	return away.normalized()


# ---------------------------------------------------------------------------------------
# Aim indicator
#
# The fighter carries the drawing; the level decides what it says. That split is not tidiness
# - a dash preview has to stop where the arena does, and the arena's size is knowledge this
# node owns and the wizard deliberately does not.
#
# Driven every rendered frame rather than on a signal, because the thing being previewed
# moves: the wizard walks while aiming, and a preview refreshed only when the thumb moves
# would trail behind their own feet.
# ---------------------------------------------------------------------------------------

func _update_aim_indicator() -> void:
	var indicator := _player.aim_indicator()
	if indicator == null:
		return
	var slot := _input.command.aiming_slot
	var book := _player.abilities()
	if slot < 0 or book == null or _player.is_eliminated() or not _player.accepts_input:
		indicator.clear()
		return
	var ability := book.ability_in(slot)
	if ability == null:
		indicator.clear()
		return
	var aim := _preview_direction(book)
	indicator.show_for(ability, aim, _preview_reach(ability, aim))


## The direction a cast would go out with RIGHT NOW, decided exactly the way the cast decides
## it: the command's aim if there is one, and the caster's own facing if there is not.
##
## Asking AbilityComponent for the fallback rather than working it out again is the point. The
## two answers agreeing is then a property of there being one answer.
func _preview_direction(book: AbilityComponent) -> Vector3:
	var command := _input.command
	if command.has_aim and command.aim_dir.length_squared() > 0.0001:
		return Vector3(command.aim_dir.x, 0.0, command.aim_dir.y).normalized()
	return book.caster_facing().normalized()


## How far the preview should reach, which is not always how far the spell does.
##
## A dash stops where it will actually land. A projectile stops at the rim: Fireball flies
## 21.6m and the arena is 14m across, so an honest lane is a stripe across the whole screen,
## most of it over a void where there is nothing left to hit. The fan is NOT trimmed - a wave
## cast at the edge really does catch someone hanging over it, and shortening the drawing
## would be a lie about who gets hit.
func _preview_reach(ability: Ability, aim: Vector3) -> float:
	match ability.cast_type:
		Ability.CastType.DASH:
			var landing := _blink_landing(_player, aim, ability)
			var travel := landing - _player.global_position
			return Vector2(travel.x, travel.z).length()
		Ability.CastType.PROJECTILE:
			return minf(ability.effective_range(), _distance_to_rim(_player.global_position, aim))
		_:
			return ability.effective_range()


## Metres from `from` to the arena's rim along `aim`, on the ground plane.
##
## A ray against a circle, solved rather than stepped. `from` is assumed to be inside the
## arena, which makes the near root negative and the far one the answer; a wizard already
## over the void gets the clamp below rather than a square root of a negative number.
func _distance_to_rim(from: Vector3, aim: Vector3) -> float:
	var p := Vector2(from.x, from.z)
	var d := Vector2(aim.x, aim.z)
	if d.length_squared() < 0.0001:
		return _arena_edge
	d = d.normalized()
	var b := p.dot(d)
	var c := p.length_squared() - _arena_edge * _arena_edge
	var disc := b * b - c
	if disc <= 0.0:
		return _arena_edge
	return maxf(-b + sqrt(disc), 0.5)


# ---------------------------------------------------------------------------------------
# Round wiring
#
# The round system never learns what a KillZone is, and the KillZone never learns what a
# round is. One reports that a body left the world; the other decides that this means
# elimination. Joining them is the level's job, like every other seam here.
# ---------------------------------------------------------------------------------------

func _wire_rounds() -> void:
	for fighter in _fighters:
		_rounds.add_fighter(fighter, _spawn_of(fighter), _title_of(fighter),
			fighter.team, _side_name(fighter.team))
	# A body that leaves the world entirely still counts - a hit hard enough to clear a 60m
	# lava field has earned it - but on a flat arena nothing reaches this any more. It is a
	# backstop now, not the rule.
	_kill_zone.fighter_fell.connect(_rounds.report_out)

	# Burning to nothing goes through the same door a fall does. The round system never learns
	# that lava exists, exactly as it never learned what a KillZone was.
	for fighter in _fighters:
		var hp := fighter.health()
		if hp != null:
			hp.emptied.connect(_rounds.report_out.bind(fighter))
	_rounds.round_started.connect(_on_round_started)
	_rounds.countdown_changed.connect(_on_countdown)
	_rounds.fighter_eliminated.connect(_on_eliminated)
	_rounds.round_ended.connect(_on_round_ended)
	_rounds.score_changed.connect(_hud.set_score)
	_rounds.match_ended.connect(_on_match_ended)


func _on_round_started(number: int) -> void:
	# A wizard put back on their spawn point must not set off toward wherever they had clicked
	# in the round before, nor open the round holding a spell they armed while dying in it.
	_move_target_set = false
	_input.clear_orders()
	_arena.reset()
	_feel.stopped_burning()
	_kill_zone.clear()
	_hud.set_round(number)
	print("[round] %d start" % number)


func _on_countdown(remaining: int) -> void:
	_hud.set_banner("GO" if remaining <= 0 else str(remaining))
	_feel.countdown(remaining)
	if remaining <= 0:
		# Let "GO" sit for a beat, then clear it rather than leaving it over the fight.
		await get_tree().create_timer(0.6).timeout
		if _rounds.is_live():
			_hud.set_banner("")


func _on_eliminated(fighter: Player, title: String) -> void:
	# Read before `eliminate()` hides the body - which the round system has already done by
	# the time this fires, but the position it left behind is still the right place to mark.
	_feel.eliminated(fighter.global_position, fighter == _player)
	print("[round] %s eliminated" % title)


func _on_round_ended(winner: Player, title: String) -> void:
	if winner == null:
		_hud.set_banner("DRAW", Color(0.85, 0.85, 0.9))
		print("[round] draw")
		return
	# "YOU WINS" reads badly. main.gd owns these titles, so main.gd conjugates them.
	_hud.set_banner("YOU WIN" if title == "YOU" else "%s WINS" % title,
		Color(1.0, 0.85, 0.35))
	_feel.round_over(winner == _player)
	print("[round] %s wins the round" % title)


func _on_match_ended(_winner: Player, title: String) -> void:
	_hud.set_banner("YOU TAKE THE MATCH" if title == "YOU" else "%s TAKES THE MATCH" % title,
		Color(0.55, 1.0, 0.6))
	print("[round] %s takes the match" % title)


func _run_cast_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# a moving target would make every flight assertion a coin toss.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var book := _player.abilities()
	var fireball := book.ability_in(0)
	print("[cast-test] %s: cooldown=%.2fs speed=%.0fm/s lifetime=%.2fs" % [
		fireball.id, fireball.cooldown, fireball.projectile_speed, fireball.lifetime])

	# --- the spellbook is data-driven ---------------------------------------------------
	_expect("slot 0 holds an Ability resource", fireball != null and fireball.id == &"fireball",
		"id=%s" % fireball.id)
	_expect("starts off cooldown", book.is_ready(0), "ready=%s" % book.is_ready(0))

	# --- pool starts prewarmed, nothing in flight ----------------------------------------
	var built_at_start := _pool.total_count()
	_expect("pool prewarmed, nothing in flight",
		_pool.active_count() == 0 and built_at_start > 0,
		"built=%d active=%d" % [built_at_start, _pool.active_count()])

	# --- stand inside the spell's own reach ----------------------------------------------
	#
	# Not at whatever distance the spawns happen to be. The fighters used to start 7m apart
	# while Fireball flew 21.6m, so every flight assertion below worked by accident; when the
	# arena grew to a 10m opening gap and the spell was cut to 6.3m, the shot expired in
	# mid-air and the suite reported a broken projectile. Half the reach is unambiguous and
	# still a real flight, and it re-derives itself if the numbers move again.
	var reach := fireball.effective_range() * 0.5
	await _place_fighters(Vector3(0.0, 1.2, -reach * 0.5), Vector3(0.0, 1.2, reach * 0.5))

	# Listening BEFORE the shot, not after it. Connecting afterwards is a race: the assertions
	# in between cost four physics ticks, and once the spell was retuned to leave at 15.5 m/s
	# the impact happened inside them - so the suite reported a projectile that never arrived
	# when in fact it had already arrived.
	var hit_body: Array = []
	_pool.projectile_hit.connect(func(b, _d, _a, _s): hit_body.append(b), CONNECT_ONE_SHOT)

	# --- a cast produces exactly one projectile ------------------------------------------
	var fired: bool = book.try_cast(0, Vector3(0, 0, -1))
	# One physics tick, NOT _settle(). _settle() straddles render frames, and on a machine
	# whose renderer is slower than its 60Hz physics a dozen ticks can turn over inside it -
	# by which time the spell has crossed the arena and the cooldown has visibly drained. The
	# suite then reports failures that are about the frame rate and not about the code (it
	# reported four of them here). Everything asserted below is gameplay state, so it waits
	# on the gameplay clock.
	await get_tree().physics_frame
	_expect("try_cast succeeded", fired, "returned %s" % fired)
	_expect("one projectile in flight", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())
	_expect("cast put the slot on cooldown", not book.is_ready(0),
		"remaining=%.2fs" % book.cooldown_remaining(0))
	_expect("cooldown fraction near 1.0 right after casting",
		book.cooldown_fraction(0) > 0.85, "fraction=%.2f" % book.cooldown_fraction(0))

	# --- a second cast during cooldown is refused ----------------------------------------
	var again: bool = book.try_cast(0, Vector3(0, 0, -1))
	_expect("second cast refused while on cooldown", not again, "returned %s" % again)
	_expect("refused cast spawned nothing", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())

	# --- it actually flies, in the aimed direction ---------------------------------------
	var shot: Projectile = null
	for child in _pool.get_children():
		if (child as Projectile).is_active():
			shot = child
			break
	var start_z: float = shot.global_position.z
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var moved: float = start_z - shot.global_position.z
	_expect("projectile travels along the aim (-Z)", moved > 0.1,
		"moved %.3fm in 3 ticks" % moved)

	# --- it hits the bot, and the pool takes it back -----------------------------------
	var waited := 0.0
	while _pool.active_count() > 0 and waited < 2.0:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	_expect("projectile reached the opponent", hit_body.size() == 1,
		"hits=%d after %.2fs" % [hit_body.size(), waited])
	_expect("pool reclaimed it", _pool.active_count() == 0,
		"active=%d" % _pool.active_count())
	_expect("the caster was not hit by its own spell",
		hit_body.size() == 1 and hit_body[0] != _player,
		"hit %s" % (hit_body[0].name if hit_body.size() > 0 else "<nothing>"))

	# --- cooldown expires and the slot comes back ----------------------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_expect("slot ready again after cooldown", book.is_ready(0),
		"fraction=%.2f" % book.cooldown_fraction(0))

	# --- reuse, not growth ----------------------------------------------------------------
	for i in 5:
		book.try_cast(0, Vector3(1, 0, 0))
		while not book.is_ready(0):
			await get_tree().physics_frame
		while _pool.active_count() > 0:
			await get_tree().physics_frame
	_expect("pool reuses instead of allocating", _pool.total_count() == built_at_start,
		"built %d at start, %d after 6 casts" % [built_at_start, _pool.total_count()])

	# --- the input latch turns one press into exactly one cast ----------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_input.request_ability(0)
	await _settle()
	_expect("a latched request casts once", _pool.active_count() == 1,
		"active=%d" % _pool.active_count())
	await _settle()
	_expect("the latch does not re-fire", book.cooldown_remaining(0) > 0.0 and _pool.active_count() <= 1,
		"active=%d remaining=%.2f" % [_pool.active_count(), book.cooldown_remaining(0)])

	print("[cast-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## The test the whole ownership design exists for: a left thumb steering while a right thumb
## casts. Two controls, two finger indices, neither aware of the other. If this ever fails,
## the game is unplayable on a phone no matter how good everything else is.
func _run_two_thumb_tests() -> void:
	# This suite is ABOUT the thumb controls, so it asks for them rather than
	# hoping the device shows them. AUTO now means a real touchscreen.
	_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# the wizard must move because the STICK moved it, nothing else.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var stick := _mobile.joystick
	var button := _mobile.buttons[0]
	var book := _player.abilities()
	var stick_centre := stick.get_global_rect().get_center()
	var button_centre := button.get_global_rect().get_center()
	print("[twothumb] stick=%s button=%s (gap %.0f units)" % [
		stick_centre, button_centre, stick_centre.distance_to(button_centre)])

	for i in _mobile.buttons.size():
		var other: AbilityButton = _mobile.buttons[i]
		_expect("stick and button %d do not overlap" % i,
			not stick.get_global_rect().grow(44.0).intersects(other.get_global_rect().grow(16.0)),
			"stick=%s button=%s" % [stick.get_global_rect(), other.get_global_rect()])
	# And no two spells share a finger. A cluster tight enough to thumb is a cluster tight
	# enough to mis-tap, and a mis-tapped Teleport at the rim is a lost round.
	for i in _mobile.buttons.size():
		for j in range(i + 1, _mobile.buttons.size()):
			var a: AbilityButton = _mobile.buttons[i]
			var b: AbilityButton = _mobile.buttons[j]
			var gap: float = a.get_global_rect().get_center().distance_to(b.get_global_rect().get_center())
			var need: float = a.radius + a.activation_padding + b.radius + b.activation_padding
			_expect("buttons %d and %d cannot share a finger" % [i, j], gap >= need,
				"centres %.0f apart, need %.0f" % [gap, need])

	# --- left thumb takes the stick -------------------------------------------------------
	_emit_touch(0, stick_centre, true)
	_emit_drag(0, stick_centre + Vector2(stick.base_radius, 0.0))
	await _settle()
	_expect("finger 0 owns the stick", stick.touch_index() == 0,
		"stick owner=%d" % stick.touch_index())
	_expect("button untouched by the stick's finger", button.touch_index() == -1,
		"button owner=%d" % button.touch_index())
	var moving_before: Vector2 = _input.command.move_dir

	# --- right thumb taps the button, while the left is still down ------------------------
	var before_active := _pool.active_count()
	_emit_touch(1, button_centre, true)
	await _settle()
	_expect("finger 1 owns the button", button.touch_index() == 1,
		"button owner=%d" % button.touch_index())
	_expect("stick keeps its own finger", stick.touch_index() == 0,
		"stick owner=%d" % stick.touch_index())
	_expect("movement is unaffected by the aim",
		_input.command.move_dir.is_equal_approx(moving_before),
		"before=%s after=%s" % [moving_before, _input.command.move_dir])
	# The press opens an aim and casts nothing. That is drag-to-aim, not a regression -
	# --aim-test is where the whole gesture is asserted.
	_expect("the press only starts aiming", _pool.active_count() == before_active,
		"active %d -> %d" % [before_active, _pool.active_count()])

	# --- releasing the right thumb casts, and must not disturb the left -------------------
	_emit_touch(1, button_centre, false)
	await _settle()
	_expect("the lift actually cast", _pool.active_count() == before_active + 1,
		"active %d -> %d" % [before_active, _pool.active_count()])
	_expect("casting put the slot on cooldown", not book.is_ready(0),
		"remaining=%.2fs" % book.cooldown_remaining(0))
	_expect("button released cleanly", button.touch_index() == -1,
		"button owner=%d" % button.touch_index())
	_expect("stick still steering after the button lifted",
		stick.touch_index() == 0 and _input.command.move_dir.is_equal_approx(moving_before),
		"stick owner=%d move_dir=%s" % [stick.touch_index(), _input.command.move_dir])

	# --- and the wizard really is moving while all this happens ---------------------------
	# Forty ticks, not ten. Under the map's movement model a wizard starting from rest is
	# still on its 0.6s acceleration ramp after ten - it covers eight centimetres, which this
	# read as "not moving" when it was moving exactly as designed. Forty ticks is two thirds
	# of a second and carries about half a metre.
	var pos_before: Vector3 = _player.global_position
	for i in 40:
		await get_tree().physics_frame
	var travelled: float = _player.global_position.distance_to(pos_before)
	_expect("wizard moved while casting", travelled > 0.3,
		"travelled %.2fm in 40 ticks" % travelled)

	# --- left thumb lifts -----------------------------------------------------------------
	_emit_touch(0, stick_centre, false)
	await _settle()
	_expect("both controls idle after both fingers lift",
		stick.touch_index() == -1 and button.touch_index() == -1
			and _input.command.move_dir.length() < 0.0001,
		"stick=%d button=%d move_dir=%s" % [
			stick.touch_index(), button.touch_index(), _input.command.move_dir])

	# --- a finger landing on neither control disturbs nothing -----------------------------
	var empty_spot := get_viewport().get_visible_rect().size * 0.5
	_emit_touch(3, empty_spot, true)
	await _settle()
	_expect("a touch on empty screen claims nothing",
		stick.touch_index() == -1 and button.touch_index() == -1,
		"stick=%d button=%d" % [stick.touch_index(), button.touch_index()])
	_emit_touch(3, empty_spot, false)
	await _settle()

	print("[twothumb] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Casts a spell N seconds in, so a delayed --shot can catch it. It goes through the same
## latch a thumb does, so the screenshot shows what a player would have seen.
func _cast_at(seconds: float, slot: int) -> void:
	await get_tree().create_timer(seconds).timeout
	_input.request_ability(slot)


# ---------------------------------------------------------------------------------------
# Knockback harness
#
# The central mechanic, so it is checked by measurement rather than by feel. Two things must
# hold: the same hit at the same instability always carries the same distance, and that
# distance is the one the formula intends. Linear drag makes the second checkable in closed
# form - v squared over 2f - which is exactly why the drag is linear.
# ---------------------------------------------------------------------------------------

## Hits the bot with a known speed and returns how far it slid on the ground plane.
func _measure_slide(speed: float, instability: float) -> float:
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame
	var start := _bot.global_position
	var impulse := Knockback.velocity(speed, Vector3(0, 0, -1), instability, knockback_rules)
	_bot.apply_knockback(impulse)
	var guard := 0
	while _bot.knockback_velocity().length() > 0.001 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	var moved := _bot.global_position - start
	return Vector2(moved.x, moved.z).length()


func _run_knockback_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# a slide with steering in it measures the bot, not the formula.
	_freeze_bot()
	# The countdown freezes fighters, so anything that casts or steers before the
	# round is live is measuring a fighter that was told to stand still.
	await _wait_for_live()
	var rules := knockback_rules
	print("[knockback] rules: base=%.1f per100=%.1f max=%.1f lift=%.1f | bot drag=%.2f/s" % [
		rules.base_multiplier, rules.per_100_instability, rules.max_multiplier, rules.lift,
		_bot.drag_per_second])
	# The reference map's own reading, printed rather than asserted: what one Fireball does to
	# a target at each stage of a round. This is the number to argue with after a play session,
	# and the reason it is printed is that no assertion can tell "far" from "too far".
	for points in [0.0, 50.0, 100.0, 150.0]:
		var shove := Knockback.base_impulse(7.0, 1.0) * Knockback.multiplier(points, rules)
		print("[knockback]   Fireball at %3d%%: %5.2f m/s, carries %5.2f m" % [
			int(points), shove, Knockback.slide_distance(shove, _bot.drag_per_second)])

	# --- the curve is pure arithmetic, check it directly ---------------------------------
	_expect("multiplier at 0% is 1.0",
		is_equal_approx(Knockback.multiplier(0.0, rules), 1.0),
		"%.3f" % Knockback.multiplier(0.0, rules))
	_expect("multiplier at 100% is 2.0",
		is_equal_approx(Knockback.multiplier(100.0, rules), 2.0),
		"%.3f" % Knockback.multiplier(100.0, rules))
	_expect("multiplier at 150% is 2.5",
		is_equal_approx(Knockback.multiplier(150.0, rules), 2.5),
		"%.3f" % Knockback.multiplier(150.0, rules))
	_expect("multiplier is capped",
		is_equal_approx(Knockback.multiplier(9999.0, rules), rules.max_multiplier),
		"%.3f" % Knockback.multiplier(9999.0, rules))

	# --- direction: you are thrown the way the spell was travelling ----------------------
	var dir_impulse := Knockback.velocity(6.0, Vector3(0, 0, -1), 0.0, rules)
	_expect("thrown along the spell's line", dir_impulse.z < -5.9 and absf(dir_impulse.x) < 0.01,
		"impulse=%s" % dir_impulse)
	_expect("a hit adds lift", is_equal_approx(dir_impulse.y, rules.lift),
		"y=%.2f" % dir_impulse.y)

	# --- measured slide matches the closed form ------------------------------------------
	# 2.0 m/s, not the 6.0 this used to use. Under exponential drag a hit carries `v/0.673`,
	# so 6.0 would slide the bot nine metres - off an eleven-metre ring and into the lava,
	# where it burns down mid-measurement and the number measures the kill zone instead.
	var base_speed := 2.0
	var predicted := Knockback.slide_distance(base_speed, _bot.drag_per_second)
	var measured := await _measure_slide(base_speed, 0.0)
	_expect("slide at 0% matches v/-ln(drag)",
		absf(measured - predicted) / predicted < 0.15,
		"predicted %.2fm, measured %.2fm" % [predicted, measured])

	# --- the same hit twice carries the same distance ------------------------------------
	var again := await _measure_slide(base_speed, 0.0)
	_expect("identical hits carry identical distance",
		absf(again - measured) < 0.02, "%.4fm then %.4fm" % [measured, again])

	# --- instability escalates it, LINEARLY ----------------------------------------------
	# This asserted 2.25x for a long time and the number was right for linear friction, where
	# distance went as speed squared. Exponential drag integrates to `v/k`, so distance is
	# linear in the impulse: 50% instability is 1.5x the speed and 1.5x the carry.
	#
	# That is a real loss of escalation and it is not being hidden here. What replaces it is
	# the absolute distances, which are much larger - a clean hit now crosses most of the
	# ring at zero instability, so the pressure comes from every exchange rather than only
	# from late ones. See docs/warlock-reference.md section 4.
	var at50 := await _measure_slide(base_speed, 50.0)
	var ratio := at50 / measured
	_expect("50% instability carries ~1.5x as far", absf(ratio - 1.5) < 0.15,
		"%.2fm vs %.2fm = %.2fx" % [at50, measured, ratio])

	# --- and eventually it throws you off ------------------------------------------------
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame
	# Sized off the arena rather than off a literal: this asserted `> 7.2` from the days of a
	# seven-metre ring and has been passing for free on every larger board since. A hit that
	# carries twice the diameter must clear any spawn, whichever way it points.
	var clear_it := 2.0 * _arena.radius * -log(_bot.drag_per_second)
	var hard := Knockback.velocity(clear_it, Vector3(0, 0, -1), 0.0, knockback_rules)
	_bot.apply_knockback(hard)
	var left_arena := false
	for i in 240:
		await get_tree().physics_frame
		var p := _bot.global_position
		if Vector2(p.x, p.z).length() > _arena.radius or p.y < 0.0:
			left_arena = true
			break
	_expect("a hit at 200% throws the target off the arena", left_arena,
		"ended at %s" % _bot.global_position)
	_bot.respawn_at(bot_spawn)
	for i in 20:
		await get_tree().physics_frame

	# --- instability accumulates, and a respawn clears it ---------------------------------
	var inst := _bot.instability()
	_expect("the target starts stable", is_equal_approx(inst.current, 0.0), "%.1f%%" % inst.current)
	inst.add(12.0)
	inst.add(12.0)
	_expect("instability accumulates", is_equal_approx(inst.current, 24.0),
		"%.1f%%" % inst.current)
	_bot.respawn_at(bot_spawn)
	_expect("respawn resets instability", is_equal_approx(inst.current, 0.0),
		"%.1f%%" % inst.current)

	# --- hitstun exists and expires ------------------------------------------------------
	_bot.apply_knockback(Knockback.velocity(base_speed, Vector3(0, 0, -1), 0.0, rules))
	_expect("a hit causes hitstun", _bot.is_in_hitstun(), "in hitstun=%s" % _bot.is_in_hitstun())
	var waited := 0
	while _bot.is_in_hitstun() and waited < 300:
		await get_tree().physics_frame
		waited += 1
	_expect("hitstun expires", not _bot.is_in_hitstun(), "after %d ticks" % waited)

	# --- end to end: a real Fireball raises instability and moves the target --------------
	_bot.respawn_at(bot_spawn)
	_player.respawn_at(spawn_point)
	for i in 20:
		await get_tree().physics_frame
	# Inside the spell's own reach, for the reason written on --cast-test's placement: the
	# fighters' spawn gap and Fireball's range are independent numbers, and a suite that
	# relies on them lining up reports a broken projectile when they stop.
	var shot_reach: float = _player.abilities().ability_in(0).effective_range() * 0.5
	await _place_fighters(Vector3(0.0, 1.2, -shot_reach * 0.5),
		Vector3(0.0, 1.2, shot_reach * 0.5))
	var before_pos := _bot.global_position
	_player.abilities().try_cast(0, Vector3(0, 0, -1))
	var hit_seen := false
	for i in 120:
		await get_tree().physics_frame
		if _bot.instability().current > 0.0:
			hit_seen = true
			break
	_expect("a cast Fireball raises the target's instability", hit_seen,
		"instability=%.1f%%" % _bot.instability().current)
	for i in 60:
		await get_tree().physics_frame
	var shifted := (_bot.global_position - before_pos)
	_expect("and pushes it away from the caster", shifted.z < -0.3,
		"moved %.2fm along z" % shifted.z)

	print("[knockback] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Waits until the round is actually live. The countdown freezes input, so a test that
## steers or casts before this returns is measuring a fighter that has been told to stand
## still - which looks exactly like a broken control and is not one.
func _wait_for_live() -> void:
	var guard := 0
	while not _rounds.is_live() and guard < 1200:
		await get_tree().process_frame
		guard += 1


func _run_round_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# a fighter that walks off on its own would end the round early.
	_freeze_bot()
	print("[round-test] countdown=%.1fs interlude=%.1fs wins_needed=%d" % [
		_rounds.countdown_seconds, _rounds.interlude_seconds, _rounds.wins_needed])

	# --- a match opens in countdown, with everyone frozen ---------------------------------
	_expect("match opens in countdown", _rounds.state == RoundManager.State.COUNTDOWN,
		"state=%d" % _rounds.state)
	_expect("fighters are frozen during the countdown",
		not _player.accepts_input and not _bot.accepts_input,
		"player=%s bot=%s" % [_player.accepts_input, _bot.accepts_input])
	_expect("round 1", _rounds.round_number == 1, "round=%d" % _rounds.round_number)
	_expect("score starts level", _rounds.wins_for("YOU") == 0 and _rounds.wins_for("BOT") == 0,
		"%s" % str(_rounds.scores()))

	# --- steering really is ignored while frozen ------------------------------------------
	_input.set_override_vector(Vector2(1, 0), true)
	var frozen_at := _player.global_position
	for i in 15:
		await get_tree().physics_frame
	var drift := Vector2(_player.global_position.x - frozen_at.x,
		_player.global_position.z - frozen_at.z).length()
	_expect("a frozen fighter does not move", drift < 0.05, "drifted %.3fm" % drift)

	# --- it goes live ---------------------------------------------------------------------
	await _wait_for_live()
	_expect("round goes live after the countdown", _rounds.is_live(), "state=%d" % _rounds.state)
	_expect("input is returned on go", _player.accepts_input and _bot.accepts_input,
		"player=%s bot=%s" % [_player.accepts_input, _bot.accepts_input])

	var live_at := _player.global_position
	# Forty-five ticks for the same reason as `--twothumb-test`: fifteen is a quarter of a
	# second, and a quarter of a second into a 0.6s ramp is eight centimetres of travel.
	for i in 45:
		await get_tree().physics_frame
	var moved := Vector2(_player.global_position.x - live_at.x,
		_player.global_position.z - live_at.z).length()
	_expect("and the fighter can move again", moved > 0.5, "moved %.2fm" % moved)
	_input.set_override_vector(Vector2.ZERO, false)

	# --- knock the bot off and check the whole cascade -----------------------------------
	_expect("two fighters standing", _rounds.alive_count() == 2,
		"alive=%d" % _rounds.alive_count())
	_bot.apply_knockback(Vector3(0, 4, -40))
	var guard := 0
	while _rounds.alive_count() > 1 and guard < 600:
		await get_tree().physics_frame
		guard += 1
	_expect("the faller is eliminated", _bot.is_eliminated(),
		"eliminated=%s pos=%s" % [_bot.is_eliminated(), _bot.global_position])
	_expect("an eliminated fighter is hidden", not _bot.visible, "visible=%s" % _bot.visible)
	_expect("round ends when one is left", _rounds.state == RoundManager.State.OVER,
		"state=%d" % _rounds.state)
	_expect("the survivor scores", _rounds.wins_for("YOU") == 1,
		"scores=%s" % str(_rounds.scores()))
	_expect("the faller does not", _rounds.wins_for("BOT") == 0,
		"scores=%s" % str(_rounds.scores()))

	# --- and it all resets -----------------------------------------------------------------
	_player.instability().add(40.0)
	var guard2 := 0
	while _rounds.round_number < 2 and guard2 < 1200:
		await get_tree().process_frame
		guard2 += 1
	_expect("a new round begins", _rounds.round_number == 2, "round=%d" % _rounds.round_number)
	_expect("the eliminated fighter is back", not _bot.is_eliminated() and _bot.visible,
		"eliminated=%s visible=%s" % [_bot.is_eliminated(), _bot.visible])
	_expect("both are standing again", _rounds.alive_count() == 2,
		"alive=%d" % _rounds.alive_count())
	_expect("instability is cleared on reset",
		is_equal_approx(_player.instability().current, 0.0),
		"player=%.1f%%" % _player.instability().current)
	_expect("fighters are back at their spawns",
		_bot.global_position.distance_to(bot_spawn) < 0.5,
		"bot at %s, spawn %s" % [_bot.global_position, bot_spawn])
	_expect("the score carries across rounds", _rounds.wins_for("YOU") == 1,
		"scores=%s" % str(_rounds.scores()))
	_expect("the new round starts frozen again",
		_rounds.state == RoundManager.State.COUNTDOWN, "state=%d" % _rounds.state)

	# --- a fall outside a live round is ignored --------------------------------------------
	var before := _rounds.alive_count()
	_rounds.report_out(_bot)
	_expect("a fall during the countdown is ignored", _rounds.alive_count() == before,
		"alive %d -> %d" % [before, _rounds.alive_count()])

	# --- the match ends when someone reaches the target ------------------------------------
	# The real 3s countdown and 2s interlude have already been verified above. Shorten them
	# now so proving the match-end condition does not cost thirty seconds of wall clock.
	_rounds.countdown_seconds = 0.15
	_rounds.interlude_seconds = 0.15
	await _wait_for_live()
	# An Array, not a bool. GDScript lambdas capture local variables BY VALUE, so
	# `matched = true` inside the closure would write to a copy and the outer variable would
	# stay false forever. Arrays are reference types, so appending is visible outside.
	var matched: Array = []
	_rounds.match_ended.connect(func(_w, _t): matched.append(true), CONNECT_ONE_SHOT)
	var safety := 0
	# Exit on the signal, not on the score: start_match() zeroes the wins the moment the
	# match is won, so a score-based condition would never see the target reached.
	while matched.is_empty() and safety < 40:
		await _wait_for_live()
		_rounds.report_out(_bot)
		var g := 0
		while _rounds.state != RoundManager.State.COUNTDOWN and g < 1200:
			await get_tree().process_frame
			g += 1
		safety += 1
	_expect("reaching the target ends the match", not matched.is_empty(),
		"wins=%d needed=%d" % [_rounds.wins_for("YOU"), _rounds.wins_needed])

	print("[round-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Bot harness
#
# The bot is the first thing in this project that PLAYS the game, so it is judged the way a
# player would be: does it hold its distance, does it point at what it is shooting at, does
# it stay on the arena, does difficulty change anything, and does it cheat. Almost none of
# this reads the bot's internals - the assertions read the same InputCommand the fighter
# reads and the same positions a screenshot would show, so a bot rewritten from scratch
# would still have to pass them.
# ---------------------------------------------------------------------------------------

## Puts both fighters where a test wants them and holds them there while the bot notices.
##
## Pinned every tick, not placed once. The bot's reaction time is a real delay, so a reading
## taken on the frame after a teleport is its memory of the PREVIOUS arrangement - which
## looks exactly like a broken bot and is not one. Holding them still also means the answer
## is about the arrangement that was asked for, and not about wherever the two of them had
## walked to by the time the reading was taken.
func _place_fighters(bot_at: Vector3, player_at: Vector3) -> void:
	await _wait_for_live()
	var settled := 0.0
	while settled < 0.75:
		_bot.respawn_at(bot_at)
		_player.respawn_at(player_at)
		await get_tree().physics_frame
		settled += 1.0 / 60.0


## Distance from the centre of the arena, on the ground plane.
func _radius_of(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


## Metres between the two fighters, on the ground plane.
func _gap() -> float:
	return Vector2(_bot.global_position.x - _player.global_position.x,
		_bot.global_position.z - _player.global_position.z).length()


## Unit vector from the bot to the player: what a perfect aim would be.
func _true_aim() -> Vector2:
	var offset := Vector2(_player.global_position.x - _bot.global_position.x,
		_player.global_position.z - _bot.global_position.z)
	if offset.length_squared() < 0.0001:
		return Vector2.ZERO
	return offset.normalized()


## Which way a fighter's wizard is actually pointing. Same convention as player.gd's facing:
## yaw 0 looks down -Z, so a yaw of `a` looks along (-sin a, -cos a).
func _facing_of(fighter: Player) -> Vector2:
	var visual := fighter.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return Vector2.ZERO
	return Vector2(-sin(visual.rotation.y), -cos(visual.rotation.y))


func _run_bot_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# The bot rolls its aim error and its strafe timing. A suite that fails one run in ten is
	# worse than no suite at all, so the random stream is pinned for the duration.
	_brain.reseed(20260823)
	# The human stands still throughout: a zero override beats both the keyboard and the
	# stick, so nothing that happens to be held can wander the player into a measurement.
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var budget: float = float(BotController.PROFILES[_brain.skill]["aim_error"]) + 8.0
	print("[bot-test] skill=%d reaction=%.2fs aim_error=%.1fdeg safe=%.2fm of %.2fm" % [
		_brain.skill,
		float(BotController.PROFILES[_brain.skill]["reaction"]),
		float(BotController.PROFILES[_brain.skill]["aim_error"]),
		_brain.safe_radius(), _brain.arena_radius])

	# --- one seam, two drivers -----------------------------------------------------------
	_expect("both fighters are driven through the same seam",
		_player.input_controller is PlayerInputController
			and _bot.input_controller is PlayerInputController
			and _player.input_controller != _bot.input_controller,
		"player=%s bot=%s" % [_player.input_controller, _bot.input_controller])
	_expect("the bot drives the fighter it was handed",
		_brain.body == _bot and _brain.target == _player,
		"body=%s target=%s" % [_brain.body, _brain.target])
	# Read the platform's own shape here rather than repeating a number. Asserting against a
	# literal 7.0 stopped meaning anything the moment the arena grew - and worse, it went on
	# passing right up until the export default happened to match it.
	var shape := get_node_or_null(^"Arena/Platform/Collision") as CollisionShape3D
	var measured: float = (shape.shape as CylinderShape3D).radius if shape != null else -1.0
	_expect("the arena radius is read off the arena, not typed in",
		shape != null and is_equal_approx(_brain.arena_radius, measured),
		"bot has %.2fm, the platform is %.2fm" % [_brain.arena_radius, measured])

	# --- and no device can reach it -------------------------------------------------------
	# A key that a device-polling controller would obey. The bot inherits exactly such a
	# controller and overrides its _process to nothing; this is that override, asserted. With
	# move_left held down, the bot must still walk towards a target that is to its RIGHT.
	Input.action_press("move_left")
	await _place_fighters(Vector3(-4.0, 1.2, 0.0), Vector3(4.5, 1.2, 0.0))
	var keyed: Vector2 = _brain.command.move_dir
	Input.action_release("move_left")
	_expect("a held key cannot steer the bot", keyed.dot(Vector2(1.0, 0.0)) > 0.3,
		"move_left held, bot asked for %s" % keyed)

	# --- keeping its distance -------------------------------------------------------------
	_expect("too far away: it closes in", keyed.dot(Vector2(1.0, 0.0)) > 0.3,
		"gap %.1fm -> %s" % [_gap(), keyed])

	await _place_fighters(Vector3(0.0, 1.2, 0.0), Vector3(1.6, 1.2, 0.0))
	_expect("too close: it backs off", _brain.command.move_dir.dot(Vector2(-1.0, 0.0)) > 0.3,
		"gap %.1fm -> %s" % [_gap(), _brain.command.move_dir])

	# The distance it HOLDS, not the one it prefers - the spell's reach clamps the first.
	var half := _brain.holding_range() * 0.5
	await _place_fighters(Vector3(-half, 1.2, 0.0), Vector3(half, 1.2, 0.0))
	_expect("at its preferred range it circles instead of charging",
		absf(_brain.command.move_dir.dot(Vector2(1.0, 0.0))) < 0.25,
		"gap %.1fm -> %s" % [_gap(), _brain.command.move_dir])

	# --- aiming at what it is shooting at ---------------------------------------------------
	var aim: Vector2 = _brain.command.aim_dir
	var wanted := _true_aim()
	_expect("it always has an aim", _brain.command.has_aim and aim.length() > 0.99,
		"has_aim=%s aim=%s" % [_brain.command.has_aim, aim])
	var aim_off := rad_to_deg(absf(aim.angle_to(wanted)))
	_expect("the aim lands inside the skill's error budget", aim_off <= budget,
		"%.1f degrees off, budget %.1f" % [aim_off, budget])
	# move_dir and aim_dir have been separate fields since Session 3 with nothing to prove
	# it. This is the first thing in the project that fills them differently.
	_expect("it aims where it is not walking",
		absf(aim.dot(_brain.command.move_dir)) < 0.5,
		"aim=%s move=%s" % [aim, _brain.command.move_dir])
	var face_off := rad_to_deg(absf(_facing_of(_bot).angle_to(wanted)))
	_expect("and the wizard is turned to face it", face_off <= budget,
		"%.1f degrees off, budget %.1f" % [face_off, budget])

	# --- it will not walk off ---------------------------------------------------------------
	# Standing past its own safe line, with the target luring it further out. From here the
	# one rule it may never break is asking to move outward.
	await _place_fighters(Vector3(_brain.safe_radius() + 0.5, 1.2, 0.0), Vector3(9.0, 1.2, 0.0))
	var outward := Vector2(1.0, 0.0)
	_expect("past the safe line it never asks to go further out",
		_brain.command.move_dir.dot(outward) <= 0.001,
		"at %.2fm (safe %.2fm) -> %s" % [
			_radius_of(_bot.global_position), _brain.safe_radius(), _brain.command.move_dir])
	_expect("it heads back towards the centre",
		_brain.command.move_dir.dot(-outward) > 0.3, "move=%s" % _brain.command.move_dir)

	# Now let it run, with the lure still sitting off the rim. Being thrown off the arena is
	# the game; walking off it is a bug.
	var lure := Vector3(8.5, 1.2, 0.0)
	var worst := 0.0
	var elapsed := 0.0
	while elapsed < 6.0:
		_player.respawn_at(lure)
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		# The first stretch is the walk back in from the placement above, which is the bot
		# obeying the rule rather than breaking it.
		if elapsed > 1.2:
			worst = maxf(worst, _radius_of(_bot.global_position))
	_expect("chasing a target off the arena, it stays on the arena",
		worst <= _brain.safe_radius() + 0.35,
		"reached %.2fm, safe line %.2fm, rim %.2fm" % [
			worst, _brain.safe_radius(), _brain.arena_radius])
	_expect("and is still standing", not _bot.is_eliminated(),
		"eliminated=%s at %s" % [_bot.is_eliminated(), _bot.global_position])

	# --- and it actually fights ---------------------------------------------------------------
	var post := Vector3(0.0, 1.2, 0.0)
	# At the distance the bot actually holds, not the raw preference. Those two stopped being
	# the same number when the spell's reach started clamping it.
	await _place_fighters(Vector3(0.0, 1.2, -_brain.holding_range()), post)
	# Arrays, not counters. A GDScript lambda captures a local by VALUE, so an int would be
	# incremented inside the closure and stay zero outside it - see ARCHITECTURE.md.
	var casts: Array = []
	var landed: Array = []
	var on_cast := func(_slot: int, _ability: Ability) -> void:
		casts.append(1)
	var on_hit := func(body: Node3D, _direction: Vector3, _ability: Ability,
			_shooter: Node3D) -> void:
		if body == _player:
			landed.append(1)
	_bot.abilities().cast_performed.connect(on_cast)
	_pool.projectile_hit.connect(on_hit)
	# The window is derived from the spell rather than fixed at five seconds. Fireball's
	# cooldown is the map's 4.8s, so five seconds is ONE cast and this asserted two - it was
	# measuring the cooldown, not the bot. Two and a bit cooldowns is what "casts repeatedly"
	# means for whatever spell the bot happens to be holding.
	var primary := _bot.abilities().ability_in(0)
	var window := primary.cooldown * 2.2 + 1.0
	var fighting := 0.0
	while fighting < window:
		_player.respawn_at(post)
		await get_tree().physics_frame
		fighting += 1.0 / 60.0
	_bot.abilities().cast_performed.disconnect(on_cast)
	_pool.projectile_hit.disconnect(on_hit)
	_expect("it uses its spell unprompted", casts.size() >= 2,
		"%d casts in %.1fs, on a %.1fs cooldown" % [casts.size(), window, primary.cooldown])
	_expect("and lands them on a stationary target", landed.size() >= 1,
		"%d of %d casts hit" % [landed.size(), casts.size()])

	# --- difficulty is real, and it is not a stat bonus ----------------------------------------
	var calm: Dictionary = BotController.PROFILES[BotController.Skill.CALM]
	var sharp: Dictionary = BotController.PROFILES[BotController.Skill.SHARP]
	_expect("a sharper bot reacts sooner", float(sharp["reaction"]) < float(calm["reaction"]),
		"sharp %.2fs vs calm %.2fs" % [float(sharp["reaction"]), float(calm["reaction"])])
	_expect("a sharper bot aims truer", float(sharp["aim_error"]) < float(calm["aim_error"]),
		"sharp %.1fdeg vs calm %.1fdeg" % [float(sharp["aim_error"]), float(calm["aim_error"])])
	_expect("a sharper bot shoots more often", float(sharp["cast_gap"]) < float(calm["cast_gap"]),
		"sharp %.2fs vs calm %.2fs" % [float(sharp["cast_gap"]), float(calm["cast_gap"])])
	_expect("a sharper bot respects the edge more",
		float(sharp["edge_margin"]) > float(calm["edge_margin"]),
		"sharp %.2fm vs calm %.2fm" % [float(sharp["edge_margin"]), float(calm["edge_margin"])])

	var was := _brain.skill
	_brain.skill = BotController.Skill.CALM
	var calm_line := _brain.safe_radius()
	_brain.skill = BotController.Skill.SHARP
	var sharp_line := _brain.safe_radius()
	_brain.skill = was
	_expect("changing difficulty takes effect at once", sharp_line < calm_line,
		"safe radius: calm %.2fm, sharp %.2fm" % [calm_line, sharp_line])

	# The assertion the whole difficulty design exists for. A bot that cheated on speed, on
	# how far a hit throws it, or on which spell it carries would be teaching the player
	# about a game nobody else is playing.
	_expect("the bot fights with the player's numbers",
		is_equal_approx(_bot.move_speed, _player.move_speed)
			and is_equal_approx(_bot.drag_per_second, _player.drag_per_second)
			and is_equal_approx(_bot.acceleration, _player.acceleration)
			and is_equal_approx(_bot.hitstun_per_speed, _player.hitstun_per_speed),
		"speed %.2f/%.2f drag %.2f/%.2f" % [
			_bot.move_speed, _player.move_speed,
			_bot.drag_per_second, _player.drag_per_second])
	_expect("and with the player's spell",
		_bot.abilities().ability_in(0) == _player.abilities().ability_in(0),
		"%s vs %s" % [_bot.abilities().ability_in(0).id, _player.abilities().ability_in(0).id])

	# --- a countdown freezes it, with nothing queued up behind the freeze -----------------------
	_rounds.begin_round()
	await _settle()
	var parked := _bot.global_position
	for i in 20:
		await get_tree().physics_frame
	var drift := Vector2(_bot.global_position.x - parked.x,
		_bot.global_position.z - parked.z).length()
	_expect("a frozen bot does not steer", drift < 0.05, "drifted %.3fm" % drift)
	_expect("and holds no cast behind the countdown", _brain.command.ability_pressed == -1,
		"latched slot %d" % _brain.command.ability_pressed)
	_input.set_override_vector(Vector2.ZERO, false)

	print("[bot-test] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Spell harness
#
# Three of the four spells do not throw a projectile, so nothing about them can be watched
# flying across the arena. Scourge hits on the frame it is cast, Teleport moves the caster
# between one tick and the next, and Shield is a number that changes what a LATER hit
# does. Each of those is easy to write and easy to get silently wrong, which is exactly the
# shape of thing that needs measuring rather than playing.
# ---------------------------------------------------------------------------------------

## First slot holding a spell of the given type, or -1. The suite finds spells the way the
## bot does, by what they ARE, so re-ordering the spellbook cannot quietly re-point a test.
func _slot_with(book: AbilityComponent, cast_type: Ability.CastType) -> int:
	for slot in book.slot_count():
		var ability := book.ability_in(slot)
		if ability != null and ability.cast_type == cast_type:
			return slot
	return -1


## Flat displacement of the bot over `seconds`, starting now.
func _drift_of(fighter: Player, seconds: float) -> Vector2:
	var from := fighter.global_position
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	return Vector2(fighter.global_position.x - from.x, fighter.global_position.z - from.z)


func _run_spell_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# The suite casts AT the bot and measures where it ends up, so it must not steer.
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()

	var book := _player.abilities()
	var target := _bot.instability()
	var fireball := _slot_with(book, Ability.CastType.PROJECTILE)
	var cone := _slot_with(book, Ability.CastType.CONE)
	var dash := _slot_with(book, Ability.CastType.DASH)
	var buff := _slot_with(book, Ability.CastType.BUFF)
	print("[spells] slots: projectile=%d cone=%d dash=%d buff=%d of %d" % [
		fireball, cone, dash, buff, book.slot_count()])

	# --- the loadout ---------------------------------------------------------------------
	_expect("the wizard carries four spells", book.slot_count() == 4,
		"%d slots" % book.slot_count())
	_expect("one of each cast type, and all four found",
		fireball >= 0 and cone >= 0 and dash >= 0 and buff >= 0,
		"projectile=%d cone=%d dash=%d buff=%d" % [fireball, cone, dash, buff])
	_expect("the keyboard can reach every slot",
		InputMap.has_action("cast_1") and InputMap.has_action("cast_2")
			and InputMap.has_action("cast_3") and InputMap.has_action("cast_4"),
		"cast_1..4 in the input map")

	var wave := book.ability_in(cone)
	var jump := book.ability_in(dash)
	var shield := book.ability_in(buff)

	# --- Scourge: it hits what is in the fan --------------------------------------------
	# The bot is put two and a half metres along +X, and the wave is aimed the same way.
	await _place_fighters(Vector3(2.5, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	var before: float = target.current
	var cone_fired: bool = book.try_cast(cone, Vector3(1, 0, 0))
	_expect("Scourge was ready", cone_fired, "try_cast returned %s" % cone_fired)
	await get_tree().physics_frame
	_expect("a target inside the fan is hit",
		is_equal_approx(target.current - before, wave.damage),
		"damage points %.0f%% -> %.0f%%, spell adds %.0f" % [before, target.current, wave.damage])
	var pushed := await _drift_of(_bot, 0.35)
	_expect("and is thrown away from the caster", pushed.x > 1.0 and absf(pushed.y) < 0.6,
		"moved %s" % pushed)
	# Scourge is the map's heaviest single hit - 10 damage against Fireball's 7 - even though
	# it shoves at 0.8 where Fireball shoves at 1.0. The comparison is the impulse, not either
	# field on its own, which is the point of collapsing the three fields into one.
	var wave_push := Knockback.base_impulse(wave.damage, wave.push_mult)
	var ball := book.ability_in(fireball)
	var ball_push := Knockback.base_impulse(ball.damage, ball.push_mult)
	_expect("the close-range burst hits harder than Fireball", wave_push > ball_push,
		"%.2f vs %.2f m/s" % [wave_push, ball_push])

	# --- ...and misses what is not ----------------------------------------------------------
	# Out of range: the same aim, half again as far as the fan is long.
	await _place_fighters(Vector3(wave.area * 1.5, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	before = target.current
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	_expect("a target beyond the fan's reach is missed",
		is_equal_approx(target.current, before),
		"at %.1fm, reach %.1fm, instability %.0f%%" % [wave.area * 1.5, wave.area, target.current])

	# Out of angle: well inside the reach, but off to the side of where the wave was aimed.
	await _place_fighters(Vector3(0.0, 1.2, -2.5), Vector3(0.0, 1.2, 0.0))
	book.reset()
	before = target.current
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	_expect("a target beside the fan is missed", is_equal_approx(target.current, before),
		"90 degrees off a %.0f degree half-angle, instability %.0f%%" % [wave.cone_angle, target.current])

	# The push follows the line out from the caster, not the line the wave was aimed along.
	# That is the whole reason Scourge is a finisher: standing at the shoulder of the fan
	# throws you sideways, which near a rim is off it.
	await _place_fighters(Vector3(2.0, 1.2, -1.6), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(cone, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var shoved := await _drift_of(_bot, 0.35)
	_expect("the push is away from the caster, not along the aim",
		shoved.y < -0.4 and shoved.x > 0.4,
		"target sat up and left of the aim; it moved %s" % shoved)

	# --- Teleport: it moves you, exactly as far as it says --------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	var from := _player.global_position
	var dash_fired: bool = book.try_cast(dash, Vector3(1, 0, 0))
	_expect("Teleport was ready", dash_fired, "try_cast returned %s" % dash_fired)
	await get_tree().physics_frame
	var jumped := Vector2(_player.global_position.x - from.x, _player.global_position.z - from.z)
	_expect("Teleport moves the caster its full distance",
		absf(jumped.x - jump.dash_distance) < 0.2 and absf(jumped.y) < 0.2,
		"moved %s, spell says %.1fm" % [jumped, jump.dash_distance])
	_expect("and put itself on cooldown", not book.is_ready(dash),
		"remaining %.2fs" % book.cooldown_remaining(dash))

	# --- ...and never into the void -----------------------------------------------------------
	var rim := _arena_edge - 0.4
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(rim, 1.2, 0.0))
	book.reset()
	book.try_cast(dash, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var landed := _radius_of(_player.global_position)
	_expect("Teleport aimed off the arena lands on the arena", landed <= _arena_edge - 0.5,
		"from %.2fm outward, landed at %.2fm, rim %.2fm" % [rim, landed, _arena_edge])

	# --- ...and cancels the slide, but not the stun --------------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	_player.apply_knockback(Knockback.velocity(8.0, Vector3(1, 0, 0), 0.0, knockback_rules))
	_expect("hit, and sliding", _player.knockback_velocity().length() > 1.0,
		"%.1f m/s" % _player.knockback_velocity().length())
	book.try_cast(dash, Vector3(-1, 0, 0))
	await get_tree().physics_frame
	_expect("Teleport cancels the slide", _player.knockback_velocity().length() < 0.01,
		"%.3f m/s" % _player.knockback_velocity().length())
	_expect("but not the hitstun, so it is not a free reset", _player.is_in_hitstun(),
		"in hitstun=%s" % _player.is_in_hitstun())

	# --- Shield: it goes up, and it comes down --------------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	var buff_fired: bool = book.try_cast(buff, Vector3.ZERO)
	_expect("Shield was ready", buff_fired, "try_cast returned %s" % buff_fired)
	await get_tree().physics_frame
	_expect("the shield is up", _player.is_shielded(), "is_shielded=%s" % _player.is_shielded())
	var elapsed := 0.0
	while _player.is_shielded() and elapsed < shield.duration * 3.0:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
	_expect("and it expires on time", absf(elapsed - shield.duration) < 0.12,
		"lasted %.2fs, spell says %.2fs" % [elapsed, shield.duration])

	# --- ...and a shielded hit carries less ---------------------------------------------------------
	# The same hit, twice, on the same body: once bare, once behind the shield. Measured as
	# distance travelled, because that is the thing a player actually experiences.
	var blow := Knockback.velocity(8.0, Vector3(1, 0, 0), 0.0, knockback_rules)
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	_player.apply_knockback(blow)
	var bare := await _drift_of(_player, 0.7)
	await _place_fighters(Vector3(0.0, 1.2, -5.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(buff, Vector3.ZERO)
	await get_tree().physics_frame
	_player.apply_knockback(blow)
	var guarded := await _drift_of(_player, 0.7)
	_expect("a shielded hit carries a fraction as far",
		guarded.length() < bare.length() * 0.5 and bare.length() > 0.5,
		"%.2fm bare, %.2fm shielded (spell lets %.0f%% through)" % [
			bare.length(), guarded.length(), shield.knockback_resist * 100.0])

	print("[spells] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## The four buttons, end to end: a finger on button N casts spell N and nothing else.
##
## Separate from the suite above because it needs injected touch and therefore a real window,
## while everything above is arithmetic and physics that would run anywhere.
func _run_button_tests() -> void:
	# This suite is ABOUT the thumb controls, so it asks for them rather than
	# hoping the device shows them. AUTO now means a real touchscreen.
	_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var book := _player.abilities()
	_expect("there is a button per spell", _mobile.buttons.size() == book.slot_count(),
		"%d buttons, %d spells" % [_mobile.buttons.size(), book.slot_count()])

	for i in _mobile.buttons.size():
		var button: AbilityButton = _mobile.buttons[i]
		_expect("button %d drives slot %d" % [i, i], button.slot == i, "slot=%d" % button.slot)
		_expect("button %d can read its spell" % i, button.source == book,
			"source=%s" % button.source)

	for i in _mobile.buttons.size():
		var button: AbilityButton = _mobile.buttons[i]
		while not book.is_ready(i):
			await get_tree().physics_frame
		var centre := button.get_global_rect().get_center()
		_emit_touch(0, centre, true)
		await _settle()
		_emit_touch(0, centre, false)
		await _settle()
		_expect("tapping button %d casts %s" % [i, book.ability_in(i).id],
			not book.is_ready(i), "remaining %.2fs" % book.cooldown_remaining(i))

	# A finger between two buttons must not cast either. The hit areas are discs, so the
	# corner where two bounding boxes would have overlapped belongs to nobody.
	var a: AbilityButton = _mobile.buttons[0]
	var b: AbilityButton = _mobile.buttons[1]
	# The midpoint of the FREE interval, not the midpoint of the line: the primary button is
	# larger, so halfway between two centres is still inside the big one.
	var ca := a.get_global_rect().get_center()
	var cb := b.get_global_rect().get_center()
	var span := ca.distance_to(cb)
	var near := a.radius + a.activation_padding
	var far := span - (b.radius + b.activation_padding)
	var between := ca.lerp(cb, ((near + far) * 0.5) / maxf(span, 0.001))
	_emit_touch(1, between, true)
	await _settle()
	_expect("a tap in the gap between two buttons claims nothing",
		a.touch_index() == -1 and b.touch_index() == -1,
		"gap at %s claimed by %d/%d" % [between, a.touch_index(), b.touch_index()])
	_emit_touch(1, between, false)
	await _settle()

	print("[buttons] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Aim harness
#
# Drag-to-aim is three claims, and only the first is easy to see by playing: a press opens an
# aim instead of casting, the lift fires along the line the thumb drew, and the direction
# latched at the lift survives the gap before the character consumes it. That third one is
# the reason this suite exists. It fails only when a render frame lands between the lift and
# the physics tick, which on a desktop is roughly never and on a phone under load is often -
# so it is exactly the bug that ships.
# ---------------------------------------------------------------------------------------

## How far the harness drags, in canvas units. Comfortably past the aim deadzone, so a test
## failing here is about the aim and not about the threshold.
const AIM_DRAG := 130.0


## Screen-right and screen-forward, on the ground plane, read off the live camera.
##
## Worked out from the camera rather than assumed to be +X and -Z. The camera is un-yawed
## today, so the two agree - and the day it is not, this suite says which of the two moved.
func _screen_axes() -> Array:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return [Vector2.RIGHT, Vector2.UP]
	var right3: Vector3 = cam.global_transform.basis.x
	var fwd3: Vector3 = -cam.global_transform.basis.z
	return [
		Vector2(right3.x, right3.z).normalized(),
		Vector2(fwd3.x, fwd3.z).normalized(),
	]


## Flat direction of the last cast the player made.
func _last_aim() -> Vector2:
	var flat := Vector2(_last_cast_dir.x, _last_cast_dir.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector2.ZERO


## Presses button `slot`, drags `screen_dir` (y-up), and leaves the finger down.
## Returns where the finger now is, so the caller can lift it in the right place - a lift at
## the button centre would erase the drag and turn the whole gesture back into a tap.
func _drag_aim(slot: int, screen_dir: Vector2) -> Vector2:
	var button: AbilityButton = _mobile.buttons[slot]
	var centre := button.get_global_rect().get_center()
	_emit_touch(0, centre, true)
	await _settle()
	var to := centre + Vector2(screen_dir.x, -screen_dir.y).normalized() * AIM_DRAG
	_emit_drag(0, to)
	await _settle()
	return to


func _run_aim_tests() -> void:
	# This suite is ABOUT the thumb controls, so it asks for them rather than
	# hoping the device shows them. AUTO now means a real touchscreen.
	_mobile.visibility_mode = MobileControls.Visibility.ALWAYS
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	# Nothing here is about the opponent, and a bot walking into a Fireball would end a round
	# in the middle of a measurement.
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var book := _player.abilities()
	var indicator := _player.aim_indicator()
	var axes := _screen_axes()
	var screen_right: Vector2 = axes[0]
	var screen_fwd: Vector2 = axes[1]
	var fireball := book.ability_in(0)
	print("[aim-test] deadzone=%.0f drag=%.0f right=%s forward=%s" % [
		_input.aim_deadzone, AIM_DRAG, screen_right, screen_fwd])

	_expect("the fighter has an aim indicator", indicator != null,
		"indicator=%s" % indicator)
	if indicator == null:
		get_tree().quit(1)
		return
	_expect("nothing is drawn before a finger lands", not indicator.is_showing(), "clear")

	# --- a press opens the aim, and casts nothing -----------------------------------------
	var button: AbilityButton = _mobile.buttons[0]
	var centre := button.get_global_rect().get_center()
	var before := _pool.active_count()
	_emit_touch(0, centre, true)
	await _settle()
	_expect("press starts aiming slot 0", _input.command.aiming_slot == 0,
		"aiming=%d" % _input.command.aiming_slot)
	_expect("press alone casts nothing",
		_pool.active_count() == before and book.is_ready(0),
		"active=%d ready=%s" % [_pool.active_count(), book.is_ready(0)])
	_expect("the indicator is up", indicator.is_showing(),
		"shape=%d" % indicator.shape())
	_expect("a projectile draws a lane", indicator.shape() == AimIndicator.Shape.LANE,
		"shape=%d" % indicator.shape())

	# A lane that FITS shows the whole spell. Fireball reaches 5.4m on a 20m arena, so from
	# a spawn there is nothing to trim - and asserting a trim here is what broke the moment
	# the spell stopped out-ranging the board.
	_expect("a lane that fits shows the spell's whole reach",
		is_equal_approx(indicator.reach(), fireball.effective_range()),
		"reach %.2fm of %.2fm" % [indicator.reach(), fireball.effective_range()])

	# --- and a lane that would overrun IS trimmed, at the rim -----------------------------
	#
	# Standing one metre inside the rim and aiming out. Measured from the position and the
	# aim rather than by asking the code that drew it: the far end has to land ON the rim.
	_emit_touch(0, centre, false)
	await _settle()
	while not book.is_ready(0):
		await get_tree().physics_frame
	await _place_fighters(Vector3(0.0, 1.2, -3.0), Vector3(_arena_edge - 1.0, 1.2, 0.0))
	var rim_at := await _drag_aim(0, Vector2(1.0, 0.0))
	var tip := _player.global_position + _preview_direction(book) * indicator.reach()
	_expect("a lane that would overrun stops at the rim",
		indicator.reach() < fireball.effective_range()
			and absf(_radius_of(tip) - _arena_edge) < 0.05,
		"reach %.2fm of %.2fm, tip at r=%.2f (edge %.2f)" % [
			indicator.reach(), fireball.effective_range(), _radius_of(tip), _arena_edge])
	_emit_touch(0, rim_at, false)
	await _settle()
	while not book.is_ready(0):
		await get_tree().physics_frame
	await _place_fighters(Vector3(0.0, 1.2, -3.0), Vector3(0.0, 1.2, 0.0))
	_emit_touch(0, centre, true)
	await _settle()

	# --- a small roll is a tap, not an aim ------------------------------------------------
	_emit_drag(0, centre + Vector2(10.0, 0.0))
	await _settle()
	_expect("a roll under the deadzone is not an aim", not _input.command.has_aim,
		"has_aim=%s aim=%s" % [_input.command.has_aim, _input.command.aim_dir])

	# --- drag right: the aim, the wizard and the indicator all turn -----------------------
	var held := centre + Vector2(AIM_DRAG, 0.0)
	_emit_drag(0, held)
	await _settle()
	var aim: Vector2 = _input.command.aim_dir
	_expect("dragging right aims screen-right", aim.normalized().dot(screen_right) > 0.99,
		"aim=%s right=%s" % [aim, screen_right])
	for i in 24:
		await get_tree().physics_frame
	_expect("the wizard turns to face the drag", _facing_of(_player).dot(screen_right) > 0.98,
		"facing=%s" % _facing_of(_player))

	# --- the lift is the cast, and it goes where the thumb pointed ------------------------
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, held, false)
	await _settle()
	_expect("the lift casts", _pool.active_count() == before + 1,
		"active %d -> %d" % [before, _pool.active_count()])
	_expect("the spell left along the drag", _last_aim().dot(screen_right) > 0.99,
		"cast=%s right=%s" % [_last_aim(), screen_right])
	_expect("the indicator goes away on the lift", not indicator.is_showing(), "cleared")

	# --- the aim latched at the lift survives the tick that consumes it -------------------
	#
	# The finger lifts and the character casts on the NEXT physics tick. If the walking
	# direction is allowed to overwrite the aim in between, the spell comes out sideways -
	# rarely, and only under load. So: aim forward, walk right, lift, and check which one
	# the spell believed.
	while not book.is_ready(0):
		await get_tree().physics_frame
	_input.set_override_vector(Vector2(1.0, 0.0), true)
	var landed := await _drag_aim(0, Vector2(0.0, 1.0))
	_expect("the drag beats the walking direction",
		_input.command.aim_dir.normalized().dot(screen_fwd) > 0.99,
		"aim=%s forward=%s" % [_input.command.aim_dir, screen_fwd])
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, landed, false)
	await _settle()
	_expect("the latched aim survived to the cast", _last_aim().dot(screen_fwd) > 0.99,
		"cast=%s forward=%s move=%s" % [_last_aim(), screen_fwd, _input.command.move_dir])

	# --- and a plain tap still casts where you are heading --------------------------------
	while not book.is_ready(0):
		await get_tree().physics_frame
	_last_cast_dir = Vector3.ZERO
	_emit_touch(0, centre, true)
	await _settle()
	_emit_touch(0, centre, false)
	await _settle()
	_expect("a tap still casts where you are heading", _last_aim().dot(screen_right) > 0.99,
		"cast=%s move=%s" % [_last_aim(), _input.command.move_dir])
	_input.set_override_vector(Vector2.ZERO, true)

	# --- every cast type draws its own shape ----------------------------------------------
	var cone_slot := _slot_with(book, Ability.CastType.CONE)
	var cone := book.ability_in(cone_slot)
	var cone_at := await _drag_aim(cone_slot, Vector2(0.0, 1.0))
	_expect("a cone draws a fan", indicator.shape() == AimIndicator.Shape.FAN,
		"shape=%d" % indicator.shape())
	_expect("the fan is the spell's own fan",
		is_equal_approx(indicator.reach(), cone.area)
			and is_equal_approx(indicator.half_angle(), cone.cone_angle),
		"reach=%.2f (area %.2f) half=%.1f (cone %.1f)" % [
			indicator.reach(), cone.area, indicator.half_angle(), cone.cone_angle])
	_emit_touch(0, cone_at, false)
	await _settle()

	var buff_slot := _slot_with(book, Ability.CastType.BUFF)
	var buff_at := await _drag_aim(buff_slot, Vector2(0.0, 1.0))
	_expect("a self-cast draws a ring around you",
		indicator.shape() == AimIndicator.Shape.SELF, "shape=%d" % indicator.shape())
	_emit_touch(0, buff_at, false)
	await _settle()

	# --- a dash previews where it will REALLY land ----------------------------------------
	#
	# Standing close enough to the rim that a Teleport would leave the arena, so the preview has
	# to come out shorter than the spell. Positioned against the ARENA rather than at a fixed
	# 3m, so growing the board cannot quietly turn this into a test of nothing.
	var dash_slot := _slot_with(book, Ability.CastType.DASH)
	var dash := book.ability_in(dash_slot)
	var out_at := _arena_edge - BLINK_EDGE_MARGIN - dash.dash_distance * 0.4
	await _place_fighters(Vector3(0.0, 1.2, -3.5), Vector3(out_at, 1.2, 0.0))
	var dash_at := await _drag_aim(dash_slot, Vector2(1.0, 0.0))
	_expect("a dash draws a line to a landing spot",
		indicator.shape() == AimIndicator.Shape.DASH, "shape=%d" % indicator.shape())
	var previewed := indicator.reach()
	_expect("the preview is clamped by the arena", previewed < dash.dash_distance - 0.5,
		"previewed %.2fm of %.2fm" % [previewed, dash.dash_distance])
	var from := _player.global_position
	_emit_touch(0, dash_at, false)
	await _settle()
	var travelled := Vector2(_player.global_position.x - from.x,
		_player.global_position.z - from.z).length()
	_expect("the wizard lands exactly where the line ended",
		absf(travelled - previewed) < 0.05,
		"drew %.2fm, travelled %.2fm" % [previewed, travelled])
	_expect("and lands inside the arena", _radius_of(_player.global_position) <= _arena_edge,
		"r=%.2f edge=%.2f" % [_radius_of(_player.global_position), _arena_edge])

	print("[aim] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Stands the player in the lava and holds them there, so a delayed --shot catches the burn
## bar part-way down.
##
## The bar only exists while someone is on fire, which makes it the one piece of the game that
## cannot be photographed by simply starting a round - the same reason the reference project
## grew a pose flag for its flying creep and another for its bosses.
## Fans every PROJECTILE spell in the catalogue out from the middle of an empty arena, over and
## over, so a `--shot:N` at any moment catches all five shapes in flight together.
##
## Fired straight into the pool rather than through a spellbook. A wizard holds four spells and
## only some of them are projectiles, so casting these properly would mean re-arming between
## every shot and photographing them one at a time - and what has to be checked here is exactly
## that they look DIFFERENT FROM EACH OTHER, which needs them in one frame.
##
## Re-fired on a loop like `--burn-pose` holds its burn: the shapes are only visible while they
## are in the air, and the shortest of them lives half a second.
func _bolt_pose() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	if catalogue == null:
		return
	var bolts: Array[Ability] = []
	for spell in catalogue.all_spells():
		if spell.cast_type == Ability.CastType.PROJECTILE:
			bolts.append(spell)
	print("[harness] bolt pose: %d projectile spells" % bolts.size())
	await _wait_for_live()
	while is_inside_tree():
		# Parked well off to the side. The caster is a live body and a spell fired past its nose
		# still shoves it, which would walk the next volley somewhere else.
		_player.respawn_at(Vector3(0.0, 1.2, 9.0))
		_bot.respawn_at(Vector3(0.0, 1.2, 40.0))
		# PARALLEL LANES, not a fan. Every shape leaves along +X and is therefore seen from the
		# same angle, so what the photograph compares is the shapes and not the foreshortening -
		# a fan had a cone flying away from the camera next to a bar flying across it, and the
		# two were not comparable at all.
		for index in bolts.size():
			var lane := Vector3(-8.0, 1.2, -4.0 + 2.0 * float(index))
			_pool.fire(bolts[index], lane, Vector3.RIGHT, _player)
		await _wait(1.2)


func _burn_pose() -> void:
	await _wait_for_live()
	_freeze_bot()
	_arena.shrinking = false
	var out_at := _arena.radius + 1.5
	print("[harness] burning the player at r=%.1fm" % out_at)
	while is_inside_tree() and not _player.is_eliminated():
		_player.global_position = Vector3(out_at, 1.2, 0.0)
		_player.velocity = Vector3.ZERO
		await get_tree().physics_frame


## Holds a drag on a spell button and never lifts it, so a delayed --shot photographs the
## indicator. Nothing casts: the cast is the lift, and this run never lifts.
func _hold_aim(slot: int, direction: Vector2) -> void:
	await _wait_for_live()
	if slot < 0 or slot >= _mobile.buttons.size():
		push_warning("--aim-hold: no button %d" % slot)
		return
	var dir := direction
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	var button: AbilityButton = _mobile.buttons[slot]
	var centre := button.get_global_rect().get_center()
	# A finger index nothing else in the harness uses, so an --aim-hold can be combined with
	# another injected gesture without the two claiming each other's events.
	_emit_touch(9, centre, true)
	await _settle()
	_emit_drag(9, centre + Vector2(dir.x, -dir.y) * AIM_DRAG)
	print("[harness] holding aim on slot %d toward %s" % [slot, dir])


# ---------------------------------------------------------------------------------------
# Game feel harness
#
# Feel is the one thing in this project that cannot be judged by a number - "does that hit
# land well" is a question for a human. What CAN be checked is that every channel actually
# fires, that they scale with the hit rather than being on or off, and that hitstop gives the
# engine back afterwards. A hitstop that leaks is not a subtle bug: the whole game runs at a
# tenth speed forever, and it would pass every other suite in this file, because they all
# park the feel.
# ---------------------------------------------------------------------------------------

## Waits for a shake to die, so the next reading starts from zero. Bounded, because a stuck
## shake should fail an assertion rather than hang the run.
func _settle_shake() -> void:
	var guard := 0
	while _camera_rig.shake_level() > 0.001 and guard < 600:
		await get_tree().process_frame
		guard += 1


## Applies one hit and returns how much shake it added, read on the same frame so nothing has
## decayed yet.
func _shake_from_hit(victim: Player, ability: Ability) -> float:
	await _settle_shake()
	var inst := victim.instability()
	if inst != null:
		inst.reset()
	var before := _camera_rig.shake_level()
	_apply_hit(victim, Vector3(1.0, 0.0, 0.0), ability)
	return _camera_rig.shake_level() - before


func _run_feel_tests() -> void:
	await _settle()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	# Both fighters in the middle, so a Scourge at full strength cannot throw either of
	# them off the arena in the middle of a measurement.
	await _place_fighters(Vector3(0.0, 1.2, -2.5), Vector3(0.0, 1.2, 0.0))
	var book := _player.abilities()
	var light := book.ability_in(0)
	var heavy := book.ability_in(_slot_with(book, Ability.CastType.CONE))
	var sounds := $Sounds as SoundBank
	var sparks := $Sparks as ImpactBurst
	var streak := $Streak as GroundStreak
	print("[feel-test] stop=%.3f-%.3fs heavy at %.1f m/s, %d sounds in the bank" % [
		_feel.stop_min, _feel.stop_max, _feel.heavy_speed, sounds.names().size()])

	_expect("the feel layer has all four channels",
		_feel.camera != null and _feel.sounds != null and _feel.sparks != null
			and _feel.streak != null,
		"camera=%s sounds=%s sparks=%s streak=%s" % [
			_feel.camera != null, _feel.sounds != null, _feel.sparks != null,
			_feel.streak != null])
	for id in [&"cast", &"hit", &"heavy", &"fall", &"tick", &"go", &"win", &"lose", &"blink"]:
		_expect("the bank has a %s" % id, sounds.has(id), "")

	# --- one hit reaches every channel -----------------------------------------------------
	await _settle_shake()
	var sparks_before := sparks.active_count()
	var began := Time.get_ticks_msec()
	_apply_hit(_player, Vector3(1.0, 0.0, 0.0), light)
	_expect("a hit throws sparks", sparks.active_count() > sparks_before,
		"active %d -> %d" % [sparks_before, sparks.active_count()])
	_expect("a hit shakes the camera", _camera_rig.shake_level() > 0.0,
		"shake=%.3f" % _camera_rig.shake_level())
	_expect("a hit slows the world", _feel.is_stopped() and Engine.time_scale < 1.0,
		"time_scale=%.3f" % Engine.time_scale)
	_expect("a hit makes a noise", sounds.playing_count() > 0,
		"%d voice(s)" % sounds.playing_count())

	# --- and gives the engine back ---------------------------------------------------------
	#
	# Measured in WALL CLOCK time, which is the whole point. Counting a hitstop down with a
	# delta that the hitstop itself scaled stretches it by exactly the factor applied - the
	# 0.035s stop would last 0.29s and still look like it worked.
	var guard := 0
	while Engine.time_scale < 1.0 and guard < 600:
		await get_tree().process_frame
		guard += 1
	var stopped_for := (Time.get_ticks_msec() - began) / 1000.0
	_expect("the world speeds back up", is_equal_approx(Engine.time_scale, 1.0),
		"time_scale=%.3f after %d frames" % [Engine.time_scale, guard])
	# The tolerance is a rendered frame either way: this poll can only notice the engine came
	# back on a frame boundary, so a 0.072s stop reads as 0.087s on a 60fps run. What it is
	# really guarding against is an order of magnitude - a hitstop counted down with its own
	# slowed delta comes out EIGHT times too long and would still look fine in a log.
	_expect("the hitstop lasted about as long as it asked to (within a frame)",
		stopped_for >= _feel.stop_min * 0.5 and stopped_for <= _feel.stop_max + 0.10,
		"%.3fs, asked for %.3f-%.3f" % [stopped_for, _feel.stop_min, _feel.stop_max])

	# --- the channels scale with the hit ---------------------------------------------------
	var light_shake := await _shake_from_hit(_player, light)
	var heavy_shake := await _shake_from_hit(_player, heavy)
	_expect("a heavier hit shakes harder", heavy_shake > light_shake + 0.01,
		"light %.3f, heavy %.3f" % [light_shake, heavy_shake])
	var on_bot := await _shake_from_hit(_bot, heavy)
	_expect("a hit on the opponent shakes less than one on you",
		on_bot < heavy_shake * 0.9 and on_bot > 0.0,
		"you %.3f, them %.3f" % [heavy_shake, on_bot])

	# --- a dash leaves a streak, and takes it away again ------------------------------------
	var dash := book.ability_in(_slot_with(book, Ability.CastType.DASH))
	_cast_dash(dash, Vector3(1.0, 0.0, 0.0), _player)
	await get_tree().process_frame
	_expect("a dash draws a streak", streak.is_showing(), "showing=%s" % streak.is_showing())
	var waited := 0.0
	while streak.is_showing() and waited < 2.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_expect("the streak fades on its own", not streak.is_showing(),
		"still up after %.2fs" % waited)

	# --- and the whole thing can be switched off --------------------------------------------
	while sparks.active_count() > 0:
		await get_tree().process_frame
	_feel.enabled = false
	await _settle_shake()
	_apply_hit(_player, Vector3(1.0, 0.0, 0.0), heavy)
	_expect("a parked feel throws no sparks", sparks.active_count() == 0,
		"active=%d" % sparks.active_count())
	_expect("a parked feel does not shake", _camera_rig.shake_level() <= 0.001,
		"shake=%.3f" % _camera_rig.shake_level())
	_expect("a parked feel leaves time alone", is_equal_approx(Engine.time_scale, 1.0),
		"time_scale=%.3f" % Engine.time_scale)

	print("[feel] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Cover harness
#
# Obstacles are the first thing in the arena that is neither a fighter nor the floor, and
# they make three promises: a spell dies against them, a wizard cannot walk through them, and
# they are placed so that neither side of a 1v1 gets the better of them. The third is the one
# that cannot be seen by playing - an arena that quietly favours one spawn is a fairness bug
# that reads as "the bot is good today".
# ---------------------------------------------------------------------------------------

## Every obstacle in the arena, as flat positions.
func _cover_points() -> Array:
	var out: Array = []
	for child in _obstacles.get_children():
		var body := child as Node3D
		if body != null:
			out.append(Vector2(body.global_position.x, body.global_position.z))
	return out


## Instability on a fighter, or -1 if it has none.
func _instability_of(fighter: Player) -> float:
	var inst := fighter.instability()
	return inst.current if inst != null else -1.0


func _reset_instability() -> void:
	for fighter in [_player, _bot]:
		var inst: InstabilityComponent = fighter.instability()
		if inst != null:
			inst.reset()


## Waits `seconds` on the gameplay clock.
func _wait(seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		await get_tree().physics_frame
		waited += 1.0 / 60.0


func _run_cover_tests() -> void:
	await _settle()
	_quiet_feel()
	# Cover moves with the ring now, so a closing arena would walk the obstacles out from
	# under every position this suite measures.
	_freeze_arena()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var book := _player.abilities()
	var fireball := book.ability_in(0)
	var wave := book.ability_in(_slot_with(book, Ability.CastType.CONE))
	var points := _cover_points()
	print("[cover-test] %d obstacles at %s" % [points.size(), points])

	_expect("the arena has cover", points.size() >= 2, "%d obstacle(s)" % points.size())

	# --- fair to both spawns ----------------------------------------------------------------
	#
	# Point symmetry about the centre: turn the arena 180 degrees and it is the same arena. That
	# is the only arrangement under which two fighters starting opposite each other are looking
	# at the same problem.
	var symmetric := true
	for point in points:
		var mirrored := false
		for other in points:
			if (other + point).length() < 0.05:
				mirrored = true
				break
		if not mirrored:
			symmetric = false
	_expect("the layout is the same from both spawns", symmetric,
		"every obstacle needs one at its mirror")

	# Nothing may stand in the opening lane, or the first exchange of every round is a wall.
	var space := get_world_3d().direct_space_state
	var lane := PhysicsRayQueryParameters3D.create(spawn_point, bot_spawn)
	lane.collision_mask = ConeCast.WORLD_MASK
	_expect("the lane between the spawns is open", space.intersect_ray(lane).is_empty(),
		"%s -> %s" % [spawn_point, bot_spawn])

	# --- a spell dies against a rock ---------------------------------------------------------
	#
	# Both fighters on the same line as RockA, with the rock between them. Same shot that lands
	# in --cast-test, one obstacle in the way.
	var rock: Vector2 = points[0]
	var lined_up := Vector3(rock.x, 1.2, rock.y + 1.7)
	var behind := Vector3(rock.x, 1.2, rock.y - 1.7)
	await _place_fighters(behind, lined_up)
	_reset_instability()
	_pool.fire(fireball, _player.global_position + Vector3(0.0, 0.0, -0.9),
		Vector3(0.0, 0.0, -1.0), _player)
	await _wait(1.5)
	_expect("a projectile dies against cover", is_equal_approx(_instability_of(_bot), 0.0),
		"bot at %.0f%% instability" % _instability_of(_bot))

	# --- and the same shot lands with nothing in the way --------------------------------------
	#
	# The control. Without it, a suite that broke every projectile would pass the assertion
	# above and call it cover.
	await _place_fighters(Vector3(0.0, 1.2, -1.7), Vector3(0.0, 1.2, 1.7))
	_reset_instability()
	_pool.fire(fireball, _player.global_position + Vector3(0.0, 0.0, -0.9),
		Vector3(0.0, 0.0, -1.0), _player)
	await _wait(1.5)
	_expect("the same shot lands down an open lane", _instability_of(_bot) > 0.0,
		"bot at %.0f%% instability" % _instability_of(_bot))

	# --- a cone is stopped by cover too --------------------------------------------------------
	await _place_fighters(behind, lined_up)
	_reset_instability()
	_cast_cone(wave, Vector3(0.0, 0.0, -1.0), _player)
	await _wait(0.3)
	_expect("a cone does not reach through cover",
		is_equal_approx(_instability_of(_bot), 0.0),
		"bot at %.0f%% instability" % _instability_of(_bot))

	await _place_fighters(Vector3(0.0, 1.2, -1.7), Vector3(0.0, 1.2, 1.7))
	_reset_instability()
	_cast_cone(wave, Vector3(0.0, 0.0, -1.0), _player)
	await _wait(0.3)
	_expect("the same cone catches an exposed target", _instability_of(_bot) > 0.0,
		"bot at %.0f%% instability" % _instability_of(_bot))

	# --- and you cannot walk through one --------------------------------------------------------
	#
	# Started 2.5m out and walked straight at it. Both halves matter: the wizard has to CLOSE
	# the distance and then stop. Asserting only "did not reach the centre" passes just as
	# happily when the stick was pushed the wrong way and the wizard walked off the other side,
	# which is exactly how this assertion first passed while testing nothing.
	await _place_fighters(bot_spawn, Vector3(rock.x, 1.2, rock.y + 2.5))
	var started := Vector2(_player.global_position.x - rock.x,
		_player.global_position.z - rock.y).length()
	# Screen-forward is -Z and the rock is at -Z from the wizard, so this walks INTO it.
	_input.set_override_vector(Vector2(0.0, 1.0), true)
	await _wait(1.5)
	var gap := Vector2(_player.global_position.x - rock.x,
		_player.global_position.z - rock.y).length()
	_input.set_override_vector(Vector2.ZERO, true)
	_expect("a wizard walks up to a rock and stops", gap < started - 0.5 and gap > 0.9,
		"%.2fm -> %.2fm from its centre (rock is 0.7 wide, a wizard 0.5)" % [started, gap])

	print("[cover] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Lava harness
#
# The lava replaced instant elimination, which means the round can now be lost slowly - and
# a slow loss is exactly the kind of rule that can be wrong for a long time without anybody
# noticing. Four things have to hold: it burns while you are out, it stops the moment you are
# back on stone, it ends the round at zero, and a fighter who turns around and walks back
# SURVIVES with something left. That last one is the whole point of the change; without it
# this is just a slower void.
# ---------------------------------------------------------------------------------------

## Puts one fighter at a radius and holds them there, so a burn can be measured without a
## slide or a bot walking out of the measurement.
##
## Writes the position directly rather than calling `respawn_at()`, which the other suites use
## for pinning. `respawn_at` resets instability AND health - it is what a round start does -
## so pinning with it wipes the very number this suite is measuring, once per tick. The first
## run reported the lava burning 0.4 points in a second against an advertised 22.
func _hold_at(fighter: Player, radius: float, seconds: float) -> void:
	var waited := 0.0
	while waited < seconds:
		fighter.global_position = Vector3(radius, 1.2, 0.0)
		fighter.velocity = Vector3.ZERO
		await get_tree().physics_frame
		waited += 1.0 / 60.0


func _run_lava_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	var hp := _player.health()
	print("[lava-test] max=%.0f burn=%.0f/s, arena r=%.1fm" % [
		hp.maximum, hp.burn_per_second, _arena_edge])

	_expect("a fighter has something to burn", hp != null and hp.current == hp.maximum,
		"%.0f of %.0f" % [hp.current, hp.maximum])

	# --- on the stone, nothing happens ------------------------------------------------------
	await _hold_at(_player, _arena_edge * 0.5, 0.5)
	_expect("standing on the stone costs nothing",
		is_equal_approx(hp.current, hp.maximum), "%.1f" % hp.current)

	# --- off the stone, it burns at the rate it says ----------------------------------------
	#
	# Measured against the component's own rate rather than a copied number: a retune should
	# move the game, not break the suite.
	var out_at := _arena_edge + 2.0
	await _hold_at(_player, out_at, 1.0)
	var burned := hp.maximum - hp.current
	_expect("the lava burns", burned > 0.0, "%.1f burned in 1s" % burned)
	_expect("it burns at the rate it advertises",
		absf(burned - hp.burn_per_second) < hp.burn_per_second * 0.25,
		"%.1f in 1s, rate is %.0f/s" % [burned, hp.burn_per_second])

	# --- and walking back stops it, but does not undo it ------------------------------------
	#
	# Stone used to mend; it only holds now. A fighter who reaches it stops bleeding out
	# exactly where they were, which is what makes the total a budget rather than a bar that
	# tops back up between exchanges.
	var lowest := hp.current
	await _hold_at(_player, _arena_edge * 0.5, 1.0)
	_expect("walking back onto stone stops the burn", is_equal_approx(hp.current, lowest),
		"%.1f -> %.1f" % [lowest, hp.current])

	# --- a dunk is survivable, which is the entire point ------------------------------------
	#
	# Two seconds out there and back. If this ever fails, being knocked out of the ring has
	# gone back to being a death sentence and the change was pointless.
	hp.reset()
	await _hold_at(_player, out_at, 2.0)
	_expect("two seconds in the lava is survivable", hp.is_alive(),
		"%.0f left of %.0f" % [hp.current, hp.maximum])
	_expect("and it cost something that lasts", hp.current < hp.maximum * 0.75,
		"%.0f left of %.0f" % [hp.current, hp.maximum])

	# --- and a spell can drain it directly, on top of instability --------------------------
	#
	# The rule this project shipped with was that no spell may ever touch health. Fireball now
	# does, deliberately, and this is the assertion that would fail first if that stopped being
	# true - a Fireball landing and health NOT moving would mean the damage silently fell off
	# somewhere between the ability and the component.
	hp.reset()
	var fireball := _player.abilities().ability_in(0)
	var inst := _bot.instability()
	if inst != null:
		inst.reset()
	var bot_hp := _bot.health()
	bot_hp.reset()
	_apply_hit(_bot, Vector3(0.0, 0.0, -1.0), fireball)
	_expect("a Fireball drains health directly",
		is_equal_approx(bot_hp.current, bot_hp.maximum - fireball.damage),
		"%.1f left of %.1f, spell claims %.1f damage" % [
			bot_hp.current, bot_hp.maximum, fireball.damage])
	_expect("and raises damage points by the SAME number", is_equal_approx(inst.current, fireball.damage),
		"damage points=%.1f, damage=%.1f" % [inst.current, fireball.damage])

	# Put the bot back before anything else in this suite runs. The Fireball above does not
	# just chip it any more - under the map's drag that one hit carries the bot eight metres,
	# which off-centre is into the lava, where it burns down and ends the round. Every later
	# section here measures the PLAYER burning, and a round that resets underneath it heals
	# the player and restarts the clock: the burn came out at a third of its real rate and the
	# elimination that fired belonged to the wrong fighter.
	_bot.respawn_at(Vector3(0.0, 1.2, 3.0))
	bot_hp.reset()
	await get_tree().physics_frame

	# --- the bar over the wizard's head follows it ------------------------------------------
	var bar := _player.get_node_or_null(^"HealthBar") as HealthBar
	_expect("the fighter carries a burn bar", bar != null, "bar=%s" % bar)
	if bar != null:
		# Back on the stone BEFORE resetting. Leave the fighter in the lava and the next tick
		# burns a sliver off again, so the bar is correctly visible and the assertion reads as
		# a broken bar - the number even prints as 100%, because 99.6 rounds.
		await _hold_at(_player, _arena_edge * 0.5, 0.1)
		hp.reset()
		await get_tree().process_frame
		_expect("it is hidden while nothing has burned", not bar.visible,
			"visible=%s at %.1f%%" % [bar.visible, hp.fraction() * 100.0])
		await _hold_at(_player, out_at, 1.0)
		await get_tree().process_frame
		_expect("it appears once the lava bites", bar.visible, "visible=%s" % bar.visible)
		_expect("and shows what is left",
			absf(bar.shown_fraction() - hp.fraction()) < 0.02,
			"bar %.2f against %.2f" % [bar.shown_fraction(), hp.fraction()])

	# --- and you can WALK back in, which is the promise the whole change rests on ------------
	#
	# The stone stands 8cm proud of the lava, and a CharacterBody3D does not step up walls.
	# What saves it is the capsule: its lower sphere meets a lip that small at about 33 degrees
	# off vertical, inside the 45 the body counts as floor, so it rides up. That is a chain of
	# three assumptions about someone else's physics engine, and it is the difference between
	# a second chance and a wizard stuck against a kerb until it burns to death. Measured.
	hp.reset()
	_player.global_position = Vector3(_arena_edge + 1.2, 1.2, 0.0)
	for i in 10:
		await get_tree().physics_frame
	var walked_in := false
	var toward_centre := Vector2(-1.0, 0.0)
	_input.set_override_vector(toward_centre, true)
	var trudge := 0.0
	while trudge < 4.0:
		await get_tree().physics_frame
		trudge += 1.0 / 60.0
		if _radius_of(_player.global_position) < _arena_edge - 0.6:
			walked_in = true
			break
	_input.set_override_vector(Vector2.ZERO, true)
	_expect("a burning fighter can walk back onto the stone", walked_in,
		"reached r=%.2f in %.1fs (edge %.1f)" % [
			_radius_of(_player.global_position), trudge, _arena_edge])
	_expect("and is standing on it, not sunk into it",
		absf(_player.global_position.y - 1.0) < 0.25,
		"y=%.2f" % _player.global_position.y)

	# --- staying in it ends the round -------------------------------------------------------
	var eliminations: Array = []
	var watch := func(fighter: Player, _title: String) -> void:
		eliminations.append(fighter)
	_rounds.fighter_eliminated.connect(watch)
	var guard := 0.0
	while hp.is_alive() and guard < 12.0:
		_player.global_position = Vector3(out_at, 1.2, 0.0)
		_player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		guard += 1.0 / 60.0
	# One more tick for the signal to travel.
	await get_tree().physics_frame
	_rounds.fighter_eliminated.disconnect(watch)
	_expect("staying in it burns you down", not hp.is_alive(),
		"%.1f left after %.1fs" % [hp.current, guard])
	_expect("burning to nothing takes you out of the round",
		eliminations.has(_player), "%d elimination(s)" % eliminations.size())

	print("[lava] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


# ---------------------------------------------------------------------------------------
# Shrinking-ring harness
#
# The ring closing is the only thing that ends a round nobody wins, so it has to be right in
# four ways: it holds still through the grace period, it closes at the rate it advertises, it
# stops at the floor, and everything that reads the radius follows it. That last one is the
# expensive failure - a bot with a stale edge walks into lava, and a lava rule with a stale
# edge burns a fighter standing on stone.
# ---------------------------------------------------------------------------------------

func _run_shrink_tests() -> void:
	await _settle()
	_quiet_feel()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()
	# Deliberately NOT frozen: this suite is the one that watches it move.
	_arena.shrinking = true
	_arena.reset()
	print("[shrink-test] start=%.1fm min=%.1fm grace=%.0fs rate=%.2fm/s" % [
		_arena.start_radius, _arena.min_radius, _arena.grace_seconds,
		_arena.shrink_per_second])

	_expect("a round starts at full size",
		is_equal_approx(_arena.radius, _arena.start_radius),
		"%.2fm of %.2fm" % [_arena.radius, _arena.start_radius])
	_expect("the lava rule and the arena agree", is_equal_approx(_arena_edge, _arena.radius),
		"edge=%.2f arena=%.2f" % [_arena_edge, _arena.radius])
	_expect("so does the bot", is_equal_approx(_brain.arena_radius, _arena.radius),
		"bot=%.2f arena=%.2f" % [_brain.arena_radius, _arena.radius])

	# --- it holds still while the fight opens -------------------------------------------------
	var held := _arena.radius
	await _wait(1.0)
	_expect("it does not move during the grace period",
		is_equal_approx(_arena.radius, held) and _arena.grace_left() > 0.0,
		"%.2fm, %.1fs of grace left" % [_arena.radius, _arena.grace_left()])

	# --- then it closes, at the rate it says ---------------------------------------------------
	#
	# Rather than wait out the whole grace period in real time, spend it: the clock is the
	# arena's own, and ticking it directly is the same thing the round does, only faster.
	while _arena.grace_left() > 0.0:
		_arena.tick(1.0 / 60.0)
	var before := _arena.radius
	var cover_before: Vector2 = _cover_points()[0]
	var camera_before: float = _camera_rig.distance
	await _wait(1.0)
	var closed := before - _arena.radius
	_expect("it closes once the grace runs out", closed > 0.0,
		"%.2fm -> %.2fm" % [before, _arena.radius])
	_expect("at the rate it advertises",
		absf(closed - _arena.shrink_per_second) < _arena.shrink_per_second * 0.25,
		"%.2fm in 1s, rate is %.2fm/s" % [closed, _arena.shrink_per_second])
	_expect("and it says it is closing", _arena.is_closing(), "is_closing=%s" % _arena.is_closing())

	# --- everything that reads the radius came with it -----------------------------------------
	_expect("the lava rule followed it in", is_equal_approx(_arena_edge, _arena.radius),
		"edge=%.2f arena=%.2f" % [_arena_edge, _arena.radius])
	_expect("the bot followed it in", is_equal_approx(_brain.arena_radius, _arena.radius),
		"bot=%.2f arena=%.2f" % [_brain.arena_radius, _arena.radius])
	_expect("the camera came in with it", _camera_rig.distance < camera_before,
		"%.2f -> %.2f" % [camera_before, _camera_rig.distance])
	var cover_now: Vector2 = _cover_points()[0]
	_expect("the cover came in with it", cover_now.length() < cover_before.length() - 0.01,
		"%.2fm -> %.2fm from the centre" % [cover_before.length(), cover_now.length()])
	_expect("and the cover is still inside the ring", cover_now.length() < _arena.radius,
		"cover at %.2fm, rim at %.2fm" % [cover_now.length(), _arena.radius])

	# --- it stops at the floor -----------------------------------------------------------------
	var guard := 0
	while _arena.radius > _arena.min_radius and guard < 60 * 120:
		_arena.tick(1.0 / 60.0)
		guard += 1
	_arena.tick(1.0)
	_expect("it stops at the minimum", is_equal_approx(_arena.radius, _arena.min_radius),
		"%.2fm of a %.2fm floor" % [_arena.radius, _arena.min_radius])
	_expect("and stops saying it is closing", not _arena.is_closing(), "still closing")

	# --- but the camera barely follows it at all -----------------------------------------------
	#
	# Two things hold it back and this asserts the one that matters. CAMERA_FLOOR_RADIUS stops
	# it framing the last few metres; CAMERA_SHRINK_FOLLOW stops it framing ANY of them
	# tightly. Without the second, the lens travelled 41% of its own distance over a close, the
	# wizard grew by 69% on screen, and what that reads as is the character inflating while the
	# island shrinks under them - two things moving opposite ways.
	#
	# So the squeeze belongs to the GEOMETRY. The ring closes by the same amount it always did;
	# the lens is asserted to stay put.
	var opening := maxf(_arena.start_radius, CAMERA_FLOOR_RADIUS) * CAMERA_FRAMING
	var travelled := opening - _camera_rig.distance
	_expect("the camera barely moves while the ring closes to its minimum",
		travelled >= 0.0 and travelled < opening * 0.2,
		"lens moved %.2fm of %.2fm (%.0f%%), ring alone would have moved it %.2fm" % [
			travelled, opening, 100.0 * travelled / opening,
			opening - _arena.min_radius * CAMERA_FRAMING])
	_expect("and it never follows the ring past its floor",
		_camera_rig.distance > _arena.min_radius * CAMERA_FRAMING + 0.5,
		"camera=%.2f, ring alone would put it at %.2f" % [
			_camera_rig.distance, _arena.min_radius * CAMERA_FRAMING])

	# --- a new round gives the whole board back ------------------------------------------------
	_arena.reset()
	_expect("a new round starts full size again",
		is_equal_approx(_arena.radius, _arena.start_radius)
			and is_equal_approx(_arena_edge, _arena.start_radius),
		"%.2fm, edge %.2fm" % [_arena.radius, _arena_edge])

	print("[shrink] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## The roster and the seven spells added with it.
##
## Split into two halves. The first is pure data - what the catalogue holds, and that picks
## survive a round trip through ids - and needs neither a window nor a live round. The second
## casts each new spell and measures the ONE rule that makes it that spell: a lance that
## out-reaches a fireball, a seeker that turns, a loopshot that comes home and can catch the
## same wizard twice, a lunge that hits what it runs through, a bolt that trades places, a
## rewind that undoes where you are but not what you took, and a buff that pays for a hit in
## walking speed.
##
## Every assertion derives its numbers from the spell under test, never from the scene - see
## ARCHITECTURE.md on the two suites that broke when Fireball was retuned.
func _run_loadout_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)

	_expect("the level was handed a catalogue", catalogue != null,
		"catalogue=%s" % catalogue)
	if catalogue == null:
		get_tree().quit(1)
		return

	# --- the roster ------------------------------------------------------------------------
	var all := catalogue.all_spells()
	var ids := {}
	var blank := 0
	for spell in all:
		ids[spell.id] = true
		if spell.blurb.is_empty() or spell.display_name.is_empty():
			blank += 1
	print("[loadout] %d spells across %d columns" % [all.size(), catalogue.columns.size()])
	_expect("every spell has a unique id", ids.size() == all.size(),
		"%d ids for %d spells" % [ids.size(), all.size()])
	_expect("every spell is named and described", blank == 0,
		"%d missing a name or a blurb" % blank)

	# Colour stopped being enough at eleven spells - three of them are some shade of blue - so
	# the SHAPE is what has to be unique.
	#
	# WITHIN A COLUMN, and that is a change from "across the whole roster". At eleven spells the
	# two were the same assertion; at twenty-two they are not, and the stronger one would demand
	# twenty-two distinct drawings to protect a comparison nobody ever makes. What a player
	# actually compares is a column, when they pick from it - and what they carry is Fireball
	# plus ONE spell from each column, so unique-per-column already guarantees four different
	# shapes on the bar. The primary is checked against every column for the same reason: it is
	# on every bar, so it may not collide with anything.
	var stray := 0
	var glyph_clash := ""
	var primary_glyph: int = catalogue.primary.glyph if catalogue.primary != null else -1
	for column in catalogue.columns:
		var shapes := {}
		for spell in column.spells:
			if spell.glyph < 0 or spell.glyph >= Ability.Glyph.size():
				stray += 1
			if shapes.has(spell.glyph) and glyph_clash.is_empty():
				glyph_clash = "%s in %s" % [spell.display_name, column.title]
			if spell.glyph == primary_glyph and glyph_clash.is_empty():
				glyph_clash = "%s shares the primary's shape" % spell.display_name
			shapes[spell.glyph] = true
	_expect("no two spells in a column draw the same glyph", glyph_clash.is_empty(),
		glyph_clash if not glyph_clash.is_empty() else "%d spells, %d columns" % [
			all.size(), catalogue.columns.size()])
	_expect("and every one of them is a shape that exists", stray == 0,
		"%d glyphs outside the enum" % stray)

	# The same argument one layer further in: an icon tells them apart before the cast, and the
	# bolt has to tell them apart while it is in the air. Only the spells that actually fly are
	# checked - `bolt` means nothing on a cone, a dash or a buff, and they all sit at the
	# default, which is not a clash. Per column, for the reason above.
	var bolt_clash := ""
	var primary_bolt: int = catalogue.primary.bolt if catalogue.primary != null else -1
	var flies: int = 0
	for column in catalogue.columns:
		var bolts := {}
		for spell in column.spells:
			if spell.cast_type != Ability.CastType.PROJECTILE:
				continue
			flies += 1
			if bolts.has(spell.bolt) and bolt_clash.is_empty():
				bolt_clash = "%s in %s" % [spell.display_name, column.title]
			if spell.bolt == primary_bolt and bolt_clash.is_empty():
				bolt_clash = "%s flies like the primary" % spell.display_name
			bolts[spell.bolt] = true
	_expect("no two projectiles in a column fly as the same shape", bolt_clash.is_empty(),
		bolt_clash if not bolt_clash.is_empty() else "%d projectile spells" % flies)

	# THE POINT OF THE GAME IS THE EDGE, NOT THE BAR. Spell damage is a chip that shortens your
	# next trip into the lava; it is not a way to win on its own. Ten clean hits was the number
	# picked for that - Fireball at five was a damage race with a knockback theme, and the whole
	# arena stopped mattering. Pinned here because it is a design rule, not a taste: a spell
	# retuned past it changes what the game IS, and that should take an argument rather than a
	# decimal point.
	var bar := _player.health()
	var full := bar.maximum if bar != null else 100.0
	var quickest := INF
	var quickest_name := ""
	# Seconds a spell needs to empty a bar with PERFECT uptime - every cast landing, nothing
	# dodged, nobody walking away. Nothing like a real fight, which is the point: it is the
	# floor, and even the floor has to be slower than the lava.
	var fastest_seconds := INF
	for spell in all:
		if spell.damage <= 0.0:
			continue
		var hits: float = full / spell.damage
		if hits < quickest:
			quickest = hits
			quickest_name = spell.display_name
		fastest_seconds = minf(fastest_seconds, hits * spell.cooldown)
	var lava_seconds := full / _player.health().burn_per_second
	_expect("no spell empties a full bar in under ten clean hits", quickest >= 9.99,
		"%s is the fastest at %.1f hits of %.0f" % [quickest_name, quickest, full])
	_expect("and the lava is still the quickest way to empty one",
		lava_seconds < fastest_seconds,
		"lava %.1fs, best spell %.1fs at perfect uptime" % [lava_seconds, fastest_seconds])
	_expect("the primary is Fireball", catalogue.primary != null
		and catalogue.primary.id == &"fireball", "primary=%s" % catalogue.primary)
	var primary_in_column := false
	for column in catalogue.columns:
		if column.index_of(&"fireball") >= 0:
			primary_in_column = true
	_expect("and is not also a choice", not primary_in_column,
		"Fireball is fixed, so it must not compete for a slot")
	_expect("one column per remaining button",
		catalogue.slot_count() == _mobile.buttons.size(),
		"%d slots, %d buttons" % [catalogue.slot_count(), _mobile.buttons.size()])

	# --- picks survive the trip through ids ---------------------------------------------------
	var defaults := catalogue.default_picks()
	var round_trip := catalogue.picks_from_ids(catalogue.ids_from_picks(defaults))
	_expect("default picks round-trip through their ids", round_trip == defaults,
		"%s -> %s" % [str(defaults), str(round_trip)])
	var mixed := catalogue.picks_from_ids(
		PackedStringArray(["loopshot", "warp_bolt", "momentum"]))
	var mixed_book := catalogue.spellbook(mixed)
	_expect("picks by id arm the spells they name",
		mixed_book.size() == 4 and mixed_book[0].id == &"fireball"
			and mixed_book[1].id == &"loopshot" and mixed_book[2].id == &"warp_bolt"
			and mixed_book[3].id == &"momentum",
		str(catalogue.ids_from_picks(mixed)))
	var stale := catalogue.picks_from_ids(PackedStringArray(["no_such_spell", "momentum"]))
	_expect("an id the catalogue lost leaves that column on its default",
		stale[0] == 0 and stale[2] == catalogue.columns[2].index_of(&"momentum"),
		"stale picks %s" % str(stale))
	var absurd := catalogue.spellbook(PackedInt32Array([99, -4]))
	var holes := 0
	for spell in absurd:
		if spell == null:
			holes += 1
	_expect("an out-of-range pick still produces a whole spellbook",
		absurd.size() == 4 and holes == 0, "%d spells, %d holes" % [absurd.size(), holes])

	var rng_a := RandomNumberGenerator.new()
	var rng_b := RandomNumberGenerator.new()
	rng_a.seed = 77
	rng_b.seed = 77
	_expect("a seeded random loadout replays",
		catalogue.random_picks(rng_a) == catalogue.random_picks(rng_b),
		"same seed, same picks")

	# --- arming ---------------------------------------------------------------------------
	_picks = mixed
	_arm_fighters(false)
	var book := _player.abilities()
	_expect("the chosen spells reach the wizard",
		book.slot_count() == 4 and book.ability_in(0).id == &"fireball"
			and book.ability_in(1).id == &"loopshot"
			and book.ability_in(3).id == &"momentum",
		"slot 0 %s, slot 1 %s, slot 3 %s" % [
			book.ability_in(0).id, book.ability_in(1).id, book.ability_in(3).id])
	_expect("and the buttons follow them",
		_mobile.buttons[1].source == book
			and _mobile.buttons[1].source.ability_in(1).id == &"loopshot",
		"button 1 draws %s" % _mobile.buttons[1].source.ability_in(1).display_name)

	# --- the screen itself, end to end -------------------------------------------------------
	# Driven through its own public surface rather than through injected touch: what is under
	# test is that a pick reaches a spellbook, not that a finger can find a panel.
	_open_loadout()
	_expect("the screen opens", _loadout.is_open(), "is_open=%s" % _loadout.is_open())

	# THE BUTTON THAT LEAVES THE SCREEN MUST BE ON THE SCREEN. This is not a style check.
	# Going from eleven spells to twenty-two put eight rows in a column, and eight rows put the
	# last two options AND the FIGHT button below the bottom edge - a menu with no way out,
	# which is the worst failure a menu has. The columns scroll now; this is what says so, and
	# it is the assertion that will catch the next roster that outgrows the layout.
	await get_tree().process_frame
	await get_tree().process_frame
	var fight: Button = null
	for node in _loadout.find_children("*", "Button", true, false):
		if (node as Button).text == "FIGHT":
			fight = node as Button
	var screen := get_viewport().get_visible_rect().size
	_expect("the FIGHT button is on the screen", fight != null
			and fight.global_position.y + fight.size.y <= screen.y
			and fight.global_position.y >= 0.0,
		"button bottom %.0f of %.0f" % [
			(fight.global_position.y + fight.size.y) if fight != null else -1.0, screen.y])
	_expect("and nothing fights behind it",
		not _player.accepts_input and not _bot.accepts_input and not _mobile.visible,
		"player=%s bot=%s controls=%s" % [
			_player.accepts_input, _bot.accepts_input, _mobile.visible])
	_loadout.select(0, catalogue.columns[0].index_of(&"arc_lance"))
	_loadout.select(2, catalogue.columns[2].index_of(&"rewind"))
	_loadout.confirm()
	await get_tree().physics_frame
	_expect("what was picked is what the wizard carries",
		book.ability_in(1).id == &"arc_lance" and book.ability_in(3).id == &"rewind",
		"slot 1 %s, slot 3 %s" % [book.ability_in(1).id, book.ability_in(3).id])
	_expect("the controls come back with the fight",
		_mobile.visible and _hud.visible and not _loadout.is_open(),
		"controls=%s hud=%s menu=%s" % [_mobile.visible, _hud.visible, _loadout.is_open()])
	_expect("and the picks are remembered for next time",
		LoadoutStore.load_picks(catalogue) == _picks,
		"stored %s" % str(catalogue.ids_from_picks(LoadoutStore.load_picks(catalogue))))

	await _wait_for_live()

	# --- Lightning: the long one --------------------------------------------------------------
	var fireball: Ability = catalogue.primary
	var lance := _spell(&"arc_lance")
	_expect("Lightning reaches far past Fireball",
		lance.effective_range() > fireball.effective_range() * 1.8,
		"%.1fm vs %.1fm" % [lance.effective_range(), fireball.effective_range()])
	_expect("and pays for it in cooldown", lance.cooldown > fireball.cooldown * 2.0,
		"%.1fs vs %.1fs" % [lance.cooldown, fireball.cooldown])

	# --- Homing: it turns, and the turn is what lands it ----------------------------------------
	await _equip(&"seeker", &"blink", &"arcane_shield")
	await _place_fighters(Vector3(0.0, 1.2, 0.0), Vector3(0.0, 1.2, -5.0))
	var seeker := _spell(&"seeker")
	var opening := Vector3(sin(deg_to_rad(45.0)), 0.0, cos(deg_to_rad(45.0)))
	book.reset()
	book.try_cast(1, opening)
	await get_tree().physics_frame
	var flying := _pool.in_flight()
	_expect("the seeker is away", flying.size() == 1, "%d in flight" % flying.size())
	var launched := flying[0].direction() if flying.size() == 1 else Vector3.ZERO
	await _wait(0.25)
	var now := _pool.in_flight()
	var steered := now[0].direction() if now.size() == 1 else launched
	var opened := Vector2(launched.x, launched.z).angle_to(Vector2(0.0, 1.0))
	var closed := Vector2(steered.x, steered.z).angle_to(Vector2(0.0, 1.0))
	_expect("a seeker turns toward what it can see", absf(closed) < absf(opened) - 0.15,
		"aimed %.0f degrees off, now %.0f" % [rad_to_deg(opened), rad_to_deg(closed)])
	var caught := await _instability_after(seeker.lifetime + 0.2)
	_expect("and lands the shot the aim missed", caught >= seeker.damage - 0.01,
		"damage points rose %.0f, spell adds %.0f" % [caught, seeker.damage])

	# --- Boomerang: it comes home, and it can catch you twice --------------------------------------
	await _equip(&"loopshot", &"blink", &"arcane_shield")
	var loop := _spell(&"loopshot")
	_expect("its stated reach is the outward leg, not the whole flight",
		absf(loop.effective_range()
			- loop.projectile_speed * loop.lifetime * loop.returns_after) < 0.2,
		"%.1fm for a %.1fs flight at %.1f m/s" % [
			loop.effective_range(), loop.lifetime, loop.projectile_speed])
	# Thrown at nobody, so the only thing that can bring it back is the spell.
	await _place_fighters(Vector3(0.0, 1.2, 9.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	var furthest := 0.0
	var nearest := INF
	var turned := false
	var ticks := 0
	while ticks < int(loop.lifetime * 60.0) + 6:
		await get_tree().physics_frame
		ticks += 1
		var air := _pool.in_flight()
		if air.is_empty():
			break
		var gap: float = air[0].global_position.distance_to(_player.global_position)
		furthest = maxf(furthest, gap)
		if furthest > 1.0 and gap < furthest - 0.5:
			turned = true
		if turned:
			nearest = minf(nearest, gap)
	_expect("a loopshot turns around", turned, "flew out to %.1fm" % furthest)
	_expect("and comes back to the hand", nearest < furthest * 0.5,
		"out to %.1fm, back to %.1fm" % [furthest, nearest])

	var hits := [0]
	var counter := func(_b: Node3D, _d: Vector3, a: Ability, _s: Node3D) -> void:
		if a.id == &"loopshot":
			hits[0] += 1
	_pool.projectile_hit.connect(counter)
	await _place_fighters(Vector3(4.0, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	# Pinned by writing the position, not by respawning - a respawn would clear the very
	# instability this is about to read. See ARCHITECTURE.md.
	var held := Vector3(4.0, 1.2, 0.0)
	var waited := 0.0
	while waited < loop.lifetime + 0.2:
		_bot.global_position = held
		await get_tree().physics_frame
		waited += 1.0 / 60.0
	_pool.projectile_hit.disconnect(counter)
	_expect("and can catch the same wizard going and coming", hits[0] >= 2,
		"%d hits from one cast" % hits[0])

	# --- Thrust: a charge that hits what it runs through --------------------------------------------
	await _equip(&"force_wave", &"lunge", &"arcane_shield")
	var lunge := _spell(&"lunge")
	await _place_fighters(Vector3(3.0, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	var before := _instability_of(_bot)
	var from := _player.global_position
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var moved := Vector2(_player.global_position.x - from.x, _player.global_position.z - from.z)
	_expect("a lunge moves the caster its full distance",
		absf(moved.length() - lunge.dash_distance) < 0.3,
		"moved %.2fm, spell says %.1fm" % [moved.length(), lunge.dash_distance])
	_expect("and catches whoever was in the way",
		_instability_of(_bot) - before >= lunge.damage - 0.01,
		"instability rose %.0f, spell adds %.0f" % [
			_instability_of(_bot) - before, lunge.damage])

	# --- ...and a plain Teleport still does not -------------------------------------------------------
	await _equip(&"force_wave", &"blink", &"arcane_shield")
	await _place_fighters(Vector3(3.0, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	before = _instability_of(_bot)
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await _wait(0.2)
	_expect("an escape is still only an escape",
		is_equal_approx(_instability_of(_bot), before),
		"Teleport left instability at %.0f" % _instability_of(_bot))

	# --- Swap: it trades, and it does not hurt ----------------------------------------------
	await _equip(&"force_wave", &"warp_bolt", &"arcane_shield")
	await _place_fighters(Vector3(4.5, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	var mine := _player.global_position
	var theirs := _bot.global_position
	before = _instability_of(_bot)
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await _wait(0.5)
	_expect("a warp bolt puts the caster where the target stood",
		_player.global_position.distance_to(theirs) < 1.0,
		"landed %.2fm from where they were" % _player.global_position.distance_to(theirs))
	_expect("and the target where the caster was",
		_bot.global_position.distance_to(mine) < 1.5,
		"landed %.2fm from where I was" % _bot.global_position.distance_to(mine))
	_expect("and costs the target nothing but the ground they held",
		is_equal_approx(_instability_of(_bot), before),
		"instability %.0f" % _instability_of(_bot))

	# --- Time Shift: it undoes where you are, never what you took ----------------------------------------
	await _equip(&"force_wave", &"blink", &"rewind")
	var rewind := _spell(&"rewind")
	await _place_fighters(Vector3(0.0, 1.2, 6.0), Vector3(2.0, 1.2, 0.0))
	var anchor := _player.global_position
	var hp := _player.health()
	var health_then := hp.current
	book.reset()
	book.try_cast(3, Vector3.ZERO)
	await get_tree().physics_frame
	_player.global_position = Vector3(-5.0, 1.2, 4.0)
	hp.damage(30.0)
	_player.instability().add(40.0)
	var instability_then := _instability_of(_player)
	await _wait(rewind.duration + 0.25)
	_expect("a rewind puts the caster back where they cast it",
		_player.global_position.distance_to(anchor) < 0.3,
		"landed %.2fm from the anchor" % _player.global_position.distance_to(anchor))
	_expect("and mends what the round burned off",
		absf(hp.current - health_then) < 0.5,
		"health %.0f, was %.0f at cast" % [hp.current, health_then])
	_expect("but not what the round made of you",
		is_equal_approx(_instability_of(_player), instability_then),
		"instability %.0f, still the %.0f it climbed to" % [
			_instability_of(_player), instability_then])

	# --- Rush: the hit pays for itself -------------------------------------------------------
	await _equip(&"force_wave", &"blink", &"momentum")
	var momentum := _spell(&"momentum")
	var blow := Knockback.velocity(9.0, Vector3(1, 0, 0), 0.0, knockback_rules)
	await _place_fighters(Vector3(0.0, 1.2, 6.0), Vector3(0.0, 1.2, 0.0))
	_player.apply_knockback(blow)
	var bare := await _drift_of(_player, 0.7)
	await _place_fighters(Vector3(0.0, 1.2, 6.0), Vector3(0.0, 1.2, 0.0))
	book.reset()
	book.try_cast(3, Vector3.ZERO)
	await get_tree().physics_frame
	_player.apply_knockback(blow)
	var braced := await _drift_of(_player, 0.7)
	_expect("a hit taken under it carries less", braced.length() < bare.length() * 0.8
		and bare.length() > 0.5,
		"%.2fm bare, %.2fm braced" % [bare.length(), braced.length()])
	_expect("and what it swallowed becomes speed", _player.speed_bonus() > 0.05,
		"+%.2f m/s on a %.1f m/s walk" % [_player.speed_bonus(), _player.move_speed])
	for repeat in 6:
		_player.apply_knockback(blow)
		await get_tree().physics_frame
	_expect("and never past its ceiling",
		_player.speed_bonus() <= momentum.speed_cap + 0.001,
		"+%.2f m/s, cap %.2f" % [_player.speed_bonus(), momentum.speed_cap])
	await _wait(momentum.duration + 0.2)
	_expect("the speed leaves with the buff", _player.speed_bonus() <= 0.001,
		"+%.2f m/s after it dropped" % _player.speed_bonus())

	print("[loadout] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Arms the player with these three choices and lets a tick pass, so the spellbook the next
## assertion reads is the one it asked for.
## The eleven spells the port added, one section per MECHANIC rather than per spell.
##
## Every other suite here predates them and none of it touches a blast, a split, a stream, a
## bounce, a root, a drain, a pull or a tether. Those eight are the only genuinely new runtime
## in the roster - the other three spells are existing fields in new combinations - so this is
## the file that says whether the roster works.
##
## Runs in 1v1 with the bot frozen and the arena pinned, like every measuring suite here. The
## one thing it cannot do that way is BOUNCE, which needs a second enemy to bounce to; that
## section asserts what a bounce does with nobody to reach instead, which is the case that
## would otherwise crash.
func _run_roster_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	await _wait_for_live()
	var centre := Vector3(0.0, 1.2, 0.0)

	# --- BLAST: Meteor catches what it did not touch --------------------------------------
	#
	# The bot is parked BESIDE where the meteor lands, off the line it flies down, so the
	# projectile passes it and expires on empty ground. Anything the bot takes came from the
	# blast and from nothing else - which is the whole point of the mechanic and the thing an
	# ordinary hit test cannot tell apart.
	await _equip(&"meteor", &"blink", &"arcane_shield")
	var meteor := _spell(&"meteor")
	_expect("a meteor has a blast", meteor.area > 0.0, "%.1fm" % meteor.area)
	# Where it will come down: the spawn offset plus a whole lifetime of flight.
	var lands_at := meteor.spawn_offset + meteor.projectile_speed * meteor.lifetime
	var aside := 2.0
	var watching := Vector3(lands_at, 1.2, aside)
	await _place_fighters(watching, centre)
	var before := _instability_of(_bot)
	var book := _player.abilities()
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	await _pin_while({_bot: watching}, meteor.lifetime + 0.3)
	var edge_hit := _instability_of(_bot) - before
	_expect("a blast catches a wizard it never touched", edge_hit > 0.0,
		"landed %.1fm away, damage points rose %.1f" % [aside, edge_hit])
	_expect("and softened by distance, because the centre is the worst place to be",
		absf(edge_hit - meteor.damage * (1.0 - aside / meteor.falloff_over)) < 0.6,
		"%.1f of the spell's %.1f at %.1fm out" % [edge_hit, meteor.damage, aside])

	# --- SPLIT: one Splitter becomes six ---------------------------------------------------
	await _equip(&"splitter", &"blink", &"arcane_shield")
	var splitter := _spell(&"splitter")
	_expect("a splitter names what it breaks into", splitter.split_child is Ability,
		"child=%s" % splitter.split_child)
	await _place_fighters(Vector3(0.0, 1.2, 40.0), centre)
	book = _player.abilities()
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	# Just past the parent's own lifetime: the fragments exist and none of them has expired.
	await _wait(splitter.lifetime + 0.15)
	_expect("it breaks into its full count", _pool.active_count() >= splitter.splits_into,
		"%d in flight, spell says %d" % [_pool.active_count(), splitter.splits_into])
	await _wait(1.4)

	# --- STREAM: one Fire Spray is six shots, spaced out ----------------------------------
	await _equip(&"fire_spray", &"blink", &"arcane_shield")
	var spray := _spell(&"fire_spray")
	await _place_fighters(Vector3(0.0, 1.2, 40.0), centre)
	var fired: Array = []
	var count_shot := func(_a: Ability, _from: Vector3, _dir: Vector3, _c: Node3D) -> void:
		fired.append(1)
	_pool.projectile_spent.connect(func(_at, _d, a: Ability, _s): fired.append(a.id))
	book = _player.abilities()
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	# One shot is away immediately; the sixth leaves five intervals later, and each then flies
	# its whole lifetime before it is spent.
	await _wait(spray.stream_interval * float(spray.stream_count) + spray.lifetime + 0.4)
	_expect("a stream is one cast and several shots", fired.size() == spray.stream_count,
		"%d spent, spell says %d" % [fired.size(), spray.stream_count])

	# --- ROOT: Entangle takes the legs -----------------------------------------------------
	# Slot 2, because Entangle sits in the CONTROL column. Passing it as `_equip`'s first
	# argument silently leaves that column on its default and casts something else entirely -
	# which is what this section did first, and it read as a root that does not work.
	await _equip(&"arc_lance", &"entangle", &"arcane_shield")
	var web := _spell(&"entangle")
	await _place_fighters(Vector3(3.0, 1.2, 0.0), centre)
	book = _player.abilities()
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await _wait(web.lifetime + 0.2)
	_expect("an entangled wizard is rooted", _bot.is_rooted(), "rooted=%s" % _bot.is_rooted())
	# Told to walk and unable to. The bot's brain is frozen, so this drives the body directly.
	var held_at := _bot.global_position
	await _wait(1.0)
	var crawled := Vector2(_bot.global_position.x - held_at.x,
		_bot.global_position.z - held_at.z).length()
	_expect("and goes nowhere while it lasts", crawled < 0.35, "moved %.2fm in a second" % crawled)
	await _wait(web.root_seconds)
	_expect("the root expires", not _bot.is_rooted(), "rooted=%s" % _bot.is_rooted())

	# --- DRAIN: their health becomes yours -------------------------------------------------
	# Slot 3: Drain sits in GUARD, beside the wards, because taking health back is the same
	# kind of answer they are.
	await _equip(&"arc_lance", &"blink", &"drain")
	var drain := _spell(&"drain")
	await _place_fighters(Vector3(2.5, 1.2, 0.0), centre)
	var mine := _player.health()
	var theirs := _bot.health()
	mine.reset()
	theirs.reset()
	mine.damage(30.0)
	var wounded := mine.current
	book = _player.abilities()
	book.reset()
	book.try_cast(3, Vector3(1, 0, 0))
	await _pin_while({_bot: Vector3(2.5, 1.2, 0.0)}, drain.lifetime + 0.3)
	_expect("a drain takes health off the target",
		theirs.current < theirs.maximum - 0.01,
		"%.1f of %.1f left" % [theirs.current, theirs.maximum])
	_expect("and gives the same back to the caster",
		absf((mine.current - wounded) - (theirs.maximum - theirs.current)) < 0.5,
		"caster gained %.1f, target lost %.1f" % [
			mine.current - wounded, theirs.maximum - theirs.current])
	mine.reset()

	# --- TETHER: Link keeps bleeding after it lands ----------------------------------------
	await _equip(&"arc_lance", &"link", &"arcane_shield")
	var link := _spell(&"link")
	await _place_fighters(Vector3(2.5, 1.2, 0.0), centre)
	theirs.reset()
	book = _player.abilities()
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await _pin_while({_bot: Vector3(2.5, 1.2, 0.0)}, link.lifetime + 0.3)
	var at_impact := theirs.current
	_expect("a link lands", at_impact < theirs.maximum, "%.1f left" % at_impact)
	await _wait(1.5)
	var bled := at_impact - theirs.current
	_expect("and keeps bleeding afterwards", bled > 0.0, "%.1f more over 1.5s" % bled)
	_expect("at about the rate it advertises",
		absf(bled - link.tether_dps * 1.5) < link.tether_dps * 0.5,
		"%.1f in 1.5s, rate is %.1f/s" % [bled, link.tether_dps])
	theirs.reset()

	# --- PULL: Gravity drags a bystander in ------------------------------------------------
	await _equip(&"arc_lance", &"gravity", &"arcane_shield")
	var field := _spell(&"gravity")
	_expect("gravity pulls", field.pull_force > 0.0, "%.1f m/s^2" % field.pull_force)
	# Fired PAST the bot, at ninety degrees to the line between them, so nothing it does to
	# them can be the projectile arriving. Only the field reaches that far.
	await _place_fighters(Vector3(0.0, 1.2, -2.6), centre)
	var stood_at := _bot.global_position
	book = _player.abilities()
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await _wait(0.9)
	var drift := Vector2(_bot.global_position.x - stood_at.x,
		_bot.global_position.z - stood_at.z)
	_expect("a bystander is dragged toward the field", drift.x > 0.15,
		"moved %s" % drift)
	await _wait(field.lifetime)

	# --- SELF-DAMAGE: Cataclysm costs the caster ------------------------------------------
	await _equip(&"arc_lance", &"blink", &"cataclysm")
	var boom := _spell(&"cataclysm")
	_expect("cataclysm catches its own caster", boom.hits_caster, "hits_caster=%s" % boom.hits_caster)
	await _place_fighters(Vector3(1.6, 1.2, 0.0), centre)
	mine.reset()
	theirs.reset()
	_reset_instability()
	book = _player.abilities()
	book.reset()
	var went := book.try_cast(3, Vector3(1, 0, 0))
	_expect("cataclysm was ready", went, "try_cast returned %s" % went)
	await get_tree().physics_frame
	_expect("it hurts the caster", mine.current < mine.maximum - 0.01,
		"%.1f of %.1f left" % [mine.current, mine.maximum])
	_expect("and it hurts them more, because they are further from nothing",
		theirs.current < theirs.maximum - 0.01,
		"target %.1f, caster %.1f" % [theirs.current, mine.current])
	_expect("the caster takes the FULL hit, being at the centre of it",
		mine.maximum - mine.current > theirs.maximum - theirs.current,
		"caster lost %.1f, target at 1.6m lost %.1f" % [
			mine.maximum - mine.current, theirs.maximum - theirs.current])

	# --- ALLY HEAL: Pious mends whoever is on your side ------------------------------------
	await _equip(&"arc_lance", &"blink", &"pious")
	var pious := _spell(&"pious")
	await _place_fighters(Vector3(2.0, 1.2, 0.0), centre)
	mine.reset()
	theirs.reset()
	mine.damage(40.0)
	var hurt := mine.current
	book = _player.abilities()
	book.reset()
	book.try_cast(3, Vector3(1, 0, 0))
	await get_tree().physics_frame
	# It does NOT leave its caster better off, and that is the spell rather than a bug: the
	# map's own Pious damages everyone nearby INCLUDING you and then heals allies for half of
	# it. So a caster alone nets a loss, and the mend only pays when somebody is standing with
	# you. What is asserted is the shape - it costs the caster strictly less than the enemy
	# beside them - because that is the difference the heal actually makes.
	var caster_paid := hurt - mine.current
	var enemy_paid := theirs.maximum - theirs.current
	_expect("pious costs its caster less than the enemy beside them",
		caster_paid < enemy_paid - 0.01,
		"caster %.1f, enemy %.1f" % [caster_paid, enemy_paid])
	_expect("and the difference is exactly the mend",
		absf((enemy_paid - caster_paid) - pious.ally_heal) < 0.01,
		"%.1f of a %.1f heal" % [enemy_paid - caster_paid, pious.ally_heal])
	_expect("and it still hurts the enemy standing in it", theirs.current < theirs.maximum,
		"%.1f of %.1f left" % [theirs.current, theirs.maximum])
	mine.reset()
	theirs.reset()

	# --- BOUNCE: with nobody to reach, it simply stops -------------------------------------
	#
	# The interesting half of a bounce needs a second enemy and this suite is 1v1; what is
	# asserted here is the case that would otherwise be a crash - a bounce with nowhere to go.
	await _equip(&"bouncer", &"blink", &"arcane_shield")
	var bouncer := _spell(&"bouncer")
	_expect("a bouncer bounces", bouncer.bounces > 0, "%d" % bouncer.bounces)
	await _place_fighters(Vector3(2.5, 1.2, 0.0), centre)
	_reset_instability()
	book = _player.abilities()
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	await _pin_while({_bot: Vector3(2.5, 1.2, 0.0)}, bouncer.lifetime + 0.5)
	var once := _instability_of(_bot)
	_expect("it lands once", absf(once - bouncer.damage) < 0.01,
		"damage points %.1f, spell says %.1f" % [once, bouncer.damage])
	await _wait(0.6)
	_expect("and does not come back for a second helping when there is nobody else",
		absf(_instability_of(_bot) - once) < 0.01,
		"%.1f, was %.1f" % [_instability_of(_bot), once])

	# --- WINDWALK: a charge that hits, at the map's own reach ------------------------------
	await _equip(&"arc_lance", &"wind_walk", &"arcane_shield")
	var walk := _spell(&"wind_walk")
	_expect("windwalk is a charge and it connects", walk.dash_hits,
		"dash_hits=%s" % walk.dash_hits)
	await _place_fighters(Vector3(3.0, 1.2, 0.0), centre)
	_reset_instability()
	var stood := _player.global_position
	book = _player.abilities()
	book.reset()
	book.try_cast(2, Vector3(1, 0, 0))
	await get_tree().physics_frame
	var travelled := Vector2(_player.global_position.x - stood.x,
		_player.global_position.z - stood.z).length()
	_expect("it carries the caster its full distance",
		absf(travelled - walk.dash_distance) < 0.4,
		"moved %.2fm, spell says %.1fm" % [travelled, walk.dash_distance])
	_expect("and shoves whoever was in the way",
		_instability_of(_bot) >= walk.damage - 0.01,
		"damage points %.1f, spell says %.1f" % [_instability_of(_bot), walk.damage])

	print("[roster] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


func _equip(strike: StringName, motion: StringName, guard: StringName) -> void:
	_picks = catalogue.picks_from_ids(PackedStringArray([
		String(strike), String(motion), String(guard)]))
	_arm_fighters(false)
	await get_tree().physics_frame


## One spell out of the catalogue, by id. Fails loudly rather than returning null, because
## every caller below immediately reads a number off it.
func _spell(id: StringName) -> Ability:
	for spell in catalogue.all_spells():
		if spell.id == id:
			return spell
	_expect("the catalogue holds %s" % id, false, "not found")
	return Ability.new()


## How much instability the bot gained over `seconds`.
func _instability_after(seconds: float) -> float:
	var before := _instability_of(_bot)
	await _wait(seconds)
	return _instability_of(_bot) - before


## Two a side: the roster, the sides, friendly fire, and what a round ends on.
##
## The one rule worth stating up front, because three separate pieces of code implement it and
## a suite is the only thing that can prove they agree: an ALLY IS NOT THERE. A spell does not
## hurt them, and it does not stop on them either - it passes through and reaches whoever is
## behind. Anything less turns a teammate into cover, and a teammate you have to walk around is
## worse than no teammate at all.
func _run_team_tests() -> void:
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	_input.set_override_vector(Vector2.ZERO, true)
	await _wait_for_live()

	_expect("the match was formed two a side", _team_match and _fighters.size() == 4,
		"%d fighters, team match=%s" % [_fighters.size(), _team_match])
	if _fighters.size() < 4:
		print("[teams] FAILURES (%d failure(s))" % maxi(_touch_failures, 1))
		get_tree().quit(1)
		return

	var ally: Player = _fighters[2]
	var foe: Player = _fighters[3]
	print("[teams] %s+%s (side %d) vs %s+%s (side %d)" % [
		_title_of(_player), _title_of(ally), _player.team,
		_title_of(_bot), _title_of(foe), _bot.team])

	# --- the sides ---------------------------------------------------------------------------
	_expect("the player has an ally on their own side",
		ally.team == _player.team and ally != _player,
		"%s is on side %d, you are on %d" % [_title_of(ally), ally.team, _player.team])
	_expect("and two opponents on the other",
		_bot.team == foe.team and _bot.team != _player.team,
		"sides %d and %d against %d" % [_bot.team, foe.team, _player.team])
	_expect("everyone is registered with the round system",
		_rounds.alive_count() == 4 and _rounds.teams_standing() == 2,
		"%d standing across %d sides" % [_rounds.alive_count(), _rounds.teams_standing()])
	_expect("the score is kept by side, not by body", _rounds.scores().size() == 2,
		"score reads %s" % str(_rounds.scores()))
	_expect("teammates know each other",
		_player.is_ally_of(ally) and ally.is_ally_of(_player)
			and not _player.is_ally_of(_bot),
		"you/ally=%s you/bot=%s" % [_player.is_ally_of(ally), _player.is_ally_of(_bot)])
	_expect("and nobody is their own ally", not _player.is_ally_of(_player),
		"a caster is excluded by one rule, not two")

	# --- a projectile passes THROUGH an ally and reaches the enemy behind them ------------------
	# Three wizards on one line: the caster, their teammate in the way, and the target beyond.
	var book := _player.abilities()
	var fireball := book.ability_in(0)
	var reach := fireball.effective_range()
	await _line_up({
		_player: Vector3(0.0, 1.2, 0.0),
		ally: Vector3(reach * 0.35, 1.2, 0.0),
		_bot: Vector3(reach * 0.7, 1.2, 0.0),
		foe: Vector3(0.0, 1.2, 40.0),
	}, 0.4)
	var ally_before := _instability_of(ally)
	var foe_before := _instability_of(_bot)
	book.reset()
	book.try_cast(0, Vector3(1, 0, 0))
	await _pin_while({
		_player: Vector3(0.0, 1.2, 0.0),
		ally: Vector3(reach * 0.35, 1.2, 0.0),
	}, fireball.lifetime + 0.2)
	_expect("a spell does not hurt a teammate standing in its way",
		is_equal_approx(_instability_of(ally), ally_before),
		"%s at %.0f%%, was %.0f%%" % [_title_of(ally), _instability_of(ally), ally_before])
	_expect("and does not stop on them either - it reaches the enemy behind",
		_instability_of(_bot) - foe_before >= fireball.damage - 0.01,
		"%s rose %.0f, spell adds %.0f" % [
			_title_of(_bot), _instability_of(_bot) - foe_before, fireball.damage])

	# --- and neither does a cone ----------------------------------------------------------------
	await _equip(&"force_wave", &"blink", &"arcane_shield")
	var wave := _spell(&"force_wave")
	await _line_up({
		_player: Vector3(0.0, 1.2, 0.0),
		ally: Vector3(wave.area * 0.4, 1.2, 0.0),
		_bot: Vector3(wave.area * 0.75, 1.2, 0.0),
		foe: Vector3(0.0, 1.2, 40.0),
	}, 0.4)
	ally_before = _instability_of(ally)
	foe_before = _instability_of(_bot)
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	await get_tree().physics_frame
	_expect("a wave skips the teammate inside its fan",
		is_equal_approx(_instability_of(ally), ally_before),
		"%s at %.0f%%" % [_title_of(ally), _instability_of(ally)])
	_expect("and catches the enemy in the same fan",
		_instability_of(_bot) - foe_before >= wave.damage - 0.01,
		"%s rose %.0f" % [_title_of(_bot), _instability_of(_bot) - foe_before])

	# --- a bounce needs somebody to bounce TO, which is why it is tested here ---------------
	#
	# `--roster-test` is 1v1 and can only assert what a bounce does with nowhere to go. This is
	# the interesting half: it hits one enemy, finds the other, and hits neither of them twice.
	# The double hit is not hypothetical - the bounce was spawned on top of the wizard it came
	# off, overlapped them on its first frame, and caught the same person again.
	await _equip(&"bouncer", &"blink", &"arcane_shield")
	var bouncer := _spell(&"bouncer")
	var line_up := {
		_player: Vector3(0.0, 1.2, 0.0),
		_bot: Vector3(2.6, 1.2, 0.0),
		foe: Vector3(2.6, 1.2, 3.0),
		ally: Vector3(0.0, 1.2, 40.0),
	}
	await _line_up(line_up, 0.4)
	_reset_instability()
	book = _player.abilities()
	book.reset()
	book.try_cast(1, Vector3(1, 0, 0))
	await _pin_while(line_up, bouncer.lifetime * 2.0 + 0.6)
	var first := _instability_of(_bot)
	var second := _instability_of(foe)
	_expect("a bounce reaches the second enemy", second > 0.0,
		"%s rose %.1f" % [_title_of(foe), second])
	_expect("and it never touches the ally", is_equal_approx(_instability_of(ally), 0.0),
		"%s rose %.1f" % [_title_of(ally), _instability_of(ally)])

	# WITH TWO ENEMIES A BOUNCER PING-PONGS, and that is the spell rather than a bug. Each hop
	# aims at the nearest enemy that is not the one it just left, and with only two on the board
	# that is always the other one - so `bounces` of 3 means four hits alternating between them,
	# each a fifth weaker than the last. It was written as "neither of them is hit twice" first,
	# which was a guess about the spell rather than a reading of it.
	#
	# Asserted as the TOTAL, because that is the one number that proves both halves at once: the
	# right number of hops happened AND each lost the right fraction.
	var chain := 0.0
	var share := 1.0
	for hop in bouncer.bounces + 1:
		chain += share
		share *= 1.0 - bouncer.bounce_falloff
	_expect("and the whole chain lands, a fifth weaker each hop",
		absf((first + second) - bouncer.damage * chain) < 0.05,
		"%.2f dealt over %d hops, arithmetic says %.2f" % [
			first + second, bouncer.bounces + 1, bouncer.damage * chain])
	_expect("with the first hop the hardest",
		first > second and second > 0.0,
		"%s %.1f, %s %.1f" % [_title_of(_bot), first, _title_of(foe), second])
	_reset_instability()

	# --- one down is not one side down ------------------------------------------------------------
	ally.eliminate()
	_rounds.report_out(ally)
	await get_tree().physics_frame
	_expect("losing a teammate does not end the round",
		_rounds.is_live() and _rounds.teams_standing() == 2,
		"live=%s, %d sides up, %d bodies" % [
			_rounds.is_live(), _rounds.teams_standing(), _rounds.alive_count()])

	# --- a bot whose target falls turns to the other one ---------------------------------------------
	var brain: BotController = _brains[0]
	brain.enabled = true
	brain.target = _player
	brain.enemies = [_player, ally]
	# The ally is already out, so the only enemy left standing is the player. One glance and it
	# should have noticed - reaction time is a handicap on noticing, never a licence to keep
	# fighting a body that has left the round.
	await _wait(0.6)
	_expect("a bot re-targets when its enemy leaves the round",
		brain.target == _player and not brain.target.is_eliminated(),
		"it is now fighting %s" % _title_of(brain.target))
	brain.enabled = false

	# --- a whole side down ends it -------------------------------------------------------------------
	var wins_before := _rounds.wins_for("YOU")
	_bot.eliminate()
	_rounds.report_out(_bot)
	await get_tree().physics_frame
	foe.eliminate()
	_rounds.report_out(foe)
	await get_tree().physics_frame
	_expect("clearing a whole side ends the round", not _rounds.is_live(),
		"state=%d, %d sides up" % [_rounds.state, _rounds.teams_standing()])
	_expect("and the side that survived takes it, not the survivor",
		_rounds.wins_for("YOU") == wins_before + 1,
		"YOU %d -> %d, score %s" % [
			wins_before, _rounds.wins_for("YOU"), str(_rounds.scores())])

	print("[teams] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Puts each fighter where the dictionary says and holds them there for `seconds`.
##
## `_place_fighters` only knows about two bodies, and by writing `global_position` rather than
## calling `respawn_at` this keeps the instability the next assertion is about to read. See
## ARCHITECTURE.md on the suite that measured the lava burning 0.4 points in a second.
func _line_up(spots: Dictionary, seconds: float) -> void:
	await _pin_while(spots, seconds)


func _pin_while(spots: Dictionary, seconds: float) -> void:
	var held := 0.0
	while held < seconds:
		for fighter in spots:
			var body := fighter as Player
			if is_instance_valid(body) and not body.is_eliminated():
				body.global_position = spots[fighter]
		await get_tree().physics_frame
		held += 1.0 / 60.0


## Playing at a desk, the way the map this game follows plays: right click to walk, a key to
## arm a spell, a left click to say where it goes.
##
## Needs a REAL WINDOW. `Input.warp_mouse` and parsed mouse buttons do nothing under
## `--headless`, so a headless run reports failures that say nothing about the code.
func _run_pc_tests() -> void:
	_mobile.visibility_mode = MobileControls.Visibility.HIDDEN
	await _settle()
	_quiet_feel()
	_clear_cover()
	_freeze_arena()
	_freeze_bot()
	await _wait_for_live()

	# --- the bindings ------------------------------------------------------------------------
	_expect("Q W E R are the four spell slots",
		_action_has_key("cast_1", KEY_Q) and _action_has_key("cast_2", KEY_W)
			and _action_has_key("cast_3", KEY_E) and _action_has_key("cast_4", KEY_R),
		"%s | %s | %s | %s" % [_keys_of("cast_1"), _keys_of("cast_2"),
			_keys_of("cast_3"), _keys_of("cast_4")])
	_expect("the left button sends an armed spell",
		_action_has_mouse(PlayerInputController.PRIMARY_CLICK, MOUSE_BUTTON_LEFT),
		_keys_of(PlayerInputController.PRIMARY_CLICK))
	_expect("the right button walks you there",
		_action_has_mouse(PlayerInputController.MOVE_CLICK, MOUSE_BUTTON_RIGHT),
		_keys_of(PlayerInputController.MOVE_CLICK))
	_expect("W no longer walks - it is a spell now",
		not _action_has_key("move_forward", KEY_W), _keys_of("move_forward"))
	_expect("and the arrow keys still do, because nothing else wants them",
		_action_has_key("move_forward", KEY_UP) and _action_has_key("move_left", KEY_LEFT)
			and _action_has_key("move_back", KEY_DOWN)
			and _action_has_key("move_right", KEY_RIGHT), _keys_of("move_forward"))
	# AUTO for this one assertion: the suite runs with the controls forced HIDDEN, and what is
	# under test here is precisely what AUTO decides on a machine with no touchscreen.
	_mobile.visibility_mode = MobileControls.Visibility.AUTO
	await _settle()
	_expect("a desktop gets no thumbstick, but does get a spell bar to read",
		not _mobile.joystick.visible and _mobile.visible
			and not _mobile.is_touch_driving(),
		"stick=%s, bar=%s, thumb driving=%s" % [
			_mobile.joystick.visible, _mobile.visible, _mobile.is_touch_driving()])
	_mobile.visibility_mode = MobileControls.Visibility.HIDDEN
	await _settle()
	_expect("with no controls drawn, the cursor is live", _pointing_is_live(),
		"the touchscreen flag says %s and is not consulted"
			% DisplayServer.is_touchscreen_available())

	# --- a key ARMS, and casts nothing -----------------------------------------------------
	await _place_fighters(Vector3(6.0, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	_input.set_override_vector(Vector2.ZERO, true)
	var book := _player.abilities()
	book.reset()
	await _equip(&"force_wave", &"blink", &"arcane_shield")
	_emit_key(KEY_Q, true)
	_emit_key(KEY_Q, false)
	await _settle()
	_expect("a key arms a spell and casts nothing", _input.armed_slot() == 0
		and _pool.in_flight().is_empty() and book.is_ready(0),
		"armed=%d, %d in flight" % [_input.armed_slot(), _pool.in_flight().size()])
	_expect("and the indicator comes up for it", _input.command.aiming_slot == 0,
		"aiming_slot=%d" % _input.command.aiming_slot)

	# --- the cursor only aims while something is armed ---------------------------------------
	var cam := get_viewport().get_camera_3d()
	Input.warp_mouse(cam.unproject_position(_player.global_position + Vector3(4.0, 0.0, 0.0)))
	Input.flush_buffered_events()
	await _settle()
	_expect("an armed spell follows the cursor",
		_input.command.has_aim
			and _input.command.aim_dir.distance_to(Vector2(1, 0)) < 0.1,
		"aim reads %s" % _input.command.aim_dir)

	# --- a left click sends it THERE -----------------------------------------------------------
	await _click(MOUSE_BUTTON_LEFT)
	await get_tree().physics_frame
	var flying := _pool.in_flight()
	_expect("a left click sends the armed spell at the cursor", flying.size() == 1
		and Vector2(flying[0].direction().x, flying[0].direction().z)
			.distance_to(Vector2(1, 0)) < 0.12,
		"%d in flight, heading %s" % [flying.size(),
			flying[0].direction() if flying.size() == 1 else Vector3.ZERO])
	_expect("and puts the spell away again", _input.armed_slot() == -1
		and _input.command.aiming_slot == -1,
		"armed=%d" % _input.armed_slot())

	# --- ...and with nothing armed, the wizard faces where it walks -----------------------------
	_input.set_override_vector(Vector2(0.0, 1.0), true)
	await _settle()
	_expect("with nothing armed the cursor does not turn your head",
		_input.command.aim_dir.distance_to(_input.command.move_dir) < 0.01,
		"aim %s vs move %s, cursor is off to the right" % [
			_input.command.aim_dir, _input.command.move_dir])
	_input.set_override_vector(Vector2.ZERO, true)

	# --- the same key, or a right click, takes it back --------------------------------------------
	book.reset()
	_emit_key(KEY_Q, true)
	_emit_key(KEY_Q, false)
	await _settle()
	_emit_key(KEY_Q, true)
	_emit_key(KEY_Q, false)
	await _settle()
	_expect("the same key again puts the spell away", _input.armed_slot() == -1,
		"armed=%d" % _input.armed_slot())
	# Armed through the controller, not through a key. That the KEY arms is proved three
	# assertions up; what is under test here is what a right click does to something armed, and
	# an injected key that occasionally misses its frame turns this into a test of nothing -
	# it silently became "right click with nothing armed", which of course walks you off.
	_input.arm(0)
	await _settle()
	await _click(MOUSE_BUTTON_RIGHT)
	_expect("a right click cancels it rather than walking you off",
		_input.armed_slot() == -1 and not _input.is_click_moving(),
		"armed=%d, walking=%s" % [_input.armed_slot(), _input.is_click_moving()])
	_expect("and nothing was cast by any of that", book.is_ready(0),
		"slot ready=%s" % book.is_ready(0))

	# --- with nothing armed, the LEFT button walks you too ---------------------------------
	# A fallback, because a browser can swallow a right click before the game sees one. It can
	# never be ambiguous: armed, the left button sends; empty, it walks.
	# Arming has to SHOW, and on a desk the button is the only place it can. Q felt like a key
	# that did nothing until this existed.
	_input.arm(1)
	await _settle()
	_expect("the armed slot lights up on the bar",
		_mobile.buttons[1].armed and not _mobile.buttons[0].armed,
		"slot 1 lit=%s, slot 0 lit=%s" % [
			_mobile.buttons[1].armed, _mobile.buttons[0].armed])
	_input.disarm()
	await _settle()
	_expect("and goes dark when it is put away", not _mobile.buttons[1].armed,
		"slot 1 lit=%s" % _mobile.buttons[1].armed)
	_expect("no key is bound twice - R was a spell AND a round restart",
		not _action_has_key("cast_4", KEY_R) or not InputMap.has_action("debug_respawn"),
		"debug_respawn exists=%s" % InputMap.has_action("debug_respawn"))

	_expect("the letters on the icons come from the input map, not from a list",
		PlayerInputController.key_label_for(0) == "Q"
			and PlayerInputController.key_label_for(1) == "W"
			and PlayerInputController.key_label_for(2) == "E"
			and PlayerInputController.key_label_for(3) == "R",
		"%s %s %s %s" % [PlayerInputController.key_label_for(0),
			PlayerInputController.key_label_for(1), PlayerInputController.key_label_for(2),
			PlayerInputController.key_label_for(3)])

	# --- a ward needs no place, so it goes at once ---------------------------------------------------
	# Placed first, and `_place_fighters` waits for a LIVE round. The suite had been casting
	# straight on from the previous section while the round turned over underneath it:
	# `accepts_input` was false, the cast was dropped, and it read as a ward that does not work.
	# The rule is in ARCHITECTURE.md and this suite was ignoring it.
	await _place_fighters(Vector3(6.0, 1.2, 0.0), Vector3(0.0, 1.2, 0.0))
	# And again HERE, not only inside `_place_fighters`. That waits for a live round before it
	# starts pinning, and the round can turn over during the three quarters of a second it then
	# spends pinning - which is exactly what happened: the bot had been shoved into the lava by
	# the casts above, round 2 opened mid-pin, and the ward was cast into a countdown.
	await _wait_for_live()
	book.reset()
	_emit_key(KEY_R, true)
	_emit_key(KEY_R, false)
	# `accepts_input` is PINNED across the window, the way the other suites pin a position.
	# What is under test is a rule about arming, and the round loop keeps turning over
	# underneath this suite - the bot has been shot at for twenty seconds by now - which drops
	# the cast into a countdown and reads as a ward that does not fire. Pinning the one piece
	# of state the test is not about is the same trick `_place_fighters` uses, and for the same
	# reason. See ARCHITECTURE.md on suites that measure a fighter correctly told to stand still.
	var held := 0.0
	while held < 0.3:
		_player.accepts_input = true
		await get_tree().physics_frame
		held += 1.0 / 60.0
	_expect("a ward fires on the key, with no click to place it",
		_player.is_shielded() and _input.armed_slot() == -1,
		"shielded=%s, armed=%d, round live=%s, accepts input=%s, slot 3 ready=%s" % [
			_player.is_shielded(), _input.armed_slot(), _rounds.is_live(),
			_player.accepts_input, book.is_ready(3)])

	# --- right click walks you there, and stops when you arrive ---------------------------------------
	await _place_fighters(Vector3(0.0, 1.2, 9.0), Vector3(0.0, 1.2, 0.0))
	await _wait_for_live()
	_input.set_override_vector(Vector2.ZERO, false)
	var spot := Vector3(4.5, 0.0, 0.0)
	Input.warp_mouse(cam.unproject_position(spot))
	Input.flush_buffered_events()
	await _click(MOUSE_BUTTON_RIGHT)
	_expect("a right click on the ground gives a walk order", _input.is_click_moving(),
		"walking=%s" % _input.is_click_moving())
	_expect("and leaves a mark on the ground where it landed",
		_move_marker.is_showing()
			and Vector2(_move_marker.global_position.x - spot.x,
				_move_marker.global_position.z - spot.z).length() < 0.2,
		"marker showing=%s at %s, clicked %s" % [
			_move_marker.is_showing(), _move_marker.global_position, spot])
	var walked := 0.0
	while walked < 4.0 and _input.is_click_moving():
		# Pinned, like the ward window above. A fighter whose round has turned over ignores
		# `move_dir` entirely, so the order stands, the wizard does not move, and it reads as
		# click-to-move being broken. Same trap, second time in one suite.
		_player.accepts_input = true
		await get_tree().physics_frame
		walked += 1.0 / 60.0
	var gap := Vector2(_player.global_position.x - spot.x, _player.global_position.z - spot.z)
	_expect("the wizard walks to it and stops", gap.length() < 1.0
		and not _input.is_click_moving(),
		"stopped %.2fm away after %.1fs" % [gap.length(), walked])

	# --- and a new round does not resume last round's order ---------------------------------------------
	Input.warp_mouse(cam.unproject_position(Vector3(-6.0, 0.0, 0.0)))
	Input.flush_buffered_events()
	await _click(MOUSE_BUTTON_RIGHT)
	_on_round_started(99)
	await _settle()
	_expect("a round reset drops the standing walk order",
		not _input.is_click_moving() and _input.armed_slot() == -1,
		"walking=%s, armed=%d" % [_input.is_click_moving(), _input.armed_slot()])

	print("[pc] %s (%d failure(s))" % [
		"ALL PASS" if _touch_failures == 0 else "FAILURES", _touch_failures])
	get_tree().quit(1 if _touch_failures > 0 else 0)


## Injects a mouse button, the way `_emit_key` injects a key.
##
## Flushed immediately: a parsed event alone sits in the queue for an unpredictable number of
## frames, which is the trap ARCHITECTURE.md records against every other injected input here.
func _emit_click(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = get_viewport().get_mouse_position()
	event.global_position = event.position
	_dispatch(event)


## A whole click, with the pipeline given time to turn over on each half.
##
## A right click takes THREE hops to become a walk order - the controller reads the button, the
## level turns it into a patch of ground, the character walks toward it - and one `_settle()`
## straddles two of them. Every failure that produced looked like a dead mouse button.
func _click(button: MouseButton) -> void:
	_emit_click(button, true)
	await _settle()
	_emit_click(button, false)
	await _settle()
	await _settle()


func _action_has_key(action: String, code: Key) -> bool:
	for event in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null and key.physical_keycode == code:
			return true
	return false


func _action_has_mouse(action: String, button: MouseButton) -> bool:
	for event in InputMap.action_get_events(action):
		var click := event as InputEventMouseButton
		if click != null and click.button_index == button:
			return true
	return false


## What an action is bound to, for the failure line. A binding assertion that fails without
## saying what IS bound sends you to the project file to find out.
func _keys_of(action: String) -> String:
	var parts := PackedStringArray()
	for event in InputMap.action_get_events(action):
		parts.append(event.as_text())
	return "%s: %s" % [action, ", ".join(parts)]

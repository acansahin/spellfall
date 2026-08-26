class_name RoundManager
extends Node

## Runs the round loop: countdown, live, someone falls, someone wins, reset.
##
## Deliberately knows nothing about combat. It never reads instability, never applies
## knockback, never spawns a projectile. It is handed a list of fighters and told when one
## falls; everything else is bookkeeping. That separation is why the brief warns against a
## giant GameManager - a round system tangled into combat cannot be tested without playing
## the game, and cannot be replaced when the rules change.
##
## It counts TEAMS, not bodies. A 1v1 is two teams of one and reads exactly as it always did;
## a 2v2 is two teams of two, and the only thing that changes is that a round ends when a SIDE
## is gone rather than when one fighter is left. Score is per team for the same reason - "YOU 2
## BOT 1" is a statement about sides, and in a 2v2 nobody wants two rows saying the same thing.
##
## It also does not know what a KillZone is, or what lava is. `report_out()` is the only way
## in, so burning to nothing, dropping out of the world, a suicide, or a server telling us
## someone disconnected all arrive through one door. It was called `report_fall` while falling
## was the only way to lose; the lava made that name a lie.

signal round_started(number: int)
## Seconds left, counted down. 0 means "go".
signal countdown_changed(remaining: int)
signal fighter_eliminated(fighter: Player, title: String)
## `winner` is null on a draw - everyone fell within the same moment.
signal round_ended(winner: Player, title: String)
signal score_changed(scores: Array)
signal match_ended(winner: Player, title: String)

enum State { IDLE, COUNTDOWN, LIVE, OVER }

## Seconds of frozen countdown before a round goes live.
@export var countdown_seconds: float = 3.0

## Seconds the winner is shown before the next round starts.
@export var interlude_seconds: float = 2.0

## Round wins needed to take the match.
@export var wins_needed: int = 3

var state: State = State.IDLE
var round_number: int = 0

var _fighters: Array[Player] = []
var _titles: Array[String] = []
var _spawns: Array[Vector3] = []
var _alive: Array[bool] = []

## Which side each fighter is on, parallel to `_fighters`.
var _teams: Array[int] = []

## Side ids in the order they were first seen, their names, and their round wins. Three
## parallel arrays rather than a dictionary of dictionaries, because `scores()` has to report
## them IN ORDER and a Dictionary makes that a sort nobody asked for.
var _team_ids: Array[int] = []
var _team_names: Array[String] = []
var _wins: Array[int] = []
var _timer: float = 0.0
var _last_announced: int = -1


## Registers a fighter. Order defines row order in the instability readout.
##
## `team` defaults to the fighter's own, so a 1v1 registers exactly as it always did and the
## two sides fall out of `player.tscn` saying 0 and `bot_wizard.tscn` saying 1.
##
## `team_name` is what the SCORE calls that side, and only the first fighter of a side gets to
## name it - in a 2v2 the ally does not add a second row, it joins one.
func add_fighter(fighter: Player, spawn: Vector3, title: String,
		team: int = -1, team_name: String = "") -> void:
	var side := team if team >= 0 else fighter.team
	_fighters.append(fighter)
	_titles.append(title)
	_spawns.append(spawn)
	_alive.append(true)
	_teams.append(side)
	if not _team_ids.has(side):
		_team_ids.append(side)
		_team_names.append(team_name if team_name != "" else title)
		_wins.append(0)


func start_match() -> void:
	for i in _wins.size():
		_wins[i] = 0
	round_number = 0
	score_changed.emit(scores())
	begin_round()


func begin_round() -> void:
	round_number += 1
	for i in _fighters.size():
		_alive[i] = true
		_fighters[i].revive_at(_spawns[i])
		_fighters[i].accepts_input = false
	state = State.COUNTDOWN
	_timer = countdown_seconds
	_last_announced = -1
	round_started.emit(round_number)


func _process(delta: float) -> void:
	match state:
		State.COUNTDOWN:
			_tick_countdown(delta)
		State.OVER:
			_tick_interlude(delta)
		_:
			pass


func _tick_countdown(delta: float) -> void:
	_timer -= delta
	var whole := maxi(0, ceili(_timer))
	if whole != _last_announced:
		_last_announced = whole
		countdown_changed.emit(whole)
	if _timer > 0.0:
		return
	state = State.LIVE
	for fighter in _fighters:
		fighter.accepts_input = true


func _tick_interlude(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	if _match_winner() >= 0:
		start_match()
	else:
		begin_round()


## The only way a fighter leaves a round.
func report_out(body: Node3D) -> void:
	if state != State.LIVE:
		return
	var index := _fighters.find(body)
	if index < 0 or not _alive[index]:
		return
	_alive[index] = false
	_fighters[index].eliminate()
	fighter_eliminated.emit(_fighters[index], _titles[index])
	_check_for_winner()


## The round is over when one SIDE is left, not when one fighter is. In a 1v1 those are the
## same sentence; in a 2v2 they are not, and counting bodies would end the round the moment
## anybody fell.
func _check_for_winner() -> void:
	var sides := _standing_teams()
	if sides.size() > 1:
		return
	state = State.OVER
	_timer = interlude_seconds
	for fighter in _fighters:
		fighter.accepts_input = false

	if sides.is_empty():
		# Everyone went over within the same instant. Nobody scores.
		round_ended.emit(null, "")
		return
	var side: int = sides[0]
	var slot := _team_ids.find(side)
	_wins[slot] += 1
	score_changed.emit(scores())
	# The winner reported is a fighter, because that is what every listener wants: the level
	# marks their position and the camera looks at them. In a 2v2 it is whoever of the winning
	# side is still standing, which after an elimination is the survivor and otherwise is
	# simply the first of them - neither of which is a claim about who did the work.
	round_ended.emit(_first_standing_of(side), _team_names[slot])
	var champion := _match_winner()
	if champion >= 0:
		match_ended.emit(_first_standing_of(_team_ids[champion]), _team_names[champion])


func _standing() -> Array[int]:
	var out: Array[int] = []
	for i in _alive.size():
		if _alive[i]:
			out.append(i)
	return out


## The sides with at least one fighter left, in the order they were registered.
func _standing_teams() -> Array[int]:
	var out: Array[int] = []
	for i in _alive.size():
		if _alive[i] and not out.has(_teams[i]):
			out.append(_teams[i])
	return out


## Anyone still up on `side`, or the first fighter registered to it if nobody is - which is the
## draw case, where the caller wants a body to point at more than it wants a survivor.
func _first_standing_of(side: int) -> Player:
	var fallback: Player = null
	for i in _fighters.size():
		if _teams[i] != side:
			continue
		if fallback == null:
			fallback = _fighters[i]
		if _alive[i]:
			return _fighters[i]
	return fallback


## Index into `_team_ids` of the side that has taken the match, or -1.
func _match_winner() -> int:
	for i in _wins.size():
		if _wins[i] >= wins_needed:
			return i
	return -1


## [[team name, wins], ...] for the score readout. One entry per SIDE, not per fighter.
func scores() -> Array:
	var out: Array = []
	for i in _team_ids.size():
		out.append([_team_names[i], _wins[i]])
	return out


func is_live() -> bool:
	return state == State.LIVE


func alive_count() -> int:
	return _standing().size()


## Round wins for a side. Accepts either the side's own name or the name of any fighter on it,
## so a caller that only knows "YOU" gets the right answer whether "YOU" is a person or a team.
func wins_for(title: String) -> int:
	var slot := _team_names.find(title)
	if slot < 0:
		var who := _titles.find(title)
		if who >= 0:
			slot = _team_ids.find(_teams[who])
	return _wins[slot] if slot >= 0 else 0


## How many SIDES are still in the round. `alive_count()` above counts bodies; this counts what
## the round actually ends on.
func teams_standing() -> int:
	return _standing_teams().size()


## Which side `fighter` is on, or -1 if it was never registered.
func team_of(fighter: Player) -> int:
	var i := _fighters.find(fighter)
	return _teams[i] if i >= 0 else -1

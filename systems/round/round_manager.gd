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
## It also does not know what a KillZone is. `report_fall()` is the only way in, so a future
## out-of-bounds rule, a suicide, or a server telling us someone disconnected all arrive
## through one door.

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
var _wins: Array[int] = []
var _alive: Array[bool] = []
var _timer: float = 0.0
var _last_announced: int = -1


## Registers a fighter. Order defines slot order in the score readout.
func add_fighter(fighter: Player, spawn: Vector3, title: String) -> void:
	_fighters.append(fighter)
	_titles.append(title)
	_spawns.append(spawn)
	_wins.append(0)
	_alive.append(true)


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


## The only way a fall enters this system.
func report_fall(body: Node3D) -> void:
	if state != State.LIVE:
		return
	var index := _fighters.find(body)
	if index < 0 or not _alive[index]:
		return
	_alive[index] = false
	_fighters[index].eliminate()
	fighter_eliminated.emit(_fighters[index], _titles[index])
	_check_for_winner()


func _check_for_winner() -> void:
	var standing := _standing()
	if standing.size() > 1:
		return
	state = State.OVER
	_timer = interlude_seconds
	for fighter in _fighters:
		fighter.accepts_input = false

	if standing.is_empty():
		# Everyone went over within the same instant. Nobody scores.
		round_ended.emit(null, "")
		return
	var index: int = standing[0]
	_wins[index] += 1
	score_changed.emit(scores())
	round_ended.emit(_fighters[index], _titles[index])
	var champion := _match_winner()
	if champion >= 0:
		match_ended.emit(_fighters[champion], _titles[champion])


func _standing() -> Array[int]:
	var out: Array[int] = []
	for i in _alive.size():
		if _alive[i]:
			out.append(i)
	return out


func _match_winner() -> int:
	for i in _wins.size():
		if _wins[i] >= wins_needed:
			return i
	return -1


## [[title, wins], ...] for the score readout.
func scores() -> Array:
	var out: Array = []
	for i in _titles.size():
		out.append([_titles[i], _wins[i]])
	return out


func is_live() -> bool:
	return state == State.LIVE


func alive_count() -> int:
	return _standing().size()


func wins_for(title: String) -> int:
	var i := _titles.find(title)
	return _wins[i] if i >= 0 else 0

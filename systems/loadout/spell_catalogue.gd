class_name SpellCatalogue
extends Resource

## Every spell in the game, arranged as the choice a player is offered before a match.
##
## One fixed spell and a column per remaining slot. The fixed one is not a column with a single
## entry: it is the spell the whole game is taught with, it is on the same button every match,
## and a player who has picked nothing still has something to press. Everything else is a
## choice, and the choices are exclusive - one per column, never two from one.
##
## This is DATA. Adding a spell is adding a `.tres` to `data/abilities/` and listing it in a
## column here; nothing in `main.gd`, the loadout screen or the bot learns a new name. That is
## the same promise `Ability` makes about spells, extended to the roster.
##
## The structure is taken from the Warcraft III arena map this game takes after, which offers
## its spells the same way - see GAME_DESIGN.md on what was and was not borrowed.

## The spell every wizard carries, in slot 0. Never chosen and never replaced.
@export var primary: Ability = null

## One per remaining slot, in slot order: `columns[0]` fills slot 1.
@export var columns: Array[SpellColumn] = []


## How many spell buttons a wizard built from this catalogue has.
func slot_count() -> int:
	return columns.size() + 1


## The picks a player who chooses nothing gets: the first spell of every column.
func default_picks() -> PackedInt32Array:
	var picks := PackedInt32Array()
	picks.resize(columns.size())
	picks.fill(0)
	return picks


## A random loadout. The bot takes one each match, which is the cheapest way to make sure every
## spell in the catalogue is something the player has actually had used against them.
##
## Takes the generator rather than making one, so a scripted run that seeds the bot gets the
## same opponent twice - the same reason `BotController.reseed` exists.
func random_picks(rng: RandomNumberGenerator) -> PackedInt32Array:
	var picks := PackedInt32Array()
	for column in columns:
		picks.append(rng.randi_range(0, maxi(column.spells.size() - 1, 0)))
	return picks


## Turns picks into a spellbook: the primary first, then one spell per column.
##
## Short, over-long and out-of-range pick lists all produce a full book, because this is fed by
## a saved file, a command line and a UI - three sources that can each be stale in a different
## way, and none of which should be able to produce a wizard with a hole in its spellbook.
func spellbook(picks: PackedInt32Array) -> Array[Ability]:
	var book: Array[Ability] = []
	if primary != null:
		book.append(primary)
	for i in columns.size():
		var choice := picks[i] if i < picks.size() else 0
		var spell := columns[i].spell_at(choice)
		if spell != null:
			book.append(spell)
	return book


## Turns a list of spell ids back into picks, ignoring any the catalogue does not hold.
##
## The inverse of `spellbook`, for the saved loadout and for `--loadout:`. An id that no longer
## exists leaves that column on its default rather than failing the whole loadout: a roster
## edit must not cost a player the two picks that are still valid.
func picks_from_ids(ids: PackedStringArray) -> PackedInt32Array:
	var picks := default_picks()
	for id in ids:
		for i in columns.size():
			var found := columns[i].index_of(StringName(id))
			if found >= 0:
				picks[i] = found
				break
	return picks


## The ids behind a set of picks, in column order. What gets saved.
func ids_from_picks(picks: PackedInt32Array) -> PackedStringArray:
	var ids := PackedStringArray()
	for i in columns.size():
		var choice := picks[i] if i < picks.size() else 0
		var spell := columns[i].spell_at(choice)
		ids.append(String(spell.id) if spell != null else "")
	return ids


## Every spell in the catalogue, primary first. For the harness, which checks the roster is
## whole - unique ids, no nulls - rather than trusting a hand-edited `.tres`.
func all_spells() -> Array[Ability]:
	var out: Array[Ability] = []
	if primary != null:
		out.append(primary)
	for column in columns:
		for spell in column.spells:
			if spell != null:
				out.append(spell)
	return out

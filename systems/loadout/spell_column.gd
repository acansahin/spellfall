class_name SpellColumn
extends Resource

## One button's worth of choice: the spells that may sit in a single slot.
##
## A column, not a category. Every spell in one competes for the same finger position, so the
## thing they have in common is not a theme - it is that you may have exactly one of them.
## That is the shape the loadout screen draws and the shape the fight enforces, and stating it
## as data means adding a fourth option to a slot is editing a `.tres`.
##
## Which slot a column drives is its INDEX in `SpellCatalogue.columns`, not a field here. A
## column that named its own slot could be listed second and claim the third button, and
## nothing on screen would look wrong.

## Shown above the choices. Two or three words - it has to fit a phone in landscape.
@export var title: String = ""

## One line under the title saying what the slot is FOR, so a player who has never seen any of
## these three still knows what they are choosing between.
@export var subtitle: String = ""

## The options, in the order they are drawn. The first is the default, which is what a run
## that skips the screen gets - so put the readable one first, not the clever one.
@export var spells: Array[Ability] = []


## The spell at `index`, or the first one if the index is out of range.
##
## Falls back rather than returning null on purpose: a stale saved pick, a shorter column
## after an edit, or a harness passing a number typed by hand must all produce a playable
## wizard. A slot holding null is a button that does nothing and says nothing about why.
func spell_at(index: int) -> Ability:
	if spells.is_empty():
		return null
	if index < 0 or index >= spells.size():
		return spells[0]
	return spells[index]


## Index of the spell with this id, or -1. Used to turn a saved or command-line loadout back
## into picks without the caller knowing what order the column is in.
func index_of(id: StringName) -> int:
	for i in spells.size():
		if spells[i] != null and spells[i].id == id:
			return i
	return -1

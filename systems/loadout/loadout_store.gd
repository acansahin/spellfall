class_name LoadoutStore
extends RefCounted

## Remembers which spells the player chose last time.
##
## This is NOT progression, and the line matters: the roadmap holds accounts, unlocks and a
## shop back until the combat is fun. Nothing here is earned, nothing is spent, and every
## spell is available on a fresh install. It exists so that playtesting the same loadout twice
## does not cost two trips through a menu - which is a tooling problem, not a game feature.
##
## Stored as spell IDS rather than as indices, so reordering a column in the catalogue cannot
## silently hand a returning player a different spell. An id the catalogue no longer holds
## leaves that column on its default; see `SpellCatalogue.picks_from_ids`.
##
## Failure is never fatal. A missing file, an unreadable one or a file from a future version
## all produce the default loadout, because a corrupt preference must never be the reason a
## game does not open.

const PATH := "user://loadout.cfg"
const SECTION := "loadout"
const KEY := "spells"


## The stored picks, or the catalogue's defaults.
static func load_picks(catalogue: SpellCatalogue) -> PackedInt32Array:
	if catalogue == null:
		return PackedInt32Array()
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return catalogue.default_picks()
	var ids: PackedStringArray = config.get_value(SECTION, KEY, PackedStringArray())
	if ids.is_empty():
		return catalogue.default_picks()
	return catalogue.picks_from_ids(ids)


## Writes the picks. Returns false if it could not, which nothing is expected to act on -
## losing a preference is not worth interrupting a match for.
static func save_picks(catalogue: SpellCatalogue, picks: PackedInt32Array) -> bool:
	if catalogue == null:
		return false
	var config := ConfigFile.new()
	config.set_value(SECTION, KEY, catalogue.ids_from_picks(picks))
	return config.save(PATH) == OK


## Forgets the stored loadout. For the harness, which must be able to prove the DEFAULT path
## works on a machine that has already played a match.
static func clear() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

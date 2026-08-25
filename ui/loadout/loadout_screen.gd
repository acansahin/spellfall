class_name LoadoutScreen
extends CanvasLayer

## The screen before the match: one spell per column, then fight.
##
## It is BUILT FROM THE CATALOGUE, not laid out in a scene. Adding a fourth option to a column
## is editing `data/spell_catalogue.tres` and nothing else - no node to add, no index to keep
## in step, no label to retype. That is the same promise `Ability` makes about spells and
## `SpellCatalogue` makes about the roster, and it is the only reason a menu is allowed to
## exist in a prototype at all.
##
## It decides NOTHING about the fight. It emits `confirmed` with a list of indices and the
## level turns that into a spellbook, exactly as the touch buttons emit a press and the level
## turns that into a cast. A menu that reached into an AbilityComponent would be a second place
## a wizard gets armed.
##
## Sizes are canvas units against the 1280x720 design resolution, like every other UI value in
## this project - see mobile_controls.gd on why they are not fractions of the viewport.

## The player is done choosing. `picks[i]` is the chosen index within `columns[i]`.
signal confirmed(picks: PackedInt32Array)

## Height of one option's tap target. Comfortably past the ~48dp minimum a thumb wants, and
## sized so the longest column - four options - still leaves room for the title and the button
## underneath it on a 720-unit canvas.
const OPTION_HEIGHT := 74.0

## Width of a column. Three of these plus the gaps fill the design width with a margin either
## side; a fourth column would need this to come down, which is the moment to notice.
const COLUMN_WIDTH := 372.0

const BACKDROP := Color(0.043, 0.035, 0.09, 0.97)
const IDLE_FILL := Color(1, 1, 1, 0.06)
const IDLE_EDGE := Color(1, 1, 1, 0.16)
const DIM_TEXT := Color(0.72, 0.72, 0.80)

## Side of the square each option's glyph sits in. Matched to the two lines of text beside it,
## so the icon reads as the row's own mark rather than as a picture stuck next to one.
const ICON_SIDE := 46.0

var _catalogue: SpellCatalogue = null
var _picks := PackedInt32Array()

## The option panels, per column, so a selection can restyle its own row without rebuilding
## the screen. Parallel to `_catalogue.columns`.
var _panels: Array = []


func _ready() -> void:
	# Set here and deliberately NOT also in the scene. A value written in both places is a value
	# the script silently wins - which is how `projectile.tscn`'s collision mask spent a session
	# saying one thing while the flying projectile did another. Above the HUD and the touch
	# controls, and dark until somebody opens it.
	layer = 10
	visible = false


## Shows the screen for `catalogue`, with `picks` pre-selected.
##
## Building here and not in `_ready()` because the catalogue arrives from the level - the same
## hand-it-its-dependencies rule the stick, the bot and the HUD already follow. A screen that
## loaded its own catalogue would be a second place the roster is named.
func open(catalogue: SpellCatalogue, picks: PackedInt32Array) -> void:
	_catalogue = catalogue
	_picks = picks.duplicate()
	while _picks.size() < catalogue.columns.size():
		_picks.append(0)
	_build()
	visible = true


func close() -> void:
	visible = false


## True while the player is still choosing. The level asks, so a harness that skipped the
## screen and a player who has finished with it look the same from outside.
func is_open() -> bool:
	return visible


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_panels.clear()

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = BACKDROP
	# STOP, not ignore. The backdrop is what makes the rest of the game untouchable while this
	# is up: a tap that lands between two columns must not fall through to whatever the level
	# happens to be drawing underneath.
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(backdrop)

	var page := VBoxContainer.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.offset_left = 40.0
	page.offset_right = -40.0
	page.offset_top = 24.0
	page.offset_bottom = -24.0
	page.add_theme_constant_override("separation", 14)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(page)

	page.add_child(_heading("CHOOSE YOUR SPELLS", 30, Color(1, 0.93, 0.72)))
	page.add_child(_heading("Pick one from each column.", 16, DIM_TEXT))
	if _catalogue.primary != null:
		page.add_child(_build_fixed(_catalogue.primary))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 22)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(row)

	for index in _catalogue.columns.size():
		row.add_child(_build_column(index))

	var start := Button.new()
	start.text = "FIGHT"
	start.custom_minimum_size = Vector2(280.0, 62.0)
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.add_theme_font_size_override("font_size", 24)
	start.pressed.connect(_on_start)
	page.add_child(start)


## The spell nobody chooses, shown anyway.
##
## It is the one thing on this screen that is not a decision, and leaving it off made the screen
## say the player carries three spells. It also puts Fireball's own glyph in front of them once,
## which is otherwise the only icon in the game they meet for the first time mid-fight.
##
## Drawn deliberately unlike an option: no border, dimmer, centred, and it claims no input.
func _build_fixed(spell: Ability) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := SpellIcon.new()
	icon.ability = spell
	icon.custom_minimum_size = Vector2.ONE * (ICON_SIDE * 0.7)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var label := Label.new()
	label.text = "%s — always with you" % spell.display_name
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", spell.colour)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return row


func _heading(text: String, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _build_column(index: int) -> Control:
	var column: SpellColumn = _catalogue.columns[index]
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0.0)
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	box.add_child(_heading(column.title, 21, Color(1, 1, 1)))
	box.add_child(_heading(column.subtitle, 13, DIM_TEXT))

	var panels: Array = []
	for choice in column.spells.size():
		var panel := _build_option(column.spells[choice], index, choice)
		panels.append(panel)
		box.add_child(panel)
	_panels.append(panels)
	_restyle(index)
	return box


func _build_option(spell: Ability, column_index: int, choice: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(COLUMN_WIDTH, OPTION_HEIGHT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Bound rather than read off the node, so a panel cannot be asked which option it is. The
	# answer travels with the connection, which is what keeps the two lists from disagreeing
	# after a column is reordered.
	panel.gui_input.connect(_on_option_input.bind(column_index, choice))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var icon := SpellIcon.new()
	icon.ability = spell
	icon.custom_minimum_size = Vector2.ONE * ICON_SIDE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 2)
	lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lines)

	var title := HBoxContainer.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(title)

	var name_label := Label.new()
	name_label.text = spell.display_name
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", spell.colour)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(name_label)

	var cooldown := Label.new()
	# The one number on the screen, because it is the one that decides whether a spell is a
	# habit or a moment. Everything else is learned by casting it.
	cooldown.text = "%.1fs" % spell.cooldown
	cooldown.add_theme_font_size_override("font_size", 15)
	cooldown.add_theme_color_override("font_color", DIM_TEXT)
	cooldown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_child(cooldown)

	var blurb := Label.new()
	blurb.text = spell.blurb
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", DIM_TEXT)
	blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.add_child(blurb)

	return panel


## A press anywhere on an option takes it. Both event types are handled because a phone sends
## touches and a desktop dev build sends mouse buttons, and the screen has to work on both -
## the same reason `MobileControls.AUTO` keys off touch emulation.
func _on_option_input(event: InputEvent, column_index: int, choice: int) -> void:
	var pressed := false
	if event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		pressed = mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT
	if not pressed:
		return
	select(column_index, choice)


## Takes option `choice` in column `column_index`. Public so a harness can drive the screen
## without inventing touch events - `--touch-test` is where injected input is the point.
func select(column_index: int, choice: int) -> void:
	if column_index < 0 or column_index >= _picks.size():
		return
	_picks[column_index] = choice
	_restyle(column_index)


func _restyle(column_index: int) -> void:
	if column_index >= _panels.size():
		return
	var column: SpellColumn = _catalogue.columns[column_index]
	var panels: Array = _panels[column_index]
	for choice in panels.size():
		var panel: PanelContainer = panels[choice]
		var spell: Ability = column.spells[choice]
		var chosen := choice == _picks[column_index]
		var box := StyleBoxFlat.new()
		box.bg_color = Color(spell.colour.r, spell.colour.g, spell.colour.b, 0.22) \
			if chosen else IDLE_FILL
		box.border_color = spell.colour if chosen else IDLE_EDGE
		box.set_border_width_all(3 if chosen else 1)
		box.set_corner_radius_all(10)
		box.content_margin_left = 14.0
		box.content_margin_right = 14.0
		box.content_margin_top = 8.0
		box.content_margin_bottom = 8.0
		panel.add_theme_stylebox_override("panel", box)


func _on_start() -> void:
	confirm()


## Closes the screen and reports the picks - what the FIGHT button does.
##
## Public so a suite can finish the screen without inventing a touch on a button whose position
## it would have to know. `--button-test` is where injected input is the point; here it would
## only be a way of not testing the thing under test.
func confirm() -> void:
	close()
	confirmed.emit(_picks.duplicate())


## What is currently selected. For the harness and for the level, which saves it.
func picks() -> PackedInt32Array:
	return _picks.duplicate()

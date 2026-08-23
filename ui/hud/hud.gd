class_name Hud
extends CanvasLayer

## The instability readout. Reads, never writes.
##
## Instability replaces health, so this is the only number telling a player how much trouble
## they are in - it has to be legible at a glance on a phone, mid-fight, in peripheral vision.
## That is why it is colour-coded as well as numeric: you should be able to tell you are in
## danger without reading a digit.
##
## One row per fighter, added by the level. Built as a list rather than two fixed slots
## because 2v2 and a four-player free-for-all are on the roadmap, and a list costs nothing
## extra today.

## Thresholds the colour steps at, matching the bands GAME_DESIGN.md describes. Not balance
## values - purely how the number is painted.
const SAFE := Color(0.82, 0.88, 1.0)
const RISING := Color(1.0, 0.85, 0.35)
const DANGER := Color(1.0, 0.45, 0.35)

@onready var _rows: VBoxContainer = $Root/Rows

var _labels: Dictionary = {}


## Adds a readout for one fighter. `title` is what the player sees.
func add_readout(title: String, source: InstabilityComponent) -> void:
	if source == null:
		return
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 6)
	_rows.add_child(label)
	_labels[source] = {"label": label, "title": title}
	# Bind the source so one handler serves every row, however many fighters there are.
	source.changed.connect(_on_changed.bind(source))
	_refresh(source)


func _on_changed(_current: float, _previous: float, source: InstabilityComponent) -> void:
	_refresh(source)


func _refresh(source: InstabilityComponent) -> void:
	if not _labels.has(source):
		return
	var entry: Dictionary = _labels[source]
	var label: Label = entry["label"]
	label.text = "%s  %d%%" % [entry["title"], roundi(source.current)]
	label.add_theme_color_override("font_color", _tint(source.current))


func _tint(value: float) -> Color:
	if value >= 100.0:
		return DANGER
	if value >= 50.0:
		return RISING
	return SAFE

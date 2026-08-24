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
@onready var _banner: Label = $Root/Banner
@onready var _score: Label = $Root/Score
@onready var _round_label: Label = $Root/RoundLabel

var _labels: Dictionary = {}


## Adds a readout for one fighter. `title` is what the player sees.
##
## `burn` is optional and is only shown while it is below full: a health number that sits at
## 100 all round is a number the eye learns to skip, and then misses the one moment it moves.
func add_readout(title: String, source: InstabilityComponent,
		burn: HealthComponent = null) -> void:
	if source == null:
		return
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	label.add_theme_constant_override("outline_size", 6)
	_rows.add_child(label)
	_labels[source] = {"label": label, "title": title, "burn": burn}
	# Bind the source so one handler serves every row, however many fighters there are.
	source.changed.connect(_on_changed.bind(source))
	if burn != null:
		burn.changed.connect(_on_changed.bind(source))
	_refresh(source)


func _on_changed(_current: float, _previous: float, source: InstabilityComponent) -> void:
	_refresh(source)


func _refresh(source: InstabilityComponent) -> void:
	if not _labels.has(source):
		return
	var entry: Dictionary = _labels[source]
	var label: Label = entry["label"]
	var text := "%s  %d%%" % [entry["title"], roundi(source.current)]
	var burn: HealthComponent = entry.get("burn")
	var burning := burn != null and burn.current < burn.maximum
	if burning:
		text += "   %d" % ceili(burn.current)
	label.text = text
	# While something is burning, that is the only thing worth colouring for. Instability is a
	# slow build; the lava is a countdown, and a countdown wins the player's attention.
	if burning:
		label.add_theme_color_override("font_color",
			DANGER if burn.fraction() < 0.5 else RISING)
	else:
		label.add_theme_color_override("font_color", _tint(source.current))


func _tint(value: float) -> Color:
	if value >= 100.0:
		return DANGER
	if value >= 50.0:
		return RISING
	return SAFE


## Big centre text: the countdown, "GO", the winner. An empty string hides it.
##
## Centred and large because it is read in the half-second between looking up and looking
## back at the fight, which is the only attention anyone has spare for it mid-match.
func set_banner(text: String, tint: Color = Color.WHITE) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", tint)
	_banner.visible = text != ""


## `entries` is [[title, wins], ...], exactly as RoundManager reports it.
func set_score(entries: Array) -> void:
	var parts := PackedStringArray()
	for entry in entries:
		parts.append("%s %d" % [entry[0], entry[1]])
	_score.text = "   ".join(parts)


func set_round(number: int) -> void:
	_round_label.text = "ROUND %d" % number

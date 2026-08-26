class_name SpellIcon
extends Control

## A spell's glyph as a Control, for anywhere that lays icons out rather than drawing them.
##
## `AbilityButton` draws its own directly, because it already has a `_draw` and a centre and a
## radius. A menu row has none of those - it has a container that wants a rectangle of a known
## size - so this exists to be that rectangle. Both go through `SpellGlyph`, so there is one
## drawing and not two.
##
## Inert to input on purpose: the row underneath it is what the player taps, and an icon that
## swallowed the press would make the most obvious part of the option the one dead spot on it.

## The spell to draw. Null draws nothing, which is what an empty slot should look like.
@export var ability: Ability = null:
	set(value):
		ability = value
		queue_redraw()

## Fraction of the box's short side the glyph spans. Leaves a margin, so an icon set flush
## against a label still has air around it.
@export_range(0.2, 1.0, 0.01) var fill := 0.84

@export var line_width := 2.6


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	if ability == null:
		return
	var span := minf(size.x, size.y) * 0.5 * fill
	SpellGlyph.draw_into(self, ability.glyph, size * 0.5, span, ability.colour, line_width)

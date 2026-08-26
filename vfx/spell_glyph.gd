class_name SpellGlyph
extends RefCounted

## The little drawing that tells one spell from another.
##
## Vector shapes stroked into a CanvasItem, not image files. Same rule the sounds follow and
## for the same reason: everything here is placeholder, and a placeholder that costs nothing to
## throw away is one that actually gets thrown away. It also means an icon inherits its spell's
## colour for free, so tinting and shape carry the identity together.
##
## COLOUR ALONE WAS NOT ENOUGH, which is why this exists. Four spells were four tinted discs
## and that read; eleven are eleven tinted discs, and three of them are some shade of blue. On
## a phone, mid-fight, with a thumb over the button, the shape is what you actually recognise.
##
## Every shape is authored in a UNIT BOX: x and y run -1 to 1, y pointing DOWN as canvas space
## does, and `draw_into` scales that to whatever the caller wants. So one glyph serves a 72px
## spell button and a 44px menu row without a second set of numbers, and a resized button
## cannot leave its icon behind.
##
## The shapes are named for what they LOOK like, not for the spell that uses them, so two
## spells may share one and a new spell picks the closest fit rather than forcing a new
## drawing - the same reason `Ability.returns_after` is named after the behaviour and not
## after Loopshot.

## How far the arrowheads stick out, in unit-box terms.
const HEAD := 0.28


## Strokes `glyph` centred on `centre`, scaled so the unit box spans `size` in every direction.
##
## `width` is a line width in PIXELS and is deliberately not scaled with the box: a hairline on
## a 44px menu icon and a hairline on a 72px button are the same hairline, and scaling it would
## make the small one vanish.
static func draw_into(canvas: CanvasItem, glyph: Ability.Glyph, centre: Vector2, size: float,
		tint: Color, width: float) -> void:
	if canvas == null:
		return
	match glyph:
		Ability.Glyph.FLAME:
			_flame(canvas, centre, size, tint)
		Ability.Glyph.FAN:
			_fan(canvas, centre, size, tint, width)
		Ability.Glyph.BOLT:
			_bolt(canvas, centre, size, tint, width)
		Ability.Glyph.SPIRAL:
			_spiral(canvas, centre, size, tint, width)
		Ability.Glyph.BOOMERANG:
			_boomerang(canvas, centre, size, tint)
		Ability.Glyph.JUMP:
			_jump(canvas, centre, size, tint, width)
		Ability.Glyph.CHEVRON:
			_chevron(canvas, centre, size, tint, width)
		Ability.Glyph.SWAP:
			_swap(canvas, centre, size, tint, width)
		Ability.Glyph.SHIELD:
			_shield(canvas, centre, size, tint, width)
		Ability.Glyph.CLOCK:
			_clock(canvas, centre, size, tint, width)
		Ability.Glyph.SURGE:
			_surge(canvas, centre, size, tint, width)


## Prints a key's letter in the corner of a glyph's box.
##
## Bottom-right, small, and dimmer than the glyph. It is a reminder, not a label: the shape is
## what you recognise mid-fight and the letter is what you need for the first ten minutes.
##
## Drawn by the same call that draws the glyph so the two cannot drift apart in size or place,
## and skipped entirely for an empty string - a phone has no keys to name.
static func draw_key(canvas: CanvasItem, label: String, centre: Vector2, size: float,
		tint: Color) -> void:
	if canvas == null or label.is_empty():
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	# A third of the box, floored so it stays legible on the small menu icons.
	var height := clampi(int(size * 0.42), 11, 20)
	var span := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, height)
	# The baseline sits at the bottom-right of the unit box, pulled in by its own descent so a
	# letter with a tail does not hang outside the icon.
	var at := centre + Vector2(size, size) - Vector2(span.x, font.get_descent(height))
	canvas.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, height,
		Color(tint.r, tint.g, tint.b, 0.85))


# ---------------------------------------------------------------------------------------
# The shapes
#
# Each one is a handful of unit-box points. Read them as a picture: the first number is how
# far right, the second how far DOWN.
# ---------------------------------------------------------------------------------------

## Fireball. A teardrop with its point upward, and a second one inside it.
##
## The inner core is not decoration. Drawn as a single shape this read as a WATER droplet on the
## button - which is a fine thing for an icon to look like and the wrong thing for this spell.
## Two tones is what a flame has and a drop does not.
##
## Both halves stay CONVEX deliberately. The honest fire silhouette is concave, and
## `draw_colored_polygon` triangulates without checking - a concave outline comes out with
## chunks missing rather than with an error.
static func _flame(canvas: CanvasItem, centre: Vector2, size: float, tint: Color) -> void:
	_fill(canvas, [
		Vector2(0.0, -1.0), Vector2(0.30, -0.38), Vector2(0.54, 0.16), Vector2(0.34, 0.68),
		Vector2(0.0, 0.88), Vector2(-0.34, 0.68), Vector2(-0.54, 0.16), Vector2(-0.30, -0.38),
	], centre, size, tint)
	var core := Color(1.0, 1.0, 1.0, 0.55)
	_fill(canvas, [
		Vector2(0.0, -0.30), Vector2(0.17, 0.06), Vector2(0.28, 0.38), Vector2(0.17, 0.66),
		Vector2(0.0, 0.76), Vector2(-0.17, 0.66), Vector2(-0.28, 0.38), Vector2(-0.17, 0.06),
	], centre, size, core)


## Force Wave. Three arcs spreading from a point on the left: the fan, drawn as the fan.
static func _fan(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	var origin := centre + Vector2(-0.85, 0.0) * size
	for step in 3:
		var radius := (0.62 + 0.36 * float(step)) * size
		canvas.draw_arc(origin, radius, deg_to_rad(-52.0), deg_to_rad(52.0), 18, tint,
			width, true)


## Arc Lance. A lightning zigzag - the only glyph made of one unbroken hard-angled line.
static func _bolt(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	_stroke(canvas, [
		Vector2(0.45, -1.0), Vector2(-0.28, -0.06), Vector2(0.16, -0.06), Vector2(-0.45, 1.0),
	], centre, size, tint, width)


## Seeker. A curl tightening inward, with a head on the end: a path that changed its mind.
static func _spiral(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	var points: Array = []
	var turns := 2.4
	var steps := 44
	for step in steps + 1:
		var t := float(step) / float(steps)
		var angle := t * turns * TAU
		var radius := lerpf(0.12, 1.0, t)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	_stroke(canvas, points, centre, size, tint, width)
	var last: Vector2 = points[points.size() - 1]
	var before: Vector2 = points[points.size() - 4]
	_head(canvas, centre, size, tint, width, last, (last - before).normalized())


## Loopshot. A boomerang: the one glyph with a corner in it, so it cannot be mistaken for the
## two round ones. Filled, because a thrown object is an object.
static func _boomerang(canvas: CanvasItem, centre: Vector2, size: float, tint: Color) -> void:
	_fill(canvas, [
		Vector2(-0.92, 0.62), Vector2(0.0, -0.88), Vector2(0.92, 0.62),
		Vector2(0.44, 0.80), Vector2(0.0, 0.06), Vector2(-0.44, 0.80),
	], centre, size, tint)


## Blink. Two feet and nothing in between but a dashed hop - the spell is the gap.
static func _jump(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	canvas.draw_circle(centre + Vector2(-0.78, 0.58) * size, maxf(size * 0.15, 2.0), tint)
	canvas.draw_circle(centre + Vector2(0.78, 0.58) * size, maxf(size * 0.15, 2.0), tint)
	# Three dashes along an arc bulging upward. Drawn as separate short arcs rather than as a
	# dotted line, because Godot has no dash pattern and three arcs is the whole of it.
	var pivot := centre + Vector2(0.0, 0.64) * size
	var radius := 0.82 * size
	for step in 3:
		var from := deg_to_rad(-172.0 + 58.0 * float(step))
		canvas.draw_arc(pivot, radius, from, from + deg_to_rad(34.0), 8, tint, width, true)


## Lunge. Three chevrons: the shape every game has ever used for "forward, fast".
static func _chevron(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	for step in 3:
		var x := -0.78 + 0.64 * float(step)
		_stroke(canvas, [
			Vector2(x, -0.62), Vector2(x + 0.5, 0.0), Vector2(x, 0.62),
		], centre, size, tint, width)


## Warp Bolt. Two arrows passing each other. It says "exchange" and it says nothing about
## damage, which is exactly what the spell does.
static func _swap(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	_stroke(canvas, [Vector2(-0.85, -0.45), Vector2(0.72, -0.45)], centre, size, tint, width)
	_head(canvas, centre, size, tint, width, Vector2(0.85, -0.45), Vector2.RIGHT)
	_stroke(canvas, [Vector2(0.85, 0.45), Vector2(-0.72, 0.45)], centre, size, tint, width)
	_head(canvas, centre, size, tint, width, Vector2(-0.85, 0.45), Vector2.LEFT)


## Arcane Shield. A heraldic shield. There is no cleverer answer and no need for one.
static func _shield(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	_stroke(canvas, [
		Vector2(0.0, -0.92), Vector2(0.78, -0.58), Vector2(0.78, 0.16), Vector2(0.0, 0.94),
		Vector2(-0.78, 0.16), Vector2(-0.78, -0.58), Vector2(0.0, -0.92),
	], centre, size, tint, width)


## Rewind. A clock with its hands set back, and a gap in the rim with the head pointing
## ANTICLOCKWISE - which is the only part of the drawing that says "back" rather than "time".
static func _clock(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	canvas.draw_arc(centre, 0.86 * size, deg_to_rad(-58.0), deg_to_rad(250.0), 32, tint,
		width, true)
	var start := Vector2(cos(deg_to_rad(-58.0)), sin(deg_to_rad(-58.0))) * 0.86
	_head(canvas, centre, size, tint, width, start,
		Vector2(-sin(deg_to_rad(-58.0)), cos(deg_to_rad(-58.0))))
	_stroke(canvas, [Vector2(0.0, 0.0), Vector2(0.0, -0.56)], centre, size, tint, width)
	_stroke(canvas, [Vector2(0.0, 0.0), Vector2(-0.44, 0.22)], centre, size, tint, width)


## Momentum. A wall on the left, three lines leaving it longer each time, and a head: the hit
## arrives and turns into speed. Deliberately not a chevron - Lunge already owns that.
static func _surge(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float) -> void:
	_stroke(canvas, [Vector2(-0.86, -0.7), Vector2(-0.86, 0.7)], centre, size, tint, width)
	var reach: Array = [0.10, 0.56, 0.10]
	for step in 3:
		var y := -0.52 + 0.52 * float(step)
		_stroke(canvas, [Vector2(-0.52, y), Vector2(float(reach[step]), y)],
			centre, size, tint, width)
	# On the END of the middle line, not floating past it. Drawn detached first, and it read as
	# a list icon rather than as something leaving.
	_head(canvas, centre, size, tint, width, Vector2(0.86, 0.0), Vector2.RIGHT)


# ---------------------------------------------------------------------------------------
# Unit-box helpers. Everything above speaks in -1..1; only these three know about pixels.
# ---------------------------------------------------------------------------------------

static func _stroke(canvas: CanvasItem, points: Array, centre: Vector2, size: float,
		tint: Color, width: float) -> void:
	canvas.draw_polyline(_scaled(points, centre, size), tint, width, true)


static func _fill(canvas: CanvasItem, points: Array, centre: Vector2, size: float,
		tint: Color) -> void:
	canvas.draw_colored_polygon(_scaled(points, centre, size), tint)


## A little filled triangle at `at`, pointing along `facing`. Both are in unit-box terms.
static func _head(canvas: CanvasItem, centre: Vector2, size: float, tint: Color,
		width: float, at: Vector2, facing: Vector2) -> void:
	if facing.length_squared() < 0.0001:
		return
	var forward := facing.normalized()
	var side := Vector2(-forward.y, forward.x)
	# Grown a little with the line width, so a head on a thick stroke does not look pinned to
	# the end of a bar that is wider than it is.
	var span := HEAD + width * 0.004
	_fill(canvas, [
		at, at - forward * span + side * span * 0.62,
		at - forward * span - side * span * 0.62,
	], centre, size, tint)


static func _scaled(points: Array, centre: Vector2, size: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(centre + (point as Vector2) * size)
	return out

"""Generate the small textures instead of asking a picture model for them.

    python tools/make_texture.py rock   assets/materials/rock.png
    python tools/make_texture.py bark   assets/materials/bark.png
    python tools/make_texture.py canopy assets/materials/canopy.png

The ground and the lava came from a generator and should have: they are every pixel of the
screen and they want a painter. The rock, the bark and the leaves do not. A boulder is about
thirty pixels tall in this game and a tree canopy about fifty, and at that size what a texture
has to do is break up a flat colour into facets and clumps - which is arithmetic, not art.

So these are made here, seamlessly, on demand, with a seed. That buys three things a
downloaded image does not have: they TILE exactly rather than nearly, they carry no baked
light at all rather than nearly none, and the palette is a literal in this file, so retinting
a rock to match a repainted board is a number rather than a new generation.

It is also the same call the rest of this project keeps making - the sounds are synthesised in
`audio/`, the spell icons are vector shapes in `vfx/spell_glyph.gd`, and the wizard is built
out of primitives in `wizard_rig.gd`.

Everything is checked by the same `check_texture.py` the generated ones went through. It has
no idea where an image came from, which is the point.

Stdlib only, like everything in this folder.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import png_reader  # noqa: E402


# ---------------------------------------------------------------------------------------
# Noise
#
# Both of these WRAP, which is the whole reason they are written out rather than taken from
# somewhere: a texture that does not tile is worse than no texture, because the repeat draws
# a grid across the ground and the eye finds a grid instantly.
# ---------------------------------------------------------------------------------------

def _lattice(fx: int, fy: int, seed: int) -> list:
	"""A wrapping lattice of random values, `fx` across and `fy` down."""
	rng = random.Random(seed)
	return [[rng.random() for _ in range(fx)] for _ in range(fy)]


def octaves(fx: int, fy: int, count: int, seed: int) -> list:
	"""`count` lattices, each twice as fine as the last, as (grid, fx, fy).

	THE FREQUENCY AND THE LATTICE SIZE ARE THE SAME NUMBER, and that is the whole reason this
	function exists rather than a scale multiplier inside `fbm`. Sampling an 18-wide sweep
	against an 8-wide lattice does not wrap - the right edge lands in the middle of a cell -
	and the texture gets a seam down it. This was not a theory: the first bark measured a
	13x seam left-to-right and a 67x seam top-to-bottom, and `check_texture.py` found it.

	Anisotropy is why they are two numbers. Bark is noise that varies eight times as fast
	across as it does down, and that stretch IS the ridges.
	"""
	out = []
	for i in range(count):
		w = fx * (2 ** i)
		h = fy * (2 ** i)
		out.append((_lattice(w, h, seed + i * 977), w, h))
	return out


def _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


def value_noise(u: float, v: float, grid: list, fx: int, fy: int) -> float:
	"""Bilinear value noise. `u` and `v` are 0..1 across the whole texture."""
	x = u * fx
	y = v * fy
	x0 = int(math.floor(x))
	y0 = int(math.floor(y))
	sx = _smooth(x - x0)
	sy = _smooth(y - y0)
	# The modulo is the wrap. Without it the last column interpolates toward nothing.
	a = grid[y0 % fy][x0 % fx]
	b = grid[y0 % fy][(x0 + 1) % fx]
	c = grid[(y0 + 1) % fy][x0 % fx]
	d = grid[(y0 + 1) % fy][(x0 + 1) % fx]
	top = a + (b - a) * sx
	bottom = c + (d - c) * sx
	return top + (bottom - top) * sy


def fbm(u: float, v: float, bands: list) -> float:
	"""Several octaves of value noise, each finer and quieter than the last."""
	total = 0.0
	amplitude = 1.0
	weight = 0.0
	for grid, fx, fy in bands:
		total += value_noise(u, v, grid, fx, fy) * amplitude
		weight += amplitude
		amplitude *= 0.5
	return total / max(weight, 0.0001)


def worley(px: float, py: float, points: list, cells: int) -> tuple:
	"""Nearest and second-nearest feature point, and which cell won.

	`px`/`py` are in cell units. The nine-neighbour sweep with a wrap is what makes the
	pattern seamless: a point just off the left edge is also just off the right one.

	`f2 - f1` is the distance to the boundary between two cells, which is the crack in a rock
	and the gap between two clumps of leaves. It is the whole reason this is here rather than
	more `fbm`.
	"""
	cx = int(math.floor(px))
	cy = int(math.floor(py))
	f1 = 9.9
	f2 = 9.9
	owner = 0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			gx = (cx + ox) % cells
			gy = (cy + oy) % cells
			jitter = points[gy][gx]
			fx = float(cx + ox) + jitter[0]
			fy = float(cy + oy) + jitter[1]
			d = math.sqrt((fx - px) ** 2 + (fy - py) ** 2)
			if d < f1:
				f2 = f1
				f1 = d
				owner = gy * cells + gx
			elif d < f2:
				f2 = d
	return f1, f2, owner


def _points(cells: int, seed: int) -> list:
	rng = random.Random(seed)
	return [[(rng.random(), rng.random()) for _ in range(cells)] for _ in range(cells)]


def _mix(a: tuple, b: tuple, t: float) -> tuple:
	t = min(max(t, 0.0), 1.0)
	return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _byte(v: float) -> int:
	return min(255, max(0, int(v + 0.5)))


# ---------------------------------------------------------------------------------------
# The three textures
#
# Each palette is stated as the colour the game uses for that material now, plus a lighter
# and a darker relative of it. Nothing goes near black: this project's one colour rule.
# ---------------------------------------------------------------------------------------

def rock(side: int, seed: int) -> bytes:
	"""Broad facets with darker cracks between them. A cool purple-grey stone."""
	cells = 6
	pts = _points(cells, seed)
	grain = octaves(16, 16, 3, seed)
	base = (90.0, 81.0, 113.0)
	light = (146.0, 138.0, 168.0)
	crack = (52.0, 46.0, 66.0)
	sand = (122.0, 108.0, 106.0)
	out = bytearray()
	for y in range(side):
		for x in range(side):
			u = x / float(side) * cells
			v = y / float(side) * cells
			f1, f2, owner = worley(u, v, pts, cells)
			# Every facet takes a value of its own, so the rock is made of PLATES rather than
			# of one lump with lines drawn on it.
			step = ((owner * 2654435761) % 1000) / 1000.0
			face = _mix(base, light, 0.15 + step * 0.55)
			if step > 0.82:
				face = _mix(face, sand, 0.5)
			# Fine grain, at a fraction of the strength of the facets.
			g = fbm(x / float(side), y / float(side), grain)
			face = _mix(face, light, (g - 0.5) * 0.30)
			# The crack. `f2 - f1` is zero exactly on a boundary, so this is a thin dark line.
			edge = min(1.0, (f2 - f1) * 5.0)
			face = _mix(crack, face, _smooth(edge))
			out += bytes((_byte(face[0]), _byte(face[1]), _byte(face[2]), 255))
	return bytes(out)


def bark(side: int, seed: int) -> bytes:
	"""Vertical ridges. Stretched noise, because bark is noise that only varies one way."""
	# Eighteen bands across, three down: bark is noise that only really varies one way.
	grids = octaves(18, 3, 4, seed)
	base = (90.0, 62.0, 47.0)
	ridge = (140.0, 105.0, 78.0)
	groove = (54.0, 38.0, 32.0)
	out = bytearray()
	for y in range(side):
		for x in range(side):
			n = fbm(x / float(side), y / float(side), grids)
			# Folded to put a sharp crease at every zero crossing, which is a groove.
			r = abs(n - 0.5) * 2.0
			colour = _mix(groove, base, _smooth(min(1.0, r * 1.6)))
			colour = _mix(colour, ridge, _smooth(max(0.0, r - 0.45) * 1.8))
			out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2]), 255))
	return bytes(out)


def canopy(side: int, seed: int) -> bytes:
	"""Leaves in clumps, not leaves individually. A deep green with brighter outer masses."""
	cells = 9
	pts = _points(cells, seed)
	grids = octaves(14, 14, 3, seed + 7)
	deep = (22.0, 61.0, 42.0)
	mid = (46.0, 96.0, 54.0)
	bright = (104.0, 148.0, 62.0)
	shade = (16.0, 44.0, 38.0)
	out = bytearray()
	for y in range(side):
		for x in range(side):
			u = x / float(side) * cells
			v = y / float(side) * cells
			f1, f2, owner = worley(u, v, pts, cells)
			# A clump is brightest at its middle and falls away to its edge, which is what
			# gives a flat ball of leaves the look of many rounded masses.
			dome = 1.0 - min(1.0, f1 * 1.5)
			step = ((owner * 40503) % 1000) / 1000.0
			colour = _mix(deep, mid, 0.25 + step * 0.5)
			colour = _mix(colour, bright, _smooth(dome) * (0.35 + step * 0.45))
			g = fbm(x / float(side), y / float(side), grids)
			colour = _mix(colour, bright, (g - 0.5) * 0.22)
			gap = min(1.0, (f2 - f1) * 4.0)
			colour = _mix(shade, colour, _smooth(gap))
			out += bytes((_byte(colour[0]), _byte(colour[1]), _byte(colour[2]), 255))
	return bytes(out)


MAKERS = {"rock": rock, "bark": bark, "canopy": canopy}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("kind", choices=sorted(MAKERS))
	parser.add_argument("destination")
	# 512, not 1024. A boulder is thirty pixels on screen and a canopy fifty; the second
	# thousand pixels of a rock texture is memory nobody can see.
	parser.add_argument("--size", type=int, default=512)
	parser.add_argument("--seed", type=int, default=7)
	args = parser.parse_args()

	pixels = MAKERS[args.kind](args.size, args.seed)
	png_reader.write_rgba(args.destination, args.size, args.size, pixels)
	print("%s  %d x %d  seed %d  ->  %s" % (
		args.kind, args.size, args.size, args.seed, args.destination))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

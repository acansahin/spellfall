"""Measure a generated texture against what docs/arena-art-prompt.md asked for.

    python tools/check_texture.py <image.png> [--preview out.png] [--expect r,g,b]

A generator will tell you a texture is seamless and hand you one that is not, and it will
paint a sun into something you asked to be flat. Both are invisible until the texture is on
the mesh and the mesh is in the scene, by which point it is not obvious that the ART is what
is wrong. Every check here is one of the five in that doc, done with a number instead of an
eye.

The one it cannot do is the first one - "is this a texture or a picture OF a texture" - which
needs looking at. `--preview` is the answer to the second: it writes the image tiled two by
two, which is the only way a seam ever shows itself.

Stdlib only, like everything in this folder.
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import png_reader  # noqa: E402


def luma(r: int, g: int, b: int) -> float:
	return 0.2126 * r + 0.7152 * g + 0.0722 * b


def sample_grid(img: png_reader.Png, step: int) -> list:
	"""Every `step`-th pixel, as (x, y, r, g, b). Full-resolution reads are slow in Python."""
	out = []
	for y in range(0, img.height, step):
		for x in range(0, img.width, step):
			r, g, b = img.rgb(x, y)
			out.append((x, y, r, g, b))
	return out


def seam_ratio(img: png_reader.Png) -> tuple:
	"""How much worse the wrap-around edge is than an ordinary neighbouring column/row.

	A seamless texture's last column continues into its first, so the difference across that
	wrap should be about the same as the difference between any two adjacent columns. A ratio
	near 1 tiles; 3 and up is a seam you will see on the ground.
	"""
	w, h = img.width, img.height

	def diff_columns(a: int, b: int) -> float:
		total = 0.0
		count = 0
		for y in range(0, h, 4):
			ra, ga, ba = img.rgb(a, y)
			rb, gb, bb = img.rgb(b, y)
			total += abs(ra - rb) + abs(ga - gb) + abs(ba - bb)
			count += 1
		return total / maxi(count)

	def diff_rows(a: int, b: int) -> float:
		total = 0.0
		count = 0
		for x in range(0, w, 4):
			ra, ga, ba = img.rgb(x, a)
			rb, gb, bb = img.rgb(x, b)
			total += abs(ra - rb) + abs(ga - gb) + abs(ba - bb)
			count += 1
		return total / maxi(count)

	# The wrap, against the median ordinary step measured at several places across the image.
	wrap_x = diff_columns(w - 1, 0)
	wrap_y = diff_rows(h - 1, 0)
	steps_x = sorted(diff_columns(i, i + 1) for i in range(w // 8, w - 2, max(w // 16, 1)))
	steps_y = sorted(diff_rows(i, i + 1) for i in range(h // 8, h - 2, max(h // 16, 1)))
	typical_x = steps_x[len(steps_x) // 2]
	typical_y = steps_y[len(steps_y) // 2]
	return (wrap_x / max(typical_x, 0.001), wrap_y / max(typical_y, 0.001),
		wrap_x, typical_x, wrap_y, typical_y)


def maxi(value: int) -> int:
	return value if value > 0 else 1


def light_gradient(pixels: list, width: int, height: int) -> tuple:
	"""Mean brightness of a 3x3 grid, and the strongest gradient across it.

	A texture with a sun baked in is brighter on one side. The number that matters is the
	spread between the brightest and darkest third, as a percentage of the mean: a flat
	painted texture sits in single digits, a lit one does not.
	"""
	cells = [[0.0, 0] for _ in range(9)]
	for x, y, r, g, b in pixels:
		col = min(2, x * 3 // width)
		row = min(2, y * 3 // height)
		cell = cells[row * 3 + col]
		cell[0] += luma(r, g, b)
		cell[1] += 1
	means = [c[0] / maxi(c[1]) for c in cells]
	overall = sum(means) / 9.0
	spread = (max(means) - min(means)) / max(overall, 0.001) * 100.0
	# Which way it leans, if it leans: left-right, top-bottom, and the two diagonals.
	lr = (means[2] + means[5] + means[8]) - (means[0] + means[3] + means[6])
	tb = (means[6] + means[7] + means[8]) - (means[0] + means[1] + means[2])
	return spread, means, lr / 3.0, tb / 3.0


def tone_stats(pixels: list) -> dict:
	lumas = sorted(luma(r, g, b) for _x, _y, r, g, b in pixels)
	n = len(lumas)
	mean_r = sum(p[2] for p in pixels) / n
	mean_g = sum(p[3] for p in pixels) / n
	mean_b = sum(p[4] for p in pixels) / n
	return {
		"min": lumas[0],
		"p01": lumas[n // 100],
		"median": lumas[n // 2],
		"p99": lumas[(n * 99) // 100],
		"max": lumas[-1],
		"mean_rgb": (mean_r, mean_g, mean_b),
		"under_16": 100.0 * sum(1 for v in lumas if v < 16.0) / n,
		"over_180": 100.0 * sum(1 for v in lumas if v > 180.0) / n,
	}


def write_seam_strip(img: png_reader.Png, path: str, band: int = 96) -> None:
	"""The wrap seam at FULL resolution, with the join down the middle of the image.

	The 2x2 preview is downscaled, so a one-pixel seam disappears into it - which is exactly
	the seam that then shows up as a faint grid on the ground. This crops the last `band`
	columns and the first `band` columns and butts them together, so if there is a line, it is
	the vertical line in the centre. The horizontal wrap is stacked underneath the same way.
	"""
	w, h = img.width, img.height
	band = min(band, w // 2, h // 2)
	rows = []
	for y in range(0, h, 2):  # every other row: the strip only has to be long enough to read
		row = []
		for x in range(w - band, w):
			row.append(img.rgb(x, y))
		for x in range(band):
			row.append(img.rgb(x, y))
		rows.append(row)
	for x in range(0, w, 2):
		pass
	# The top/bottom wrap, rotated into the same layout so one image answers both.
	lower = []
	for x in range(0, w, 2):
		col = []
		for y in range(h - band, h):
			col.append(img.rgb(x, y))
		for y in range(band):
			col.append(img.rgb(x, y))
		lower.append(col)
	width = band * 2
	height = len(rows) + len(lower)
	out = bytearray()
	for row in rows:
		for r, g, b in row:
			out += bytes((r, g, b, 255))
	for col in lower:
		for r, g, b in col:
			out += bytes((r, g, b, 255))
	png_reader.write_rgba(path, width, height, bytes(out))


def write_preview(img: png_reader.Png, path: str, side: int = 256) -> None:
	"""The image, box-downscaled and laid out two by two, so the seams sit in the middle."""
	step_x = img.width / float(side)
	step_y = img.height / float(side)
	small = []
	for y in range(side):
		row = []
		for x in range(side):
			row.append(img.rgb(int(x * step_x), int(y * step_y)))
		small.append(row)
	out = bytearray()
	for y in range(side * 2):
		row = small[y % side]
		for x in range(side * 2):
			r, g, b = row[x % side]
			out += bytes((r, g, b, 255))
	png_reader.write_rgba(path, side * 2, side * 2, bytes(out))


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("image")
	parser.add_argument("--preview", default="")
	parser.add_argument("--seam-strip", default="", dest="seam_strip")
	parser.add_argument("--expect", default="", help="the colour the game uses now, as r,g,b")
	parser.add_argument("--step", type=int, default=3, help="sample every Nth pixel")
	args = parser.parse_args()

	img = png_reader.Png(args.image)
	print("%s" % os.path.basename(args.image))
	square = "square" if img.width == img.height else "NOT SQUARE"
	pot = "power of two" if img.width and (img.width & (img.width - 1)) == 0 else "not a power of two"
	print("  size            %d x %d  (%s, %s, %d channels)" % (
		img.width, img.height, square, pot, img.channels))

	# --- 2. does it tile? ------------------------------------------------------------------
	rx, ry, wrap_x, step_x, wrap_y, step_y = seam_ratio(img)
	verdict_x = "tiles" if rx < 2.0 else ("marginal" if rx < 3.0 else "SEAM")
	verdict_y = "tiles" if ry < 2.0 else ("marginal" if ry < 3.0 else "SEAM")
	print("  seam left/right %.2fx an ordinary column  (%.1f vs %.1f)   %s" % (
		rx, wrap_x, step_x, verdict_x))
	print("  seam top/bottom %.2fx an ordinary row     (%.1f vs %.1f)   %s" % (
		ry, wrap_y, step_y, verdict_y))

	pixels = sample_grid(img, args.step)

	# --- 3. is there a sun in it? ----------------------------------------------------------
	spread, means, lr, tb = light_gradient(pixels, img.width, img.height)
	lit = "flat" if spread < 12.0 else ("slight lean" if spread < 20.0 else "LIT FROM ONE SIDE")
	print("  brightness spread %.1f%% across a 3x3 grid   %s" % (spread, lit))
	print("      lean: %+.1f left-to-right, %+.1f top-to-bottom (of 255)" % (lr, tb))

	# --- 4. is anything black? and 5. what is the palette? ---------------------------------
	tone = tone_stats(pixels)
	black = "no black" if tone["p01"] >= 16.0 else "NEAR-BLACK PRESENT"
	print("  luma            min %.0f  p01 %.0f  median %.0f  p99 %.0f  max %.0f   %s" % (
		tone["min"], tone["p01"], tone["median"], tone["p99"], tone["max"], black))
	print("  %.2f%% of pixels under luma 16, %.2f%% over 180 (bright/molten)" % (
		tone["under_16"], tone["over_180"]))
	r, g, b = tone["mean_rgb"]
	print("  mean colour     (%.0f, %.0f, %.0f)" % (r, g, b))
	if args.expect:
		want = [float(v) for v in args.expect.split(",")]
		gap = ((r - want[0]) ** 2 + (g - want[1]) ** 2 + (b - want[2]) ** 2) ** 0.5
		near = "on palette" if gap < 45.0 else ("close" if gap < 80.0 else "OFF PALETTE")
		print("  against (%.0f, %.0f, %.0f): distance %.0f   %s" % (
			want[0], want[1], want[2], gap, near))

	if args.seam_strip:
		write_seam_strip(img, args.seam_strip)
		print("  seam strip      %s  (the join is the vertical line down the centre;"
			" the lower half is the top/bottom wrap)" % args.seam_strip)
	if args.preview:
		write_preview(img, args.preview)
		print("  preview         %s  (tiled 2x2 - look at the two seams down the middle)" % (
			args.preview))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

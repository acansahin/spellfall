"""Bring a generated texture into the game at a size the GPU likes.

    python tools/fit_texture.py <in.png> <out.png> [--size 1024]

Generators return whatever size they feel like - 1254 square, in the first pair this repo
received - and that is not wrong so much as wasteful: a power of two mipmaps down to a clean
chain and costs less memory, which matters on the phones this game is for.

The downscale is an AREA AVERAGE, not a nearest-neighbour pick. Sampling one pixel out of
every block is what makes hand-painted art sparkle at distance, and sparkle reads to a player
as "low resolution" - the opposite of what shrinking it is for. The ground here is seen at a
55 degree slant across the whole screen, which is the worst case for it.

Stdlib only, like everything in this folder.
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import png_reader  # noqa: E402


def area_downscale(img: png_reader.Png, side: int) -> bytes:
	"""Box-filter to `side` x `side`, averaging every source pixel that lands in each cell."""
	sx = img.width / float(side)
	sy = img.height / float(side)
	out = bytearray()
	for y in range(side):
		y0 = int(y * sy)
		y1 = max(y0 + 1, int((y + 1) * sy))
		for x in range(side):
			x0 = int(x * sx)
			x1 = max(x0 + 1, int((x + 1) * sx))
			r = g = b = 0
			n = 0
			for yy in range(y0, min(y1, img.height)):
				for xx in range(x0, min(x1, img.width)):
					pr, pg, pb = img.rgb(xx, yy)
					r += pr
					g += pg
					b += pb
					n += 1
			n = n if n else 1
			out += bytes((r // n, g // n, b // n, 255))
	return bytes(out)


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("source")
	parser.add_argument("destination")
	parser.add_argument("--size", type=int, default=1024)
	args = parser.parse_args()

	img = png_reader.Png(args.source)
	if img.width != img.height:
		print("warning: %dx%d is not square; the result will be stretched" % (
			img.width, img.height), file=sys.stderr)
	pixels = area_downscale(img, args.size)
	png_reader.write_rgba(args.destination, args.size, args.size, pixels)
	print("%d x %d  ->  %d x %d   %s" % (
		img.width, img.height, args.size, args.size, args.destination))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

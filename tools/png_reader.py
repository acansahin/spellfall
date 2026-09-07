"""Minimal PNG read/write: enough for the sprite tools, with no third-party dependency.

The repo already reads Warcraft III archives with nothing but the standard library, and the
art pipeline holds the same line: a PNG is a few chunks around a zlib stream, and decoding
one is shorter than the argument for adding Pillow to a hobby project's toolchain.
"""
import struct
import zlib


class Png:
    def __init__(self, path):
        blob = open(path, "rb").read()
        assert blob[:8] == b"\x89PNG\r\n\x1a\n", "not a png"
        pos = 8
        idat = b""
        self.width = self.height = 0
        self.depth = self.colour = 0
        while pos < len(blob):
            length, kind = struct.unpack_from(">I4s", blob, pos)
            data = blob[pos + 8: pos + 8 + length]
            if kind == b"IHDR":
                (self.width, self.height, self.depth, self.colour,
                 _comp, _filt, _inter) = struct.unpack(">IIBBBBB", data)
            elif kind == b"IDAT":
                idat += data
            elif kind == b"IEND":
                break
            pos += 12 + length
        assert self.depth == 8, f"depth {self.depth} unsupported"
        channels = {0: 1, 2: 3, 4: 2, 6: 4}[self.colour]
        raw = zlib.decompress(idat)
        stride = self.width * channels
        out = bytearray(stride * self.height)
        prev = bytearray(stride)
        pos = 0
        for y in range(self.height):
            filt = raw[pos]
            pos += 1
            line = bytearray(raw[pos:pos + stride])
            pos += stride
            if filt == 1:
                for i in range(channels, stride):
                    line[i] = (line[i] + line[i - channels]) & 0xFF
            elif filt == 2:
                for i in range(stride):
                    line[i] = (line[i] + prev[i]) & 0xFF
            elif filt == 3:
                for i in range(stride):
                    left = line[i - channels] if i >= channels else 0
                    line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
            elif filt == 4:
                for i in range(stride):
                    a = line[i - channels] if i >= channels else 0
                    b = prev[i]
                    c = prev[i - channels] if i >= channels else 0
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                    line[i] = (line[i] + pred) & 0xFF
            out[y * stride:(y + 1) * stride] = line
            prev = line
        self.channels = channels
        self.pixels = bytes(out)

    def rgb(self, x, y):
        i = (y * self.width + x) * self.channels
        return self.pixels[i], self.pixels[i + 1], self.pixels[i + 2]


    def rgba(self, x, y):
        """(r, g, b, a); alpha is 255 on files that have no alpha channel."""
        i = (y * self.width + x) * self.channels
        px = self.pixels
        if self.channels == 4:
            return px[i], px[i + 1], px[i + 2], px[i + 3]
        return px[i], px[i + 1], px[i + 2], 255


def write_rgba(path, width, height, pixels):
    """Write 8-bit RGBA `pixels` (a bytes-like of width*height*4) as a PNG."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter: none. The images are small and zlib does the work.
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(kind, payload):
        return (struct.pack(">I", len(payload)) + kind + payload
                + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    signature = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    blob = (signature + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(blob)

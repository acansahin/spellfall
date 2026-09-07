"""Read a Warcraft III map archive, including the encrypted ones.

Stdlib only, on purpose: this repo has no third-party dependency and adding one to read a
2011 map file would be a poor trade. The MPQ format is small enough to write out.

WHY THIS FILE EXISTS AT ALL, given that the sibling tower-defense repo already has
`tools/extract_w3x.py`: that reader raises "key recovery is not implemented" on every file in
`Warlock097.w3x`, because every file in that map is encrypted. The message is misleading -
key *recovery* is only needed when the file's NAME is unknown. For a known name the key is
just `_hash(basename, 3)`, and the rest is bookkeeping:

  * flag 0x00020000 (FIX_KEY) adjusts it to `(key + block_offset) ^ file_size`
  * the sector-offset table is decrypted at `key - 1`
  * sector *i* is decrypted at `key + i`

That is roughly forty lines, it was written once in an earlier session, it was written to a
scratchpad instead of a repo, and it was gone by the next session. Hence: here, committed.

The object-data parsers below carry the other trap. `.w3a` (abilities) and `.w3u` (units) are
NOT the same layout: an ability modification carries two extra ints - the level/variation and
a data pointer - before its value, and a unit modification does not. Reading one with the
other's parser yields garbage that looks like data rather than raising.
"""

from __future__ import annotations

import bz2
import re
import struct
import zlib

FLAG_ENCRYPTED = 0x00010000
FLAG_FIX_KEY = 0x00020000
FLAG_COMPRESSED = 0x00000200

KNOWN_FILES = [
	"(listfile)", "(attributes)",
	"war3map.w3e", "war3map.w3i", "war3map.wts", "war3map.w3u", "war3map.w3t",
	"war3map.w3a", "war3map.w3b", "war3map.w3d", "war3map.w3q", "war3map.w3h",
	"war3map.doo", "war3map.shd", "war3map.wpm", "war3map.mmp", "war3mapMap.blp",
	"war3map.j", "scripts\\war3map.j",
]


class ArchiveError(Exception):
	pass


def _crypt_table() -> dict[int, int]:
	"""The fixed table MPQ uses for both hashing and encryption."""
	table: dict[int, int] = {}
	seed = 0x00100001
	for i in range(0x100):
		for j in range(5):
			seed = (seed * 125 + 3) % 0x2AAAAB
			high = (seed & 0xFFFF) << 0x10
			seed = (seed * 125 + 3) % 0x2AAAAB
			table[i + j * 0x100] = high | (seed & 0xFFFF)
	return table


_CT = _crypt_table()


def _hash(text: str, kind: int) -> int:
	"""MPQ string hash. `kind` picks which of the four hashes to compute.

	kind 1 and 2 locate a file in the hash table; kind 3 is the file's encryption key.
	"""
	seed1, seed2 = 0x7FED7FED, 0xEEEEEEEE
	for char in text.upper().replace("/", "\\"):
		value = ord(char)
		seed1 = _CT[(kind * 0x100) + value] ^ ((seed1 + seed2) & 0xFFFFFFFF)
		seed2 = (value + seed1 + seed2 + (seed2 << 5) + 3) & 0xFFFFFFFF
	return seed1


def _decrypt(data: bytes, key: int) -> bytes:
	"""Decrypt whole 4-byte words. Any tail shorter than a word is handled by the caller."""
	seed = 0xEEEEEEEE
	out = bytearray()
	for offset in range(0, len(data) - 3, 4):
		seed = (seed + _CT[0x400 + (key & 0xFF)]) & 0xFFFFFFFF
		value = struct.unpack_from("<I", data, offset)[0] ^ ((key + seed) & 0xFFFFFFFF)
		key = ((((~key) << 0x15) + 0x11111111) | (key >> 0x0B)) & 0xFFFFFFFF
		seed = (value + seed + (seed << 5) + 3) & 0xFFFFFFFF
		out += struct.pack("<I", value)
	return bytes(out)


class Archive:
	"""Minimal read-only MPQ reader, enough for a Warcraft III map."""

	def __init__(self, path: str) -> None:
		with open(path, "rb") as handle:
			self.raw = handle.read()
		self.path = path
		self.map_name = ""
		if self.raw[:4] == b"HM3W":
			end = self.raw.index(b"\0", 8)
			self.map_name = self.raw[8:end].decode("utf-8", "replace")
		self.base = self._find_header()
		(_, _, _, sector_shift, hash_off, block_off,
			hash_count, self.block_count) = struct.unpack_from(
				"<IIHHIIII", self.raw, self.base + 4)
		self.sector_size = 512 << sector_shift
		self.hash_table = _decrypt(
			self.raw[self.base + hash_off: self.base + hash_off + hash_count * 16],
			_hash("(hash table)", 3))
		self.block_table = _decrypt(
			self.raw[self.base + block_off: self.base + block_off + self.block_count * 16],
			_hash("(block table)", 3))
		self.index: dict[tuple[int, int], int] = {}
		for i in range(hash_count):
			name_a, name_b, _locale, block = struct.unpack_from(
				"<IIII", self.hash_table, i * 16)
			if block < 0xFFFFFFFE:
				self.index[(name_a, name_b)] = block

	def _find_header(self) -> int:
		for offset in range(0, len(self.raw), 512):
			if self.raw[offset:offset + 4] == b"MPQ\x1a":
				return offset
		raise ArchiveError(f"{self.path}: no MPQ header found")

	def has(self, name: str) -> bool:
		return (_hash(name, 1), _hash(name, 2)) in self.index

	def _block(self, name: str) -> tuple[int, int, int, int]:
		key = (_hash(name, 1), _hash(name, 2))
		if key not in self.index:
			raise ArchiveError(f"{self.path}: {name} not in archive")
		return struct.unpack_from("<IIII", self.block_table, self.index[key] * 16)

	def read(self, name: str) -> bytes:
		pos, _csize, fsize, flags = self._block(name)
		key = 0
		if flags & FLAG_ENCRYPTED:
			# The key comes from the BASENAME, never the full path inside the archive.
			key = _hash(name.split("\\")[-1], 3)
			if flags & FLAG_FIX_KEY:
				key = ((key + pos) ^ fsize) & 0xFFFFFFFF
		start = self.base + pos
		if not flags & FLAG_COMPRESSED:
			data = self.raw[start:start + fsize]
			return _decrypt(data, key) if flags & FLAG_ENCRYPTED else data
		sectors = (fsize + self.sector_size - 1) // self.sector_size
		table_raw = self.raw[start:start + (sectors + 1) * 4]
		if flags & FLAG_ENCRYPTED:
			table_raw = _decrypt(table_raw, (key - 1) & 0xFFFFFFFF)
		table = struct.unpack_from(f"<{sectors + 1}I", table_raw, 0)
		out = bytearray()
		for i in range(sectors):
			chunk = self.raw[start + table[i]: start + table[i + 1]]
			if flags & FLAG_ENCRYPTED:
				decoded = _decrypt(chunk, (key + i) & 0xFFFFFFFF)
				# _decrypt drops a tail shorter than a word; MPQ leaves such a tail in clear.
				chunk = decoded + chunk[len(decoded):]
			expected = min(self.sector_size, fsize - i * self.sector_size)
			# A sector that did not shrink is stored raw, with no method byte.
			if len(chunk) >= expected:
				out += chunk[:expected]
				continue
			method, payload = chunk[0], chunk[1:]
			if method == 0x02:
				out += zlib.decompress(payload)
			elif method == 0x10:
				out += bz2.decompress(payload)
			else:
				raise ArchiveError(f"{name}: unsupported compression 0x{method:02x}")
		return bytes(out)

	def files(self) -> list[tuple[str, int, int]]:
		"""(name, compressed, uncompressed) for every name we can guess."""
		found = []
		for name in KNOWN_FILES:
			if not self.has(name):
				continue
			_pos, csize, fsize, _flags = self._block(name)
			found.append((name, csize, fsize))
		return found


def parse_wts(text: str) -> dict[int, str]:
	"""war3map.wts - the table every TRIGSTR_nnn reference points into."""
	strings: dict[int, str] = {}
	for match in re.finditer(r"STRING\s+(\d+)[^{]*\{", text):
		start = match.end()
		end = text.index("}", start)
		strings[int(match.group(1))] = text[start:end].strip()
	return strings


def parse_object_data(buf: bytes, has_level: bool) -> list[tuple[bytes, bytes, dict]]:
	"""Parse a .w3a / .w3u / .w3t object-data table.

	`has_level` is the whole trap. Abilities, upgrades and doodads carry a level/variation
	int and a data-pointer int before each value; units, items and destructibles do not.
	Guessing wrong reads plausible-looking garbage rather than raising, so the caller states
	it and this never sniffs.
	"""
	off = 0
	_version = struct.unpack_from("<I", buf, off)[0]
	off += 4
	records: list[tuple[bytes, bytes, dict]] = []
	for _table in range(2):  # original objects, then custom ones
		count = struct.unpack_from("<I", buf, off)[0]
		off += 4
		for _ in range(count):
			original, new = buf[off:off + 4], buf[off + 4:off + 8]
			off += 8
			mod_count = struct.unpack_from("<I", buf, off)[0]
			off += 4
			mods: dict[bytes, dict[int, object]] = {}
			for _ in range(mod_count):
				field = buf[off:off + 4]
				off += 4
				if has_level:
					kind, level, _pointer = struct.unpack_from("<III", buf, off)
					off += 12
				else:
					kind = struct.unpack_from("<I", buf, off)[0]
					off += 4
					level = 0
				if kind == 0:
					value = struct.unpack_from("<i", buf, off)[0]
					off += 4
				elif kind in (1, 2):
					value = struct.unpack_from("<f", buf, off)[0]
					off += 4
				elif kind == 3:
					end = buf.index(b"\0", off)
					value = buf[off:end].decode("utf-8", "replace")
					off = end + 1
				else:
					raise ArchiveError(f"unknown value type {kind} at offset {off}")
				off += 4  # the end-of-modification marker, always the object's own id
				mods.setdefault(field, {})[level] = value
			records.append((original, new, mods))
	return records


def strip_colour(text: str) -> str:
	"""Drop Warcraft III's inline colour codes and line breaks from a tooltip."""
	text = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(text))
	text = re.sub(r"\|n", " ", text)
	return re.sub(r"\s+", " ", text).strip()

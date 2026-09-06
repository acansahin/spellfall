"""Print the reference map's own numbers, so a balance argument has a source.

    python tools/warlock_dump.py files       # what is in the archive
    python tools/warlock_dump.py units       # the wizard: HP, speed, collision
    python tools/warlock_dump.py abilities   # 22 spells: hotkey, cooldowns, tooltip
    python tools/warlock_dump.py hits        # every damage/push call site in the script
    python tools/warlock_dump.py speeds      # every per-second constant in the script
    python tools/warlock_dump.py metres      # the whole lot converted at 128 units / metre

`--map <path>` overrides the default location. `--units-per-metre N` overrides 128.

WHY `hits` AND `speeds` EXIST. The map's script is obfuscated - every identifier is two
scrambled letters and the newlines are stripped - so it cannot be read like source. But the
two things this port needs from it survive obfuscation completely:

  * `WW(caster, victim, damage, push_mult)` and `SW(...)` are the map's only two hit
    functions, and their call sites carry each spell's real damage expression and push
    multiplier in the clear.
  * The script integrates at a 0.03 s tick, so every speed in it is written `N*.03`. Grepping
    that literal harvests every projectile speed, dash speed and walk speed in the map.

Neither is a guess about what the code means; both are the arguments the code passes.
"""

from __future__ import annotations

import argparse
import collections
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import w3x  # noqa: E402

DEFAULT_MAP = os.path.join(
	os.path.expanduser("~"), "OneDrive", "Desktop", "Warcraft III", "Maps", "Download",
	"Warlock097.w3x")

SCRIPT = "scripts\\war3map.j"

# The tick the map's own physics runs at. Every speed in the script is a per-tick value
# written as `<units per second>*.03`, which is what makes `speeds` possible.
TICK = 0.03

UNIT_FIELDS = {
	b"unam": "name", b"uhpm": "hp", b"umvs": "speed", b"uhpr": "regen",
	b"ucol": "collision", b"usca": "scale", b"usid": "sight", b"udef": "armour",
}


def load(path: str) -> tuple[w3x.Archive, dict[int, str]]:
	archive = w3x.Archive(path)
	strings = w3x.parse_wts(archive.read("war3map.wts").decode("utf-8", "replace"))
	return archive, strings


def resolve(value, strings: dict[int, str]) -> str:
	"""A tooltip is stored as TRIGSTR_nnn pointing into war3map.wts."""
	if isinstance(value, str) and value.startswith("TRIGSTR_"):
		return strings.get(int(value[8:]), value)
	return str(value)


def _number(token: str) -> int:
	"""JASS writes an integer in decimal or as $HEX."""
	return int(token[1:], 16) if token.startswith("$") else int(token)


def cmd_files(archive: w3x.Archive, _strings, _args) -> None:
	print(f"map name: {archive.map_name}")
	print(f"{'file':30} {'packed':>9} {'raw':>9}")
	for name, packed, raw in archive.files():
		print(f"{name:30} {packed:>9} {raw:>9}")


def cmd_units(archive: w3x.Archive, strings, _args) -> None:
	records = w3x.parse_object_data(archive.read("war3map.w3u"), has_level=False)
	for _original, new, mods in records:
		row = {UNIT_FIELDS[key]: list(value.values())[0]
			for key, value in mods.items() if key in UNIT_FIELDS}
		if not row:
			continue
		name = w3x.strip_colour(resolve(row.pop("name", ""), strings))
		body = "  ".join(f"{key}={value}" for key, value in sorted(row.items()))
		print(f"{new.decode('utf-8', 'replace'):6} {name:26} {body}")


def cmd_abilities(archive: w3x.Archive, strings, _args) -> None:
	records = w3x.parse_object_data(archive.read("war3map.w3a"), has_level=True)
	for _original, new, mods in records:
		name = w3x.strip_colour(resolve(list(mods.get(b"anam", {}).values() or [""])[0], strings))
		if not name:
			continue
		hotkey = list(mods.get(b"ahky", {}).values() or [""])[0]
		cooldowns = mods.get(b"acdn", {})
		first = cooldowns.get(1, cooldowns.get(min(cooldowns), "")) if cooldowns else ""
		levels = len(cooldowns)
		tip = w3x.strip_colour(resolve(list(mods.get(b"aub1", {}).values() or [""])[0], strings))
		print(f"{new.decode('utf-8', 'replace'):6} {name:22} hotkey={hotkey or '-':2} "
			f"cd={first if first == '' else round(float(first), 2)} levels={levels}")
		if tip:
			print(f"       {tip}")


def cmd_hits(archive: w3x.Archive, _strings, _args) -> None:
	"""Every `WW(` / `SW(` call: the map's only two ways to damage and push a wizard.

	`WW` pushes the victim along caster -> victim. `SW` pushes them along the PROJECTILE's
	own travel. The third argument is the damage, the fourth the push multiplier.
	"""
	script = archive.read(SCRIPT).decode("utf-8", "replace")
	print("call WW(caster, victim, DAMAGE, PUSH)   push along caster->victim")
	print("call SW(caster, victim, DAMAGE, PUSH)   push along the projectile's travel")
	print()
	for match in re.finditer(r"call (WW|SW)\(", script):
		# The arguments nest, so walk to the matching bracket rather than splitting on ",".
		start = match.end()
		depth, index = 1, start
		while depth and index < len(script):
			if script[index] == "(":
				depth += 1
			elif script[index] == ")":
				depth -= 1
			index += 1
		print(f"  {match.group(1)}({script[start:index - 1]})")


def cmd_speeds(archive: w3x.Archive, _strings, args) -> None:
	"""Every `N*.03` in the script: a units-per-second speed, converted to metres."""
	script = archive.read(SCRIPT).decode("utf-8", "replace")
	counts = collections.Counter(
		match.group(1) for match in re.finditer(r"(\$?[0-9A-Fa-f]+)\*\.03", script))
	print(f"{'literal':>10} {'units/s':>9} {'m/s':>8} {'uses':>5}")
	rows = []
	for token, uses in counts.items():
		try:
			value = _number(token)
		except ValueError:
			continue  # `CB*.03` and friends: a named constant, not a literal
		rows.append((value, token, uses))
	for value, token, uses in sorted(rows):
		print(f"{token:>10} {value:>9} {value / args.units_per_metre:>8.2f} {uses:>5}")


def cmd_metres(archive: w3x.Archive, strings, args) -> None:
	"""The port's own conversion table. One scale, stated once, applied to everything."""
	per_metre = args.units_per_metre
	records = w3x.parse_object_data(archive.read("war3map.w3u"), has_level=False)
	hero = None
	for _original, _new, mods in records:
		name = w3x.strip_colour(resolve(list(mods.get(b"unam", {}).values() or [""])[0], strings))
		if name == "Warlock":
			hero = {UNIT_FIELDS[key]: list(value.values())[0]
				for key, value in mods.items() if key in UNIT_FIELDS}
			break
	if hero is None:
		raise SystemExit("no unit named Warlock in this map")

	speed = float(hero["speed"])
	print(f"scale: 1 metre = {per_metre} units  (one terrain cell)")
	print()
	print(f"  hero HP          {hero['hp']}")
	print(f"  hero regen       {hero.get('regen', 0)}")
	print(f"  walk speed       {speed:g} u/s   ->  {speed / per_metre:.3f} m/s")
	print(f"  obstacle radius  70 u        ->  {70 / per_metre:.3f} m")
	print()
	# The movement integrator, read off the script's own constants:
	#   IA = 210*.03  top speed per tick        AA = IA/20  acceleration per tick
	#   every tick, velocity *= .98             tick = 0.03 s
	top_per_tick = speed * TICK
	accel_per_tick = top_per_tick / 20.0
	accel_per_second = accel_per_tick / (TICK * TICK)
	drag_per_second = 0.98 ** (1.0 / TICK)
	print("movement, converted from the 0.03 s tick to per-second:")
	print(f"  top speed        {speed / per_metre:.3f} m/s")
	print(f"  acceleration     {accel_per_second / per_metre:.3f} m/s^2"
		f"   ({accel_per_second:.1f} u/s^2)")
	print(f"  drag             x{drag_per_second:.4f} per second   (0.98 per tick)")
	print(f"  time to top      {top_per_tick / accel_per_tick * TICK:.2f} s")
	print()
	# UW = (100 + damage_points) * damage * push * .03, added to a per-tick velocity.
	# Dividing out the tick leaves a plain per-second impulse.
	print("a hit, converted the same way:")
	print("  dv (u/s) = (100 + damage_points) * damage * push_mult")
	print(f"  dv (m/s) = (100 + damage_points) * damage * push_mult / {per_metre}")
	for points in (0, 50, 100, 150):
		impulse = (100.0 + points) * 7.0 * 1.0 / per_metre
		carry = impulse / -__import__("math").log(drag_per_second)
		print(f"    Fireball (7.0) at {points:>3} damage points: "
			f"{impulse:5.2f} m/s, carries {carry:5.2f} m")


COMMANDS = {
	"files": cmd_files,
	"units": cmd_units,
	"abilities": cmd_abilities,
	"hits": cmd_hits,
	"speeds": cmd_speeds,
	"metres": cmd_metres,
}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("command", choices=sorted(COMMANDS))
	parser.add_argument("--map", default=DEFAULT_MAP)
	parser.add_argument("--units-per-metre", type=float, default=128.0)
	args = parser.parse_args()
	if not os.path.exists(args.map):
		print(f"error: no map at {args.map}", file=sys.stderr)
		return 2
	archive, strings = load(args.map)
	COMMANDS[args.command](archive, strings, args)
	return 0


if __name__ == "__main__":
	raise SystemExit(main())

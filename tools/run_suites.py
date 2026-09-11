"""Run the test suites and tell the truth about which ones are flaky.

    python tools/run_suites.py                 # all of them
    python tools/run_suites.py knockback bot   # just these
    python tools/run_suites.py --retries 2

WHY THIS EXISTS. Running the suites as a shell loop produced a failure in a different suite on
three separate occasions - `--pc-test`, `--roster-test`, `--knockback-test` - and every one of
them passed three times out of three when re-run on the identical tree seconds later. Three
unrelated bugs would not behave like that. Something about running seventeen Godot windows
back to back is producing spurious failures, and until that is understood, **a batch result
cannot be read as a verdict**: a red line might be the code and might be the runner.

So this runs each suite, RE-RUNS any that fail, and reports the three outcomes as three
different things:

    PASS            passed first time
    FLAKY           failed, then passed - the runner, almost certainly, but see the log
    FAIL            failed every attempt - this one is real

A retry that silently swallowed the first failure would be worse than the shell loop it
replaces, because it would hide a genuine intermittent bug. The point is not to make the batch
green; it is to make "green" mean something again.

DO NOT EDIT THE TREE WHILE A BATCH IS RUNNING. Each suite is a fresh Godot process that parses
the project when it starts, so a `.gd`, `.tscn` or `.tres` saved halfway through a run is parsed
by every suite after it and by none before. That reports as `SCRIPT ERROR` against whichever
suites happened to start during the edit - which reads exactly like a real regression in code
those suites never touch. Cost a confused re-run once: `team` and `button` failed while
`loadout` and `roster`, run minutes earlier from the same batch, passed.

A `class_name` that is NEW to the project needs `Godot.exe --headless --path . --import` before
anything can refer to it. Without it the class is missing from
`.godot/global_script_class_cache.cfg` and every reference is a parse error - "Could not find
type X in the current scope" - which looks like a typo and is not one.

`--pc-test` is excluded from the default set and has to be asked for by name. It needs a REAL
WINDOW with focus and a real `Input.warp_mouse`, and it reliably loses that focus partway
through a long unattended run - which is the one flake here whose cause IS understood.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time

GODOT = r"C:\Program Files\Godot\Godot.exe.exe"

# Every suite that survives an unattended batch. `pc` is deliberately not here; see above.
SUITES = [
	"touch", "key", "cast", "twothumb", "knockback", "round", "bot", "spells",
	"loadout", "roster", "team", "button", "aim", "feel", "cover", "lava", "shrink",
]

PASS_LINE = re.compile(r"ALL PASS \((\d+) failure")
FAIL_LINE = re.compile(r"^\s*\[FAIL\]\s+(.*)$", re.MULTILINE)


def run_one(project: str, suite: str, frames: int) -> tuple:
	"""(passed, first failure line or '', seconds)."""
	started = time.time()
	proc = subprocess.run(
		[GODOT, "--path", project, "res://core/game/main.tscn",
			"--quit-after", str(frames), "--", "--%s-test" % suite],
		capture_output=True, text=True, errors="replace")
	took = time.time() - started
	out = proc.stdout + proc.stderr
	if "SCRIPT ERROR" in out or "Parse Error" in out:
		return False, "SCRIPT ERROR", took, out
	failures = FAIL_LINE.findall(out)
	if failures:
		return False, failures[0].strip(), took, out
	return bool(PASS_LINE.search(out)), "", took, out


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("suites", nargs="*", default=[])
	parser.add_argument("--project", default=os.getcwd())
	parser.add_argument("--frames", type=int, default=9000)
	parser.add_argument("--retries", type=int, default=1)
	parser.add_argument("--log", default="")
	args = parser.parse_args()

	wanted = args.suites if args.suites else SUITES
	log = open(args.log, "w", encoding="utf-8") if args.log else None
	results = []
	for suite in wanted:
		attempts = 0
		passed = False
		detail = ""
		spent = 0.0
		while attempts <= args.retries and not passed:
			passed, detail, took, out = run_one(args.project, suite, args.frames)
			spent += took
			attempts += 1
			if log is not None:
				log.write("########## --%s-test attempt %d\n%s\n" % (suite, attempts, out))
		if passed and attempts == 1:
			state = "PASS"
		elif passed:
			state = "FLAKY"
		else:
			state = "FAIL"
		results.append((suite, state, detail, spent))
		print("  %-10s %-6s %5.1fs  %s" % (suite, state, spent, detail))
		sys.stdout.flush()
	if log is not None:
		log.close()

	firm = sum(1 for _s, state, _d, _t in results if state == "PASS")
	flaky = [s for s, state, _d, _t in results if state == "FLAKY"]
	failed = [s for s, state, _d, _t in results if state == "FAIL"]
	print()
	print("%d of %d passed first time" % (firm, len(results)))
	if flaky:
		print("FLAKY (passed on a retry): %s" % ", ".join(flaky))
	if failed:
		print("FAILED: %s" % ", ".join(failed))
	return 1 if failed else 0


if __name__ == "__main__":
	raise SystemExit(main())

class_name SoundBank
extends Node

## Every sound in the game, synthesized at startup. There are no audio files.
##
## Not a purity exercise - it is what "placeholders until the game is fun" means for audio.
## A recorded thump commits to a feel before anybody knows what the hit should feel like,
## costs a licence or a session to replace, and lands in the repo as a binary nobody can
## diff. A tone with an envelope is four numbers: too soft, too long, wrong pitch, all fixed
## by editing a line. Real audio is a Phase 4 job, and it will replace calls to `play()`
## rather than anything that reads this file.
##
## It is also the only file that knows an AudioStreamPlayer exists. GameFeel asks for a name
## and never learns how the noise is made.
##
## Everything is mono, 22050Hz, 16-bit. At arena scale nobody can hear the difference and the
## whole bank builds in a few milliseconds.

## Samples per second. Low on purpose: these are thumps and beeps, not music.
const RATE := 22050

## How many sounds may overlap. A busy moment is a cast, a hit and a fall inside 200ms, and
## six leaves room for the round to end on top of that. Past this the oldest is stolen, which
## is the right failure - a dropped tail nobody notices beats a missing hit.
const VOICES := 6

## Softens every sample. Synthesized tones are loud in a way recordings are not, and this is
## the one knob that moves all of them together.
@export_range(0.0, 1.0, 0.01) var master := 0.55

var _bank: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	_build()
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		# Keep playing while the tree is paused: hitstop does not pause the tree, but a
		# future pause menu will, and a sound cut off by opening a menu sounds like a bug.
		player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(player)
		_voices.append(player)


## Plays a sound by name. Unknown names are ignored rather than fatal - a feel call for a
## sound nobody has written yet should not take the game down.
##
## `pitch_spread` randomises the pitch a little either way. Fireball fires every 0.9s and the
## identical sample nine times in a row is what makes a game sound cheap; a few percent of
## drift is enough to stop the ear noticing the repeat.
func play(id: StringName, pitch_spread: float = 0.06, volume_db: float = 0.0) -> void:
	var stream: AudioStreamWAV = _bank.get(id)
	if stream == null:
		return
	var player := _voices[_next]
	_next = (_next + 1) % _voices.size()
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_spread, pitch_spread)
	player.volume_db = volume_db
	player.play()


## True if `id` is in the bank. For the harness.
func has(id: StringName) -> bool:
	return _bank.has(id)


## How many voices are sounding right now. For the harness.
func playing_count() -> int:
	var n := 0
	for player in _voices:
		if player.playing:
			n += 1
	return n


func names() -> Array:
	return _bank.keys()


# ---------------------------------------------------------------------------------------
# The bank
#
# Each sound is one line of intent: what it is, how long, and what it does over that time.
# A sweep DOWN reads as weight (a thump, a fall); a sweep UP reads as effort (a cast, a
# countdown going somewhere). Noise is the crack on top - the part that says two things
# touched - and it is always shorter than the tone underneath it.
# ---------------------------------------------------------------------------------------

func _build() -> void:
	# A cast is effort with no impact: it rises and stops, because the interesting part has
	# not happened yet.
	_bank[&"cast"] = _wav(_mix([
		_sweep(0.13, 380.0, 780.0, 0.45, 7.0),
		_noise(0.05, 0.10, 20.0),
	]))
	# Blink is the same idea taken further and made airier - mostly noise, so it reads as
	# displacement rather than as a projectile leaving.
	_bank[&"blink"] = _wav(_mix([
		_sweep(0.20, 300.0, 1250.0, 0.22, 5.0),
		_noise(0.18, 0.22, 4.0),
	]))
	_bank[&"shield"] = _wav(_mix([
		_sweep(0.30, 520.0, 660.0, 0.30, 3.0),
		_sweep(0.30, 780.0, 990.0, 0.16, 3.0),
	]))
	# A hit is weight plus a crack. The tone falls; the noise is over in 50ms.
	_bank[&"hit"] = _wav(_mix([
		_sweep(0.20, 230.0, 95.0, 0.60, 9.0),
		_noise(0.06, 0.30, 22.0),
	]))
	# The same event, heavier: lower, longer, and it takes its time going away.
	_bank[&"heavy"] = _wav(_mix([
		_sweep(0.34, 170.0, 58.0, 0.75, 5.0),
		_noise(0.11, 0.34, 11.0),
	]))
	# Falling is the only long sound in the game. It has to last as long as the drop reads
	# for, or the wizard goes silent halfway down.
	_bank[&"fall"] = _wav(_mix([
		_sweep(0.55, 430.0, 70.0, 0.45, 2.2),
		_noise(0.55, 0.10, 2.0),
	]))
	# Countdown: three of these, then the one that is different.
	_bank[&"tick"] = _wav(_sweep(0.07, 660.0, 660.0, 0.35, 16.0))
	_bank[&"go"] = _wav(_mix([
		_sweep(0.18, 880.0, 1180.0, 0.40, 6.0),
		_noise(0.04, 0.10, 24.0),
	]))
	# Winning rises, losing falls. Nothing else about them differs, which is the whole
	# vocabulary a two-second banner needs.
	_bank[&"win"] = _wav(_chord([660.0, 880.0, 1320.0], 0.16, 0.34))
	_bank[&"lose"] = _wav(_chord([440.0, 330.0, 220.0], 0.16, 0.30))


# ---------------------------------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------------------------------

## A sine sweeping from `f0` to `f1` over `seconds`, under an exponential decay.
##
## The phase is integrated rather than computed as `sin(TAU * f(t) * t)`. That shortcut is
## the classic sweep bug: it makes the INSTANTANEOUS frequency race past f1 and the sound
## ends somewhere nobody asked for.
func _sweep(seconds: float, f0: float, f1: float, gain: float, decay: float) -> PackedFloat32Array:
	var count := maxi(int(seconds * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		var freq := lerpf(f0, f1, t)
		phase += TAU * freq / float(RATE)
		out[i] = sin(phase) * gain * _envelope(i, count, decay)
	return out


## Filtered white noise under the same envelope. The filter is a one-pole average, which is
## enough to take the hiss off and leave a crack.
func _noise(seconds: float, gain: float, decay: float) -> PackedFloat32Array:
	var count := maxi(int(seconds * RATE), 1)
	var out := PackedFloat32Array()
	out.resize(count)
	var last := 0.0
	for i in count:
		last = lerpf(last, randf_range(-1.0, 1.0), 0.55)
		out[i] = last * gain * _envelope(i, count, decay)
	return out


## Notes played one after another, each fading into the next. The chord name is a lie kept
## because it reads better than "arpeggio": they do not overlap.
func _chord(freqs: Array, note_seconds: float, gain: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for freq in freqs:
		out.append_array(_sweep(note_seconds, float(freq), float(freq), gain, 4.0))
	return out


## Fade in, then decay. The 2ms attack is not cosmetic: a waveform that starts at full
## amplitude begins with a step, and a step is a click on every speaker ever made.
func _envelope(index: int, count: int, decay: float) -> float:
	var attack := maxi(int(0.002 * RATE), 1)
	var rise := 1.0 if index >= attack else float(index) / float(attack)
	return rise * exp(-decay * float(index) / float(count))


## Sums several parts, longest wins. Clipped softly rather than hard - two loud parts landing
## on the same sample would otherwise square off and buzz.
func _mix(parts: Array) -> PackedFloat32Array:
	var longest := 0
	for part in parts:
		longest = maxi(longest, (part as PackedFloat32Array).size())
	var out := PackedFloat32Array()
	out.resize(longest)
	for part in parts:
		var samples: PackedFloat32Array = part
		for i in samples.size():
			out[i] = out[i] + samples[i]
	for i in out.size():
		out[i] = tanh(out[i])
	return out


## Packs float samples into a 16-bit mono stream.
func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i] * master, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	return stream

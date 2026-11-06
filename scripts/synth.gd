## Sounds made from scratch (v0.10.0), so they need no files: Thunderhorn's roars (three kinds), thunder cracks, the
## prize's trumpet stinger and maraca shakes (as in Jacob's 4X game's LoadingFiesta), and a sad trombone.
## Each returns an AudioStreamWAV (16-bit mono, 22 050 Hz); `play` plays one once on a throwaway player.
class_name Synth

const RATE := 22050


static func _wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size()
	return w


static func play(parent: Node, stream: AudioStream, volume_db := 0.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## A bull's roar from a storm: a low growl (a saw falling in pitch, roughened by noise) with a thunder rumble under it.
## kind 0: the entrance (long, rising then falling), 1: enraged (higher, harsher), 2: a short bellow, 3: the death
## (a long fall into a rumble).
static func roar(kind := 0) -> AudioStreamWAV:
	var dur: float = [2.4, 1.8, 1.0, 3.2, 4.4][kind]   # 4 (v0.11.0): the Storm Leap's long howl
	var base: float = [78.0, 105.0, 90.0, 70.0, 86.0][kind]
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + kind
	var ph := 0.0
	var lp := 0.0
	var rumble := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var bend := 1.0 + 0.35 * sin(minf(u * 2.2, 1.0) * PI) - (0.45 * u if kind == 3 else 0.0)
		if kind == 4:   # the howl: a rising cry that wavers, holds and breaks
			bend = 1.0 + 0.5 * sin(minf(u * 1.4, 1.0) * PI * 0.5) + 0.08 * sin(t * 9.0) - 0.3 * maxf(u - 0.8, 0.0) * 5.0
		ph += base * bend * (1.0 + 0.04 * sin(t * 37.0)) / RATE
		var saw := 2.0 * fposmod(ph, 1.0) - 1.0
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		rumble += (noise - rumble) * 0.015
		var env := minf(t / 0.12, 1.0) * clampf((dur - t) / 0.5, 0.0, 1.0)
		var grit := 0.35 if kind == 1 else 0.22
		d[i] = (saw * 0.55 + lp * grit * 3.0 + rumble * 4.0) * env * 0.7
	return _wav(d)


## v0.11.0 Thunderhorn's other sounds. kind: "snort" (a nasal blast of breath), "hoof" (a heavy hoof stamp: a thud
## and a click), "scrape" (a hoof raking gravel), "crackle" (sparse electric snaps), "charge" (a rising electric
## whine under crackle: the Storm Leap's charge-up), "whoosh" (air rushing past), "zap" (a static hit: a falling
## buzz), "slam" (a deep ground boom), "chirp" (an orb launching: a rising zip), "stun" (a static stun's long buzz),
## "pant" (three heavy breaths), "eat" (crunching an apple), "buzz" (a Static orb).
static func fx(kind: String) -> AudioStreamWAV:
	var dur: float = {"snort": 0.45, "hoof": 0.35, "scrape": 0.5, "crackle": 1.0, "charge": 1.6, "whoosh": 0.7,
		"zap": 0.25, "slam": 1.4, "chirp": 0.18, "stun": 0.9, "pant": 1.4, "eat": 0.35, "buzz": 0.6}.get(kind, 0.5)
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.2
		lp2 += (noise - lp2) * 0.03
		var v := 0.0
		match kind:
			"snort":   # breath through big nostrils: band noise, a quick swell and a rattle
				var env := minf(t / 0.03, 1.0) * exp(-t * 7.0)
				v = (lp - lp2) * 2.2 * env * (0.75 + 0.25 * sin(t * TAU * 38.0))
			"hoof":
				ph += (70.0 - 30.0 * u) / RATE
				v = sin(ph * TAU) * exp(-t * 16.0) * 1.1 + lp * exp(-t * 60.0) * 1.2 + lp2 * 3.0 * exp(-t * 9.0)
			"scrape":
				var grit := 1.0 if rng.randf() < 0.25 else 0.3
				v = (noise - lp) * grit * 0.7 * sin(u * PI) + lp2 * 2.0 * sin(u * PI)
			"crackle":
				v = (noise if rng.randf() < 0.012 else 0.0) * 1.2 + (noise - lp) * 0.08 * (0.5 + 0.5 * sin(t * 50.0))
			"charge":
				ph += (140.0 + 700.0 * u * u) / RATE
				var s := 2.0 * fposmod(ph, 1.0) - 1.0
				v = s * 0.25 * minf(u * 3.0, 1.0) + (noise if rng.randf() < 0.02 + 0.05 * u else 0.0) * 0.9 + lp2 * 2.0 * u
			"whoosh":
				var c := 0.04 + 0.3 * sin(u * PI)
				lp += (noise - lp) * c
				v = lp * 1.6 * sin(u * PI)
			"zap":
				ph += (900.0 - 700.0 * u) / RATE
				v = (1.0 if fposmod(ph, 1.0) < 0.5 else -1.0) * 0.35 * (1.0 - u) + noise * 0.3 * exp(-t * 25.0)
			"slam":
				ph += (48.0 - 18.0 * u) / RATE
				v = sin(ph * TAU) * exp(-t * 4.0) * 1.2 + noise * exp(-t * 30.0) + lp2 * 5.0 * exp(-t * 2.2)
			"chirp":
				ph += (500.0 + 2200.0 * u) / RATE
				v = sin(ph * TAU) * 0.45 * sin(u * PI) + noise * 0.15 * (1.0 - u)
			"stun":
				ph += 120.0 / RATE
				v = (2.0 * fposmod(ph, 1.0) - 1.0) * 0.3 * (1.0 - u) * (0.6 + 0.4 * sin(t * 60.0)) + (noise if rng.randf() < 0.03 else 0.0)
			"pant":
				var b := fposmod(t, 0.46) / 0.46
				v = (lp - lp2) * 1.8 * sin(b * PI) * (0.7 if b < 0.5 else 0.45)
			"buzz":   # v0.12.0 a Static orb: an angry electric buzz, wobbling, crackling
				ph += (95.0 + 12.0 * sin(t * TAU * 7.0)) / RATE
				var saw := 2.0 * fposmod(ph, 1.0) - 1.0
				v = saw * 0.32 * sin(u * PI) * (0.6 + 0.4 * sin(t * TAU * 31.0)) + (noise if rng.randf() < 0.04 else 0.0) * 0.6
			"eat":
				var bite := fposmod(t, 0.12)
				v = (noise - lp) * exp(-bite * 40.0) * 0.9
		d[i] = clampf(v, -1.0, 1.0)
	return _wav(d)


## A thunder crack: a sharp burst of noise, then a long rolling rumble.
static func thunder() -> AudioStreamWAV:
	var dur := 2.2
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.25
		lp2 += (noise - lp2) * 0.02
		var crack := noise * exp(-t * 18.0)
		var roll := lp2 * 5.0 * exp(-t * 1.6) * (0.7 + 0.3 * sin(t * 9.0))
		d[i] = clampf(crack * 0.9 + lp * 0.4 * exp(-t * 6.0) + roll, -1.0, 1.0)
	return _wav(d)


## The prize's blaring trumpet chord (D major, a sawtooth stack swelling in), as in the 4X game.
static func trumpet() -> AudioStreamWAV:
	var dur := 1.1
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var freqs := [293.66, 369.99, 440.0, 587.33]
	for i in n:
		var t := float(i) / RATE
		var env := minf(1.0, t / 0.03) * (maxf(0.0, 1.0 - (t - 0.8) / 0.3) if t > 0.8 else 1.0)
		var vib := 1.0 + 0.006 * sin(t * TAU * 6.0)
		var s := 0.0
		for f in freqs:
			s += 2.0 * fposmod(t * float(f) * vib, 1.0) - 1.0
		d[i] = clampf(s / freqs.size() * 1.6, -1.0, 1.0) * env
	return _wav(d)


## One bar of maraca shakes at the band's 165 bpm (eighths, accented on the beat); loops.
static func maracas() -> AudioStreamWAV:
	var beat := 60.0 / 165.0
	var n := int(RATE * beat * 4.0)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1824
	var lp := 0.0
	for k in 8:
		var start := int(k * beat * 0.5 * RATE)
		var accent := 1.0 if k % 2 == 0 else 0.6
		for i in int(0.07 * RATE):
			if start + i >= n:
				break
			var env := exp(-float(i) / (0.018 * RATE)) * accent
			var noise := rng.randf_range(-1.0, 1.0)
			lp += (noise - lp) * 0.55
			d[start + i] += (noise - lp) * env * 0.9
	return _wav(d, true)


## The sad trombone: four notes sliding down, the last one wobbling ("wah wah wah waaaah").
static func sad_trombone() -> AudioStreamWAV:
	var notes := [[233.08, 0.45], [220.0, 0.45], [207.65, 0.45], [196.0, 1.4]]
	var total := 0.0
	for nt in notes:
		total += float(nt[1])
	var n := int(RATE * total)
	var d := PackedFloat32Array()
	d.resize(n)
	var i0 := 0
	var ph := 0.0
	for k in notes.size():
		var f0: float = notes[k][0]
		var len := int(RATE * float(notes[k][1]))
		for i in len:
			var t := float(i) / RATE
			var f := f0 * (1.0 - 0.03 * t / float(notes[k][1]))
			if k == notes.size() - 1:
				f *= 1.0 + 0.025 * sin(t * TAU * 5.5) * minf(t * 2.0, 1.0)
			ph += f / RATE
			var x := fposmod(ph, 1.0)
			var tone := (2.0 * x - 1.0) * 0.6 + sin(ph * TAU) * 0.5   # brassy: a saw softened by a sine
			var env := minf(t / 0.04, 1.0) * clampf((float(notes[k][1]) - t) / 0.08, 0.0, 1.0)
			var wah := 0.55 + 0.45 * minf(t / 0.15, 1.0)
			if i0 + i < n:
				d[i0 + i] = tone * env * wah * 0.6
		i0 += len
	return _wav(d)

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


## bus (v0.12.9): "Effects" (default), "Music" or "Voice" (SoundSettings: their volumes are in the sound menu).
static func play(parent: Node, stream: AudioStream, volume_db := 0.0, bus := "Effects") -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
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
## "pant" (three heavy breaths), "eat" (crunching an apple), "buzz" (a Static orb), "heal" (v0.12.0: a heal-aura
## pulse's chime); v0.12.0 the horn beam: "beam_hum" (the orb charging: a rising whine with a swelling hum and
## quickening snaps), "beam" / "beam_long" (the beam firing, 1.6 s / 2.75 s: a crackling sustained roar with a slow
## warble, rising in the attack and dying away), "pop" (the orb collapsing).
static func fx(kind: String) -> AudioStreamWAV:
	var dur: float = {"snort": 0.45, "hoof": 0.35, "scrape": 0.5, "crackle": 1.0, "charge": 1.6, "whoosh": 0.7,
		"zap": 0.25, "slam": 1.4, "chirp": 0.18, "stun": 0.9, "pant": 1.4, "eat": 0.82, "buzz": 0.6, "heal": 0.55,
		"beam_hum": 1.05, "beam": 1.6, "beam_long": 2.75, "pop": 0.35, "clang": 0.6, "thock": 0.22}.get(kind, 0.5)
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
			"clang":   # v0.12.5 a blow blocked on a blade or staff: a bright metallic ring (inharmonic partials) on a hit
				v = (sin(t * TAU * 1180.0) * 0.32 + sin(t * TAU * 1730.0) * 0.22 + sin(t * TAU * 2610.0) * 0.14 + sin(t * TAU * 3920.0) * 0.08) \
					* exp(-t * 9.0) + noise * exp(-t * 90.0) * 0.9
			"thock":   # v0.12.5 a blow caught on fists, a bow or a slingshot: a dull, woody knock
				ph += (210.0 - 90.0 * u) / RATE
				v = sin(ph * TAU) * exp(-t * 28.0) * 1.0 + lp * exp(-t * 50.0) * 1.6
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
			"beam_hum":   # the orb charging: a whine rising an octave and more, a hum under it, snaps quickening
				ph += (180.0 + 520.0 * u * u) / RATE
				lp += (sin(ph * TAU * 0.5) - lp) * 0.05
				var whine := sin(ph * TAU) * 0.22 + (2.0 * fposmod(ph * 2.0, 1.0) - 1.0) * 0.06
				v = (whine + lp * 0.5) * minf(u * 2.5, 1.0) * (0.6 + 0.4 * u) * (0.85 + 0.15 * sin(t * TAU * (9.0 + 20.0 * u))) 					+ (noise if rng.randf() < 0.008 + 0.05 * u else 0.0) * 0.7
			"beam", "beam_long":   # a crackling sustained roar with a warble
				var env := minf(t / 0.05, 1.0) * minf((dur - t) / 0.35, 1.0)
				ph += (72.0 + 9.0 * sin(t * TAU * 3.1)) / RATE
				var growl := (2.0 * fposmod(ph, 1.0) - 1.0) * 0.3 + sin(ph * TAU * 2.0) * 0.15
				lp += (noise - lp) * 0.35
				var hiss := (noise - lp) * 0.25 * (0.7 + 0.3 * sin(t * TAU * 5.3))
				var snap := (noise if rng.randf() < 0.035 else 0.0) * 0.9
				v = (growl * (0.8 + 0.2 * sin(t * TAU * 11.0)) + hiss + lp2 * 2.5 + snap) * env
			"pop":
				ph += (900.0 * exp(-t * 18.0) + 60.0) / RATE
				v = sin(ph * TAU) * exp(-t * 14.0) * 0.8 + noise * exp(-t * 40.0) * 0.7
			"heal":   # v0.12.0 a heal-aura pulse: a soft shimmering chime (a major triad, rising, with tremolo)
				var env := minf(t / 0.04, 1.0) * exp(-t * 4.5)
				var trem := 0.75 + 0.25 * sin(t * TAU * 11.0)
				v = (sin(t * TAU * 523.0 * (1.0 + 0.03 * u)) + 0.7 * sin(t * TAU * 659.0) + 0.5 * sin(t * TAU * 784.0 * (1.0 + 0.03 * u))) * 0.22 * env * trem
			"eat":   # v0.12.9 a crisp bite into an apple, a wet juicy crackle, then two softer chews (was 3 harsh hisses)
				v = 0.0
				# [start, strength, how crisp] for the bite and the chews
				for b in [[0.0, 1.0, 1.0], [0.36, 0.45, 0.6], [0.58, 0.32, 0.5]]:
					var bt: float = t - float(b[0])
					if bt >= 0.0 and bt < 0.22:
						# crunch: a quick run of tiny cracks (sparse clicks of bright noise), thickest at the start
						var dens: float = 0.35 * float(b[2]) * exp(-bt * 14.0)
						var crack: float = (noise - lp) * (1.0 if rng.randf() < dens else 0.12)
						# the flesh giving way: a soft thud under it
						var thud: float = sin(bt * TAU * (180.0 - 300.0 * bt)) * exp(-bt * 45.0) * 0.5
						v += (crack * exp(-bt * 16.0) + thud) * float(b[1])
				# juice: a wet, bubbly squelch after the bite
				var jt := t - 0.07
				if jt > 0.0 and jt < 0.3:
					v += (lp - lp2) * 2.4 * sin(jt / 0.3 * PI) * (0.55 + 0.45 * sin(t * TAU * 37.0)) * 0.5
				v *= 0.8
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


## v0.12.3 the Duel Stone's corruption (Cutscene), made here like everything else:
##   "drone"   the corrupting drone: low detuned saws a tritone apart beating against each other, swelling, a sub-rumble
##             and a slow filter sweep, darkening as it goes (5 s);
##   "creak"   bone creaks as the dead claw up: stick-slip clicks speeding up and slowing in bursts over a low groan of
##             earth (1.6 s; played a few times, overlapping);
##   "whisper" the possessed whisper-chord: breathy noise through shifting vowel formants (many voices whispering) over
##             a dissonant chord (minor second and tritone sines) with a tremolo that quickens (3.4 s);
##   "snap"    every bone snapping straight at once as they freeze and turn (0.5 s);
##   "slam"    Thunderhorn's hooves meeting the stone: a stone crack with a deep boom (1.2 s).
static func corrupt(kind: String) -> AudioStreamWAV:
	var dur: float = {"drone": 5.0, "creak": 1.6, "whisper": 3.4, "snap": 0.5, "slam": 1.2}.get(kind, 1.0)
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("corrupt_" + kind)
	var lp := 0.0
	var lp2 := 0.0
	var bp := [0.0, 0.0, 0.0, 0.0]   # the whisper's formant filters (state-variable: low and band per voice)
	var ph := [0.0, 0.0, 0.0, 0.0, 0.0]
	var click_t := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.06
		lp2 += (noise - lp2) * 0.01
		var v := 0.0
		match kind:
			"drone":
				var env := minf(t / 0.8, 1.0) * clampf((dur - t) / 1.0, 0.0, 1.0)
				var f0 := 55.0 * (1.0 - 0.08 * u)
				var fs := [f0, f0 * 1.007, f0 * 1.414, f0 * 1.421, f0 * 0.5]
				var s := 0.0
				for k in fs.size():
					ph[k] += float(fs[k]) / RATE
					s += (2.0 * fposmod(ph[k], 1.0) - 1.0) * (0.6 if k == 4 else 0.3)
				var cut := 0.04 + 0.1 * (0.5 + 0.5 * sin(t * TAU * 0.35))   # a slow sweep of the filter
				bp[0] += (s - bp[0]) * cut
				v = (bp[0] * 0.8 + lp2 * 2.2) * env * (0.85 + 0.15 * sin(t * TAU * 1.3))
			"creak":
				var env := minf(t / 0.05, 1.0) * clampf((dur - t) / 0.3, 0.0, 1.0)
				var rate := 30.0 + 160.0 * (0.5 + 0.5 * sin(t * TAU * (1.1 + 0.4 * sin(t * 3.0))))   # stick-slip speeding up and slowing
				click_t += rate / RATE
				var click := 0.0
				if click_t >= 1.0:
					click_t -= 1.0
					click = 1.0
				ph[0] = ph[0] * 0.86 + click   # each click rings a little (a hollow, woody knock)
				ph[1] += (190.0 + 60.0 * sin(t * 7.0)) / RATE
				var knock: float = ph[0] * sin(ph[1] * TAU)
				ph[2] += (42.0 + 6.0 * sin(t * 2.0)) / RATE
				var groan := (2.0 * fposmod(ph[2], 1.0) - 1.0)
				bp[1] += (groan - bp[1]) * 0.03
				v = (knock * 0.5 + bp[1] * 0.9 + lp2 * 1.6) * env
			"whisper":
				var env := minf(t / 0.6, 1.0) * clampf((dur - t) / 0.8, 0.0, 1.0)
				var breath := noise - lp   # bright breath noise
				var w := 0.0
				for k in 3:   # three formants sliding between vowels at different speeds: a crowd of whispers
					var fc: float = float([600.0, 1200.0, 2600.0][k]) * (1.0 + 0.35 * sin(t * TAU * float([0.7, 1.3, 2.1][k]) + k))
					var f := 2.0 * sin(PI * fc / RATE)
					var lo: float = bp[k]
					var ba: float = ph[k + 2] if k < 3 else 0.0
					lo += f * ba
					var hi := breath - lo - 0.5 * ba
					ba += f * hi
					bp[k] = lo
					if k < 3:
						ph[k + 2] = ba
					w += ba * float([0.9, 0.6, 0.35][k])
				var trem := 0.6 + 0.4 * sin(t * TAU * (4.0 + 6.0 * u))
				ph[0] += 233.08 / RATE   # B flat, A natural and E: a minor second and a tritone
				ph[1] += 220.0 / RATE
				var e := sin(t * TAU * 329.63) * 0.5 + sin(t * TAU * 155.56) * 0.6
				var chord := (sin(ph[0] * TAU) + sin(ph[1] * TAU) + e) * 0.11 * trem
				v = (w * 0.55 * (0.7 + 0.3 * sin(t * TAU * 3.3)) + chord) * env
			"snap":
				var crack := noise * exp(-t * 60.0) * 1.2
				var crack2 := noise * exp(-maxf(t - 0.07, 0.0) * 70.0) * (1.0 if t > 0.07 else 0.0) * 0.8
				ph[0] += (120.0 - 60.0 * u) / RATE
				v = crack + crack2 + sin(ph[0] * TAU) * exp(-t * 12.0) * 0.6
			"slam":
				ph[0] += (40.0 - 14.0 * u) / RATE
				var boom := sin(ph[0] * TAU) * exp(-t * 3.0) * 1.3
				var crack := (noise - lp) * exp(-t * 25.0) * 1.2
				v = boom + crack + lp2 * 4.0 * exp(-t * 2.0)
		d[i] = clampf(v, -1.0, 1.0)
	return _wav(d)


## v0.12.2 a golem acknowledging an order: a short, gravelly "hrm" (a low buzzy tone through a moving low-pass, with
## a rasp of noise), pitched down for the titan. kind 0: an order taken, 1: a lower, longer "hrrmm" (attack).
static func grunt(kind := 0, titan := false) -> AudioStreamWAV:
	var dur := 0.32 if kind == 0 else 0.48
	var base := (92.0 if kind == 0 else 74.0) * (0.7 if titan else 1.0)
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + kind
	var ph := 0.0
	var lp := 0.0
	var f1 := 0.0
	for i in n:
		var t := float(i) / RATE
		var u := t / dur
		ph += base * (1.0 + 0.18 * sin(u * PI) - 0.12 * u) / RATE
		var buzz := 2.0 * fposmod(ph, 1.0) - 1.0
		f1 += (buzz - f1) * (0.08 + 0.05 * sin(u * PI * 2.0))
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.12
		var env := minf(t / 0.03, 1.0) * clampf((dur - t) / 0.12, 0.0, 1.0)
		d[i] = clampf((f1 * 1.6 + lp * 0.5 * (0.6 + 0.4 * sin(t * TAU * 23.0))) * env * 0.8, -1.0, 1.0)
	return _wav(d)


## v0.12.6 the prize fiesta's comic sounds (PrizeScreen's meme moments):
##   "airhorn"  three party air-horn blasts (BWAAA BWA BWAAAAA): a stack of detuned square-ish saws a fifth apart that
##              dip in pitch at each start (2.0 s);
##   "siren"    the "ay ay ay" siren: three wailing sweeps, each starting higher, with a little vibrato (2.0 s);
##   "whistle"  a slide whistle falling (the giant sombrero dropping) (1.0 s);
##   "boing"    a spring boing (the tortilla bouncing) (0.6 s);
##   "thwack"   a stick whacking the piñata: a hollow papery knock (0.25 s);
##   "pinata"   the piñata bursting: a papery crunch, a pop and a sparkly shower of little candy ticks (1.4 s);
##   "firework" a rocket whistling up and bursting into crackles (1.6 s);
##   "bonk"     the chancla landing: a rubbery slap with a cartoon "doink" (0.4 s);
##   "ting"     the ring catching the light: a bright little bell (inharmonic partials ringing out) (1.0 s).
static func fiesta(kind: String) -> AudioStreamWAV:
	var dur: float = {"airhorn": 2.0, "siren": 2.0, "whistle": 1.0, "boing": 0.6, "thwack": 0.25, "pinata": 1.4,
		"firework": 1.6, "bonk": 0.4, "ting": 1.0}.get(kind, 0.5)
	var n := int(RATE * dur)
	var d := PackedFloat32Array()
	d.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 165 + kind.length()
	var ph := [0.0, 0.0, 0.0, 0.0]
	var lp := 0.0
	var spark := 0.0
	var blasts := [[0.0, 0.42], [0.5, 0.22], [0.8, 1.15]]
	var horn := [415.0, 419.0, 622.0, 311.0]
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		var noise := rng.randf_range(-1.0, 1.0)
		match kind:
			"airhorn":
				for b in blasts:
					var tb := t - float(b[0])
					if tb >= 0.0 and tb < float(b[1]):
						var bend := 1.0 - 0.12 * exp(-tb * 30.0)
						var env := minf(tb / 0.012, 1.0) * clampf((float(b[1]) - tb) / 0.05, 0.0, 1.0)
						for k in horn.size():
							ph[k] += float(horn[k]) * bend / RATE
							var x: float = fposmod(ph[k], 1.0)
							s += ((1.0 if x < 0.45 else -1.0) * 0.5 + (2.0 * x - 1.0) * 0.5) * env * 0.3
			"siren":
				var seg := fmod(t, 0.66) / 0.66
				var k := floori(t / 0.66)
				var f := (330.0 + 90.0 * k) * (1.0 + 0.55 * sin(seg * PI * 0.85)) * (1.0 + 0.02 * sin(t * TAU * 7.0))
				ph[0] += f / RATE
				var env := minf(seg / 0.05, 1.0) * clampf((1.0 - seg) / 0.12, 0.0, 1.0)
				s = (sin(ph[0] * TAU) * 0.7 + (2.0 * fposmod(ph[0], 1.0) - 1.0) * 0.25) * env * 0.8
			"whistle":
				ph[0] += lerpf(1900.0, 380.0, pow(t / dur, 0.8)) / RATE
				s = (sin(ph[0] * TAU) + noise * 0.06) * minf(t / 0.03, 1.0) * clampf((dur - t) / 0.1, 0.0, 1.0) * 0.6
			"boing":
				ph[0] += (180.0 + 260.0 * exp(-t * 6.0) * (0.5 + 0.5 * cos(t * TAU * 11.0))) / RATE
				s = sin(ph[0] * TAU) * exp(-t * 4.5) * minf(t / 0.005, 1.0) * 0.8
			"thwack":
				lp += (noise - lp) * 0.25
				ph[0] += (220.0 * (1.0 - t * 1.5)) / RATE
				s = lp * 1.6 * exp(-t * 30.0) + sin(ph[0] * TAU) * 0.7 * exp(-t * 18.0)
			"pinata":
				lp += (noise - lp) * 0.3
				var crunch := lp * 1.8 * exp(-t * 9.0) * (0.6 + 0.4 * sin(t * TAU * 37.0))
				ph[0] += (140.0 * exp(-t * 8.0) + 50.0) / RATE
				var pop := sin(ph[0] * TAU) * exp(-t * 12.0)
				if t > 0.12 and rng.randf() < 0.012 * exp(-(t - 0.12) * 1.8):
					spark = maxf(spark, rng.randf_range(0.5, 1.0))
				spark *= 0.995
				s = crunch + pop + sin(t * TAU * (2200.0 + 600.0 * sin(t * 13.0))) * spark * 0.5 + (noise - lp) * spark * 0.4
			"firework":
				if t < 0.7:
					ph[0] += lerpf(900.0, 2600.0, t / 0.7) / RATE
					s = sin(ph[0] * TAU) * 0.25 * minf(t / 0.05, 1.0)
				else:
					var tb := t - 0.7
					lp += (noise - lp) * 0.06
					if rng.randf() < 0.02 * exp(-tb * 2.0):
						spark = 1.0
					spark *= 0.993
					s = lp * 4.0 * exp(-tb * 7.0) + noise * spark * 0.7
			"bonk":
				lp += (noise - lp) * 0.4
				ph[0] += (520.0 * exp(-t * 5.0) + 160.0) / RATE
				s = lp * 1.4 * exp(-t * 40.0) + sin(ph[0] * TAU) * exp(-t * 7.0) * 0.8
			"ting":
				s = (sin(t * TAU * 1760.0) * exp(-t * 4.0) + sin(t * TAU * 2794.0) * 0.5 * exp(-t * 6.0)
					+ sin(t * TAU * 4186.0) * 0.3 * exp(-t * 9.0)) * minf(t / 0.003, 1.0) * 0.5
		d[i] = clampf(s, -1.0, 1.0)
	return _wav(d)

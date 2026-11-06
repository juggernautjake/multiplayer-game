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
	var dur: float = [2.4, 1.8, 1.0, 3.2][kind]
	var base: float = [78.0, 105.0, 90.0, 70.0][kind]
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
		ph += base * bend * (1.0 + 0.04 * sin(t * 37.0)) / RATE
		var saw := 2.0 * fposmod(ph, 1.0) - 1.0
		var noise := rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		rumble += (noise - rumble) * 0.015
		var env := minf(t / 0.12, 1.0) * clampf((dur - t) / 0.5, 0.0, 1.0)
		var grit := 0.35 if kind == 1 else 0.22
		d[i] = (saw * 0.55 + lp * grit * 3.0 + rumble * 4.0) * env * 0.7
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

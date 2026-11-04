## Binary packing for the two hot messages (inputs and snapshots). Small packets, no Variant overhead:
## a 32-player snapshot is about 1.2 KB.
class_name Codec


## Inputs, newest last. The client sends its last few inputs in every packet (redundancy against packet loss).
static func encode_inputs(inputs: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(inputs.size())
	for i: Sim.PlayerInput in inputs:
		b.put_u32(i.seq)
		b.put_u8(i.buttons)
		b.put_float(i.yaw)
	return b.data_array


static func decode_inputs(data: PackedByteArray) -> Array:
	var out: Array = []
	if data.size() < 1:
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	if data.size() < 1 + n * 9:
		return out
	for k in n:
		var seq := b.get_u32()
		var btn := b.get_u8()
		var yaw := b.get_float()
		if is_finite(yaw):
			out.append(Sim.PlayerInput.new(seq, btn, yaw))
	return out


## ack: the last input sequence the server applied for the receiving client. ents: Array of [peer_id, PlayerState].
static func encode_snapshot(tick: int, ack: int, ents: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u32(ack)
	b.put_u16(ents.size())
	for e in ents:
		var s: Sim.PlayerState = e[1]
		b.put_u32(e[0])
		b.put_float(s.pos.x); b.put_float(s.pos.y); b.put_float(s.pos.z)
		b.put_float(s.vel.x); b.put_float(s.vel.y); b.put_float(s.vel.z)
		b.put_float(s.yaw)
		b.put_u8(1 if s.grounded else 0)
	return b.data_array


## -> { tick, ack, ents: { peer_id: PlayerState } }
static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var tick := b.get_u32()
	var ack := b.get_u32()
	var n := b.get_u16()
	var ents := {}
	for k in n:
		var id := b.get_u32()
		var s := Sim.PlayerState.new()
		s.pos = Vector3(b.get_float(), b.get_float(), b.get_float())
		s.vel = Vector3(b.get_float(), b.get_float(), b.get_float())
		s.yaw = b.get_float()
		s.grounded = b.get_u8() == 1
		ents[id] = s
	return { "tick": tick, "ack": ack, "ents": ents }

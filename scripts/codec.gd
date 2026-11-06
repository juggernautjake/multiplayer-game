## Binary packing for the two hot messages (inputs and snapshots). Small packets, no Variant overhead:
## an input is 38 bytes, a player in a snapshot 83 bytes (v0.11.0: stun as 16 bits, static and knock-down added; v0.12.0: 8 wand
## recharges).
class_name Codec


## Inputs, newest last. The client sends its last few inputs in every packet (redundancy against packet loss).
static func encode_inputs(inputs: Array) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_u8(inputs.size())
	for i: Sim.PlayerInput in inputs:
		b.put_u32(i.seq)
		b.put_u16(i.buttons)
		b.put_float(i.yaw)
		b.put_16(int(round(clampf(i.pitch, -1.6, 1.6) * 10000.0)))
		b.put_u8(i.weapon)
		b.put_u32(i.view_tick)
		b.put_float(i.aim_yaw)
		b.put_float(i.face_yaw)
		b.put_u8(i.spell)
		b.put_float(i.aim_point.x)
		b.put_float(i.aim_point.y)
		b.put_float(i.aim_point.z)
	return b.data_array


const INPUT_BYTES := 38
const RECHARGES := 8   # v0.12.0: the wand's eight spells (Sim.PlayerState.recharge)


static func decode_inputs(data: PackedByteArray) -> Array:
	var out: Array = []
	if data.size() < 1:
		return out
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	if data.size() < 1 + n * INPUT_BYTES:
		return out
	for k in n:
		var seq := b.get_u32()
		var btn := b.get_u16()
		var yaw := b.get_float()
		var pitch := b.get_16() / 10000.0
		var weapon := b.get_u8()
		var view := b.get_u32()
		var aim_yaw := b.get_float()
		var face_yaw := b.get_float()
		var spell := b.get_u8()
		var ap := Vector3(b.get_float(), b.get_float(), b.get_float())
		if is_finite(yaw) and is_finite(aim_yaw) and is_finite(face_yaw) and is_finite(ap.x) and is_finite(ap.y) and is_finite(ap.z):
			out.append(Sim.PlayerInput.new(seq, btn, yaw, pitch, weapon, view, aim_yaw, face_yaw, spell, ap))
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
		b.put_u8(s.dash_ticks)
		b.put_u8(s.dash_cd)
		b.put_u8(s.weapon)
		b.put_u8(s.atk)
		b.put_u8(s.atk_cd)
		b.put_u8(s.charge)
		b.put_u8(s.swing_n)
		b.put_u8(s.hp)
		b.put_u8(s.dead)
		b.put_u8(s.owned)
		b.put_u8(s.arrows)
		b.put_u8(s.rocks)
		b.put_u8(s.combo)
		b.put_u8(s.combo_t)
		b.put_u16(s.mana)
		b.put_u8(s.spell)
		b.put_u16(s.shield)
		b.put_u16(s.stun)
		for i in RECHARGES:
			b.put_u16(s.recharge[i])
		b.put_u8(s.slow)
		b.put_u8(s.staff_lvl)
		b.put_u8(s.wand_lvl)
		b.put_u16(s.zap)
		b.put_u8(s.zap_cd)
		b.put_u8(s.down)
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
		s.dash_ticks = b.get_u8()
		s.dash_cd = b.get_u8()
		s.weapon = b.get_u8()
		s.atk = b.get_u8()
		s.atk_cd = b.get_u8()
		s.charge = b.get_u8()
		s.swing_n = b.get_u8()
		s.hp = b.get_u8()
		s.dead = b.get_u8()
		s.owned = b.get_u8()
		s.arrows = b.get_u8()
		s.rocks = b.get_u8()
		s.combo = b.get_u8()
		s.combo_t = b.get_u8()
		s.mana = b.get_u16()
		s.spell = b.get_u8()
		s.shield = b.get_u16()
		s.stun = b.get_u16()
		for i in RECHARGES:
			s.recharge[i] = b.get_u16()
		s.slow = b.get_u8()
		s.staff_lvl = b.get_u8()
		s.wand_lvl = b.get_u8()
		s.zap = b.get_u16()
		s.zap_cd = b.get_u8()
		s.down = b.get_u8()
		ents[id] = s
	return { "tick": tick, "ack": ack, "ents": ents }

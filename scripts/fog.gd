## The wand's Fog (v0.12.0, level 2): a cloud about 25 x 25 m centred on the caster, lasting 10 s, thinning and
## drifting away over its last 2 s. The server keeps the list (Net.fogs) and tells everyone with the "fog" spell event;
## every client keeps the same records (FogView) and draws them by the same rules.
##
## Who sees what (all decided here, in pure static functions, so the rules are the same for the server's NPCs and
## golems and for every client, and can be tested headless):
##   - the caster and the caster's allies (anyone the caster can't hurt: other players with PvP off, the caster's
##     golems) see the fog faint and see-through, every ENEMY of the caster inside it as a vivid glowing outline, and
##     themselves outlined while they're in it;
##   - an ENEMY of the caster inside it is half blind: a screen-space fog closes in to 2-3 m (look_for gives NORMAL
##     only within NEAR of them), colours are washed out, the crosshair stays; it clears within CLEAR ticks of leaving
##     or as the cloud thins (impair());
##   - anyone else outside it sees thick layered smoke that hides every player, golem and challenger inside (their
##     names and health bars too), in both the 3D figure and the Pip views;
##   - NPC brains (challengers, minions, enemy golems) can't target anything hidden from them; inside the fog they
##     are confused (NpcAI / Golems: thrash or stumble), outside they steer round it (steer());
##   - clouds overlapping: from casters on the same side (allies: PvP off makes all players one side; golems are
##     their summoner's side) nothing changes: that side sees clearly through all of them, with enemy outlines, and
##     their enemies are blind in them as usual. Where an enemy caster's cloud overlaps a cloud from the other side
##     (overlap_at()), EVERYONE inside that overlap is blind, both sides, and there are no outlines there: none on
##     anyone standing in it, none seen from inside it. NPC brains and golems are lost in it likewise;
##   - Thunderhorn ignores it completely (he has no fog code at all).
## "Enemies" are worked out like Net.can_hurt: challengers and minions (ids from NPC_ID0) fight every player and never
## each other; two players only when both have PvP on. A golem counts as its summoner.
class_name Fog
extends RefCounted

const HALF := 12.5          # metres from the centre to each side: 25 x 25 m
const TOP := 7.0            # how high the cloud reaches above its centre
const DURATION := 600       # ticks (10 s)
const FADE := 120           # the last 2 s: thinning and drifting
const DRIFT := 1.5          # m/s it drifts while it thins
const NEAR := 2.5           # m: an enemy inside can still make out what's this close
const CLEAR := 30           # ticks for the blindness to clear after leaving (0.5 s)
const NPC_ID0 := 1000000    # ids from here on are challengers / minions (Net.next_npc)

enum Look { NORMAL, OUTLINED, HIDDEN }


## A fog record (Dictionary, so it can be sent as is): id, centre, caster, start tick, duration, fade, half size and
## the drift direction (worked out from the id: the same on every machine).
## v0.12.7: "lv", its caster's Fog mastery (II / III: poisonous, drawn with a green tinge and bubbles).
static func make(id: int, centre: Vector3, caster: int, t0: int, sp := {}) -> Dictionary:
	var a := float(id) * 2.399963
	return { "id": id, "c": Vector3(centre.x, centre.y, centre.z), "caster": caster, "t0": t0,
		"dur": int(sp.get("duration", DURATION)), "fade": int(sp.get("fade", FADE)),
		"half": float(sp.get("half", HALF)), "drift": Vector2(cos(a), sin(a)) * DRIFT, "lv": int(sp.get("lv", 1)) }


## The record as an event's arguments, and back.
static func to_args(f: Dictionary) -> Array:
	return [f.id, f.c, f.caster, f.t0, f.dur, f.fade, f.half, int(f.get("lv", 1))]


static func from_args(a: Array) -> Dictionary:
	return make(int(a[0]), a[1], int(a[2]), int(a[3]), { "duration": a[4], "fade": a[5], "half": a[6],
		"lv": int(a[7]) if a.size() > 7 else 1 })


static func ends(f: Dictionary) -> int:
	return int(f.t0) + int(f.dur)


static func alive(f: Dictionary, tick: float) -> bool:
	return tick < ends(f) and tick >= float(f.t0) - 1.0


## 1 while it's thick, falling to 0 over the last `fade` ticks.
static func density(f: Dictionary, tick: float) -> float:
	var left := float(ends(f)) - tick
	if left <= 0.0 or tick < float(f.t0) - 1.0:
		return 0.0
	return clampf(left / maxf(float(f.fade), 1.0), 0.0, 1.0)


## Where its centre is now (it drifts while thinning).
static func centre(f: Dictionary, tick: float) -> Vector3:
	var fading := maxf(tick - float(ends(f) - int(f.fade)), 0.0) * Config.DT
	var d: Vector2 = f.drift
	return (f.c as Vector3) + Vector3(d.x, 0, d.y) * fading


## Half its size now (it spreads a little as it thins).
static func half_now(f: Dictionary, tick: float) -> float:
	return float(f.half) * (1.0 + 0.15 * (1.0 - density(f, tick)))


## Is this point inside the cloud (thick enough to matter)?
static func covers(f: Dictionary, pos: Vector3, tick: float) -> bool:
	if density(f, tick) < 0.12:
		return false
	var c := centre(f, tick)
	var h := half_now(f, tick)
	return absf(pos.x - c.x) <= h and absf(pos.z - c.z) <= h and pos.y < c.y + TOP and pos.y > c.y - 3.0


## Enemies, like Net.can_hurt (a golem passes its summoner's id). pvp: id -> PvP on.
static func enemies(a: int, b: int, pvp: Dictionary) -> bool:
	if a == b or a == 0 or b == 0:
		return false
	var na := a >= NPC_ID0
	var nb := b >= NPC_ID0
	if na or nb:
		return not (na and nb)
	return bool(pvp.get(a, false)) and bool(pvp.get(b, false))


## On the caster's side: the caster, or anyone the caster can't hurt.
static func friend(f: Dictionary, who: int, pvp: Dictionary) -> bool:
	return who == int(f.caster) or not enemies(int(f.caster), who, pvp)


## Is this point inside clouds from casters on opposing sides (an opposing overlap: blind for everyone)?
static func overlap_at(pos: Vector3, fogs: Array, tick: float, pvp: Dictionary) -> bool:
	var casters := []
	for f: Dictionary in fogs:
		if covers(f, pos, tick) and not (int(f.caster) in casters):
			casters.append(int(f.caster))
	for i in casters.size():
		for j in range(i + 1, casters.size()):
			if enemies(casters[i], casters[j], pvp):
				return true
	return false


## How blind `viewer` (at pos) is: the thickest fog they're inside whose caster is their enemy (0..1); in an overlap
## of opposing casters' clouds, the thickest of those, whoever they are.
static func impair(viewer: int, pos: Vector3, fogs: Array, tick: float, pvp: Dictionary) -> float:
	var k := 0.0
	var over := overlap_at(pos, fogs, tick, pvp)
	for f: Dictionary in fogs:
		if (over or not friend(f, viewer, pvp)) and covers(f, pos, tick):
			k = maxf(k, density(f, tick))
	return k


## The whole view for one viewer: { impair: 0..1, see_through: [fog ids drawn faint for them], inside: [fog ids
## they're in] }. Fogs not in see_through are drawn as thick smoke.
static func view_for(viewer: int, pos: Vector3, fogs: Array, tick: float, pvp: Dictionary) -> Dictionary:
	var thru := []
	var inside := []
	for f: Dictionary in fogs:
		if not alive(f, tick):
			continue
		if friend(f, viewer, pvp):
			thru.append(f.id)
		if covers(f, pos, tick):
			inside.append(f.id)
	return { "impair": impair(viewer, pos, fogs, tick, pvp), "see_through": thru, "inside": inside }


## How `viewer` (at vpos) sees someone (`side`: a player's id, or a golem's summoner) standing at `pos`.
## is_self: the viewer looking at themselves.
static func look_for(viewer: int, vpos: Vector3, side: int, pos: Vector3, fogs: Array, tick: float, pvp: Dictionary,
		is_self := false) -> int:
	var look := Look.NORMAL
	var blind := impair(viewer, vpos, fogs, tick, pvp) > 0.0
	if is_self:   # yourself: outlined in a friendly cloud; blind (no outline) in an enemy's or an overlap
		if blind:
			return Look.NORMAL
	elif overlap_at(vpos, fogs, tick, pvp) or overlap_at(pos, fogs, tick, pvp):
		# an opposing overlap: no outlines into, out of or through it; anyone in a cloud is hidden unless right beside a
		# viewer who's in it too
		var in_fog := false
		for f: Dictionary in fogs:
			if covers(f, pos, tick):
				in_fog = true
		if not in_fog:
			return Look.NORMAL
		if blind and Vector2(pos.x - vpos.x, pos.z - vpos.z).length() <= NEAR:
			return Look.NORMAL
		return Look.HIDDEN
	for f: Dictionary in fogs:
		if not covers(f, pos, tick):
			continue
		if friend(f, viewer, pvp):
			if is_self or enemies(int(f.caster), side, pvp):
				look = maxi(look, Look.OUTLINED)
		elif is_self:
			continue   # an enemy of the caster inside it: their own screen is fogged (impair), not their body
		elif covers(f, vpos, tick) and Vector2(pos.x - vpos.x, pos.z - vpos.z).length() <= NEAR:
			continue   # blind in it, but this close they can make it out
		else:
			return Look.HIDDEN
	return look


## Can an NPC brain (or a golem) on side `viewer` at vpos target someone on `side` at pos? Not if they're hidden in
## a fog the viewer is an enemy of (NPCs don't get the NEAR exception: they're confused in there anyway).
static func can_see(viewer: int, vpos: Vector3, side: int, pos: Vector3, fogs: Array, tick: float, pvp: Dictionary) -> bool:
	if overlap_at(pos, fogs, tick, pvp):
		return false
	for f: Dictionary in fogs:
		if covers(f, pos, tick) and not friend(f, viewer, pvp):
			return false
	return true


## Is the viewer on side `viewer` lost inside an enemy fog (the NPCs' confusion)?
static func lost(viewer: int, pos: Vector3, fogs: Array, tick: float, pvp: Dictionary) -> bool:
	return impair(viewer, pos, fogs, tick, pvp) > 0.0


## Steering for a walker outside a fog it's an enemy of: the wanted direction, turned along the cloud's edge if it
## would carry it in within `margin` m (it goes round instead). Returns the direction (unit or zero).
static func steer(viewer: int, pos: Vector3, want: Vector2, fogs: Array, tick: float, pvp: Dictionary, margin := 2.0) -> Vector2:
	if want.length() < 0.01:
		return want
	var dir := want.normalized()
	for f: Dictionary in fogs:
		if friend(f, viewer, pvp) or density(f, tick) < 0.12:
			continue
		var c := centre(f, tick)
		var h := half_now(f, tick) + margin
		var rel := Vector2(pos.x - c.x, pos.z - c.z)
		if absf(rel.x) <= h - margin and absf(rel.y) <= h - margin:
			continue   # already inside: that's for the confusion to handle
		var ahead := rel + dir * 1.5
		if absf(ahead.x) > h or absf(ahead.y) > h:
			continue   # this step doesn't take it in
		# slide round the edge: along the face it would cross (a steady choice: a strafe's lean doesn't flip it, so
		# nobody dithers at the edge)
		var out := Vector2.ZERO
		if absf(rel.x) - h > absf(rel.y) - h:
			out = Vector2(signf(rel.x), 0)
		else:
			out = Vector2(0, signf(rel.y))
		var along := Vector2(-out.y, out.x)
		var lean := along.dot(dir)   # the way the wish clearly leans (round a corner it's already past)
		if absf(lean) < 0.6:         # heading at the face (a strafe's lean doesn't count): toward the nearer corner
			lean = along.dot(rel) if absf(along.dot(rel)) > 0.3 else 1.0
		if lean < 0.0:
			along = -along
		dir = (along + out * 0.35).normalized()
	return dir


## Drop the fogs that are over.
static func prune(fogs: Array, tick: float) -> Array:
	return fogs.filter(func(f): return tick < float(ends(f)))

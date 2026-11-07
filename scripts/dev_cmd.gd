## v0.12.6 (Jacob) the dev console's commands, run on the server (host-authoritative): grant weapons and levels to
## anyone, top everything out, spawn fighters (any weapon, tier, weapon level, side, size and name), change a unit's
## side or size, heal, god mode, kill, clear, teleport, rename, summon Thunderhorn. The host can always use them;
## guests only after the host types `cheats on`. `name <new name>` (your own name) works for everyone.
## Open the console with ` (the key left of 1). `help` lists everything; `help <command>` explains one.
##
## Targets (who a command is for): me, all, players, units (every spawned fighter), friendly / hostile / neutral,
## a name (or the start of one, any case; put names with spaces in "quotes"), or #id (from `list`).
class_name DevCmd

const WEAPON_WORDS := { "fists": Weapons.FISTS, "fist": Weapons.FISTS, "club": Weapons.CLUB, "sword": Weapons.SWORD,
	"bow": Weapons.BOW, "sling": Weapons.SLING, "slingshot": Weapons.SLING, "staff": Weapons.STAFF, "wand": Weapons.WAND }
const SIDE_WORDS := { "friendly": Net.Side.ALLY, "friend": Net.Side.ALLY, "ally": Net.Side.ALLY, "allies": Net.Side.ALLY,
	"hostile": Net.Side.HOSTILE, "enemy": Net.Side.HOSTILE, "foe": Net.Side.HOSTILE,
	"neutral": Net.Side.NEUTRAL, "neutrals": Net.Side.NEUTRAL }
const SIDE_COLORS := [Color("4fc85a"), Color("d23a2a"), Color("e3c02c")]
const SIZE_MIN := 0.3
const SIZE_MAX := 4.0
const MAX_SPAWN := 20

## name -> [usage, what it does]
const HELP := {
	"help": ["help [command]", "every command, or what one does"],
	"list": ["list", "everyone in the game with their #id, side, size, weapon and levels"],
	"give": ["give <weapon|all> [target]", "hand over a weapon (with full ammo for the bow and slingshot)"],
	"take": ["take <weapon|all> [target]", "take a weapon away (fists stay)"],
	"level": ["level <weapon|all|magic|arms> <1-4|max> [target]", "set weapon levels (staff/wand: spells; the rest: damage)"],
	"mastery": ["mastery <spell|staff|wand|all> <1-3|max> [target]", "set spell mastery (I-III; spell names may be partial: fire, tele)"],
	"max": ["max [target]", "top out EVERYTHING: every weapon, every level 4, every spell mastery III, full ammo, health and mana (also: maxall)"],
	"spawn": ["spawn <weapon|random|mix> [count] [tier 1-3] [friendly|neutral|hostile] [size N] [level 1-4] [smiguel] [name \"...\"]",
		"spawn fighters in front of you, e.g.  spawn sword 3 friendly tier 3 level 4 size 1.5"],
	"side": ["side <target> <friendly|neutral|hostile>", "change whose side units are on"],
	"size": ["size <target> <0.3-4>", "make someone bigger or smaller (their reach and hitbox too)"],
	"tier": ["tier <target> <1-3>", "how good a spawned fighter is (aim, dodging, reactions)"],
	"heal": ["heal [target]", "full health and mana, stuns and static cleared"],
	"god": ["god [target] [on|off]", "takes no damage (toggles)"],
	"kill": ["kill <target>", "knock them out"],
	"clear": ["clear [units|hostile|friendly|neutral]", "remove spawned fighters (all of them by default)"],
	"ammo": ["ammo [target]", "full arrows and stones"],
	"tp": ["tp <target>", "teleport to someone"],
	"bring": ["bring <target>", "teleport someone to you"],
	"name": ["name <new name>", "change your own name (anyone can)"],
	"rename": ["rename <target> <new name>", "rename someone or a unit"],
	"boss": ["boss", "summon Thunderhorn now"],
	"cheats": ["cheats <on|off>", "host only: let guests use these commands too"],
	"smiguel": ["smiguel [target]", "unlock Smiguel and play as him at once (also: unlock smiguel, skin smiguel)"],
	"unlock": ["unlock <smiguel|all> [target]", "unlock a character (as if they'd beaten Thunderhorn)"],
	"skin": ["skin <pip|smiguel> [target]", "play as a character you've unlocked (pip: back to normal)"],
	"peek": ["peek", "make Smiguel peek out from behind something near you now"],
}


## Run one line typed by `from`; -> the reply for their console.
static func run(net: Net, from: int, line: String) -> String:
	var a := tokens(line.strip_edges().trim_prefix("/"))
	if a.is_empty():
		return ""
	var cmd := str(a[0]).to_lower()
	a.remove_at(0)
	if cmd in ["maxall", "topall", "maxout"]:
		cmd = "max"
	if cmd == "name":
		return _name(net, from, " ".join(a))
	if cmd != "help" and from != 1 and not net.dev_cheats:
		return "Only the host can use dev commands (the host can type: cheats on)"
	if not net.players.has(from) and cmd not in ["help", "list", "boss", "cheats", "clear"]:
		return "You're not in the game"
	match cmd:
		"help":
			return _help(a)
		"list":
			return _list(net)
		"give", "take":
			return _give(net, from, a, cmd == "give")
		"level", "lvl":
			return _level(net, from, a)
		"mastery", "master":
			return _mastery(net, from, a)
		"max":
			return _max(net, from, a)
		"spawn":
			return _spawn(net, from, a)
		"side":
			return _side(net, from, a)
		"size":
			return _size(net, from, a)
		"tier":
			return _tier(net, from, a)
		"heal":
			return _each(net, from, a, "heal")
		"ammo":
			return _each(net, from, a, "ammo")
		"god":
			return _god(net, from, a)
		"kill":
			if a.is_empty():
				return "usage: " + HELP.kill[0]
			return _each(net, from, a, "kill")
		"clear":
			return _clear(net, a)
		"tp", "bring":
			return _tp(net, from, a, cmd == "bring")
		"rename":
			return _rename(net, from, a)
		"boss":
			if net.boss != null:
				return "Thunderhorn is already here"
			net.summon_boss()
			return "Thunderhorn is coming"
		"smiguel":
			var outs := []
			for q in targets(net, from, str(a[0]) if a.size() > 0 else ""):
				net.unlock(q, "smiguel")
				q.skin = "smiguel"
				outs.append(q.name)
			net._server_send_roster()
			net.save_progress()
			return "¡Smiguel! Unlocked and worn by: %s" % ", ".join(outs) if not outs.is_empty() else "No one by that name"
		"unlock":
			if a.is_empty():
				return "usage: " + HELP.unlock[0]
			var what := str(a[0]).to_lower()
			if what not in ["smiguel", "all"]:
				return "Characters: smiguel"
			var outs := []
			for q in targets(net, from, str(a[1]) if a.size() > 1 else ""):
				net.unlock(q, "smiguel")
				outs.append(q.name)
			return "Unlocked Smiguel for: %s (wear him: skin smiguel, or Esc > Character)" % ", ".join(outs)
		"skin", "character", "char":
			if a.is_empty():
				return "usage: " + HELP.skin[0]
			var what := str(a[0]).to_lower()
			what = "" if what in ["pip", "none", "normal", "default"] else what
			var outs := []
			for q in targets(net, from, str(a[1]) if a.size() > 1 else ""):
				if what != "" and not q.unlocks.has(what):
					if q.npc:
						q.unlocks.append(what)   # (a unit can wear him without beating anyone)
					else:
						return "%s hasn't unlocked %s (unlock %s first)" % [q.name, what, what]
				if what != "" and not (what in Net.CHARACTERS):
					return "Characters: pip, smiguel"
				q.skin = what
				outs.append(q.name)
			net._server_send_roster()
			net.save_progress()
			return "%s now: %s" % [", ".join(outs), "Smiguel" if what == "smiguel" else "Pip"]
		"peek":
			if net.smiguel == null:
				return "Smiguel isn't here"
			return net.smiguel.force_peek(net)
		"cheats":
			if from != 1:
				return "Only the host can turn cheats on or off"
			net.dev_cheats = a.size() > 0 and str(a[0]).to_lower() in ["on", "1", "true", "yes"]
			return "Guests can %s use dev commands" % ("now" if net.dev_cheats else "no longer")
	return "Unknown command '%s'. Type help for the list." % cmd


## Split a line into words; "double quotes" keep spaces together.
static func tokens(line: String) -> Array:
	var out := []
	var cur := ""
	var q := false
	for c in line:
		if c == "\"":
			q = not q
			if not q:
				out.append(cur)
				cur = ""
			continue
		if c == " " and not q:
			if cur != "":
				out.append(cur)
			cur = ""
			continue
		cur += c
	if cur != "":
		out.append(cur)
	return out


## Who a target word means. `from` is "me". -> Array of Net.ServerPlayer (empty: nobody matched).
static func targets(net: Net, from: int, word: String) -> Array:
	var w := word.to_lower()
	var out := []
	match w:
		"", "me", "self", "myself":
			return [net.players[from]] if net.players.has(from) else []
		"all", "everyone":
			return net.players.values()
		"players", "humans":
			return net.players.values().filter(func(p): return not p.npc)
		"units", "npcs", "npc", "spawned":
			return net.players.values().filter(func(p): return p.npc)
	if SIDE_WORDS.has(w):
		var s: int = SIDE_WORDS[w]
		return net.players.values().filter(func(p): return p.npc and Net.side_of(p) == s)
	if w.begins_with("#") and w.substr(1).is_valid_int():
		var id := int(w.substr(1))
		return [net.players[id]] if net.players.has(id) else []
	for p: Net.ServerPlayer in net.players.values():   # exact name first, then the start of a name, then anywhere in it
		if p.name.to_lower() == w:
			return [p]
	for p: Net.ServerPlayer in net.players.values():
		if p.name.to_lower().begins_with(w):
			out.append(p)
	if out.is_empty():
		for p: Net.ServerPlayer in net.players.values():
			if w in p.name.to_lower():
				out.append(p)
	return out


static func _who(net: Net, from: int, word: String) -> Array:
	return targets(net, from, word)


static func _names(ps: Array) -> String:
	var n := ps.map(func(p): return p.name)
	if n.size() > 4:
		return "%s and %d more" % [", ".join(n.slice(0, 4)), n.size() - 4]
	return ", ".join(n)


## Do `act` ("heal", "ammo", "kill") to every target in a[0] (me if none).
static func _each(net: Net, from: int, a: Array, act: String) -> String:
	var ps := _who(net, from, str(a[0]) if a.size() > 0 else "me")
	if ps.is_empty():
		return "Nobody matches '%s' (try list)" % (a[0] if a.size() > 0 else "me")
	var what := ""
	for p: Net.ServerPlayer in ps:
		match act:
			"heal":
				_heal(p)
				what = "healed"
			"ammo":
				p.state.arrows = Weapons.MAX_AMMO
				p.state.rocks = Weapons.MAX_AMMO
				what = "full ammo"
			"kill":
				what = _kill(p)
	net._server_send_roster()
	return "%s: %s" % [_names(ps), what]


static func _weapons(word: String) -> Array:
	var w := word.to_lower()
	if w in ["all", "everything", "weapons"]:
		return range(Weapons.DATA.size())
	if w in ["magic", "spells"]:
		return [Weapons.STAFF, Weapons.WAND]
	if w in ["arms", "physical", "melee+ranged", "others"]:
		return [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD, Weapons.BOW, Weapons.SLING]
	if w == "melee":
		return [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD]
	if w == "ranged":
		return [Weapons.BOW, Weapons.SLING]
	if WEAPON_WORDS.has(w):
		return [WEAPON_WORDS[w]]
	return []


static func _help(a: Array) -> String:
	if a.size() > 0 and HELP.has(str(a[0]).to_lower()):
		var h: Array = HELP[str(a[0]).to_lower()]
		if str(a[0]).to_lower() == "mastery":   # v0.12.7: what earns each spell's mastery, and what II / III do
			var lines := ["%s\n  %s" % [h[0], h[1]], "Each spell levels up I -> II -> III from what it achieves (never on practice dummies):"]
			for slot in Weapons.MASTERY_SLOTS:
				var ws := Weapons.slot_spell(slot)
				var sp := Weapons.spell(ws[0], ws[1])
				var need: Array = sp.get("mastery", [0, 0])
				lines.append("  %-13s %s: II at %d, III at %d" % [sp.name, sp.get("by", ""), need[0], need[1]])
				lines.append("  %-13s II: %s   III: %s" % ["", sp.get("m2", {}).get("text", ""), sp.get("m3", {}).get("text", "")])
			return "\n".join(lines)
		return "%s\n  %s" % [h[0], h[1]]
	var lines := ["Dev commands (` opens and closes this; Tab completes; Up/Down for history):"]
	for k in HELP.keys():
		lines.append("  %-58s %s" % [HELP[k][0], HELP[k][1]])
	lines.append("Targets: me, all, players, units, friendly, hostile, neutral, a name (or its start), \"a name with spaces\", #id")
	lines.append("Weapons: fists club sword bow sling staff wand, or all / magic / arms / melee / ranged")
	return "\n".join(lines)


static func _list(net: Net) -> String:
	var lines := ["#id        name                              side      size  hp   weapon     staff wand  fists club sword bow sling"]
	for p: Net.ServerPlayer in net.players.values():
		var lv := []
		for w in [Weapons.FISTS, Weapons.CLUB, Weapons.SWORD, Weapons.BOW, Weapons.SLING]:
			lv.append(str(Net.arm_level(p, w)))
		lines.append("#%-9d %-33s %-9s %-5s %-4d %-10s %-5d %-5d %s%s" % [p.id, p.name.left(33),
			("player" if not p.npc else Net.SIDE_NAMES[Net.side_of(p)]), str(snappedf(p.size, 0.01)), p.state.hp, Weapons.NAMES[p.state.weapon],
			p.state.staff_lvl, p.state.wand_lvl, "     ".join(lv), "  GOD" if p.god else ""])
	return "\n".join(lines)


static func _give(net: Net, from: int, a: Array, give: bool) -> String:
	if a.is_empty():
		return "usage: " + HELP["give" if give else "take"][0]
	var ws := _weapons(str(a[0]))
	if ws.is_empty():
		return "No weapon called '%s' (fists club sword bow sling staff wand, or all)" % a[0]
	var ps := _who(net, from, str(a[1]) if a.size() > 1 else "me")
	if ps.is_empty():
		return "Nobody matches '%s'" % a[1]
	for p: Net.ServerPlayer in ps:
		for w in ws:
			if give:
				p.state.owned |= 1 << w
			elif w != Weapons.FISTS:
				p.state.owned &= ~(1 << w)
				if p.state.weapon == w:
					p.state.weapon = Weapons.FISTS
		if give and (Weapons.BOW in ws or Weapons.SLING in ws):
			p.state.arrows = Weapons.MAX_AMMO
			p.state.rocks = Weapons.MAX_AMMO
		if give and ws.size() == 1:
			p.state.weapon = ws[0]
		if p.npc and give and ws.size() == 1 and p.ai != null:   # a unit fights with what it was given
			p.ai = NpcAI.new(p.id, p.ai.owner, ws[0], p.ai.difficulty)
	net._server_send_roster()
	return "%s %s %s" % ["Gave" if give else "Took", str(a[0]).to_lower(), ("to " if give else "from ") + _names(ps)]


## Set a weapon's level: the staff and wand by their level (and kills to match), the rest by their kill count.
static func set_level(p: Net.ServerPlayer, w: int, lv: int) -> void:
	lv = clampi(lv, 1, Weapons.MAX_LEVEL)
	var k: int = Weapons.LEVEL_KILLS[lv - 1]
	if w == Weapons.STAFF:
		p.state.staff_lvl = lv
		p.kills[0] = k
	elif w == Weapons.WAND:
		p.state.wand_lvl = lv
		p.kills[1] = k
	elif Weapons.is_arm(w):
		p.arms[w] = k


static func _level(net: Net, from: int, a: Array) -> String:
	if a.size() < 2:
		return "usage: " + HELP.level[0]
	var ws := _weapons(str(a[0]))
	if ws.is_empty():
		return "No weapon called '%s'" % a[0]
	var lw := str(a[1]).to_lower()
	var lv := Weapons.MAX_LEVEL if lw in ["max", "top", "ultimate"] else (1 if lw in ["min", "reset"] else int(lw))
	if lv < 1 or lv > Weapons.MAX_LEVEL:
		return "Levels go from 1 to %d" % Weapons.MAX_LEVEL
	var ps := _who(net, from, str(a[2]) if a.size() > 2 else "me")
	if ps.is_empty():
		return "Nobody matches '%s'" % a[2]
	for p: Net.ServerPlayer in ps:
		for w in ws:
			set_level(p, w, lv)
			p.state.owned |= 1 << w
		net._fx("level_up", [p.id, ws[0], lv, ""])
	net._server_send_roster()
	return "%s level %d for %s" % [str(a[0]).to_lower(), lv, _names(ps)]


## v0.12.7: the mastery slots a word means: all / spells, staff, wand, or a spell's name (any case; the start of it,
## or any part, like "fire" or "tele"). -> [] if none.
static func mastery_slots(word: String) -> Array:
	var w := word.to_lower()
	if w in ["all", "spells", "every", "everything", "magic"]:
		return range(Weapons.MASTERY_SLOTS)
	if w == "staff" or w == "wand":
		var weapon := Weapons.STAFF if w == "staff" else Weapons.WAND
		var out := []
		for i in (Weapons.get_data(weapon).spells as Array).size():
			out.append(Weapons.mastery_slot(weapon, i))
		return out
	var starts := []
	var inside := []
	for slot in Weapons.MASTERY_SLOTS:
		var ws := Weapons.slot_spell(slot)
		var nm := str(Weapons.spell(ws[0], ws[1]).name).to_lower()
		if nm == w or nm.replace(" ", "") == w:
			return [slot]
		if nm.begins_with(w):
			starts.append(slot)
		elif w in nm:
			inside.append(slot)
	return starts if not starts.is_empty() else inside


static func _mastery(net: Net, from: int, a: Array) -> String:
	if a.size() < 2:
		return "usage: " + HELP.mastery[0] + "   (help mastery: what earns it)"
	var slots := mastery_slots(str(a[0]))
	if slots.is_empty():
		return "No spell called '%s' (a spell's name or its start, staff, wand or all)" % a[0]
	var lw := str(a[1]).to_lower()
	var lv := 3 if lw in ["max", "top", "iii"] else (2 if lw == "ii" else (1 if lw in ["i", "min", "reset"] else int(lw)))
	if lv < 1 or lv > 3:
		return "Mastery goes from 1 to 3"
	var ps := _who(net, from, str(a[2]) if a.size() > 2 else "me")
	if ps.is_empty():
		return "Nobody matches '%s'" % a[2]
	for p: Net.ServerPlayer in ps:
		for s in slots:
			net.set_mastery(p, s, lv)
		if lv > 1:
			var ws := Weapons.slot_spell(slots[0])
			net._fx("mastery_up", [p.id, ws[0], ws[1], lv])
	net._server_send_roster()
	var what := str(Weapons.spell(Weapons.slot_spell(slots[0])[0], Weapons.slot_spell(slots[0])[1]).name) if slots.size() == 1 else str(a[0]).to_lower()
	return "%s mastery %s for %s" % [what, Weapons.MASTERY_ROMAN[lv - 1], _names(ps)]


static func _heal(p: Net.ServerPlayer) -> void:
	p.state.hp = Sim.MAX_HP
	p.state.mana = Sim.MANA_FULL
	p.state.stun = 0
	p.state.zap = 0
	p.state.slow = 0
	p.state.down = 0


static func _max(net: Net, from: int, a: Array) -> String:
	var ps := _who(net, from, str(a[0]) if a.size() > 0 else "me")
	if ps.is_empty():
		return "Nobody matches '%s'" % a[0]
	for p: Net.ServerPlayer in ps:
		p.state.owned = (1 << Weapons.DATA.size()) - 1
		for w in Weapons.DATA.size():
			set_level(p, w, Weapons.MAX_LEVEL)
		net.set_mastery(p, -1, 3)   # v0.12.7: every spell's mastery III too
		p.state.arrows = Weapons.MAX_AMMO
		p.state.rocks = Weapons.MAX_AMMO
		p.state.recharge = [0, 0, 0, 0, 0, 0, 0, 0]
		_heal(p)
		net._fx("level_up", [p.id, p.state.weapon, Weapons.MAX_LEVEL, ""])
	net._server_send_roster()
	return "Everything maxed (every weapon, every level 4, every spell mastery III, full ammo, health and mana) for %s" % _names(ps)


static func _god(net: Net, from: int, a: Array) -> String:
	var who := "me"
	var mode := ""
	for t in a:
		if str(t).to_lower() in ["on", "off"]:
			mode = str(t).to_lower()
		else:
			who = str(t)
	var ps := _who(net, from, who)
	if ps.is_empty():
		return "Nobody matches '%s'" % who
	for p: Net.ServerPlayer in ps:
		p.god = (mode == "on") if mode != "" else not p.god
		if p.god:
			_heal(p)
	net._server_send_roster()
	return "God mode %s: %s" % ["on" if ps[0].god else "off", _names(ps)]


static func _kill(p: Net.ServerPlayer) -> String:
	if p.state.dead > 0:
		return "already down"
	p.state.hp = 0
	p.state.dead = Sim.RESPAWN_TICKS
	p.state.shield = 0
	p.state.charge = 0
	return "knocked out"


static func _clear(net: Net, a: Array) -> String:
	var w := str(a[0]).to_lower() if a.size() > 0 else "units"
	var n := 0
	for p: Net.ServerPlayer in net.players.values().duplicate():
		if not p.npc or p.minion:
			continue
		if w in ["units", "all", "npcs"] or (SIDE_WORDS.has(w) and Net.side_of(p) == SIDE_WORDS[w]):
			net.golems.dissolve(p.id)
			net._fx("npc_leave", [p.id, p.state.pos])
			net.players.erase(p.id)
			n += 1
	net._server_send_roster()
	return "Cleared %d unit%s" % [n, "" if n == 1 else "s"]


static func _tp(net: Net, from: int, a: Array, bring: bool) -> String:
	if a.is_empty():
		return "usage: " + HELP["bring" if bring else "tp"][0]
	var ps := _who(net, from, str(a[0]))
	if ps.is_empty():
		return "Nobody matches '%s'" % a[0]
	var me: Net.ServerPlayer = net.players[from]
	if bring:
		var i := 0
		for p: Net.ServerPlayer in ps:
			if p.id == from:
				continue
			var ang := float(i) * 1.1
			p.state.pos = me.state.pos + Vector3(sin(ang) * 2.5, 0.2, cos(ang) * 2.5)
			p.state.vel = Vector3.ZERO
			i += 1
		return "Brought %s to you" % _names(ps)
	var t: Net.ServerPlayer = ps[0]
	me.state.pos = t.state.pos + Vector3(1.5, 0.3, 1.5)
	me.state.vel = Vector3.ZERO
	return "Teleported to %s" % t.name


static func _name(net: Net, from: int, nm: String) -> String:
	nm = nm.strip_edges().left(Config.MAX_NAME)
	if nm == "":
		return "usage: name <new name>"
	if not net.players.has(from):
		return "You're not in the game"
	net.players[from].name = nm
	net._server_send_roster()
	return "You're now called %s" % nm


static func _rename(net: Net, from: int, a: Array) -> String:
	if a.size() < 2:
		return "usage: " + HELP.rename[0]
	var ps := _who(net, from, str(a[0]))
	if ps.size() != 1:
		return "Nobody matches '%s'" % a[0] if ps.is_empty() else "That matches %d (%s): be more exact or use #id" % [ps.size(), _names(ps)]
	var nm := " ".join(a.slice(1)).strip_edges().left(Config.MAX_NAME if not ps[0].npc else 40)
	var old: String = ps[0].name
	ps[0].name = nm
	net._server_send_roster()
	return "%s is now %s" % [old, nm]


static func _side(net: Net, from: int, a: Array) -> String:
	if a.size() < 2 or not SIDE_WORDS.has(str(a[1]).to_lower()):
		return "usage: " + HELP.side[0]
	var ps := _who(net, from, str(a[0])).filter(func(p): return p.npc)
	if ps.is_empty():
		return "No spawned fighters match '%s' (players are always on the players' side)" % a[0]
	var s: int = SIDE_WORDS[str(a[1]).to_lower()]
	for p: Net.ServerPlayer in ps:
		p.side = s
		p.color = SIDE_COLORS[s]
		if s == Net.Side.ALLY and p.ai != null and not net.players.has(p.ai.owner):
			p.ai.owner = from
	net._server_send_roster()
	return "%s: now %s" % [_names(ps), Net.SIDE_NAMES[s]]


static func _size(net: Net, from: int, a: Array) -> String:
	if a.size() < 2 or not str(a[1]).is_valid_float():
		return "usage: " + HELP.size[0]
	var sz := clampf(float(a[1]), SIZE_MIN, SIZE_MAX)
	var ps := _who(net, from, str(a[0]))
	if ps.is_empty():
		return "Nobody matches '%s'" % a[0]
	for p: Net.ServerPlayer in ps:
		p.size = sz
	net._server_send_roster()
	return "%s: size %s" % [_names(ps), str(snappedf(sz, 0.01))]


static func _tier(net: Net, from: int, a: Array) -> String:
	if a.size() < 2 or not str(a[1]).is_valid_int():
		return "usage: " + HELP.tier[0]
	var t := clampi(int(a[1]), 1, 3)
	var ps := _who(net, from, str(a[0])).filter(func(p): return p.npc and p.ai != null)
	if ps.is_empty():
		return "No spawned fighters match '%s'" % a[0]
	for p: Net.ServerPlayer in ps:
		p.ai.difficulty = t - 1
		var i := p.name.rfind(" (tier ")
		p.name = (p.name.left(i) if i > 0 else p.name) + " (tier %d)" % t
	net._server_send_roster()
	return "%s: tier %d" % [_names(ps), t]


## spawn <weapon|random|mix> [count] [tier N] [side] [size N] [level N] [name "..."] (words in any order after the weapon)
static func _spawn(net: Net, from: int, a: Array) -> String:
	if a.is_empty():
		return "usage: " + HELP.spawn[0]
	var wword := str(a[0]).to_lower()
	var weapon := -1
	if WEAPON_WORDS.has(wword):
		weapon = WEAPON_WORDS[wword]
	elif wword not in ["random", "any", "mix", "mixed"]:
		return "No weapon called '%s' (fists club sword bow sling staff wand, or random / mix)" % a[0]
	var count := 1
	var tier := 2
	var side := Net.Side.HOSTILE
	var size := 1.0
	var level := 1
	var nm := ""
	var as_smiguel := false
	var i := 1
	while i < a.size():
		var t := str(a[i]).to_lower()
		var nxt := str(a[i + 1]) if i + 1 < a.size() else ""
		if t in ["tier", "difficulty", "diff"] and nxt.is_valid_int():
			tier = clampi(int(nxt), 1, 3)
			i += 1
		elif t in ["size", "scale"] and nxt.is_valid_float():
			size = clampf(float(nxt), SIZE_MIN, SIZE_MAX)
			i += 1
		elif t in ["level", "lvl", "lv"] and (nxt.is_valid_int() or nxt.to_lower() == "max"):
			level = Weapons.MAX_LEVEL if nxt.to_lower() == "max" else clampi(int(nxt), 1, Weapons.MAX_LEVEL)
			i += 1
		elif t in ["name", "called"] and nxt != "":
			nm = nxt
			i += 1
		elif t in ["count", "x"] and nxt.is_valid_int():
			count = int(nxt)
			i += 1
		elif t.is_valid_int():
			count = int(t)
		elif t.begins_with("x") and t.substr(1).is_valid_int():
			count = int(t.substr(1))
		elif SIDE_WORDS.has(t):
			side = SIDE_WORDS[t]
		elif t in ["smiguel", "as_smiguel"]:
			as_smiguel = true   # v0.13.0: dressed as Smiguel
		else:
			return "Didn't understand '%s'. %s" % [a[i], HELP.spawn[0]]
		i += 1
	count = clampi(count, 1, MAX_SPAWN)
	var me: Net.ServerPlayer = net.players[from]
	var fwd := Vector3(-sin(me.state.yaw), 0, -cos(me.state.yaw))
	var made := []
	var kinds := [Weapons.SWORD, Weapons.CLUB, Weapons.BOW, Weapons.SLING, Weapons.STAFF, Weapons.WAND, Weapons.FISTS]
	for k in count:
		var w := weapon
		if wword in ["random", "any"]:
			w = kinds[randi() % kinds.size()]
		elif wword in ["mix", "mixed"]:   # one of each in turn
			w = kinds[k % kinds.size()]
		# a fan of them 6 m in front (hostile ones a little further off)
		var spread := (float(k) - float(count - 1) / 2.0) * 1.8
		var right := Vector3(-fwd.z, 0, fwd.x)
		var at := me.state.pos + fwd * (6.0 if side != Net.Side.HOSTILE else 8.0) + right * spread
		at.y = maxf(WorldLayout.ground_height(at.x, at.z, at.y + 2.0), 0.0)
		var q := spawn_unit(net, from, w, tier - 1, side, size, level, at, nm if count == 1 else ("%s %d" % [nm, k + 1] if nm != "" else ""))
		if as_smiguel:
			q.unlocks = ["smiguel"]
			q.skin = "smiguel"
			if nm == "":
				q.name = "Smiguel (tier %d)" % tier
		made.append(q)
	return "Spawned %d %s %s (tier %d, level %d, size %s): %s" % [count, Net.SIDE_NAMES[side], wword, tier, level, str(snappedf(size, 0.01)), _names(made)]


## One fighter from the console: an NPC with a challenger's brain, on `side`, at `at`, facing the summoner.
static func spawn_unit(net: Net, owner: int, w: int, difficulty: int, side: int, size: float, level: int, at: Vector3, nm := "") -> Net.ServerPlayer:
	var q := Net.ServerPlayer.new()
	q.id = net.next_npc
	net.next_npc += 1
	q.npc = true
	q.dev = true
	q.side = side
	q.size = size
	var title := (nm if nm != "" else Names.npc())
	q.name = "%s (tier %d)" % [title, difficulty + 1]
	q.color = SIDE_COLORS[side]
	q.character = "pip"
	q.outfit = [3, 1, 2][side]
	q.pvp = true
	q.state = Sim.PlayerState.new()
	q.state.pos = at
	var me_pos: Vector3 = net.players[owner].state.pos if net.players.has(owner) else at + Vector3(0, 0, 1)
	var to := me_pos - at
	q.state.yaw = atan2(-to.x, -to.z)
	q.state.owned = 1 | (1 << w)
	q.state.weapon = w
	q.state.arrows = 99
	q.state.rocks = 99
	for ww in Weapons.DATA.size():
		set_level(q, ww, level)
	Sim.quantize(q.state)
	q.primed = true
	q.ai = NpcAI.new(q.id, owner, w, difficulty)
	q.ai.reach = 60.0
	net.players[q.id] = q
	net._server_send_roster()
	net._fx("npc_arrive", [q.id, at])
	return q

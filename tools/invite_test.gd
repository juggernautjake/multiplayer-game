extends SceneTree
## Invite codes: encode then decode gives back the address and port.
func _init() -> void:
	var M = load("res://scripts/main.gd")
	var bad := 0
	for c in [["192.168.1.23", 7777], ["100.101.7.42", 7777], ["73.12.250.9", 65535], ["0.0.0.0", 0], ["255.255.255.255", 7777]]:
		var code: String = M.invite_code(c[0], c[1])
		var back: Array = M.decode_invite(code.to_lower())
		var ok: bool = back == [c[0], c[1]]
		print("ok   " if ok else "FAIL ", c, " -> ", code, " -> ", back)
		if not ok: bad += 1
	print("not a code: ", M.decode_invite("192.168.1.5"))
	print(bad, " failed")
	quit(bad)

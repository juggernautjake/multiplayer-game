"""Model of the game's netcode (scripts/net.gd + sim.gd) over a bad connection: latency, jitter, packet loss.
Counts reconciliation corrections (prediction != server). Same rules: 60 Hz, inputs resent x4 unreliable,
server applies 1 input per tick (3 when >4 queued), snapshots every 2 ticks with ack, float32 rounding."""
import math, random, struct, sys

DT = 1 / 60
f32 = lambda v: struct.unpack("f", struct.pack("f", v))[0]

def step(s, btn, yaw):
    s = dict(s)
    f = (1 if btn & 1 else 0) - (1 if btn & 2 else 0)
    r = (1 if btn & 8 else 0) - (1 if btn & 4 else 0)
    sy, cy = math.sin(yaw), math.cos(yaw)
    wx, wz = -sy * f + cy * r, -cy * f - sy * r
    L = math.hypot(wx, wz); sp = 10 if btn & 32 else 6
    if L: wx, wz = wx / L * sp, wz / L * sp
    acc = (70 if s["g"] else 18) * DT
    dx, dz = wx - s["vx"], wz - s["vz"]; dl = math.hypot(dx, dz)
    if dl <= acc: s["vx"], s["vz"] = wx, wz
    else: s["vx"] += dx / dl * acc; s["vz"] += dz / dl * acc
    if s["g"] and btn & 16: s["vy"] = 10; s["g"] = False
    if not s["g"]: s["vy"] -= 28 * DT
    for a, v in (("x", "vx"), ("y", "vy"), ("z", "vz")): s[a] += s[v] * DT
    if s["y"] <= 0: s["y"] = 0; s["vy"] = 0; s["g"] = True
    for k in ("x", "y", "z", "vx", "vy", "vz"): s[k] = f32(s[k])
    return s

def run(lat_ms, jit_ms, loss, ticks=60 * 120, seed=1):
    rnd = random.Random(seed)
    s0 = dict(x=0.0, y=0.0, z=0.0, vx=0.0, vy=0.0, vz=0.0, g=True)
    server, pred = dict(s0), dict(s0)
    pending, recent, queue, last_q, last_applied, wait = [], [], {}, 0, 0, 0
    up, down = [], []  # (arrive_tick, payload)
    corrections, max_err, seq, newest_ack = 0, 0.0, 0, -1
    btn, yaw = 0, 0.0
    for t in range(ticks):
        if t % 40 == 0: btn = rnd.choice([1, 1 | 32, 1 | 8, 4, 2, 1 | 16, 0, 1 | 32 | 16])
        yaw += rnd.uniform(-0.03, 0.03); yaw = f32(yaw)
        # client tick
        seq += 1
        pred = step(pred, btn, yaw); pending.append((seq, btn, yaw))
        recent = (recent + [(seq, btn, yaw)])[-8:]
        if rnd.random() > loss:
            up.append((t + (lat_ms / 2 + rnd.uniform(0, jit_ms)) / (DT * 1000), list(recent)))
        # server receives
        for pkt in [p for p in up if p[0] <= t]:
            up.remove(pkt)
            for i in pkt[1]:
                if i[0] > last_applied and i[0] not in queue: queue[i[0]] = i
        # server tick
        budget = 3 if len(queue) > 4 else 1
        while budget and queue:
            nxt = last_applied + 1
            if nxt not in queue:
                wait += 1
                if wait < 8: break            # hold for the missing input a few ticks
                nxt = min(queue)              # give up on it
            wait = 0
            i = queue.pop(nxt); server = step(server, i[1], i[2]); last_applied = i[0]; budget -= 1
        if t % 2 == 0 and rnd.random() > loss:
            down.append((t + (lat_ms / 2 + rnd.uniform(0, jit_ms)) / (DT * 1000), dict(server), last_applied))
        # client receives snapshots (ordered: drop older than newest seen, like unreliable_ordered)
        arrived = sorted([p for p in down if p[0] <= t], key=lambda p: p[2])
        for p in arrived: down.remove(p)
        if arrived and arrived[-1][2] >= newest_ack:
            _, st, ack = arrived[-1]
            newest_ack = ack
            pending = [i for i in pending if i[0] > ack]
            rep = dict(st)
            for i in pending: rep = step(rep, i[1], i[2])
            err = math.dist((rep["x"], rep["y"], rep["z"]), (pred["x"], pred["y"], pred["z"]))
            if err > 1e-6: corrections += 1; max_err = max(max_err, err)
            pred = rep
    return corrections, max_err

for lat, jit, loss in ((30, 5, 0.0), (80, 20, 0.01), (150, 40, 0.03), (250, 80, 0.05)):
    c, e = run(lat, jit, loss)
    print(f"ping {lat:3d} ms, jitter {jit:2d} ms, loss {loss*100:3.0f}%: {c} corrections in 2 min, biggest {e*100:.2f} cm")

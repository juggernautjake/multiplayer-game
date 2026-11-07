"""A UDP proxy that behaves like a bad internet link, for testing the game's real ENet traffic (unlike the in-game
--netsim, ENet itself sees the delay here: its round-trip estimate, throttle and resends all react as they would).

    python tools/lag_proxy.py <listen port> <host port> <round trip ms> <jitter ms> <loss %> [mtu] [seconds]

The guest joins 127.0.0.1:<listen port>; packets go on to the host at 127.0.0.1:<host port>. Each direction gets half
the round trip plus 0..jitter ms (in order, like a real link: a late packet holds up the ones behind it). mtu (default
0 = off), e.g. 1280 for Tailscale: a datagram bigger than mtu - 28 travels as IP fragments, and losing any fragment
loses it, so its chance of loss grows. Every 5 s it prints packets and bytes each way and the share over the mtu.
"""
import heapq
import random
import socket
import sys
import time


def main() -> None:
    a = sys.argv[1:]
    lport, hport = int(a[0]), int(a[1])
    rtt, jit, loss = float(a[2]), float(a[3]), float(a[4]) / 100.0
    mtu = int(a[5]) if len(a) > 5 else 0
    secs = float(a[6]) if len(a) > 6 else 1e9
    front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    front.bind(("127.0.0.1", lport))
    front.setblocking(False)
    back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    back.bind(("127.0.0.1", 0))
    back.setblocking(False)
    host = ("127.0.0.1", hport)
    guest = None
    q = []          # (deliver_at, n, sock, data, to)
    n = 0
    last = {"up": 0.0, "down": 0.0}   # keeps each direction in order
    st = {k: [0, 0, 0, 0] for k in ("up", "down")}   # packets, bytes, over mtu, lost
    t_end = time.perf_counter() + secs
    t_rep = time.perf_counter() + 5.0

    def push(way: str, data: bytes, sock, to) -> None:
        nonlocal n
        s = st[way]
        s[0] += 1
        s[1] += len(data)
        frags = 1
        if mtu > 0 and len(data) > mtu - 28:
            s[2] += 1
            frags = -(-len(data) // (mtu - 48))
        if any(random.random() < loss for _ in range(frags)):
            s[3] += 1
            return
        at = max(time.perf_counter() + rtt / 2000.0 + random.random() * jit / 1000.0, last[way])
        last[way] = at
        n += 1
        heapq.heappush(q, (at, n, sock, data, to))

    while time.perf_counter() < t_end:
        busy = False
        try:
            while True:
                data, addr = front.recvfrom(65536)
                guest = addr
                push("up", data, back, host)
                busy = True
        except (BlockingIOError, ConnectionResetError):
            pass
        try:
            while True:
                data, _ = back.recvfrom(65536)
                if guest:
                    push("down", data, front, guest)
                busy = True
        except (BlockingIOError, ConnectionResetError):
            pass
        now = time.perf_counter()
        while q and q[0][0] <= now:
            _, _, sock, data, to = heapq.heappop(q)
            try:
                sock.sendto(data, to)
            except OSError:
                pass
        if now >= t_rep:
            t_rep = now + 5.0
            print("[proxy] " + "   ".join("%s %d pk/s %d B/s, %d over mtu, %d lost" % (k, v[0] / 5, v[1] / 5, v[2], v[3])
                                          for k, v in st.items()), flush=True)
            for v in st.values():
                v[:] = [0, 0, 0, 0]
        if not busy:
            time.sleep(0.0003)


if __name__ == "__main__":
    main()

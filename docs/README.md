# docs/

Documents for players. Back to the [project README](../README.md).

## how-to-host-and-join.pdf

A five-page, step-by-step guide for Windows players, written for people who are not programmers. It is linked from
the project README's "Download and play" section. Send it to friends who want to play.

| Part | What it covers |
|---|---|
| How joining works, in one minute | One person hosts; invite codes like `34CP1-P07KE`; a table of which code to send ("same Wi-Fi", "Tailscale", "over the internet") depending on where the friend is. |
| Part A: host steps | 1. Download the zip from the latest GitHub release, extract it, run `MultiplayerGame.exe` (and get past "Windows protected your PC"). 2. Allow the game through Windows Firewall on Private and Public networks, and how to fix it if you missed the prompt. 3. Let friends reach you: Tailscale (install, sign in, share your PC from the admin page) or port forwarding (UDP 7777 to your PC's local address; not possible behind CGNAT). 4. Host a game: name, look (Pip or 3D figure, F2 to switch later), port 7777, Play / Host, where the invite codes appear and which one is on the clipboard. Also: codes stay the same while your addresses do, and playing alone. |
| Part B: guest steps | Download and run the game, accept the host's Tailscale share link if there is one, paste the invite code (capitals and the dash don't matter) and click Join a friend. Troubleshooting for "No game answered". |
| Controls | The key table (mouse, WASD, Shift / Space / Q, mouse buttons, E, 1-5 or Tab, V and the mouse wheel, F2, Esc). |

The PDF is dated November 4, 2026. Its source file is not in this repository, so update it wherever it was made
when hosting, joining or the controls change. Two small differences from the README today: the PDF's controls table
does not mention eating fruit with E, and the PDF says to allow the firewall on Private **and** Public networks
while the README mentions private networks only.

## networking.md

Lag, rubber-banding and Tailscale (v0.8.0): what the netcode already did, what 0.8.0 changed and the measurements
(two copies of the game with a simulated 140-150 ms connection: no prediction corrections), how to tell whether
Tailscale is going direct or through a DERP relay (`tailscale ping`, `tailscale status`, `tailscale netcheck`, the
in-game readout) and how to get a direct path (UPnP / NAT-PMP, forwarding UDP 41641, avoiding double NAT), and a
brainstorm of future improvements, including when a dedicated server would help and what running one on a small VPS
would look like (cost, region, a systemd service, invite codes and updates).

## Numbers the server and every client must agree on.
class_name Config

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 32
const MAX_NAME := 24   # v0.12.6: was 16 (spawned units' names may run to 40)

## Fixed simulation rate (also set in project.godot: physics/common/physics_ticks_per_second).
## Every input is one step of exactly 1 / TICK_RATE seconds, on the server and on the client.
const TICK_RATE := 60
const DT := 1.0 / TICK_RATE

## World snapshots per second to each client: every SNAPSHOT_EVERY ticks.
const SNAPSHOT_EVERY := 2

## Other players are drawn this many ticks in the past (100 ms), so there are always two snapshots to blend.
const INTERP_DELAY_TICKS := 6

## Each input packet repeats the last few inputs, so a lost UDP packet costs nothing.
const INPUT_REDUNDANCY := 8

## Inputs a client may bank before extras are dropped (stops speed hacks by flooding).
const MAX_INPUT_BACKLOG := 30

## The open plane: players stay within +-WORLD_HALF metres.
const WORLD_HALF := 200.0

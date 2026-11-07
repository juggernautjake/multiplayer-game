# Dev commands (cheat sheet)

Every command in the game's dev console, as of v0.12.12.

## Opening the console

- Press **`** (the backtick key, left of **1**, under **Esc**) to open and close it.
- **Tab** finishes a command or name for you. **Up / Down** go back through what you typed before.
- The **host** can always use the commands.
- **Guests** can only use them after the host types `cheats on`. The host turns that back off with `cheats off`.
- Anyone, guest or host, can change their own name with `name <new name>`.
- Typing a `/` in front is fine: `/max` works the same as `max`.

## Who a command is for (targets)

Many commands end with a **target**. Leave the target out and the command is for **you**.

| Target | Means |
|---|---|
| `me` | you |
| `all` | everyone: players and spawned fighters |
| `players` | only real players |
| `units` | only spawned fighters (also `npcs`) |
| `friendly` / `hostile` / `neutral` | spawned fighters on that side |
| a name, or the start of one | that player or unit, for example `jake` or `gar`. Capital letters don't matter. |
| `"a name with spaces"` | put names with spaces in double quotes |
| `#id` | one exact player or unit, by the number `list` shows (for example `#1000002`) |

**Weapon words:** `fists` `club` `sword` `bow` `sling` (or `slingshot`) `staff` `wand`.
Groups: `all`, `magic` (staff and wand), `arms` (fists, club, sword, bow and sling), `melee` (fists, club and sword), `ranged` (bow and sling).

## All commands

| Command | What it does |
|---|---|
| `help` | Lists every command. |
| `help <command>` | Explains one command, for example `help spawn`. `help mastery` also shows what levels up each spell. |
| `list` | Everyone in the game with their **#id**, side, size, health, weapon and levels. |
| `give <weapon\|all> [target]` | Gives a weapon. The bow and slingshot come with full ammo. |
| `take <weapon\|all> [target]` | Takes a weapon away. Fists always stay. |
| `level <weapon\|all\|magic\|arms> <1-4\|max> [target]` | Sets weapon levels. For the staff and wand the level unlocks spells; for the other weapons it raises damage. |
| `mastery <spell\|staff\|wand\|all> <1-3\|max> [target]` | Sets spell mastery (I, II or III). Part of a spell's name works too: `fire`, `tele`, `frost`. |
| `max [target]` | **Tops out everything**: every weapon, every level 4, every spell at mastery III, full ammo, health and mana. `maxall`, `topall` and `maxout` do the same. |
| `spawn <weapon\|random\|mix> [options]` | Spawns fighters in front of you. The options are in the next section. |
| `side <target> <friendly\|neutral\|hostile>` | Changes which side spawned fighters are on. Players are always on the players' side. |
| `size <target> <0.3-4>` | Makes someone bigger or smaller. Their reach and hitbox change with them. |
| `tier <target> <1-3>` | How good a spawned fighter is (aim, dodging, reactions). 1 is easy, 3 is hard. |
| `heal [target]` | Full health and mana. Clears stuns, slows and static. |
| `ammo [target]` | Full arrows and stones (60 each). |
| `god [target] [on\|off]` | God mode: takes no damage. Without on or off it switches. |
| `kill <target>` | Knocks them out. |
| `clear [units\|hostile\|friendly\|neutral]` | Removes spawned fighters, all of them unless you name a side. The boss's minions aren't affected. |
| `tp <target>` | Teleports you to someone. |
| `bring <target>` | Teleports someone (or a group) to you. |
| `name <new name>` | Changes your own name. Anyone can use this one. |
| `rename <target> <new name>` | Renames a player or unit. Use `#id` if a name matches more than one. |
| `boss` | Summons **Thunderhorn** right now and starts the boss fight. |
| `cheats <on\|off>` | Host only: lets guests use the dev commands, or stops them. |

## Spawning fighters

```
spawn <weapon|random|mix> [count] [tier 1-3] [friendly|neutral|hostile] [size N] [level 1-4] [name "..."]
```

- **Weapon:** `sword` `club` `bow` `sling` `staff` `wand` `fists`. `random` picks one at random for each fighter; `mix` gives one of each in turn.
- **Count:** a plain number (`3`), `x3` or `count 3`. You can spawn up to **20** at once.
- **Tier:** `tier 1`, `tier 2` (the default) or `tier 3`.
- **Side:** `hostile` (the default), `friendly` or `neutral`.
  - **Friendly** fighters follow you and fight your enemies.
  - **Neutral** ones only fight whoever attacks them.
- **Size:** `size 0.3` up to `size 4` (default 1).
- **Level:** `level 1` to `level 4`, or `level max`. A higher level means harder hits and, for wizards, more spells.
- **Name:** `name "Big Steve"`. If you spawn several, they get numbers: Big Steve 1, Big Steve 2...
- The options can go in any order after the weapon. Fighters you don't name get a random funny name.

Examples:

```
spawn sword                                  one tier 2 hostile swordsman
spawn bow 5 hostile tier 3                   five tough archers
spawn mix 7 friendly level max               an army of allies, one of each weapon, fully levelled
spawn staff 1 neutral size 3 name "Gandalf"  a giant neutral wizard
spawn random x10 tier 1 size 0.5             ten tiny easy fighters with random weapons
```

## Weapon levels

All weapons go from level 1 to 4. Playing normally, a weapon levels up at **3, 7 and 12** knockouts with it.

- **Staff and wand:** each level unlocks more spells.
- **Fists, club, sword, bow and slingshot:** each level raises damage: x1.0, x1.25, x1.5, x1.8.

## Spells and mastery

The **staff** casts Lightning, Fireball, Shield, Frost Nova, Meteor, Heal Aura and Arcane Storm.
The **wand** casts Spark Beam, Golem, Teleport, Stun, Fog, Life Drain, Gravity Well and Stone Titan.

Each spell has its own mastery: I, then II, then III. In normal play it rises from what the spell achieves. Practice dummies don't count. The dev command skips straight there: `mastery fire 3`, `mastery wand max`, `mastery all 3 "Jake"`.

| Spell | Earned by | II at / III at | Mastery II | Mastery III |
|---|---|---|---|---|
| Lightning | damage to enemies (chain jumps count double) | 600 / 1800 | +25% damage, wider strike (3.75 m), chains 8 m, 7 jumps | +50% damage, wide strike (4.5 m), chains 10 m, 9 jumps, the bolt forks |
| Fireball | damage to enemies | 600 / 1800 | bigger blast, +20% damage | huge blast, +40% damage, 3 fire bomblets |
| Shield | damage the bubble soaks (+4 per shot turned away) | 250 / 750 | half the cost to raise, hits drain 30% less | hits drain 50% less, shots fly back at the shooter |
| Frost Nova | damage + 2 per second of slow on an enemy | 350 / 1050 | +25% reach, slows for 3 s | freezes enemies near you solid for 1 s, ice spikes |
| Meteor | damage (the burning ground too) | 600 / 1800 | 3 meteors | 5 meteors, wider, longer fires |
| Heal Aura | health restored to you and allies | 300 / 900 | 10 health a second, reaches 9 m | 12 a second, 10 m, cleanses stuns and slows, leaves a regen glow |
| Arcane Storm | damage to enemies | 500 / 1500 | lasts 7 s, a bolt every quarter second | wider cloud, every bolt chains once |
| Spark Beam | damage (x1.5 for hits beyond 15 m) | 500 / 1500 | +30% damage, pierces 1 enemy | +60% damage, pierces 2, arcs to one more |
| Golem | damage your golems deal | 500 / 1500 | bigger golems: +40% health, harder punches | huge golems: +80% health, ground-slam |
| Teleport | metres travelled (+ arrival burst damage) | 250 / 750 | reaches 25 m, a burst where you arrive | reaches 32 m, a shockwave where you arrive |
| Stun | seconds of stun + a quarter of the damage your side deals to stunned enemies | 120 / 360 | holds 4 s, wider burst | holds 5 s; challengers and units fight for you for 6 s after |
| Fog | enemy-seconds blinded + a quarter of your side's damage inside + poison | 250 / 750 | poison: 2 damage a second to enemies inside | 30 x 30 m, 4 poison a second, enemies slowed |
| Life Drain | damage drained + health given to allies | 400 / 1200 | +25% damage, drains 55% | +50% damage, jumps to a second enemy, bigger ally heal |
| Gravity Well | damage + 1 per second an enemy is dragged | 400 / 1200 | pulls from 9.5 m, wider burst | pulls harder, bursts twice |
| Stone Titan | damage your titan deals | 600 / 1800 | bigger titan: +35% health, harder slams | +70% health, every slam sends a stomp shockwave |

## Handy combos

```
cheats on                         (host) let your buddy use commands too
max all                           everyone gets everything, maxed
god me on                         you can't be hurt
boss                              start the Thunderhorn fight now
spawn mix 6 friendly tier 3 level max      bring backup to the boss
heal players                      patch everyone up mid-fight
bring players                     gather everyone to you
clear hostile                     remove every hostile spawned fighter
list                              see everyone's #id, side and levels
rename #1000003 "Sir Bonk"        rename one exact unit
size me 3                         become a giant
```

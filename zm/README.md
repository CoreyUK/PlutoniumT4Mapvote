# Plutonium T4 Zombies Map Vote

This is the Zombies port of the T4 multiplayer map vote. After the stock
`GAME OVER` and survived-rounds presentation, players vote between random map
choices plus a RANDOM option.

## Stock maps

- `nazi_zombie_prototype` — Nacht der Untoten
- `nazi_zombie_asylum` — Verrückt
- `nazi_zombie_sumpf` — Shi No Numa
- `nazi_zombie_factory` — Der Riese

## Installation

1. Copy `scripts/sp/t4_zm_mapvote.gsc` to
   `%localappdata%\Plutonium\storage\t4\raw\scripts\sp\t4_zm_mapvote.gsc`.
2. Copy `mod/t4_zm_mapvote` into the server's T4 `mods` folder and start the
   server with `fs_game` set to `mods/t4_zm_mapvote`.
3. Add the settings from `mapvote_zm.cfg` to the server configuration.
4. Restart the server process.

The script extends the stock `zombie_intermission_time`; it does not replace
the complete `_zombiemode.gsc`, so it is shared by all four stock maps.

## Controls

- Aim: previous choice
- Fire: next choice
- Use or reload: submit/change vote

Blue is the current cursor, green is the player's submitted vote, and gold is
shown only after the winning card is selected.

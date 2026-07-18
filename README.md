# Plutonium T4MP Map Vote

An end-of-match map vote for Call of Duty: World at War multiplayer on
Plutonium T4. It is inspired by
[DoktorSAS's map-vote projects](https://github.com/DoktorSAS), but is written
for T4's scripting and end-game behavior.

The vote displays two randomly selected maps plus a RANDOM option, live vote
totals, a timer, fair random tie-breaking, optional random gametypes,
keyboard/mouse input, and controller input.

## Installation

1. Copy `scripts/mp/t4_mapvote.gsc` to:
   `%localappdata%\Plutonium\storage\t4\raw\scripts\mp\t4_mapvote.gsc`
2. Copy `maps/mp/gametypes/_globallogic.gsc` to:
   `%localappdata%\Plutonium\storage\t4\raw\maps\mp\gametypes\_globallogic.gsc`
   on a local host, or to `main_shared/maps/mp/gametypes/_globallogic.gsc`
   in the dedicated server's game directory. This small stock-script override
   prevents T4 from forcing the Tab scoreboard over the final map vote.
3. Copy the settings from `mapvote.cfg` into the server configuration that is
   executed at startup.
4. Restart the server or rotate/restart the map.

If another mod already supplies `_globallogic.gsc`, merge the marked
`mapVoteIntermission` block into that version instead of replacing it.

This is intended for a Plutonium T4 dedicated multiplayer server.

## Controls

- Aim: previous choice
- Fire: next choice
- Use or reload: cast/change vote

The selected card has a gold border. A submitted vote changes its map name to
green. Players can change their vote until the timer expires.

## Configuration

- `mv_enable`: enable (`1`) or disable (`0`) the script.
- `mv_time`: voting time in seconds.
- `mv_result_time`: how long the winning map is displayed.
- `mv_options`: total number of cards, including RANDOM (`3` through `6`).
- `mv_allow_dlc`: include paid Map Pack maps when set to `1`; exclude them
  from both named choices and RANDOM when set to `0`.
- `mv_maps`: space-separated map IDs. At least two unique eligible maps are
  required. RANDOM selects from the eligible maps not shown as named cards.
- `mv_gametypes`: optional space-separated gametype IDs. Leave empty to retain
  the current mode.
- `mv_allow_current`: include the current map when set to `1`.
- `mv_debug`: preview the vote five seconds after map start. Keep this `0` on a
  live server.

Stock map IDs and display names are included in the script. Custom map IDs can
be added to `mv_maps` with corresponding display-name and shader entries.

The individual `.iwi` images are also published separately in
`loadscreen-reference/`, with a map ID and display-name index for other T4
mod authors.

## Testing

For a quick visual/input test, use a private or test dedicated server and set
`mv_debug 1`. For rotation testing, use a dedicated server, leave
`mv_debug 0`, and let a match end normally.

If the script fails to load, inspect the Plutonium server console for the GSC
compiler line number. Ensure the file is under `raw/scripts/mp`, not the T5/T6
`storage/scripts` layout.

## Credits

- Original T4 implementation: CoreyUK / contributors
- Design inspiration: [DoktorSAS](https://github.com/DoktorSAS)

# Polymorph: Mod Manager
This is a map chooser replacement. It allows voting for the next mod (GunGame, HNS, etc.). It does not pause plugins so plugins from the mods are not loaded unless it is being played.

## Admin Commands

### `amx_nextmod`

Console command to show/choose the next MOD to be played. When you change the next MOD it will choose a random map from the MOD's map list to be the default map.

### `amx_votemod`

Starts a vote for the next MOD (and consequently the next map). Then it changes the map.

### `amx_showmaps` / `amx_polymorph_showmaps`

Show Maps to Clients and admins.

### `amx_showmods` / `amx_polymorph_showmods`

Show Mods to Clients and admins.

### `amx_polymorph_nominate`

Opens the nomination menu.

### `amx_polymorph_vote`

Opens the vote menu.

### `amx_polymorph_settings`

Opens the settings menu.

## Client Commands

### `say nextmod`
Shows the next mod.

### `say thismod`
Shows the current mod.

### `say nominate` / `say nom`
Opens the nomination menu.

### `say showmaps`
Shows the map list.

### `say showmods`
Shows the mod list.

### `say /vote` / `say vote`
Opens the vote menu.

### `say /settings`
Opens the settings menu.

### `say rtv` / `say rockthevote`
Initiates RockTheVote (if poly_rtv is installed).

## Cvars

### `poly_mode <#>`

Modes:

0. Always stay on one mod unless changed manually with admin command. (Map votes only)
1. Play X maps then next mod will default to next in polymorph folder (Map votes only)
2. Play X maps then next mod will be chosen by vote. (Map and Mod votes)

Default: 2

### `poly_extendmod <1|0>`

Allow extending the current mod (Mode 2).

Default: 1

### `amx_extendmap_max <minutes>`

Maximum number of minutes to which the map can be extended.  Same as the original mapchooser plugin.

Default: 90

### `amx_extendmap_step <minutes>`

Number of minutes added when the map is extended.  Same as the original mapchooser plugin.

Default: 15

### `poly_prefix <string>`

Chat prefix for Polymorph messages.

Default: `^4[Polymorph]^1`

### `poly_endonround <1|0>`

Change map at round end instead of immediately.

Default: 0

### `poly_revote <1|0>`

Allow players to change their vote.

Default: 1

### `poly_allow_nomination <1|0>`

Allow players to nominate maps/mods.

Default: 1

### `poly_vote_time <seconds>`

Time to choose an option in vote.

Default: 20.0

### `poly_vote_delay <seconds>`

Time between mod vote ending and map vote starting.

Default: 10.0

### `poly_thismod <string>`

Current Mod Name (Do not change manually).

### `poly_nextmod <string>`

Next Mod Name.

## RTV Cvars (if poly_rtv is installed)

### `rtv_enable <1|0>`

Enable RockTheVote.

Default: 1

### `rtv_ratio <0.0-1.0>`

Ratio of players needed to rock the vote.

Default: 0.51

### `rtv_wait <minutes>`

Minutes after mapstart you can rtv.

Default: 1

### `rtv_show <1|0>`

Display how many more votes needed to rtv.

Default: 1

## Setup

- Install polymorph.amxx like any other plugin.
- Create the folder /addons/amxmodx/configs/polymorph/.
- Create MOD initialization files:
  - File must be in the polymorph folder.
  - File must begin with a number.
  - Example file 0_MyFirstMod.ini
    ```
    ; Mod Cofiguration
    ; Comments here.

    [mod]
    name "Mod Name"
    mapsfile maps1.ini
    mapspermod 2

    [cfg]
    sv_gravity 900
    sv_alltalk 0
    hostname "This server is running ModName"

    [plugins]
    plugin1.amxx
    plugin1b.amxx
    ```

  - "mapsfile" must be in the polymorph folder. It should contain all the maps that you want to be eligible to be played with the MOD

- If a mod comes with a `plugins-<modname>.ini` file (like Zombie Plague), it must removed.
- If you want a plugin running for all mods then place it in plugins.ini. If you want it running for only certain mods, list it in your mod's .ini file in the polymorph folder.

## Startup
The plugin will fail the first time it is run. Simply restart the server to create the plugins-polymorph.ini file.
# TF2-Dodgeball-Stats

## Presentation

This plugin is made for server owners using the [dodgeball gamemode]("https://forums.alliedmods.net/showthread.php?t=299275") on Team Fortress 2.  
#### It's a system where players can get the actual stats:

* Rank
* Points
* Kills
* Deaths
* K/D
* Playtime
* Topspeed
* Top deflections

Note that it's a plugin under developement, it could have some bugs, feel free to [create an issue](https://github.com/walgrim-dev/TF2-Dodgeball-Stats/issues) or [contact me](https://steamcommunity.com/id/walgrim/)!
Also some features will be implemented (see TODO list).</br>

## Commands

* `/rank or !rank` This command display the player stats (in chat and in a panel).
* `/top x or !top x | Example: /top 25, !top 25, !top 41, /top 41... It's up to 100.` This command display the top x players in a menu.
* `/kpd or !kpd` This command prints in the chat the player kill per death ratio.
* `/points or !points` This command print in the chat the player points.
* `/topspeed or !topspeed` This command prints the player topspeed.
* `/resetstats or !resetstats` The player can reset his stats using this command.


# Installation/Update

#### IMPORTANT: To get topspeed and topdeflections working, you'll have to add a command in general.cfg, you can find this file in `tf/addons/sourcemod/configs/dodgeball/`.
Search for the events section and add this line at **"on deflect"** event: `sm_dodgeballstats @speed @deflections @owner @target`. (See the example below)
```c
// >>> Events <<<
"on spawn"                    "sm_hsay Speed: @speed - Total deflections: @deflections"
"on deflect"                  "sm_dodgeballstats @speed @deflections @owner @target"
"on kill"                     ""
"on explode"                  "" // Actions to execute when a rocket kills a client (triggered once).
```

Then you will just have to copy/drag and drop the folder `addons` to the `tf/` server folder.
This plugin uses and creates it's own <em>MySQLite</em> database, you can find it in `tf/addons/sourcemod/data/sqlite/` called `db_sqlitestats.sq3`.


## Languages and colors

#### Actually the plugin is using english as default language and know the following languages.
* French

Feel free to help me with the other languages!

### Changing chat colors

The plugin uses the include [morecolors]("https://forums.alliedmods.net/showthread.php?t=185016") so you can change the colors in the translations files, to do that go in `addons/sourcemod/translations` they are called `dodgeballstats.phrases` (don't miss the other one in the `fr/` folder)!  

Then you can replace in the translations (by opening the .txt files) the words in brackets as `{skyblue}` or `{strange}` here are the multiple colors you can use: https://www.doctormckay.com/morecolors.php!

## Optional

If you have a MySQL database you can also use it search for `database.cfg` in `addons/sourcemod/configs` and add the following code in it:
```
"db_stats"
{
  "driver"      "mysql"
  "host"        "127.0.0.1"
  "database"    "databasename"
  "user"        "username"
  "pass"        "password"
}
```
Don't forget to fulfil the hostname or ip, databasename, username and password.

# ConVars

A file is auto-generated in `cfg/sourcemod` called `TF2_DodgeballStats.cfg`.  
#### In this one you can see the following ConVars:

```c
// Seconds the player have to wait before showing again his stats.
// -
// Default: "5"
dodgeball_antifloodseconds "5"

// Points loosed when a player is killed by his opponent.
// -
// Default: "5"
dodgeball_ondeathpoints "5"

// Points gained when a player kills his opponent.
// -
// Default: "8"
dodgeball_onkillpoints "8"

// Sets your server tag.
// -
// Default: "[Dodgeball Stats]"
dodgeball_servertag "[Dodgeball Stats]"

// Sets the title of the menu.
// -
// Default: "[Dodgeball Stats]"
dodgeball_statsmenutitle "[Dodgeball Stats]"

// Sets the title of the top menu.
// -
// Default: "Top Dodgeball Players"
dodgeball_toptitle "Top Dodgeball Players"

// Enable or disable the welcome message on player connection.
// -
// Default: "1"
// Minimum: "0.000000"
// Maximum: "1.000000"
dodgeball_welcomemessage "1"
```

# TODO LIST

* [x] Add the topspeed in the plugin.
* [x] Add the topdeflections in the plugin. 
* [x] Add more cvars.
* [ ] Make commands more flexible.
* [ ] Make modules.


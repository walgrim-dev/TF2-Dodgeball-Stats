<h1>TF2-Dodgeball-Rank</h1>

<h2>Presentation</h2>

This plugin is made for server owners using the <a href="https://forums.alliedmods.net/showthread.php?t=299275">dodgeball gamemode</a> on Team Fortress 2.</br>
<h4>It's a ranking system where players can get the actual stats for the moment:</h4>
<ul>
  <li>Rank</li>
  <li>Points</li>
  <li>Kills</li>
  <li>Deaths</li>
  <li>K/D</li>
  <li>Playtime</li>
</ul>

Note that it's a plugin under developement, it could have some bugs, feel free to <a href="https://github.com/walgrimfr/TF2-Dodgeball-Rank/issues">create an issue</a> or <a href="https://steamcommunity.com/id/walgrim/">contact me</a>!</br>
Also some features will be implemented such as topspeed (see the TODO list).</br>

<h2>Commands</h2>
<ul>
  <li><code>/rank or !rank</code> This command display the player stats (in chat and in a panel).</li>
  <li><code>/top10 or !top10</code> This command display the top 10 players in a panel.</li>
  <li><code>/kpd or !kpd</code> This command prints in the chat the player kill per death ratio.</li>
  <li><code>/points or !points</code> This command print in the chat the player points.</li>
  <li><code>/resetrank or !resetrank</code> The player can reset his stats using this command.</li>
</ul>

<h1>Installation/Update</h1>

You will just have to copy/drag and drop the folder <code>addons</code> to the <code>tf/</code> server folder.</br>
</br>
This plugin uses and creates it's own <em>MySQLite</em> database which is implemented, internal in sourcemod, you can found it in <code>tf/addons/sourcemod/data/sqlite/</code> called <code>db_sqliterank.sq3</code>.</br>

<h2>Languages and colors</h2>

<h4>Actually the plugin is using english as default language and know the following languages:</h4>
<ul>
  <li>French</li>
</ul>

Feel free to help me with the other languages! :^)</br>

<h3>Changing chat colors</h3>

The plugin uses the include <a href="https://forums.alliedmods.net/showthread.php?t=185016"><code>morecolors</code></a> so you can change the colors in the translations files, to do that go in <code>addons/sourcemod/translations</code> they are called <code>dodgeballrank.phrases</code> (don't miss the another one in the <code>fr/</code> folder)!</br>
</br>
Then you can replace in the translations (by opening the .txt files) the words in brackets as <code>{dbblue}</code> or <code>{dborange}</code> here are the multiple colors you can use: https://www.doctormckay.com/morecolors.php!

<h2>Optional</h2>

If you have a MySQL database you can also use it search for <code>database.cfg</code> in <code>addons/sourcemod/configs</code> and add the following code in it:
```
"db_rank"
{
  "driver"      "mysql"
  "host"        "127.0.0.1"
  "database"    "databasename"
  "user"        "username"
  "pass"        "password"
}
```
Don't forget to fulfil the hostname or ip, databasename, username and password.

<h1>ConVars</h1>

A file is auto-generated in <code>cfg/sourcemod</code> called <code>DodgeballRank.cfg</code>.</br>
<h4>In this one you can see the following ConVars:</h4>

```
dodgeball_servertag // Used to change the server tag above all the rank phrases.
dodgeball_rankmenutitle // Used to change the menu title when we use the /rank or !rank command.
dodgeball_top10title // Used to change the top10 title when we use the /top10 or !top10 command.
dodgeball_antifloodseconds // This one is used to avoid a flood of phrases on the server 
```

<h1>TODO LIST</h1>
<ul>
	<li>Add the topspeed in the plugin.</li>
	<li>Add the topdeflections in the plugin.</li>
	<li>Remake the point system to make it in function of deflections.</li>
	<li>Add more cvars.</li>
	<li>Add more welcome or wb messages.</li>
</ul>

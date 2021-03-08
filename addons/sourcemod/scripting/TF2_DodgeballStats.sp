#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#pragma newdecls required

public Plugin myinfo = {
	name = "[TF2] Dodgeball Stats",
	author = "Walgrim",
	description = "TF2 Stats system for dodgeball !",
	version = "1.2.1",
	url = "http://steamcommunity.com/id/walgrim/"
};

/* CVARS */
ConVar cvar_ServerTag = null;
ConVar cvar_MenuTitle = null;
ConVar cvar_TopTitle = null;
ConVar cvar_AntiFloodSeconds = null;
ConVar cvar_EnableWelcomeMessage = null;
ConVar cvar_OnKillPoints = null;
ConVar cvar_OnDeathPoints = null;

/* DATABASE */
Handle db = null;

/* SQLITE */
bool IsSQLite;

/* STATS */
enum struct DodgeballPlayer {
	int points;
	int kills;
	int deaths;
	int playtime;
	int topNumber;
	int realTimetopspeed;
	int realTimetopdeflections;
	int actualtopspeed;
	int actualtopdeflections;
	/* SETTINGS */
	int timeAtConnection;
	int lastTimeUsedCmd;
	bool isNew;	
}

DodgeballPlayer Player[MAXPLAYERS + 1];

/* GLOBAL STATS */
int rankcount;
int newspeed;
int oldspeed;

/****************************************/
char ServerTag[64];

/* MENU */
#define YES "#choice1"
#define NO "#choice2"

public void OnPluginStart() {
	/* Load Translations */
	LoadTranslations("dodgeballstats.phrases");

	/* CVARS LIST */
	cvar_ServerTag = CreateConVar("dodgeball_servertag", "[Dodgeball Stats]", "Sets your server tag.");
	cvar_MenuTitle = CreateConVar("dodgeball_statsmenutitle", "[Dodgeball Stats]", "Sets the title of the menu.");
	cvar_TopTitle = CreateConVar("dodgeball_toptitle", "Top Dodgeball Players", "Sets the title of the top menu.");
	cvar_AntiFloodSeconds = CreateConVar("dodgeball_antifloodseconds", "5", "Seconds the player have to wait before showing again his stats.");
	cvar_EnableWelcomeMessage = CreateConVar("dodgeball_welcomemessage", "1", "Enable or disable the welcome message on player connection.", _, true, 0.0, true, 1.0);
	cvar_OnKillPoints = CreateConVar("dodgeball_onkillpoints", "8", "Points gained when a player kills his opponent.");
	cvar_OnDeathPoints = CreateConVar("dodgeball_ondeathpoints", "5", "Points loosed when a player is killed by his opponent.");

	/* Reg console commands */
	RegConsoleCmd("sm_rank", CMD_Rank, "Stats CMD to display the panel.");
	RegConsoleCmd("sm_top", CMD_Top, "Top [1 to 100] CMD to display the menu.");
	RegConsoleCmd("sm_kpd", CMD_Kpd, "Command to show kpd ratio.");
	RegConsoleCmd("sm_points", CMD_Points, "Command to show points.");
	RegConsoleCmd("sm_topspeed", CMD_TopSpeed, "Command to show topspeed.");
	RegConsoleCmd("sm_resetstats", CMD_ResetStats, "Command to reset the stats.");

	/* Reg admin commands */ 
	RegAdminCmd("sm_dodgeballstats", GetDodgeballStats, ADMFLAG_ROOT, "Retrieve speed, deflections from general.cfg", _, FCVAR_PROTECTED);

	/* Hook players deaths */
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	/* Create the cfg file */
	AutoExecConfig(true, "TF2_DodgeballStats");
}

public void OnConfigsExecuted() {
	cvar_ServerTag.GetString(ServerTag, sizeof(ServerTag));
	/* Start Database */
	StartDB();
}

/* Start Database */
void StartDB() {
	//Buffer for error messages & the query
	char error[255], Query[255];
	//Connect to the database
	if (SQL_CheckConfig("db_stats")) {
		db = SQL_Connect("db_stats", true, error, sizeof(error));
	} else {
		// KeyValues
		Handle kv = CreateKeyValues("db_stats");
		KvSetString(kv, "driver", "sqlite");
		KvSetString(kv, "database", "db_sqlitestats");

		// Connect
		db = SQL_ConnectCustom(kv, error, sizeof(error), false);

		// Delete the kv
		delete kv;
	}
	GetDriver(db);

	if (db == null)
		SetFailState(error);

	//Get the strings in utf8
	SQL_SetCharset(db, "utf8");
	if (IsSQLite) {
		// The NOT NULL constraint enforces a column to NOT accept NULL values.
		Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `dbstats` (name TEXT NOT NULL, steamid TEXT UNIQUE NOT NULL, points INTEGER NOT NULL, kills INTEGER NOT NULL, deaths INTEGER NOT NULL, playtime INTEGER NOT NULL, topspeed INTEGER NOT NULL, topdeflections INTEGER NOT NULL);");
	} else {
		// The NOT NULL constraint enforces a column to NOT accept NULL values.
		Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `dbstats` (name varchar(64) NOT NULL, steamid varchar(32) NOT NULL, points int(10) NOT NULL, kills int(8) NOT NULL, deaths int(8) NOT NULL, playtime int(8) NOT NULL, topspeed int(8) NOT NULL, topdeflections int(8) NOT NULL);");
	}

	// Avoid Corruption, lock database
	SQL_LockDatabase(db);
	// Execute the query
	SQL_FastQuery(db, Query);
	// Database unlock
	SQL_UnlockDatabase(db);

	// If the plugin is reloaded we get back the old values of the current players
	LoadDatas();
}

/* Get back the old values for current players */
void LoadDatas() {
	for (int client = 1; client <= MaxClients; client++) {
		if (IsEntityConnectedClient(client) && !IsFakeClient(client)) {
			UpdateOrCreatePlayerToDB(client);
		}
	}
}

/* Client put in server */
public void OnClientPutInServer(int client) {
	if (!IsEntityConnectedClient(client) || IsFakeClient(client)) return;
	UpdateOrCreatePlayerToDB(client);
}

/* Update or Create the player row */
void UpdateOrCreatePlayerToDB(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "SELECT points, kills, deaths, playtime, topspeed, topdeflections FROM `dbstats` WHERE steamid = '%s';", GetSteamId(client));
	SQL_TQuery(db, SQL_HandlePlayer, Query, GetClientUserId(client));
}

public void SQL_HandlePlayer(Handle owner, Handle query, const char[] error, any data) {
	if (query == null) {
		SetFailState("Query failed! %s", error);
	} else {
		int client = GetClientOfUserId(data);
		Player[client].timeAtConnection = GetTime();
		/* Wanted to use SQL_GetAffectedRows but unfortunaly it doesn't work with sqlite
			 see this thread: https://stackoverflow.com/questions/37911888/the-number-of-changed-rows-rows-affected-is-always-1-with-sqlite-android */
		if (!SQL_MoreRows(query)) {
			AddPlayerToDB(client);
			Player[client].isNew = true;
		} else {
			UpdatePlayerToDB(client);
			Player[client].isNew = false;
			//Fetch rows
			SQL_FetchRow(query);
			Player[client].points = SQL_FetchInt(query, 0);
			Player[client].kills = SQL_FetchInt(query, 1);
			Player[client].deaths = SQL_FetchInt(query, 2);
			Player[client].playtime = SQL_FetchInt(query, 3);
			Player[client].actualtopspeed = SQL_FetchInt(query, 4);
			Player[client].actualtopdeflections = SQL_FetchInt(query, 5);
		}
		if (cvar_EnableWelcomeMessage.BoolValue)
			CreateTimer(10.0, WelcomeOrWb, GetClientUserId(client));
	}
}

/* When we know, if the player is new or not, Add it or Update his datas */
void AddPlayerToDB(int client) {
	char Query[255];

	if (IsSQLite) {
		Format(Query, sizeof(Query), "INSERT INTO `dbstats` VALUES('%s', '%s', 1000, 0, 0, 0, 0, 0);", GetEscapedName(client), GetSteamId(client));
	} else {
		Format(Query, sizeof(Query), "INSERT INTO `dbstats` (steamid, name, points, kills, deaths, playtime, topspeed, topdeflections) VALUES ('%s', '%s', 1000, 0, 0, 0, 0, 0);", GetSteamId(client), GetEscapedName(client));
	}
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);

	Player[client].points = 1000;
	Player[client].kills = 0;
	Player[client].deaths = 0;
	Player[client].playtime = 0;
	Player[client].actualtopspeed = 0;
	Player[client].actualtopdeflections = 0;
}

void UpdatePlayerToDB(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "UPDATE `dbstats` SET name = '%s' WHERE steamid = '%s';", GetEscapedName(client), GetSteamId(client));
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

/* Welcome/wb the client if enabled */
public Action WelcomeOrWb(Handle Timer, int clientid) {
	int client = GetClientOfUserId(clientid);
	if (!IsEntityConnectedClient(client) || IsFakeClient(client)) return Plugin_Handled;
	char ClientName[64];
	/* Get Client Name */
	GetClientName(client, ClientName, sizeof(ClientName));
	/* Synchronize Hud and clear it to avoid overwritting */
	Handle Synch = CreateHudSynchronizer();
	ClearSyncHud(client, Synch); // I'm not sure if it goes there
	SetHudTextParams(-1.0, 0.7, 5.0, GetRandomInt(0, 255), GetRandomInt(0, 255), GetRandomInt(0, 255), 255, 1, 5.0, 2.0, 2.0);
	(Player[client].isNew) ? ShowSyncHudText(client, Synch, "%t", "Welcome", ClientName) : ShowSyncHudText(client, Synch, "%t", "WelcomeBack", ClientName);
	return Plugin_Continue;
}

/* Save the playtime of the player on disconnection */
public void OnClientDisconnect(int client) {
	if (!IsEntityConnectedClient(client) || IsFakeClient(client)) return;
	char Query[255];
	int finaltime = Player[client].playtime + GetTime() - Player[client].timeAtConnection;
	Format(Query, sizeof(Query), "UPDATE `dbstats` SET playtime = %i WHERE steamid = '%s';", finaltime, GetSteamId(client));
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

/* COMMAND RANK */
public Action CMD_Rank(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	// Check if client is flooding
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char Query[255];
		//Rank count
		Format(Query, sizeof(Query), "SELECT COUNT(*) FROM `dbstats`;");
		SQL_TQuery(db, SQL_RankCount, Query);
		Format(Query, sizeof(Query), "SELECT COUNT(*) FROM (SELECT steamid, points FROM `dbstats` WHERE points >= %i ORDER BY points ASC) as rank;", Player[client].points);
		SQL_TQuery(db, SQL_StatsCallback, Query, GetClientUserId(client));
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

public void SQL_RankCount(Handle owner, Handle query, const char[] error, any data) {
	if (query == null) {
		SetFailState("Query failed! %s", error);
	} else {
		SQL_FetchRow(query);
		rankcount = SQL_FetchInt(query, 0);
	}
}

public void SQL_StatsCallback(Handle owner, Handle query, const char[] error, any data) {
	if (query == null) {
		SetFailState("Query failed! %s", error);
	} else {
		SQL_FetchRow(query);
		int i = SQL_FetchInt(query, 0);

		int client = GetClientOfUserId(data);

		float kpd = float(Player[client].kills) / float(Player[client].deaths);
		int clienttime = Player[client].playtime + GetTime() - Player[client].timeAtConnection;
		int topspeedMph = RoundFloat(Player[client].actualtopspeed * 0.042614);

		char buffer[255], menutitle[64], name[64];
		cvar_MenuTitle.GetString(menutitle, sizeof(menutitle));
		SetGlobalTransTarget(client);

		/* Panel */
		Handle panel = CreatePanel();
		SetPanelTitle(panel, menutitle);

		Format(buffer, sizeof(buffer), "%t", "Rank", i, RankNumber(client, i), rankcount, RankNumber(client, rankcount));
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Points", Player[client].points);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Kills", Player[client].kills);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Deaths", Player[client].deaths);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Kpd", kpd);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Playtime", GetPlayerPlaytime(client, clienttime));
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Topspeed", topspeedMph);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Topdeflections", Player[client].actualtopdeflections);
		DrawPanelText(panel, buffer);

		DrawPanelItem(panel, "Close");
		SendPanelToClient(panel, client, PanelHandlerNothing, 30);
		CloseHandle(panel);

		GetClientName(client, name, sizeof(name));
		for (int iClients = 1; iClients <= MaxClients; iClients++) {
			if (IsEntityConnectedClient(iClients) && !IsFakeClient(iClients)) {
				CPrintToChat(iClients, "%t", "RankPhrase", ServerTag, name, i, RankNumber(iClients, i), rankcount, Player[client].points);
			}
		}
	}
}

/* COMMAND TOP X */
public Action CMD_Top(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char Query[255], arg[128];

		GetCmdArg(1, arg, sizeof(arg));
		Player[client].topNumber = StringToInt(arg);

		if (args < 1 || args > 1 || Player[client].topNumber < 1 || Player[client].topNumber > 100) {
			ReplyToCommand(client, "%s Usage: /top <number> or !top <number>.\nExample: /top 25 (Max 100)", ServerTag);
			return Plugin_Handled;
		}
		Format(Query, sizeof(Query), "SELECT steamid, name, points FROM `dbstats` ORDER BY points DESC LIMIT 0, %i;", Player[client].topNumber);
		SQL_TQuery(db, SQL_TopCallback, Query, GetClientUserId(client));
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

public void SQL_TopCallback(Handle owner, Handle query, const char[] error, any data) {
	if (query == null) {
		SetFailState("Query failed! %s", error);
	} else {
		int client = GetClientOfUserId(data);
		if (!IsEntityConnectedClient(client)) return;

		char name[64], steamid[32], toptitle[64], buffer[255];
		cvar_TopTitle.GetString(toptitle, sizeof(toptitle));
		
		int i = 0;

		// Create Menu
		Menu menu = new Menu(TopMenu, MenuAction_Select|MenuAction_End);
		menu.SetTitle(toptitle);
		while (SQL_FetchRow(query)) {
			i++; // Count for RankNumber
			// Fetch steamid, name and points
			SQL_FetchString(query, 0, steamid, sizeof(steamid));
			SQL_FetchString(query, 1, name, sizeof(name));
			int playerpoints = SQL_FetchInt(query, 2);

			Format(buffer, sizeof(buffer), "#%i%s - %s - %i points", i, RankNumber(client, i), name, playerpoints);
			menu.AddItem(steamid, buffer);
		}

		menu.ExitButton = true;
		menu.Display(client, 30);
	}
}

public int TopMenu(Menu menu, MenuAction action, int client, int param2) {
	switch (action) {
		case MenuAction_Select: {
			char Query[255], steamid[32];
			menu.GetItem(param2, steamid, sizeof(steamid));

			Format(Query, sizeof(Query), "SELECT steamid, name, points, kills, deaths, playtime, topspeed, topdeflections FROM `dbstats` WHERE steamid = '%s';", steamid);
			SQL_TQuery(db, SQL_UserCallback, Query, GetClientUserId(client));
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

public void SQL_UserCallback(Handle owner, Handle query, const char[] error, any data) {
	if (query == null) {
		SetFailState("Query failed! %s", error);
	}

	int client = GetClientOfUserId(data);
	if (!IsEntityConnectedClient(client)) return;

	char buffer[255], name[64], steamid[32];
	int points, kills, deaths, playtime, topspeed, topdeflections;

	SQL_FetchRow(query);
	SQL_FetchString(query, 0, steamid, sizeof(steamid));
	SQL_FetchString(query, 1, name, sizeof(name));

	points = SQL_FetchInt(query, 2);
	kills = SQL_FetchInt(query, 3);
	deaths = SQL_FetchInt(query, 4);
	playtime = SQL_FetchInt(query, 5);
	topspeed = SQL_FetchInt(query, 6);
	topdeflections = SQL_FetchInt(query, 7);

	float kpd = float(kills) / float(deaths);
	topspeed = RoundFloat(topspeed * 0.042614);

	SetGlobalTransTarget(client);

	Menu menu = new Menu(MenuHandlerBack, MenuAction_Cancel|MenuAction_End);
	menu.SetTitle("%s", name);

	Format(buffer, sizeof(buffer), "%t", "Username", name);
	menu.AddItem("name", buffer);
	
	Format(buffer, sizeof(buffer), "SteamID: %s", steamid);
	menu.AddItem("steamid", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Points", points);
	menu.AddItem("points", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Kills", kills);
	menu.AddItem("kills", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Deaths", deaths);
	menu.AddItem("deaths", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Kpd", kpd);
	menu.AddItem("kpd", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Playtime", GetPlayerPlaytime(client, playtime));
	menu.AddItem("playtime", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Topspeed", topspeed);
	menu.AddItem("topspeed", buffer);
	
	Format(buffer, sizeof(buffer), "%t", "Topdeflections", topdeflections);
	menu.AddItem("topdeflections", buffer);

	menu.ExitBackButton = true;
	menu.ExitButton = true;

	menu.Display(client, 30);
}

public int MenuHandlerBack(Menu menu, MenuAction action, int client, int param2) {
	switch (action) {
		case MenuAction_Cancel: {
			if (param2 == MenuCancel_ExitBack) {
				char Query[255];
				Format(Query, sizeof(Query), "SELECT steamid, name, points, topspeed, topdeflections FROM `dbstats` ORDER BY points DESC LIMIT 0, %i;", Player[client].topNumber);
				SQL_TQuery(db, SQL_TopCallback, Query, GetClientUserId(client));
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

/* COMMAND RESETSTATS */
public Action CMD_ResetStats(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char display[255];
		SetGlobalTransTarget(client);
		// Create Menu
		Menu resetmenu = new Menu(MenuResetHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End);
		// Title
		resetmenu.SetTitle("%t", "ResetTitle");
		// Menu choices
		Format(display, sizeof(display), "%t", "ResetYes");
		resetmenu.AddItem(YES, display);
		Format(display, sizeof(display), "%t", "ResetNo");
		resetmenu.AddItem(NO, display);
		// SetMenuExitButton
		resetmenu.ExitButton = true;
		// DisplayMenu to the client
		resetmenu.Display(client, 20);
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

public int MenuResetHandler(Menu menu, MenuAction action, int client, int item) {
	switch (action) {
		case MenuAction_Select: {
			char Query[255], info[32], name[64];
			GetClientName(client, name, sizeof(name));
			menu.GetItem(item, info, sizeof(info));
			if (StrEqual(info, YES)) {
				CPrintToChat(client, "%t", "ResetPhrase_Yes", ServerTag, name);
				//Reset stats from database
				Format(Query, sizeof(Query), "UPDATE `dbstats` SET points = 1000, kills = 0, deaths = 0, playtime = 0, topspeed = 0, topdeflections = 0 WHERE steamid = '%s'", GetSteamId(client));
				SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
				Player[client].points = 1000;
				Player[client].kills = 0;
				Player[client].deaths = 0;
				Player[client].playtime = 0 - RoundToFloor(GetClientTime(client));
				Player[client].actualtopspeed = 0;
				Player[client].actualtopdeflections = 0;
			} else {
				CPrintToChat(client, "%t", "ResetPhrase_No", ServerTag, name);
			}
		}
		case MenuAction_End: {
			delete menu;
		}
	}
	return 0;
}

/* CMD KPD */
public Action CMD_Kpd(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		float kpd = float(Player[client].kills) / float(Player[client].deaths);
		CPrintToChatAll("%t", "KpdPhrase", ServerTag, name, kpd);
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

/* CMD POINTS */
public Action CMD_Points(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		CPrintToChatAll("%t", "PointsPhrase", ServerTag, name, Player[client].points);
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

/* CMD TOPSPEED */
public Action CMD_TopSpeed(int client, int args) {
	if (!IsEntityConnectedClient(client)) return Plugin_Handled;
	// Delay
	int TimeRest = GetTime() - Player[client].lastTimeUsedCmd;
	int antiFloodRest = cvar_AntiFloodSeconds.IntValue - TimeRest;
	int topspeedMph = RoundFloat(Player[client].actualtopspeed * 0.042614);
	if (!IsClientFlooding(client, Player[client].lastTimeUsedCmd)) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		CPrintToChatAll("%t", "TopSpeedPhrase", ServerTag, name, topspeedMph, Player[client].actualtopspeed);
	} else {
		CPrintToChat(client, "%t", "NoFlood", ServerTag, antiFloodRest);
	}
	return Plugin_Handled;
}

/* Register new topspeed, topdeflections */
public Action GetDodgeballStats(int client, int args) {
	if (args == 4) {
		char arg1[128], arg2[128], arg3[128], arg4[128];
		int deflections, owner, target;
		// Get stats
		/* Note: 
		This works only if the event "on deflect" is choosen in general.cfg.
		Anyway all player stats are mostly updated on death so it will not 
		update at each deflection. */
		oldspeed = newspeed;
		
		GetCmdArg(1, arg1, sizeof(arg1)); newspeed = StringToInt(arg1, 10); // newspeed
		GetCmdArg(2, arg2, sizeof(arg2)); deflections = StringToInt(arg2, 10); // deflections
		GetCmdArg(3, arg3, sizeof(arg3)); owner = StringToInt(arg3, 10); // owner
		GetCmdArg(4, arg4, sizeof(arg4)); target = StringToInt(arg4, 10); // target
		
		if (IsEntityConnectedClient(owner) && IsEntityConnectedClient(target) && !IsFakeClient(owner) && !IsFakeClient(target)) {
			Player[owner].realTimetopspeed = newspeed; 
			Player[owner].realTimetopdeflections = deflections;
			Player[target].realTimetopspeed = oldspeed; 
			Player[target].realTimetopdeflections = (deflections > 0) ? deflections - 1 : deflections;
			
			// Update Owner
			if (Player[owner].realTimetopspeed > Player[owner].actualtopspeed) {
				Player[owner].actualtopspeed = Player[owner].realTimetopspeed;
			}
			if (Player[owner].realTimetopdeflections > Player[owner].actualtopdeflections) {
				Player[owner].actualtopdeflections = Player[owner].realTimetopdeflections;
			}
			// Update Target
			if (Player[target].realTimetopspeed > Player[target].actualtopspeed) {
				Player[target].actualtopspeed = Player[target].realTimetopspeed;
			}
			if (Player[target].realTimetopdeflections > Player[target].actualtopdeflections) {
				Player[target].actualtopdeflections = Player[target].realTimetopdeflections; 
			}
		}
	}
	return Plugin_Handled;
}

/* On client kill or death add points and +1 at death or kills */
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	char AttackerName[32], VictimName[32];
	newspeed = 0; 
	oldspeed = 0;
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	GetClientName(attacker, AttackerName, sizeof(AttackerName));
	GetClientName(victim, VictimName, sizeof(VictimName));

	if (IsEntityConnectedClient(attacker) && IsEntityConnectedClient(victim) && !IsFakeClient(attacker) && !IsFakeClient(victim) && victim != attacker) {
		Player[attacker].points += cvar_OnKillPoints.IntValue; Player[attacker].kills++; Player[victim].deaths++;
		// Update stats of the victim if his points are > 1000
		if (Player[victim].points > 1000) {
			Player[victim].points -= cvar_OnDeathPoints.IntValue;
			CPrintToChat(victim, "%t", "VictimDeathPoints", ServerTag, AttackerName, Player[victim].points);
		} else {
			CPrintToChat(victim, "%t", "VictimDeathNoPoints", ServerTag, AttackerName, Player[victim].points);
		}
		CPrintToChat(attacker, "%t", "AttackerKill", ServerTag, VictimName, Player[attacker].points);

		SQLUpdateStats(attacker);
		SQLUpdateStats(victim);
	}
}

/* Update player stats */
void SQLUpdateStats(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "UPDATE `dbstats` SET points = %i, kills = %i, deaths = %i, topspeed = %i, topdeflections = %i WHERE steamid = '%s'", 
	Player[client].points, Player[client].kills, Player[client].deaths, Player[client].actualtopspeed, Player[client].actualtopdeflections, GetSteamId(client));
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

public int PanelHandlerNothing(Menu menu, MenuAction action, int param1, int param2) {
	//Nothing
}

/* Error Callback */
public void SQL_ErrorCheckCallBack(Handle owner, Handle query, const char[] error, any data) {
	// This is just an errorcallback for function who normally don't return any data
	if (query == null) {
		SetFailState("Query failed! %s", error);
	}
}

/* FUNCTIONS */

void GetDriver(Handle database) {
	char error[255], identity[16];
	// Get the driver
	Handle Driver = SQL_ReadDriver(database);
	// Get it's identity
	SQL_GetDriverIdent(Driver, identity, sizeof(identity));

	if (strcmp(identity, "sqlite", false) == 0) {
		IsSQLite = true;
	} else if (strcmp(identity, "mysql", false) == 0) {
		IsSQLite = false;
	} else {
		SetFailState(error);
	}
}

char GetEscapedName(int client) {
	char name[64], EscapedName[64*2+1];
	if (IsEntityConnectedClient(client)) {
		GetClientName(client, name, sizeof(name));
		SQL_EscapeString(db, name, EscapedName, sizeof(EscapedName));
	}
	return EscapedName;
}

char GetSteamId(int client) {
	char SteamID[32];
	if (IsEntityConnectedClient(client)) {
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID), true);
	}
	return SteamID;
}

char RankNumber(int client, int i) {
	char rankplace[32];
	// Modulo
	int j = i % 10;
	int k = i % 100;

	SetGlobalTransTarget(client);
	// Switch with the rest
	switch (j) {
		case 1: {
			if (k != 11) {	
				Format(rankplace, sizeof(rankplace), "%t", "st");
			}	
		}
		case 2: {
			if (k != 12) {
				Format(rankplace, sizeof(rankplace), "%t", "nd");	
			}
		}
		case 3: {	
			if (k != 13) {
				Format(rankplace, sizeof(rankplace), "%t", "rd");	
			}
		}
		default: { 
			Format(rankplace, sizeof(rankplace), "%t", "th"); 
		}
	}
	return rankplace;
}

char GetPlayerPlaytime(int client, int value) {
	char FinalPlayTime[255];

	int secs = value % 60,
 	mins = value / 60,
	hours = 0,
	days = 0;
	// Calculate days & hours
	if (mins > 59) {
		hours = mins / 60;
		mins = mins % 60;
	}
	if (hours > 23) {
		days = hours / 24;
		hours = hours % 24;
	}
	/* Format */
	SetGlobalTransTarget(client);
	Format(FinalPlayTime, sizeof(FinalPlayTime), "%t", "ModuloPlaytimeLang", days, hours, mins, secs);
	return FinalPlayTime;
}

bool IsClientFlooding(int client, int lasttimeused) {
	int currenttime = GetTime();
	if (currenttime - lasttimeused < cvar_AntiFloodSeconds.IntValue) {
		return true;
	}
	Player[client].lastTimeUsedCmd = currenttime;
	return false;
}

stock bool IsEntityConnectedClient(int entity) {
    return 0 < entity <= MaxClients && IsClientInGame(entity);
}

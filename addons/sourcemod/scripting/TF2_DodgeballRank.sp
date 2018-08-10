#pragma semicolon 1

#include <sourcemod>
#include <morecolors>
#pragma newdecls required

public Plugin myinfo = {
	name = "[TF2] Dodgeball Rank",
	author = "Walgrim",
	description = "TF2 Ranking system for dodgeball !",
	version = "1.0",
	url = "http://steamcommunity.com/id/walgrim/"
};

/* CVARS */
Handle cvar_ServerTag = null;
Handle cvar_MenuTitle = null;
Handle cvar_Top10Title = null;
Handle cvar_AntiFloodSeconds = null;

/* DATABASE */
Handle db = null;

/* SQLITE */
bool IsSQLite;

/* STATS */
int rankcount;
int points[MAXPLAYERS + 1];
int kills[MAXPLAYERS + 1];
int deaths[MAXPLAYERS + 1];
int playtime[MAXPLAYERS + 1];

/* SETTINGS */
int lastTimeUsedCmd[MAXPLAYERS + 1];
bool IsClientNew[MAXPLAYERS + 1];

/****************************************/
char ServerTag[64];

/* MENU */
#define YES "#choice1"
#define NO "#choice2"

public void OnPluginStart() {
	/* Load Translations */
	LoadTranslations("dodgeballrank.phrases");

	/* CVARS LIST */
	cvar_ServerTag = CreateConVar("dodgeball_servertag", "[Rank]", "Sets your server tag");
	cvar_MenuTitle = CreateConVar("dodgeball_rankmenutitle", "[Rank Title]", "Sets the title of the menu");
	cvar_Top10Title = CreateConVar("dodgeball_top10title", "[Top 10 Title]", "Sets the title of the top 10 menu");
	cvar_AntiFloodSeconds = CreateConVar("dodgeball_antifloodseconds", "5", "Seconds that have the player to wait before showing again his stats");


	/* Reg console commands */
	RegConsoleCmd("sm_rank", CMD_Rank, "Rank CMD to display the panel");
	RegConsoleCmd("sm_top10", CMD_Top10, "Top 10 CMD to display the panel");
	RegConsoleCmd("sm_kpd", CMD_Kpd, "Command to get the kpd of the player");
	RegConsoleCmd("sm_points", CMD_Points, "Command to get the points of the player");
	RegConsoleCmd("sm_resetrank", CMD_ResetRank, "Command to reset the rank");

	/* Hook players deaths */
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);
	/* Create the cfg file */
	AutoExecConfig(true, "DodgeballRank");
	/* Start Database */
	StartDB();
}

public void OnConfigsExecuted() {
	GetConVarString(cvar_ServerTag, ServerTag, sizeof(ServerTag));
}

/* Start Database */
void StartDB() {
	//Buffer for error messages & the query
	char error[255], Query[255];
	//Connect to the database
	if (SQL_CheckConfig("db_rank")) {
		db = SQL_Connect("db_rank", true, error, sizeof(error));
	} else {
		// KeyValues
		Handle kv = CreateKeyValues("db_rank");
		KvSetString(kv, "driver", "sqlite");
		KvSetString(kv, "database", "db_sqliterank");

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
		Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `dbstats` (name TEXT NOT NULL, steamid TEXT UNIQUE NOT NULL, points INTEGER NOT NULL, kills INTEGER NOT NULL, deaths INTEGER NOT NULL, playtime INTEGER NOT NULL);");
	} else {
		// The NOT NULL constraint enforces a column to NOT accept NULL values.
		Format(Query, sizeof(Query), "CREATE TABLE IF NOT EXISTS `dbstats` (name varchar(64) NOT NULL, steamid varchar(32) NOT NULL, points int(10) NOT NULL, kills int(8) NOT NULL, deaths int(8) NOT NULL, playtime int(8) NOT NULL);");
	}

	// Avoid Corruption, lock database
	SQL_LockDatabase(db);
	// Execute the query
	SQL_FastQuery(db, Query);
	// Database unlock
	SQL_UnlockDatabase(db);
}

/* Client put in server */
public void OnClientPutInServer(int client) {
	if (IsValidClient(client)) {
		UpdateOrCreatePlayerToDB(client);
	}
}

/* Update or Create the player row */
void UpdateOrCreatePlayerToDB(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "SELECT points, kills, deaths, playtime FROM `dbstats` WHERE steamid = '%s';", GetSteamId(client));
	SQL_TQuery(db, SQL_HandlePlayer, Query, GetClientUserId(client));
}

public void SQL_HandlePlayer(Handle owner, Handle hndl, const char[] error, any data) {
	if (hndl == null) {
		SetFailState("Query failed! %s", error);
	} else {
		int client = GetClientOfUserId(data);
		/* Wanted to use SQL_GetAffectedRows but unfortunaly it doesn't work with sqlite
			 see this thread: https://stackoverflow.com/questions/37911888/the-number-of-changed-rows-rows-affected-is-always-1-with-sqlite-android */
		if (!SQL_MoreRows(hndl)) {
			AddPlayerToDB(client);
			IsClientNew[client] = true;
		} else {
			UpdatePlayerToDB(client);
			IsClientNew[client] = false;
			//Fetch rows
			SQL_FetchRow(hndl);
			points[client] = SQL_FetchInt(hndl, 0);
			kills[client] = SQL_FetchInt(hndl, 1);
			deaths[client] = SQL_FetchInt(hndl, 2);
			playtime[client] = SQL_FetchInt(hndl, 3);
		}
		CreateTimer(10.0, WelcomeOrWb, GetClientUserId(client));
	}
}

/* When we know, if the player is new or not, Add it or Update his datas */
void AddPlayerToDB(int client) {
	char Query[255];

	if (IsSQLite) {
		Format(Query, sizeof(Query), "INSERT INTO `dbstats` VALUES('%s', '%s', 1000, 0, 0, 0);", GetEscapedName(client), GetSteamId(client));
	} else {
		Format(Query, sizeof(Query), "INSERT INTO `dbstats` (steamid, name, points, kills, deaths, playtime) VALUES ('%s', '%s', 1000, 0, 0, 0);", GetSteamId(client), GetEscapedName(client));
	}
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);

	points[client] = 1000;
	kills[client] = 0;
	deaths[client] = 0;
	playtime[client] = 0;
}

void UpdatePlayerToDB(int client) {
	char Query[255];

	Format(Query, sizeof(Query), "UPDATE `dbstats` SET name = '%s' WHERE steamid = '%s';", GetEscapedName(client), GetSteamId(client));
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

/* Welcome/wb the client */
public Action WelcomeOrWb(Handle Timer, int clientid) {
	char ClientName[64];
	int client = GetClientOfUserId(clientid);
	if (client == 0)
		return Plugin_Handled;
	/* Get Client Name */
	GetClientName(client, ClientName, sizeof(ClientName));
	/* Synchronize Hud and clear it to avoid overwritting */
	Handle Synch = CreateHudSynchronizer();
	ClearSyncHud(client, Synch); // I'm not sure if it goes there
	SetHudTextParams(-1.0, 0.7, 5.0, GetRandomInt(0, 255), GetRandomInt(0, 255), GetRandomInt(0, 255), 255, 1, 5.0, 2.0, 2.0);
	(IsClientNew[client]) ? ShowSyncHudText(client, Synch, "%t", "Welcome", ClientName) : ShowSyncHudText(client, Synch, "%t", "WelcomeBack", ClientName);
	return Plugin_Continue;
}

/* Save the playtime of the player on disconnection */
public void OnClientDisconnect(int client) {
	if (IsValidClient(client)) {
		char Query[255];
		int finaltime = playtime[client] + RoundToFloor(GetClientTime(client));
		Format(Query, sizeof(Query), "UPDATE `dbstats` SET playtime = %i WHERE steamid = '%s';", finaltime, GetSteamId(client));
		SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
	}
}

/* COMMAND RANK */
public Action CMD_Rank(int client, int args) {
	if (IsValidClient(client)) {
		char Query[255];
		//Rank count
		Format(Query, sizeof(Query), "SELECT COUNT(*) FROM `dbstats`;");
		SQL_TQuery(db, SQL_RankCount, Query);

		Format(Query, sizeof(Query), "SELECT COUNT(*) FROM (SELECT steamid, points FROM `dbstats` WHERE points >= %i ORDER BY points ASC) as rank;", points[client]);
		SQL_TQuery(db, SQL_RankCallback, Query, GetClientUserId(client));
	}
	return Plugin_Handled;
}

public void SQL_RankCount(Handle owner, Handle hndl, const char[] error, any data) {
	if (hndl == null) {
		SetFailState("Query failed! %s", error);
	} else {
		SQL_FetchRow(hndl);
		rankcount = SQL_FetchInt(hndl, 0);
	}
}

public void SQL_RankCallback(Handle owner, Handle hndl, const char[] error, any data) {
	if (hndl == null) {
		SetFailState("Query failed! %s", error);
	} else {
		SQL_FetchRow(hndl);
		int i = SQL_FetchInt(hndl, 0);

		int client = GetClientOfUserId(data);
		float kpd = float(kills[client]) / float(deaths[client]);
		int clienttime = playtime[client] + RoundToFloor(GetClientTime(client));

		char buffer[255], menutitle[64], name[64];
		GetConVarString(cvar_MenuTitle, menutitle, sizeof(menutitle));

		/* "Sets the global language target. This is useful for creating functions that will be compatible with the %t format specifier." */
		SetGlobalTransTarget(client);

		/* Panel */
		Handle panel = CreatePanel();
		SetPanelTitle(panel, menutitle);

		Format(buffer, sizeof(buffer), "%t", "Rank", i, RankNumber(client, i), rankcount, RankNumber(client, rankcount));
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Points", points[client]);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Kills", kills[client]);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Deaths", deaths[client]);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Kpd", kpd);
		DrawPanelText(panel, buffer);

		Format(buffer, sizeof(buffer), "%t", "Playtime", GetPlayerPlaytime(client, clienttime));
		DrawPanelText(panel, buffer);

		DrawPanelItem(panel, "Close");
		SendPanelToClient(panel, client, PanelHandlerNothing, 30);
		CloseHandle(panel);

		int TimeRest = GetTime() - lastTimeUsedCmd[client];
		if (!IsClientFlooding(client, lastTimeUsedCmd[client])) {
			GetClientName(client, name, sizeof(name));
			CPrintToChatAll("%t", "RankPhrase", ServerTag, name, i, RankNumber(client, i), rankcount, points[client]);
		} else {
			CPrintToChat(client, "%t", "NoFlood", ServerTag, GetConVarInt(cvar_AntiFloodSeconds) - TimeRest);
		}
	}
}

/* COMMAND TOP10 */
public Action CMD_Top10(int client, int args) {
	if (IsValidClient(client)) {
		char Query[255];
		Format(Query, sizeof(Query), "SELECT name, points FROM `dbstats` ORDER BY points DESC LIMIT 0, 10;");
		SQL_TQuery(db, SQL_Top10Callback, Query, GetClientUserId(client));
	}
	return Plugin_Handled;
}

public void SQL_Top10Callback(Handle owner, Handle hndl, const char[] error, any data) {
	if (hndl == null) {
		SetFailState("Query failed! %s", error);
	} else {
		char name[64], top10title[64], buffer[255];
		GetConVarString(cvar_Top10Title, top10title, sizeof(top10title));

		int client = GetClientOfUserId(data);
		int i = 0;
		// Create Panel
		Handle panel = CreatePanel();
		SetPanelTitle(panel, top10title);
		while (SQL_FetchRow(hndl)) {
			i++;
			SQL_FetchString(hndl, 0, name, sizeof(name));
			int playerpoints = SQL_FetchInt(hndl, 1);
			Format(buffer, sizeof(buffer), "#%i%s - %s - %i points", i, RankNumber(client, i), name, playerpoints);
			DrawPanelText(panel, buffer);
		}
		DrawPanelItem(panel, "Close");
		SendPanelToClient(panel, client, PanelHandlerNothing, 30);
		CloseHandle(panel);
	}
}

/* COMMAND RESETRANK */
public Action CMD_ResetRank(int client, int args) {
	if (IsValidClient(client)) {
		char display[255];
		/* "Sets the global language target. This is useful for creating functions that will be compatible with the %t format specifier." */
		SetGlobalTransTarget(client);
		// Create Menu
		Handle resetmenu = CreateMenu(MenuResetHandler, MenuAction_Select|MenuAction_Cancel|MenuAction_End);
		// Title
		SetMenuTitle(resetmenu, "%t", "ResetTitle");
		// Menu choices
		Format(display, sizeof(display), "%t", "ResetYes");
		AddMenuItem(resetmenu, YES, display);

		Format(display, sizeof(display), "%t", "ResetNo");
		AddMenuItem(resetmenu, NO, display);
		// SetMenuExitButton
		SetMenuExitButton(resetmenu, true);
		// DisplayMenu to the client
		DisplayMenu(resetmenu, client, 20);
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
				Format(Query, sizeof(Query), "UPDATE `dbstats` SET points = 1000, kills = 0, deaths = 0, playtime = 0 WHERE steamid = '%s'", GetSteamId(client));
				SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
				points[client] = 1000;
				kills[client] = 0;
				deaths[client] = 0;
				playtime[client] = 0 - RoundToFloor(GetClientTime(client));
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
	if (IsValidClient(client)) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		int TimeRest = GetTime() - lastTimeUsedCmd[client];

		if (!IsClientFlooding(client, lastTimeUsedCmd[client])) {
			float kpd = float(kills[client]) / float(deaths[client]);
			CPrintToChatAll("%t", "KpdPhrase", ServerTag, name, kpd);
		} else {
			CPrintToChat(client, "%t", "NoFlood", ServerTag, GetConVarInt(cvar_AntiFloodSeconds) - TimeRest);
		}
	}
	return Plugin_Handled;
}

/* CMD POINTS */
public Action CMD_Points(int client, int args) {
	if (IsValidClient(client)) {
		char name[64];
		GetClientName(client, name, sizeof(name));
		int TimeRest = GetTime() - lastTimeUsedCmd[client];

		if (!IsClientFlooding(client, lastTimeUsedCmd[client])) {
			CPrintToChatAll("%t", "PointsPhrase", ServerTag, name, points[client]);
		}	else {
			CPrintToChat(client, "%t", "NoFlood", ServerTag, GetConVarInt(cvar_AntiFloodSeconds) - TimeRest);
		}
	}
	return Plugin_Handled;
}

/* On client kill or death add points and +1 at death or kills */
public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	char AttackerName[32], VictimName[32];
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	GetClientName(attacker, AttackerName, sizeof(AttackerName));
	GetClientName(victim, VictimName, sizeof(VictimName));

	if (IsValidClient(attacker) && IsValidClient(victim) && victim != attacker) {
		points[attacker] += 8; kills[attacker]++; deaths[victim]++;
		//Update stats of the victim if his points are >= 1008
		if (points[victim] >= 1008) {
			points[victim] -= 8;
			CPrintToChat(victim, "%t", "VictimDeathPoints", ServerTag, AttackerName, points[victim]);
		} else {
			CPrintToChat(victim, "%t", "VictimDeathNoPoints", ServerTag, AttackerName, points[victim]);
		}
		CPrintToChat(attacker, "%t", "AttackerKill", ServerTag, VictimName, points[attacker]);

		SQLUpdateStats(attacker);
		SQLUpdateStats(victim);
	}
}

void SQLUpdateStats(int client) {
	char Query[255];
	Format(Query, sizeof(Query), "UPDATE `dbstats` SET points = %i, kills = %i, deaths = %i WHERE steamid = '%s'", points[client], kills[client], deaths[client], GetSteamId(client));
	SQL_TQuery(db, SQL_ErrorCheckCallBack, Query);
}

public int PanelHandlerNothing(Menu menu, MenuAction action, int param1, int param2) {
	//Nothing
}

/* Error Callback */
public void SQL_ErrorCheckCallBack(Handle owner, Handle hndl, const char[] error, any data) {
	// This is just an errorcallback for function who normally don't return any data
	if (hndl == null) {
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
	if (IsValidClient(client)) {
		GetClientName(client, name, sizeof(name));
		SQL_EscapeString(db, name, EscapedName, sizeof(EscapedName));
	}
	return EscapedName;
}

char GetSteamId(int client) {
	char SteamID[32];
	if (IsValidClient(client)) {
		GetClientAuthId(client, AuthId_Steam2, SteamID, sizeof(SteamID), true);
	}
	return SteamID;
}

char RankNumber(int client, int i) {
	char rankplace[32];
	/* "Sets the global language target. This is useful for creating functions that will be compatible with the %t format specifier." */
	SetGlobalTransTarget(client);
	// Modulo
	int j = i % 10;
	// Switch with the rest
	switch (j) {
		case 1: {	Format(rankplace, sizeof(rankplace), "%t", "st");	}
		case 2: {	Format(rankplace, sizeof(rankplace), "%t", "nd");	}
		case 3: {	Format(rankplace, sizeof(rankplace), "%t", "rd");	}
		default: { Format(rankplace, sizeof(rankplace), "%t", "th"); }
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
	/* "Sets the global language target. This is useful for creating functions that will be compatible with the %t format specifier." */
	SetGlobalTransTarget(client);
	/* Format */
	Format(FinalPlayTime, sizeof(FinalPlayTime), "%t", "ModuloPlaytimeLang", days, hours, mins, secs);
	return FinalPlayTime;
}

bool IsClientFlooding(int client, int lasttimeused) {
	int currenttime = GetTime();
	if (currenttime - lasttimeused < GetConVarInt(cvar_AntiFloodSeconds)) {
		return true;
	}
	lastTimeUsedCmd[client] = currenttime;
	return false;
}

bool IsValidClient(int client) {
	return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}

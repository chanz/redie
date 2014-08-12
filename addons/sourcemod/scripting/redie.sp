/***************************************************************************************

	Copyright (C) 2012 BCServ (plugins@bcserv.eu)

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
	
***************************************************************************************/

/***************************************************************************************


	C O M P I L E   O P T I O N S


***************************************************************************************/
// enforce semicolons after each code statement
#pragma semicolon 1

/***************************************************************************************


	P L U G I N   I N C L U D E S


***************************************************************************************/
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <smlib>
#include <smlib/pluginmanager>


/***************************************************************************************


	P L U G I N   I N F O


***************************************************************************************/
public Plugin:myinfo = {
	name 						= "Redie and be a ghost",
	author 						= "Chanz, MeoW",
	description 				= "Return as a ghost after you died.",
	version 					= "2.13",
	url 						= "https://github.com/chanz/redie"
}

/***************************************************************************************


	P L U G I N   D E F I N E S


***************************************************************************************/
#define LIFESTATE_DEAD 1
#define LIFESTATE_ALIVE 0

/***************************************************************************************


	G L O B A L   V A R S


***************************************************************************************/
// Server Variables


// Plugin Internal Variables


// Console Variables
new Handle:g_cvarEnable 					= INVALID_HANDLE;
new Handle:g_cvarAutoGhostTime				= INVALID_HANDLE;
new Handle:g_cvarGhostTransparency = INVALID_HANDLE;
new Handle:g_cvarHideGhostsFromObservers = INVALID_HANDLE;
new Handle:g_cvarAllTalk = INVALID_HANDLE;

// Console Variables: Runtime Optimizers
new g_iPlugin_Enable 					= 1;
new Float:g_flPlugin_AutoGhostTime	 	= 0.0;
new g_iPlugin_GhostTransparency = 175;
new bool:g_bPlugin_HideGhostsFromObservers = true;
new bool:g_bGame_AllTalk = false;

// Timers


// Library Load Checks


// Game Variables
new bool:g_bHasRoundEnded = false;
new g_iOffset_BaseEntity_CollisionGroup = -1;
new g_iOffset_PlayerResource_Alive = -1;

// Map Variables


// Client Variables
new bool:g_bIsGhost[MAXPLAYERS+1];
new bool:g_bCanPickupWeapons[MAXPLAYERS+1];
new bool:g_bRespawnAsGhost[MAXPLAYERS+1];

// M i s c


/***************************************************************************************


	F O R W A R D   P U B L I C S


***************************************************************************************/
public OnPluginStart()
{
	// Initialization for SMLib
	PluginManager_Initialize("redie", "[SM] ");
	
	// Translations
	LoadTranslations("common.phrases");
	
	
	// Command Hooks (AddCommandListener) (If the command already exists, like the command kill, then hook it!)
	AddCommandListener(CommandListener_Any);
	AddCommandListener(CommandListener_Drop, "drop");
	AddCommandListener(CommandListener_Spec_Next, "spec_next");
	AddCommandListener(CommandListener_Spec_Prev, "spec_prev");
	
	// Register New Commands (PluginManager_RegConsoleCmd) (If the command doesn't exist, hook it here)
	PluginManager_RegConsoleCmd("sm_redie", Command_Redie, "After death you can use this command to respawn as a ghost");
	
	// Register Admin Commands (PluginManager_RegAdminCmd)
	PluginManager_RegAdminCmd("sm_ghost", Command_Ghost, ADMFLAG_BAN, "Forces a player to die and be a ghost");
	
	// Cvars: Create a global handle variable.
	g_cvarEnable = PluginManager_CreateConVar("enable", "1", "Enables or disables this plugin");
	g_cvarAutoGhostTime = PluginManager_CreateConVar("auto_ghost_time", "0", "Time in seconds after a player is auto respawned as ghost after death (0 = disabled)");
	g_cvarGhostTransparency = PluginManager_CreateConVar("ghost_transparency", "175", "Transparency of a player as ghost (0 = invisible; 255 = fully visible)", 0, true, 0.0, true, 255.0);
	g_cvarHideGhostsFromObservers = PluginManager_CreateConVar("hide_ghosts_from_observers", "1", "When set to 1 spectators and dead players observing can't see or follow ghosts", 0, true, 0.0, true, 1.0);

	// Find Cvars
	g_cvarAllTalk = FindConVar("sv_alltalk");

	// Hook ConVar Change
	HookConVarChange(g_cvarEnable, ConVarChange_Enable);
	HookConVarChange(g_cvarAutoGhostTime, ConVarChange_AutoGhostTime);
	HookConVarChange(g_cvarGhostTransparency, ConVarChange_GhostTransparency);
	HookConVarChange(g_cvarHideGhostsFromObservers, ConVarChange_HideGhostsFromObservers);
	HookConVarChange(g_cvarAllTalk, ConVarChange_AllTalk);
	
	// Event Hooks
	PluginManager_HookEvent("round_start", Event_RoundStart);	
	PluginManager_HookEvent("round_end", Event_RoundEnd);
	PluginManager_HookEvent("player_spawn", Event_PlayerSpawn);
	PluginManager_HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	PluginManager_HookEvent("player_footstep", Event_PlayerFootstep, EventHookMode_Pre);

	// Sound Hook
	AddNormalSoundHook(NormalSoundHook_BlockSoundsFromGhosts);
	
	// Library
	
	
	/* Features
	if(CanTestFeatures()){
		
	}
	*/
	
	// Create ADT Arrays
	
	// Get offsets
	g_iOffset_BaseEntity_CollisionGroup = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");
	g_iOffset_PlayerResource_Alive = FindSendPropInfo("CCSPlayerResource", "m_bAlive");
}

public OnPluginEnd()
{
	// Kill ghosts to prevent game play issues.
	ResetAllGhosts();
}

public OnMapStart()
{
	new entity = FindEntityByClassname(0, "cs_player_manager");

	if (!Entity_IsValid(entity)) {

		SetFailState("can't find entity cs_player_manager (%d)", entity);
		return;
	}
	SDKHook(entity, SDKHook_ThinkPost, Hook_ThinkPost_PlayerManager);
}

public OnConfigsExecuted()
{
	// Set your ConVar runtime optimizers here
	g_iPlugin_Enable = GetConVarInt(g_cvarEnable);
	g_flPlugin_AutoGhostTime = GetConVarFloat(g_cvarAutoGhostTime);
	g_iPlugin_GhostTransparency = GetConVarInt(g_cvarGhostTransparency);
	g_bPlugin_HideGhostsFromObservers = GetConVarBool(g_cvarHideGhostsFromObservers);
	g_bGame_AllTalk = GetConVarBool(g_cvarAllTalk);

	// Timers
	CreateTimer(0.1, Timer_UpdateListeners, INVALID_HANDLE, TIMER_REPEAT);
	
	// Mind: this is only here for late load, since on map change or server start, there isn't any client.
	// Remove it if you don't need it.
	Client_InitializeAll();
}

public OnClientPostAdminCheck(client)
{
	Client_Initialize(client);
}

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if(g_bIsGhost[client])
	{
		buttons &= ~IN_USE;
		buttons &= ~IN_ATTACK;
		buttons &= ~IN_ATTACK2;
	}

	return Plugin_Changed;
}

public Action:OnClientSayCommand(client, const String:command[], const String:sArgs[]){

	if (!g_bIsGhost[client]) {
		return Plugin_Continue;
	}

	if (g_bHasRoundEnded) {
		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Please wait for the new round to begin.");
		return Plugin_Handled;
	}
	FlickerLifeState(client, 0.001);
	return Plugin_Continue;
}

/**************************************************************************************


	C A L L B A C K   F U N C T I O N S


**************************************************************************************/
public Action:NormalSoundHook_BlockSoundsFromGhosts(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (Client_IsValid(entity) &&  g_bIsGhost[entity]) {
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public Action:Timer_ResetLifeState(Handle:timer, any:userid)
{
	if (g_bHasRoundEnded) {
		return Plugin_Handled;
	}

	if (userid != -1) {
		new client = GetClientOfUserId(userid);

		if (Client_IsValid(client) && g_bIsGhost[client]) {

			SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_ALIVE);
		}
	}
	else {
		LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {

			if(g_bIsGhost[client]) {

				SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_ALIVE);
			}
		}
	}
	return Plugin_Continue;
}

public Action:Timer_TakeWeapons(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	
	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	Client_RemoveAllWeapons(client);
	g_bCanPickupWeapons[client] = false;
	return Plugin_Continue;
}

public Action:Timer_AutoGhostSpawn(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);

	if (!Client_IsValid(client)) {
		return Plugin_Handled;
	}

	if (g_bHasRoundEnded) {
		return Plugin_Handled;
	}

	if (IsPlayerAlive(client)) {
		return Plugin_Handled;
	}

	if(GetClientTeam(client) <= 1) {
		return Plugin_Handled;
	}

	g_bRespawnAsGhost[client] = true;
	CS_RespawnPlayer(client);

	Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Auto ghost respawn enabled: You are now a ghost.");
	return Plugin_Handled;
}

public Action:Timer_UpdateListeners(Handle:timer) {

	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	// Disable if all talk is on
	if (g_bGame_AllTalk) {
		return Plugin_Continue;
	}

	// We will invert all listeners as if the ghosts are marked dead by the game engine
	LOOP_CLIENTS(receiver, CLIENTFILTER_INGAMEAUTH) {

		new receiverTeam = GetClientTeam(receiver);
		LOOP_CLIENTS(sender, CLIENTFILTER_INGAMEAUTH) {

			// Skip the receiver himself
			if (receiver == sender) {
				continue;
			}

			SetListenOverride(receiver, sender, Listen_Default);

			// If a ghost listens....
			if (g_bIsGhost[receiver]) {

				// the sender is alive or a ghost an in the same team, then allow listening
				if (GetClientTeam(sender) == receiverTeam) {

					SetListenOverride(receiver, sender, Listen_Yes);
				}
				else {
					// the sender is alive or not on the same team, then disallow listening
					SetListenOverride(receiver, sender, Listen_No);
				}
			}

			// If the sender is a ghost...
			if (g_bIsGhost[sender]) {
				
				// only dead players or other ghosts on the same team can listen
				if ((!IsPlayerAlive(receiver) || g_bIsGhost[receiver]) && GetClientTeam(sender) == receiverTeam) {

					SetListenOverride(receiver, sender, Listen_Yes);
				}
				else {

					// alive players and the other team can't listen
					SetListenOverride(receiver, sender, Listen_No);
				}
			}
		}
	}

	return Plugin_Changed;
}
/**************************************************************************************

	S D K   H O O K

**************************************************************************************/
public Hook_ThinkPost_PlayerManager(entity)
{
	if (g_iPlugin_Enable == 0) {
		return;
	}

	LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {

		if(g_bIsGhost[client]) {

			SetEntData(entity, (g_iOffset_PlayerResource_Alive+client*4), 0, 1, true);
		}
	}
}

public Action:Hook_SetTransmit_Client(entity, client)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	// Information to yourself are always transmitted
	if (entity == client) {
		return Plugin_Continue;
	}

	// Ghosts can see other ghosts
	if (g_bIsGhost[entity] && g_bIsGhost[client]) {
		return Plugin_Continue;
	}

	// If a player is not alive then...
	if (g_bIsGhost[entity] && !IsPlayerAlive(client)) {

		// If the cvar redie_hide_ghosts_from_spectators then the transmit is handled (stopped)
		return g_bPlugin_HideGhostsFromObservers ? Plugin_Handled : Plugin_Continue;
	}

	// To anyone else: as long I'm ghost you can't see me.
	if (g_bIsGhost[entity]) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:Hook_WeaponCanUse_Client(client, weapon)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!g_bCanPickupWeapons[client]) {
		return Plugin_Handled;
	}

	if (g_bIsGhost[client] && g_bHasRoundEnded) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:Hook_OnTakeDamage_Client(victim, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[victim]) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}
/**************************************************************************************

	C O N  V A R  C H A N G E

**************************************************************************************/

public ConVarChange_Enable(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_iPlugin_Enable = StringToInt(newVal);

	if (g_iPlugin_Enable == 0) {
		ResetAllGhosts();
	}
}

public ConVarChange_AutoGhostTime(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_flPlugin_AutoGhostTime = StringToFloat(newVal);
}

public ConVarChange_GhostTransparency(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_iPlugin_GhostTransparency = StringToInt(newVal);
}

public ConVarChange_HideGhostsFromObservers(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_bPlugin_HideGhostsFromObservers = bool:StringToInt(newVal);
}

public ConVarChange_AllTalk(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_bGame_AllTalk = bool:StringToInt(newVal);
}

/**************************************************************************************

	C O M M A N D S

**************************************************************************************/
/* Example Command Callback
public Action:Command_(client, args)
{
	
	return Plugin_Handled;
}
*/
public Action:CommandListener_Any(client, const String:command[], argc)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	if (!Client_IsAdmin(client)) {
		return Plugin_Continue;
	}

	//PrintToChatAll("client:%d: %s", client, command);

	decl String:cmd[256];
	GetCmdArgString(cmd, sizeof(cmd));

	if (StrContains(cmd, "@dead", false) == -1 && StrContains(cmd, "@alive", false) == -1) {
		return Plugin_Continue;
	}

	// If there is any command which uses @dead or @alive we set the life states back to prevent that ghosts are treated as alive players.
	FlickerLifeState();
	return Plugin_Continue;
}

public Action:CommandListener_Drop(client, const String:command[], argc)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[client]) {
		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N} You can't drop weapons as ghost");
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:CommandListener_Spec_Next(client, const String:command[], argc)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!g_bPlugin_HideGhostsFromObservers) {
		return Plugin_Continue;
	}

	if (!g_bIsGhost[client] && !IsPlayerAlive(client)) {
		
		new observed = GetNextObservTarget(client);
		new nextObserved = GetNextObservTarget(client, observed);

		if (Client_IsValid(observed) && g_bIsGhost[observed]) {

			if (Client_IsValid(nextObserved) && !g_bIsGhost[nextObserved]) {

				// Set the next observer target that is not a ghost and prevent the command spec_next from switchen the target too.
				Client_SetObserverTarget(client, nextObserved);
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action:CommandListener_Spec_Prev(client, const String:command[], argc)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!g_bPlugin_HideGhostsFromObservers) {
		return Plugin_Continue;
	}

	if (!g_bIsGhost[client] && !IsPlayerAlive(client)) {
		
		new observed = GetPreviousObservTarget(client);
		new prevObserved = GetPreviousObservTarget(client, observed);

		if (Client_IsValid(observed) && g_bIsGhost[observed]) {
			
			if (!g_bIsGhost[prevObserved] && Client_IsValid(prevObserved)) {

				// Set the previous observer target that is not a ghost and prevent the command spec_next from switchen the target too.
				Client_SetObserverTarget(client, prevObserved);
				return Plugin_Handled;
			}
		}
	}
	return Plugin_Continue;
}

public Action:Command_Redie(client, args)
{
	if (g_iPlugin_Enable == 0) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Redie has been disabled.");
		return Plugin_Handled;
	}

	if (g_bHasRoundEnded) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Please wait for the new round to begin.");
		return Plugin_Handled;
	}

	if (g_bIsGhost[client]) {

		ForcePlayerSuicide(client);
		return Plugin_Handled;
	}

	if (IsPlayerAlive(client)) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}You must be dead to use redie.");
		return Plugin_Handled;
	}

	if(GetClientTeam(client) <= 1) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}You must be on a team.");
		return Plugin_Handled;
	}

	g_bRespawnAsGhost[client] = true;
	CS_RespawnPlayer(client);

	Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}You are now a ghost.");
	return Plugin_Handled;
}

public Action:Command_Ghost(client, args)
{
	if (g_iPlugin_Enable == 0) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Redie has been disabled.");
		return Plugin_Handled;
	}

	if (g_bHasRoundEnded) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Please wait for the new round to begin.");
		return Plugin_Handled;
	}

	if (args != 1) {
		
		decl String:command[MAX_NAME_LENGTH];
		GetCmdArg(0,command,sizeof(command));
		ReplyToCommand(client, "%sUsage: %s <target>",Plugin_Tag,command);
		return Plugin_Handled;
	}

	decl String:target[MAX_TARGET_LENGTH];
	GetCmdArg(1, target, sizeof(target));
	
	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS+1];
	decl bool:tn_is_ml;
	
	new target_count = ProcessTargetString(
		target,
		client,
		target_list,
		sizeof(target_list),
		COMMAND_FILTER_CONNECTED,
		target_name,
		sizeof(target_name),
		tn_is_ml
	);
	
	if (target_count <= 0) {

		ReplyToTargetError(client,target_count);
		return Plugin_Handled;
	}

	for (new i=0; i<target_count; ++i) {

		g_bRespawnAsGhost[target_list[i]] = true;
		CS_RespawnPlayer(target_list[i]);

		Client_PrintToChat(target_list[i], false, "{O}[{G}Redie{O}] {N}You are now a ghost.");		
	}

	LogAction(client, -1, "\"%L\" forced target %s to be ghost", client, target);
	ShowActivity2(client, Plugin_Tag, "Forced target %s to be ghost", target);
	return Plugin_Handled;
}

/**************************************************************************************

	E V E N T S

**************************************************************************************/
/* Example Callback Event
public Action:Event_Example(Handle:event, const String:name[], bool:dontBroadcast)
{

}
*/
public Action:Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast) 
{
	g_bHasRoundEnded = false;
	Client_InitializeVariablesAll();
}

public Action:Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast) 
{
	g_bHasRoundEnded = true;

	if (g_iPlugin_Enable != 0) {

		LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {

			if (g_bIsGhost[client]) {

				SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_ALIVE);
				ForcePlayerSuicide(client);
			}
		}
	}
	Client_InitializeVariablesAll();
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!Client_IsValid(client)) {

		Client_InitializeVariables(client);
		return Plugin_Continue;
	}

	if (g_bRespawnAsGhost[client]) {

		g_bIsGhost[client] = true;
		g_bRespawnAsGhost[client] = false;

		SetEntProp(client, Prop_Send, "m_nHitboxSet", 2);
		SetEntData(client, g_iOffset_BaseEntity_CollisionGroup, 2, 4, true);
		
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		Entity_SetRenderColor(client, -1, -1, -1, g_iPlugin_GhostTransparency);

		CreateTimer(0.1, Timer_TakeWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else {

		Client_InitializeVariables(client);

		SetEntProp(client, Prop_Send, "m_nHitboxSet", 0);
		
		SetEntityRenderMode(client, RENDER_NORMAL);
		Entity_SetRenderColor(client, -1, -1, -1, 255);
	}
	return Plugin_Continue;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!Client_IsValid(client)) {

		Client_InitializeVariables(client);
		return Plugin_Continue;
	}

	Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Type !redie into chat to respawn as a ghost.");
	new bool:handleEvent = g_bIsGhost[client];

	if (g_bIsGhost[client]) {
		
		Client_SetScore(client, Client_GetScore(client) + 1);
		Client_SetDeaths(client, Client_GetDeaths(client) - 1);

		new ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (Entity_IsValid(ragdoll)) {
			Entity_Kill(ragdoll);
		}
	}

	// The client was alive and not a ghost, so we auto ghost him.
	if (!g_bIsGhost[client] && g_flPlugin_AutoGhostTime > 0.0) {
		CreateTimer(g_flPlugin_AutoGhostTime, Timer_AutoGhostSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	Client_InitializeVariables(client);

	// Lets test if the round is over by setting the life state of the ghosts for a short time.
	FlickerLifeState();

	return handleEvent ? Plugin_Handled : Plugin_Continue;
}

public Action:Event_PlayerFootstep(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}
	return g_bIsGhost[client] ? Plugin_Handled : Plugin_Continue;
}


/***************************************************************************************


	P L U G I N   F U N C T I O N S


***************************************************************************************/

FlickerLifeState(client=-1, Float:time=0.2)
{
	if (client != -1) {

		SetEntProp(client, Prop_Send, "m_lifeState", LIFESTATE_DEAD);
		CreateTimer(time, Timer_ResetLifeState, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else {

		LOOP_CLIENTS(player,CLIENTFILTER_INGAMEAUTH) {

			if(g_bIsGhost[player]) {

				SetEntProp(player, Prop_Send, "m_lifeState", LIFESTATE_DEAD);
			}
		}
		CreateTimer(time, Timer_ResetLifeState, -1, TIMER_FLAG_NO_MAPCHANGE);
	}
}

ResetAllGhosts() 
{
	LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {

		if (g_bIsGhost[client]) {
			
			SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_ALIVE);
			ForcePlayerSuicide(client);
		}
	}
}

/***************************************************************************************

	S T O C K

***************************************************************************************/
stock Client_InitializeAll()
{
	LOOP_CLIENTS (client, CLIENTFILTER_ALL) {
		
		Client_Initialize(client);
	}
}

stock Client_Initialize(client)
{
	// Variables
	Client_InitializeVariables(client);
	
	
	// Functions
	
	
	/* Functions were the player needs to be in game */
	if(!IsClientInGame(client)){
		return;
	}
	
	SDKHook(client, SDKHook_WeaponCanUse, Hook_WeaponCanUse_Client);
	SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit_Client);
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage_Client);
}

stock Client_InitializeVariablesAll()
{
	LOOP_CLIENTS (client, CLIENTFILTER_ALL) {
		
		Client_InitializeVariables(client);
	}
}

stock Client_InitializeVariables(client)
{
	// Client Variables
	g_bIsGhost[client] = false;
	g_bCanPickupWeapons[client] = true;
	g_bRespawnAsGhost[client] = false;
}


//## TODO: move this to smlib
stock GetNextObservTarget(client, start=-1)
{
	if (start == -1) {
		start = Client_GetObserverTarget(client);
	}

	for (new player=start+1; player <= MaxClients; player++) {

		if (Client_IsValid(player) && IsPlayerAlive(player)) {

			return player;
		}
	}

	for (new player=0; player <= start; player++) {

		if (Client_IsValid(player) && IsPlayerAlive(player)) {

			return player;
		}
	}

	return -1;
}

stock GetPreviousObservTarget(client, start=-1)
{
	if (start == -1) {
		start = Client_GetObserverTarget(client);
	}

	for (new player=start-1; player >= 1; player--) {

		if (Client_IsValid(player) && IsPlayerAlive(player)) {

			return player;
		}
	}

	for (new player=MaxClients+1; player >= start; player--) {

		if (Client_IsValid(player) && IsPlayerAlive(player)) {

			return player;
		}
	}

	return -1;
}

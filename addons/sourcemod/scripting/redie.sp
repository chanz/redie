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
	author 						= "Chanz",
	description 				= "Return as a ghost after you died.",
	version 					= "3.0",
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

// Console Variables: Runtime Optimizers
new g_iPlugin_Enable 					= 1;
new Float:g_flPlugin_AutoGhostTime	 	= 0.0;

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
// Hook Simulate Touch
new Handle:g_hSDK_Touch = INVALID_HANDLE;

/***************************************************************************************


	F O R W A R D   P U B L I C S


***************************************************************************************/
public OnPluginStart()
{
	// Initialization for SMLib
	PluginManager_Initialize("redie", "[SM] ");
	
	// Translations
	// LoadTranslations("common.phrases");
	
	
	// Command Hooks (AddCommandListener) (If the command already exists, like the command kill, then hook it!)
	AddCommandListener(CommandListener_Any);
	AddCommandListener(CommandListener_Drop, "drop");
	AddCommandListener(CommandListener_Kill, "kill");
	
	// Register New Commands (PluginManager_RegConsoleCmd) (If the command doesn't exist, hook it here)
	PluginManager_RegConsoleCmd("sm_redie", Command_Redie, "After death you can use this command to respawn as a ghost");
	
	// Register Admin Commands (PluginManager_RegAdminCmd)
	
	
	// Cvars: Create a global handle variable.
	g_cvarEnable = PluginManager_CreateConVar("enable", "1", "Enables or disables this plugin");
	g_cvarAutoGhostTime = PluginManager_CreateConVar("auto_ghost_time", "0", "Time in seconds after a player is auto respawned as ghost after death (0 = disabled)");

	// Hook ConVar Change
	HookConVarChange(g_cvarEnable, ConVarChange_Enable);
	HookConVarChange(g_cvarAutoGhostTime, ConVarChange_AutoGhostTime);
	
	// Event Hooks
	PluginManager_HookEvent("round_start", Event_RoundStart);	
	PluginManager_HookEvent("round_end", Event_RoundEnd);
	PluginManager_HookEvent("player_spawn", Event_PlayerSpawn);
	PluginManager_HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	PluginManager_HookEvent("player_footstep", Event_PlayerFootstep, EventHookMode_Pre);

	// Sound Hook
	AddNormalSoundHook(NormalSoundHook_FlashLight);
	
	// Library
	
	
	/* Features
	if(CanTestFeatures()){
		
	}
	*/

	// Register SDK Hook to simulate touching
	new Handle:hGameConf = LoadGameConfigFile("sdkhooks.games");

	if(hGameConf == INVALID_HANDLE) {
		SetFailState("GameConfigFile sdkhooks.games was not found");
		return;
	}

	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameConf,SDKConf_Virtual,"Touch");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity,SDKPass_Pointer);
	g_hSDK_Touch = EndPrepSDKCall();
	CloseHandle(hGameConf);

	if(g_hSDK_Touch == INVALID_HANDLE) {
		SetFailState("Unable to prepare virtual function CBaseEntity::Touch");
		return;
	}
	
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
	RegisterPlayerManager();

	new maxEntities = GetMaxEntities();
	for(new entity=1; entity<maxEntities; entity++) {

		if (!IsValidEntity(entity)) {
			continue;
		}
		
		decl String:entityClassname[MAX_NAME_LENGTH];
		Entity_GetClassName(entity, entityClassname, sizeof(entityClassname));
		if (StrContains(entityClassname, "trigger_", false) == -1) {
			continue;
		}

		SDKHook(entity, SDKHook_StartTouch, Hook_OnStartTouch_Trigger);
	}
}

public OnConfigsExecuted()
{
	// Set your ConVar runtime optimizers here
	g_iPlugin_Enable = GetConVarInt(g_cvarEnable);
	g_flPlugin_AutoGhostTime = GetConVarFloat(g_cvarAutoGhostTime);

	// Timers
	
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

/**************************************************************************************


	C A L L B A C K   F U N C T I O N S


**************************************************************************************/
public Action:NormalSoundHook_FlashLight(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (Client_IsValid(entity) &&  g_bIsGhost[entity]) {

		if (StrEqual(sample, "items/flashlight1.wav", false)) {

			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
}

public Action:Timer_ResetLifeStateToAlive(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!Client_IsValid(client)) {
		return Plugin_Handled;
	}

	SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_ALIVE);
	return Plugin_Continue;
}

public Action:Timer_ResetLifeStateToDead(Handle:timer, any:userid)
{
	new client = GetClientOfUserId(userid);
	if (!Client_IsValid(client)) {
		return Plugin_Handled;
	}

	SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_DEAD);
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

	if (g_bIsGhost[client]) {
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

	if (entity == client) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[entity] && g_bIsGhost[client]) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[entity] && !IsPlayerAlive(client)) {
		return Plugin_Continue;
	}

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

public Action:Hook_OnStartTouch_Trigger(entity, other)
{
	if (!Client_IsValid(other)) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[other]) {

		// Force the touch even if the life state prevents it from touching
		//SDKCall(g_hSDK_Touch, entity, other);
		FlickerLifeState(other, LIFESTATE_ALIVE, 0.01);
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

	decl String:cmd[256];
	GetCmdArgString(cmd, sizeof(cmd));

	if (StrContains(cmd, "@me", false) == -1) {
		return Plugin_Continue;
	}

	// If an admin uses a command on himself, his life state is set to alive for a short amount of time.
	FlickerLifeState(client, LIFESTATE_ALIVE, 0.2);
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
		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N} You can't drop weapons as ghost.");
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:CommandListener_Kill(client, const String:command[], argc)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	if (g_bIsGhost[client]) {
		ForcePlayerSuicide(client);
		Client_SetScore(client, Client_GetScore(client) + 1);
		Client_SetDeaths(client, Client_GetDeaths(client) - 1);
		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N} You are no longer a ghost.");
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action:Command_Redie(client, args)
{
	if (g_iPlugin_Enable == 0) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Redie has been disabled.");
		return Plugin_Continue;
	}

	if (g_bHasRoundEnded) {

		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Please wait for the new round to begin.");
		return Plugin_Handled;
	}

	if (g_bIsGhost[client]) {

		g_bRespawnAsGhost[client] = true;
		CS_RespawnPlayer(client);
		Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}You are still a ghost and we've respawned you.");
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
	Client_InitializeVariablesAll();
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_iPlugin_Enable == 0) {
		return Plugin_Continue;
	}

	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!Client_IsValid(client)) {

		// Client is not valid, reset his variables anyway.
		Client_InitializeVariables(client);
		return Plugin_Continue;
	}

	if (g_bRespawnAsGhost[client]) {

		// The client was spawned as ghost and is not a ghost:
		g_bIsGhost[client] = true;
		g_bRespawnAsGhost[client] = false;

		// Setup hitbox and collision group
		SetEntProp(client, Prop_Send, "m_nHitboxSet", 2);
		SetEntData(client, g_iOffset_BaseEntity_CollisionGroup, 2, 4, true);

		// This is now the first method/idea used by rambomst, we will try to address the trigger problem somehow else
		SetEntProp(client, Prop_Send,"m_lifeState", LIFESTATE_DEAD);
		
		// Half transparent players to indicate ghosts.
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		Entity_SetRenderColor(client, -1, -1, -1, 150);

		// Take all weapons and do it again with a little delay to ensure all of them have spawned
		Client_RemoveAllWeapons(client);
		CreateTimer(0.1, Timer_TakeWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else {
		// Spawn as normal player, so we re initialize his variables
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
		// Client is not valid, reset his variables anyway.
		Client_InitializeVariables(client);
		return Plugin_Continue;
	}

	Client_PrintToChat(client, false, "{O}[{G}Redie{O}] {N}Type !redie into chat to respawn as a ghost.");
	new bool:handleEvent = g_bIsGhost[client];

	if (g_bIsGhost[client]) {

		new ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (Entity_IsValid(ragdoll)) {
			Entity_Kill(ragdoll);
		}
	}

	// A client has died we reset all variables, since he is now just dead
	Client_InitializeVariables(client);

	// A normal client has died and we want him to automatically respawn as ghost
	if (!g_bIsGhost[client] && g_flPlugin_AutoGhostTime > 0.0) {
		CreateTimer(g_flPlugin_AutoGhostTime, Timer_AutoGhostSpawn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}

	// If the client is a ghost, we try to block the death event
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

	if (!Client_IsValid(client)) {

		return Plugin_Continue;
	}
	return g_bIsGhost[client] ? Plugin_Handled : Plugin_Continue;
}


/***************************************************************************************


	P L U G I N   F U N C T I O N S


***************************************************************************************/
FlickerLifeState(client, flicker_to_lifestate, Float:time)
{
	if (flicker_to_lifestate == LIFESTATE_ALIVE) {
		SetEntProp(client, Prop_Send, "m_lifeState", LIFESTATE_ALIVE);
		CreateTimer(time, Timer_ResetLifeStateToDead, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	else if (flicker_to_lifestate == LIFESTATE_DEAD) {
		SetEntProp(client, Prop_Send, "m_lifeState", LIFESTATE_DEAD);
		CreateTimer(time, Timer_ResetLifeStateToAlive, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
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

RegisterPlayerManager(){
	new entity = FindEntityByClassname(0, "cs_player_manager");

	if (!Entity_IsValid(entity)) {

		SetFailState("can't find entity cs_player_manager (%d)", entity);
		return;
	}

	SDKHook(entity, SDKHook_ThinkPost, Hook_ThinkPost_PlayerManager);
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
	
	
	/* Functions where the player needs to be in game */
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


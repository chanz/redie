#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <sdkhooks>
#include <smlib>

#pragma semicolon 1

#define PLUGIN_VERSION	 "1.9"

new bool:g_bHasRoundEnded = false;
new g_Collision;
new Handle:cvar_adverts = INVALID_HANDLE;
new bool:g_IsGhost[MAXPLAYERS+1];
new bool:g_CanPickupWeapons[MAXPLAYERS+1];
new g_iOffset_PlayerResource_Alive = -1;
new bool:g_bRespawnAsGhost[MAXPLAYERS+1];

public Plugin:myinfo =
{
	name = "Redie 4 SourceMod",
	author = "MeoW, Chanz",
	description = "Return as a ghost after you died.",
	version = PLUGIN_VERSION,
	url = "http://www.trident-gaming.net/"
};

public OnPluginStart()
{
	HookEvent("round_end", Event_Round_End);
	HookEvent("round_start", Event_Round_Start);	
	HookEvent("player_spawn", Event_Player_Spawn);
	HookEvent("player_death", Event_Player_Death, EventHookMode_Pre);
	HookEvent("player_footstep", Event_PlayerFootstep, EventHookMode_Pre);
	RegConsoleCmd("sm_redie", Command_Redie);
	CreateTimer(120.0, advert, _,TIMER_REPEAT);
	CreateConVar("sm_redie_version", PLUGIN_VERSION, "Redie Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	cvar_adverts = CreateConVar("sm_redie_adverts", "1", "If enabled, redie will produce an advert every 2 minutes.");
	g_Collision = FindSendPropInfo("CBaseEntity", "m_CollisionGroup");

	LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {

		SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
		SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit); 
		g_IsGhost[client] = false;
		g_CanPickupWeapons[client] = true;
		g_bRespawnAsGhost[client] = false;
	}

	AddCommandListener(CommandListener_Any);

	AddNormalSoundHook(StopFlashLightSound);

	g_iOffset_PlayerResource_Alive = FindSendPropInfo("CCSPlayerResource", "m_bAlive");
}

public OnPluginEnd()
{
	LOOP_CLIENTS(client, CLIENTFILTER_INGAMEAUTH) {
		if (g_IsGhost[client]) {
			SetEntProp(client, Prop_Send, "m_lifeState", 0);
			ForcePlayerSuicide(client);
		}
	}
}

public OnMapStart(){
	new entity = FindEntityByClassname(0, "cs_player_manager");
	SDKHook(entity, SDKHook_ThinkPost, OnPlayerManager_ThinkPost);
}

public OnPlayerManager_ThinkPost(entity) {

	LOOP_CLIENTS(client,CLIENTFILTER_ALL) {
		if(g_IsGhost[client])
		{
			SetEntData(entity, (g_iOffset_PlayerResource_Alive+client*4), 0, 1, true);
		}
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public OnClientPostAdminCheck(client)
{
	g_IsGhost[client] = false;
	g_CanPickupWeapons[client] = true;
	g_bRespawnAsGhost[client] = false;
}

public Action:OnTakeDamage(victim, &attacker, &inflictor, &Float:damage, &damagetype){

	if (g_IsGhost[victim]) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:CommandListener_Any(client, const String:command[], argc)
{
	decl String:cmd[256];
	GetCmdArgString(cmd, sizeof(cmd));

	if (StrContains(cmd, "@dead", false) == -1 && StrContains(cmd, "@alive", false) == -1) 
	{
		return Plugin_Continue;
	}

	TestRoundEnd();
	return Plugin_Continue;
}

public Action:StopFlashLightSound(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{
	if (Client_IsValid(entity) &&  g_IsGhost[entity]) {
		if (StrEqual(sample, "items/flashlight1.wav", false)){

			return Plugin_Stop;
		}
	}
	
	return Plugin_Continue;
} 

stock TestRoundEnd(){

	LOOP_CLIENTS(client,CLIENTFILTER_ALL){
		if(g_IsGhost[client])
		{
			SetEntProp(client, Prop_Send, "m_lifeState", 1);
		}
	}
	CreateTimer(0.2, Timer_ResetLifeState, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:Timer_ResetLifeState(Handle:timer){

	LOOP_CLIENTS(client,CLIENTFILTER_ALL)
	{
		if(g_IsGhost[client])
		{
			SetEntProp(client, Prop_Send, "m_lifeState", 0);
		}
	}
}

public Action:Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast) 
{
	g_bHasRoundEnded = true;
	LOOP_CLIENTS(client,CLIENTFILTER_ALL){

		if (g_IsGhost[client]) {
			SetEntProp(client, Prop_Send, "m_lifeState", 0);
			ForcePlayerSuicide(client);
		}

		g_IsGhost[client] = false;
		g_CanPickupWeapons[client] = true;
		g_bRespawnAsGhost[client] = false;
	}
}

public Action:Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast) 
{
	g_bHasRoundEnded = false;
	LOOP_CLIENTS(client,CLIENTFILTER_ALL){
		g_IsGhost[client] = false;
		g_CanPickupWeapons[client] = true;
		g_bRespawnAsGhost[client] = false;
	}
}

public Action:Event_Player_Spawn(Handle:event, const String:name[], bool:dontBroadcast)
{	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(g_bRespawnAsGhost[client])
	{
		g_IsGhost[client] = true;
		SetEntProp(client, Prop_Send, "m_nHitboxSet", 2);
		CreateTimer(0.1, Timer_TakeWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		g_bRespawnAsGhost[client] = false;
		SetEntityRenderMode(client, RENDER_TRANSALPHA);
		Entity_SetRenderColor(client, -1, -1, -1, 150);
	}
	else
	{
		SetEntProp(client, Prop_Send, "m_nHitboxSet", 0);
		g_CanPickupWeapons[client] = true;
		g_IsGhost[client] = false;
		SetEntityRenderMode(client, RENDER_NORMAL);
		Entity_SetRenderColor(client, -1, -1, -1, 255);
	}
}



public Action:Timer_TakeWeapons(Handle:timer, any:userid){

	new client = GetClientOfUserId(userid);
	
	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	Client_RemoveAllWeapons(client);
	g_CanPickupWeapons[client] = false;
	return Plugin_Continue;
}

public Action:Event_Player_Death(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}

	PrintToChat(client, "\x01[\x03Redie\x01] \x04Type !redie into chat to respawn as a ghost.");
	new bool:handleEvent = g_IsGhost[client];

	if (g_IsGhost[client]) {
		new ragdoll = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
		if (Entity_IsValid(ragdoll)) {
			Entity_Kill(ragdoll);
		}
	}

	g_IsGhost[client] = false;
	g_CanPickupWeapons[client] = true;
	g_bRespawnAsGhost[client] = false;

	TestRoundEnd();

	return handleEvent ? Plugin_Handled : Plugin_Continue;
}

public Action:Event_PlayerFootstep(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!Client_IsValid(client)) {
		return Plugin_Continue;
	}
	return g_IsGhost[client] ? Plugin_Handled : Plugin_Continue;
}
/*public OnGameFrame(){

	LOOP_CLIENTS(client,CLIENTFILTER_ALL){
		if(g_IsGhost[client])
		{
			new ent = -1;
			while ((ent = FindEntityByClassname(ent, "cs_player_manager")) != -1)
			{
				SetEntData(ent, (g_iOffset_PlayerResource_Alive+client*4), 0, 1, true);
			}
		}
	}
}*/

public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(g_IsGhost[client])
	{
		buttons &= ~IN_USE;
		buttons &= ~IN_ATTACK;
		buttons &= ~IN_ATTACK2;
	}
	return Plugin_Changed;
}

public Action:Command_Redie(client, args)
{
	if(g_bHasRoundEnded)
	{
		PrintToChat(client, "\x01[\x03Redie\x01] \x04Please wait for the new round to begin.");
		return Plugin_Handled;
	}

	if (IsPlayerAlive(client))
	{
		PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be dead to use redie.");
		return Plugin_Handled;
	}

	if(GetClientTeam(client) <= 1)
	{
		PrintToChat(client, "\x01[\x03Redie\x01] \x04You must be on a team.");
		return Plugin_Handled;
	}

	g_bRespawnAsGhost[client] = true;
	CS_RespawnPlayer(client);

	//SetEntProp(client, Prop_Send, "m_lifeState", 1);
	SetEntData(client, g_Collision, 2, 4, true);
	PrintToChat(client, "\x01[\x03Redie\x01] \x04You are now a ghost.");
	return Plugin_Handled;
}

public Action:Hook_SetTransmit(entity, client)
{
	if (entity == client) {
		return Plugin_Continue;
	}

	if (g_IsGhost[entity] && g_IsGhost[client]) {
		return Plugin_Continue;
	}

	if (g_IsGhost[entity] && !IsPlayerAlive(client)) {
		return Plugin_Continue;
	}

	if (g_IsGhost[entity]) {
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:OnWeaponCanUse(client, weapon)
{
	if(!g_CanPickupWeapons[client]){
		return Plugin_Handled;
	}
	if (g_IsGhost[client] && g_bHasRoundEnded) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action:advert(Handle:timer)
{
	if(GetConVarInt(cvar_adverts))
	{
		PrintToChatAll ("\x01[\x03Redie\x01] \x04This server is running !redie.");
	}
	return Plugin_Continue;
}


stock GetPreviousObserver(client, start, flags=CLIENTFILTER_ALL)
{
	for (new player=start; player <= MaxClients; player--) {

		if (Client_MatchesFilter(player, CLIENTFILTER_OBSERVERS | flags)) {

			if (Client_GetObserverTarget(player) == client) {
				return player;
			}
		}
	}

	return -1;
}
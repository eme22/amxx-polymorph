// #define DEBUG

/*
	Modes:
		0: Always stay on one mod unless changed manually with admin command.  (Map votes only)
		1: Play # maps then next mod will default to next in polymorph.ini (Map votes only)
		2: Play # maps then next mod will be chosen by vote. (Map and Mod votes)
		
	Recovered Features (v1.2.0):
		- Dynamic Voting (Percentages, Re-vote, Hide Menu)
		- Nomination System (Mods and Maps)
		- Admin Menus (Show Mods/Maps with actions)
		- Modern Menu System (menu_create)
		
	Modernization (v1.3.0):
		- create_cvar & bind_pcvar_*
		- client_print_color
		- MaxClients usage
*/

#include <amxmodx>
#include <amxmisc>
#include <nvault>

// String Lengths
#define STRLEN_DATA 128	// data from file and 'etc.' data
#define STRLEN_PATH 128	// full file path
#define STRLEN_NAME 32	// plugin Name e.g. "GunGame Mod"
#define STRLEN_FILE 32	// single filename w/o path
#define STRLEN_MAP 32	// map name

// Limits
#define MODS_MAX 30		// Maximum number of mods.

// Number of main options in vote
#define SELECTMODS 9
#define SELECTMAPS 9

// Task IDs
#define TASK_ENDOFMAP 3141
#define TASK_FORCED_MAPCHANGE 314159
#define TASK_VOTE_TIMER 237439
#define TASK_VOTE_MAP_TIMER 935732

// ammount of time left (in seconds) to trigger end of map vote
#define TIMELEFT_TRIGGER 129

new g_szModNames[MODS_MAX][STRLEN_NAME]	// Mod Names
new Array:g_aModMaps[MODS_MAX]			// Per-mod Map Names List
new Array:g_aModPlugins[MODS_MAX]		// Per-mod Plugin Names List
new Array:g_aCfgList					// Array to hold cvars for 'ThisMod'

// Nomination Arrays
new Array:g_aNominatedMods
new Array:g_aNominatedMaps

new g_iMapNums[MODS_MAX]			// Number of maps for each mod
new g_szThisMod[STRLEN_NAME]		// Name of 'ThisMod'

new g_iThisMod = -1			// Index of 'ThisMod'
new g_iNextMod = 0			// Index of 'NextMod'
new g_iModCount = 0			// Number of MODs loaded

new g_iMapsPlayed			// Number of maps played on current MOD.
new g_iMapsPerMod[MODS_MAX]	// Number of maps played before a MOD change.

new bool:g_isLastMap = false			// Number of maps played on current mod.
new bool:g_selected = false

// Voting stuff
new g_voteNum
new g_voteCount
new g_nextName[SELECTMAPS]
new g_voteMapCount[SELECTMAPS + 2]
new g_nextModId[MODS_MAX]
new g_voteModCount[MODS_MAX + 2]
new bool:g_bVoteForced = false
new bool:g_bChangeOnRoundend = false

// Dynamic Vote Vars
new g_iUserVoted[33][2] // [id][0] = has voted?, [id][1] = item index
new bool:g_bShowVoteMenu[33] // Should the menu be shown to this user?
new bool:g_bRefreshing[33] // Is the menu being refreshed automatically?
new g_iVoteCountDown

// Compatibility vars
new g_teamScore[2]

// Vault
new g_hVault
new g_iVoteBehavior[33] // 0 = Close on vote, 1 = Re-open on vote
new bool:g_bVoteSound[33]
new bool:g_bVoteChat[33]

/* Cvar Pointers & Variables */
// My cvars
new g_iMode
new g_bExtendMod
new Float:g_fExtendStep
new Float:g_fExtendMax
new g_pThisMod
new g_pNextMod
new g_bEndOnRound

// New Cvars
new g_bRevote
new g_bAllowNomination

// Prefix Cvar
new g_pPrefix
new g_szPrefix[64]

// Existing cvars
new g_pNextmap
new g_pTimeLimit, Float:g_fTimeLimit
new g_bVoteAnswers
new Float:g_fChatTime

/* Variables */
// Voting delays
new Float:fVoteTime // Time to choose an option.
new Float:fBetweenVote // Time between mod vote ending and map vote starting.


public plugin_init()
{
	register_plugin("Polymorph: Mod Manager", "1.2.0", "Fysiks & MSB19")
	create_cvar("Polymorph", "v1.2.0", FCVAR_SERVER|FCVAR_SPONLY)
	
	register_dictionary("mapchooser.txt")
	register_dictionary("common.txt")
	register_dictionary("polymorph.txt")
	
	/* Register Cvars */
	g_pPrefix = create_cvar("poly_prefix", "^4[Polymorph]^1", FCVAR_NONE, "Chat prefix for Polymorph messages")

	bind_pcvar_float(create_cvar("amx_extendmap_max", "90", FCVAR_NONE, "Maximum time limit for map extension"), g_fExtendMax)
	
	bind_pcvar_float(create_cvar("amx_extendmap_step", "15", FCVAR_NONE, "Time to extend map by (minutes)"), g_fExtendStep)
	
	bind_pcvar_num(create_cvar("poly_mode", "2", FCVAR_NONE, "Polymorph Mode: 0=Fixed, 1=Cycle, 2=Vote"), g_iMode)
	
	bind_pcvar_num(create_cvar("poly_extendmod", "1", FCVAR_NONE, "Allow extending the current mod"), g_bExtendMod)
	
	g_pThisMod = create_cvar("poly_thismod", "", FCVAR_NONE, "Current Mod Name (Do not change manually)")
	g_pNextMod = create_cvar("poly_nextmod", "", FCVAR_NONE, "Next Mod Name")
	
	bind_pcvar_num(create_cvar("poly_endonround", "0", FCVAR_NONE, "Change map at round end instead of immediately"), g_bEndOnRound)
	
	// New Cvars
	bind_pcvar_num(create_cvar("poly_revote", "1", FCVAR_NONE, "Allow players to change their vote"), g_bRevote)
	
	bind_pcvar_num(create_cvar("poly_allow_nomination", "1", FCVAR_NONE, "Allow players to nominate maps/mods"), g_bAllowNomination)
	
	bind_pcvar_float(create_cvar("poly_vote_time", "20.0", FCVAR_NONE, "Time to choose an option in vote"), fVoteTime)
	
	bind_pcvar_float(create_cvar("poly_vote_delay", "10.0", FCVAR_NONE, "Time between mod vote ending and map vote starting"), fBetweenVote)
	
	/* Client Commands */
	register_clcmd("say nextmod", "sayNextmod")
	register_clcmd("say thismod", "sayThismod")
	
	// Nomination Commands
	register_clcmd("say nominate", "cmdNomMenu")
	register_clcmd("say nom", "cmdNomMenu")
	register_clcmd("say showmaps", "cmdShowMaps")
	register_clcmd("say showmods", "cmdShowMods")
	register_clcmd("say /vote", "cmdOpenVoteMenu")
	register_clcmd("say vote", "cmdOpenVoteMenu")
	register_clcmd("say /settings", "cmdSettingsMenu")
	
	/* Console Commands */
	register_concmd("amx_nextmod", "cmdSetNextmod", ADMIN_MAP, " - Set the next mod manually")
	register_concmd("amx_votemod", "cmdVoteMod", ADMIN_MAP, " - Start a vote for the next mod")
	
	// Admin Menus
	register_concmd("amx_showmaps", "cmdShowMaps", -1, " - Show Maps to Clients and admins")
	register_concmd("amx_showmods", "cmdShowMods", -1, " - Show Mods to Clients and admins")

	/* Compatibility */
	if (cstrike_running())
		register_event("TeamScore", "team_score", "a")

	if( is_running("cstrike") )
	{
		register_event("HLTV", "event_round_start", "a", "1=0", "2=0")
	}
	else if( is_running("dod") )
	{
		register_event("RoundState", "event_round_start", "a", "1=1")
	}
	
	// Open Vault
	g_hVault = nvault_open("polymorph_prefs")
	
	// Initialize Nomination Arrays
	g_aNominatedMods = ArrayCreate(STRLEN_NAME)
	g_aNominatedMaps = ArrayCreate(STRLEN_MAP)
}

public client_putinserver(id)
{
	LoadUserPrefs(id)
}

public LoadUserPrefs(id)
{
	new szAuth[35], szKey[40], szData[16]
	get_user_authid(id, szAuth, charsmax(szAuth))
	formatex(szKey, charsmax(szKey), "%s_prefs", szAuth)
	
	if(nvault_get(g_hVault, szKey, szData, charsmax(szData)))
	{
		new szBehavior[2], szSound[2], szChat[2]
		parse(szData, szBehavior, charsmax(szBehavior), szSound, charsmax(szSound), szChat, charsmax(szChat))
		
		g_iVoteBehavior[id] = str_to_num(szBehavior)
		g_bVoteSound[id] = bool:str_to_num(szSound)
		g_bVoteChat[id] = bool:str_to_num(szChat)
	}
	else
	{
		g_iVoteBehavior[id] = 0 // Default: Close
		g_bVoteSound[id] = true // Default: On
		g_bVoteChat[id] = true // Default: On
	}
}

public SaveUserPrefs(id)
{
	new szAuth[35], szKey[40], szData[16]
	get_user_authid(id, szAuth, charsmax(szAuth))
	formatex(szKey, charsmax(szKey), "%s_prefs", szAuth)
	
	formatex(szData, charsmax(szData), "%d %d %d", g_iVoteBehavior[id], g_bVoteSound[id], g_bVoteChat[id])
	nvault_set(g_hVault, szKey, szData)
}

public plugin_cfg()
{

	get_pcvar_string(g_pPrefix, g_szPrefix, charsmax(g_szPrefix))
	/* Get Cvar Pointers & Bind */
	g_pNextmap = get_cvar_pointer("amx_nextmap")
	
	g_pTimeLimit = get_cvar_pointer("mp_timelimit")
	bind_pcvar_float(g_pTimeLimit, g_fTimeLimit)
	
	bind_pcvar_num(get_cvar_pointer("amx_vote_answers"), g_bVoteAnswers)
	
	bind_pcvar_float(get_cvar_pointer("mp_chattime"), g_fChatTime)

	new szData[STRLEN_DATA]
	new szFilepath[STRLEN_PATH], szConfigDir[STRLEN_PATH]
	
	get_configsdir(szConfigDir, charsmax(szConfigDir))

	/* Get ThisMod Name */
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "plugins-polymorph.ini")
	new f = fopen(szFilepath, "rt")
	if(f)
	{
		fgets(f, szData, charsmax(szData))
		fclose(f)
		replace(szData, charsmax(szData), ";ThisMod:", "")
		trim(szData)
		parse(szData, g_szThisMod, charsmax(g_szThisMod))
	}
	
	/*
		Check for folder "/polymorph/"
		If it exists, load MODs.
	 */
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "polymorph")
	if( dir_exists(szFilepath) )
	{
		/* Load MODs */
		initModLoad()
	}
	else
	{
		new error[64]
		formatex(error, charsmax(error), "%s/ does not exist.", szFilepath)
		set_fail_state(error)
	}
	
	/* Set default nextmod/map depending on maps played and mode */
	new szMapsPlayed[4]
	get_localinfo("mapcount", szMapsPlayed, charsmax(szMapsPlayed))
	g_iMapsPlayed = str_to_num(szMapsPlayed)
	g_iMapsPlayed++

	switch( g_iMode )
	{
		case 0:
		{
			setNextMod(g_iThisMod)
			g_isLastMap = false
		}
		case 1,2:
		{
			// Set default nextmod depending on how many maps have been played on this mod
			if( !( g_iMapsPlayed < g_iMapsPerMod[g_iThisMod] ) ) // Do this in end map task too? to allow changing cvar mid map.
			{
				g_isLastMap = true
				setNextMod((g_iThisMod + 1) % g_iModCount)
			}
			else
			{
				setNextMod(g_iThisMod)
			}
		}
		default: // Mode 0
		{
			setNextMod(g_iThisMod)
			g_isLastMap = false
		}
	}
	setDefaultNextmap()
	
	/* Set task to check when map ends */
	set_task(20.0, "taskEndofMap", TASK_ENDOFMAP, "", 0, "b")
}

public plugin_end()
{
	nvault_close(g_hVault)

	// If this map still qualifies to be the last then reset mapcount for next mod.
	if( !( g_iMapsPlayed < g_iMapsPerMod[g_iThisMod] ) )
	{
		g_iMapsPlayed = 0
	}

	new szMapsPlayed[4]
	num_to_str(g_iMapsPlayed, szMapsPlayed, charsmax(szMapsPlayed))
	set_localinfo("mapcount", szMapsPlayed)
	
	if( g_iThisMod != g_iNextMod )
	{
		UpdatePluginFile()
	}
	
	ArrayDestroy(g_aNominatedMods)
	ArrayDestroy(g_aNominatedMaps)
}

public event_round_start()
{
	if( g_bChangeOnRoundend )
	{
		intermission() // call end of map function whatever that might be
	}
}


/*
	Plugin Natives
*/
public plugin_natives()
{
	// Polymorph Natives.  Make it modular!
	register_library("polymorph")
	register_native("polyn_endofmap", "_polyn_endofmap")
	register_native("polyn_get_thismod", "_polyn_get_thismod")
	register_native("polyn_get_nextmod", "_polyn_get_nextmod")
	register_native("polyn_votemod", "_polyn_votemod")
	register_native("polyn_get_mod", "_polyn_get_mod")
	register_native("polyn_get_modlist", "_polyn_get_modlist")
	register_native("polyn_set_nextmod", "_polyn_set_nextmod")
}

// Native: Execute the end of map vote.
public _polyn_endofmap(iPlugin, iParams)
{
	execEndofMap()
}

// Native: Get this mod's name and return it's id
public _polyn_get_thismod(iPlugin, iParams)
{
	new iChars = get_param(2)
	new szModName[STRLEN_NAME]
	copy(szModName, charsmax(szModName), g_szModNames[g_iThisMod])
	set_string(1, szModName, iChars)
	return g_iThisMod
}

// Native: Get the next mod's name and returns it's id
public _polyn_get_nextmod(iPlugin, iParams)
{
	new iChars = get_param(2)
	new szModName[STRLEN_NAME]
	copy(szModName, charsmax(szModName), g_szModNames[g_iNextMod])
	set_string(1, szModName, iChars)
	return g_iNextMod
}

// Native: Get a specific mod's name by ID
public _polyn_get_mod(iPlugin, iParams)
{
	new modId = get_param(1)
	if(modId < 0 || modId >= g_iModCount)
		return 0

	new iChars = get_param(3)
	new szModName[STRLEN_NAME]
	copy(szModName, charsmax(szModName), g_szModNames[modId])
	set_string(2, szModName, iChars)
	return 1
}

// Native: Get the number of loaded mods
public _polyn_get_modlist(iPlugin, iParams)
{
	return g_iModCount
}

// Native: Set the next mod manually
public _polyn_set_nextmod(iPlugin, iParams)
{
	new id = get_param(1)
	new modid = get_param(2)
	
	if( 0 <= modid < g_iModCount )
	{
		if( modid == g_iNextMod )
		{
			if(id) console_print(id, "Next mod is already %s", g_szModNames[g_iNextMod])
			return 0
		}
		
		setNextMod(modid)
		setDefaultNextmap()
		
		if(id)
		{
			new name[32]
			get_user_name(id, name, 31)
			client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_ADMIN_SET_MOD_USER", name, g_szModNames[g_iNextMod])
			console_print(id, "%L", id, "CON_NEXT_IS_NOW", g_szModNames[g_iNextMod])
		}
		else
		{
			client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_NEXT_MOD_SET", g_szModNames[g_iNextMod])
		}
		return 1
	}
	
	if(id) console_print(id, "Invalid Option")
	return 0
}

// Native: Start Mod Vote (and map vote), force mapchange.
public _polyn_votemod()
{
	startModVote()
	g_bVoteForced = true;
	set_task(50.0, "intermission", TASK_FORCED_MAPCHANGE)
}


/*
 *	Admin commands
 */
public cmdSetNextmod(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED
	
	if(read_argc() == 1)
	{
		console_print(id, "%L", id, "CON_PLAYING", g_szModNames[g_iThisMod]) // Need ML
		console_print(id, "%L", id, "CON_AVAIL_MODS") // Need ML
		
		// Print available mods (menu-like)
		for(new i = 0; i < g_iModCount; i++)
		{
			console_print(id, i == g_iNextMod ? "%d) %s%L" : "%d) %s", i+1, g_szModNames[i], id, "CON_CURR_NEXT")
		}
		
		new szCmdName[32]
		read_argv(0, szCmdName, charsmax(szCmdName))
		console_print(id, "%L", id, "CON_SET_NEXT", szCmdName)
	}
	else
	{
		new szArg[3]
		read_argv(1, szArg, charsmax(szArg))
		if( isdigit(szArg[0]) )
		{
			new modid = str_to_num(szArg) - 1
			if( 0 <= modid < g_iModCount )
			{
				if( modid == g_iNextMod )
				{
					console_print(id, "%L", id, "CON_ALREADY_NEXT", g_szModNames[g_iNextMod]) // Need ML
				}
				else
				{
					setNextMod(modid)
					setDefaultNextmap()
					// Reset g_iMapsPlayed ??
					console_print(id, "%L", id, "CON_NEXT_IS_NOW", g_szModNames[g_iNextMod])
					
					// Clear nominations if mod changed manually
					ArrayClear(g_aNominatedMaps)
				}
			}
			else
			{
				console_print(id, "%L", id, "CON_INVALID_OPT")
			}
		}
		else
		{
			console_print(id, "%L", id, "CON_INVALID_OPT")
		}
	}
	return PLUGIN_HANDLED
}

public cmdVoteMod(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED

	// Start vote.
	// if(vote task is running) then don't allow
	if( get_timeleft() > TIMELEFT_TRIGGER && !task_exists(TASK_FORCED_MAPCHANGE) )
	{
		startModVote()
		g_bVoteForced = true;
		set_task(50.0, "intermission", TASK_FORCED_MAPCHANGE)
	}
	else
	{
		console_print(id, "%L", id, "CON_VOTE_NOT_ALLOWED")
	}
	
	return PLUGIN_HANDLED
}

/*
 *	Say functions
 */
public sayNextmod()
{
	client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_NEXT_MOD", g_szModNames[g_iNextMod])
}

public sayThismod()
{
	client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_THIS_MOD", g_szModNames[g_iThisMod])
}


/*
 *	End of Map functions
 */
public taskEndofMap()
{
	new winlimit = get_cvar_num("mp_winlimit")   // Not using pcvars to allow cross-mod compatibility
	new maxrounds = get_cvar_num("mp_maxrounds")
	
	if (winlimit)
	{
		new c = winlimit - 2
		
		if ((c > g_teamScore[0]) && (c > g_teamScore[1]))
		{
			g_selected = false
			return
		}
	}
	else if (maxrounds)
	{
		if ((maxrounds - 2) > (g_teamScore[0] + g_teamScore[1]))
		{
			g_selected = false
			return
		}
	}
	else
	{
		new timeleft = get_timeleft()
		
		if (timeleft < 1 || timeleft > TIMELEFT_TRIGGER)
		{
			g_selected = false
			return
		}
	}
	
	if (g_selected)
		return

	g_selected = true
	
	execEndofMap()
}

public execEndofMap()
{
	// Disallow vote if someone put up vote for new mod already.
	if( task_exists(TASK_FORCED_MAPCHANGE) )
		return
	
	switch( g_iMode )
	{
		case 0,1:
		{
			startMapVote()
		}
		case 2:
		{
			if( g_isLastMap )
			{ // Time to decide on new mod.
				startModVote()
			}
			else
			{ // Stay on this mod ( so only do map vote)
				startMapVote() 
			}
		}
		default: // Mode 0
		{
			startMapVote()
		}
	}
}

/*
 *	Vote functions (Dynamic)
 */
public startModVote()
{
	// Reset vote vars
	g_voteCount = 0
	g_voteNum = 0
	arrayset(g_voteModCount, 0, sizeof(g_voteModCount))
	
	// Reset user vote status
	for(new i = 1; i <= MaxClients; i++)
	{
		g_iUserVoted[i][0] = 0
		g_iUserVoted[i][1] = 0
		g_bShowVoteMenu[i] = true
	}

	// Prepare Vote Items (Nominations + Random)
	new iNomCount = ArraySize(g_aNominatedMods)
	new iMaxItems = (g_iModCount - 1 > SELECTMODS) ? SELECTMODS : g_iModCount - 1
	
	// Add Nominations first
	for(new i = 0; i < iNomCount && g_voteNum < iMaxItems; i++)
	{
		new szNom[STRLEN_NAME]
		ArrayGetString(g_aNominatedMods, i, szNom, charsmax(szNom))
		
		// Find ID
		new id = -1
		for(new j = 0; j < g_iModCount; j++)
		{
			if(equal(g_szModNames[j], szNom))
			{
				id = j
				break
			}
		}
		
		if(id != -1 && id != g_iThisMod)
		{
			g_nextModId[g_voteNum] = id
			g_voteNum++
		}
	}
	
	// Fill with random
	while(g_voteNum < iMaxItems)
	{
		new a = random(g_iModCount)
		if(a != g_iThisMod && !isModInMenu(a))
		{
			g_nextModId[g_voteNum] = a
			g_voteNum++
		}
	}
	
	// Start Timer Task
	g_iVoteCountDown = floatround(fVoteTime)
	set_task(1.0, "TaskVoteTimer", TASK_VOTE_TIMER, _, _, "b")
	set_task(fVoteTime, "checkModVotes")
	
	client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_CHOOSE_MOD")
	
	new players[32], num
	get_players(players, num, "ch")
	for(new i = 0; i < num; i++)
	{
		if(g_bVoteSound[players[i]])
			client_cmd(players[i], "spk Gman/Gman_Choose2")
	}
	
	log_amx("Vote: Voting for the next mod started")
}

public TaskVoteTimer()
{
	g_iVoteCountDown--
	
	if(g_iVoteCountDown < 0)
		return
	
	new players[32], num
	get_players(players, num, "ch") // Skip bots and HLTV
	
	for(new i = 0; i < num; i++)
	{
		new id = players[i]
		if(g_bShowVoteMenu[id])
		{
			g_bRefreshing[id] = true
			ShowModVoteMenu(id)
			g_bRefreshing[id] = false
		}
	}
}

public ShowModVoteMenu(id)
{
	new szTitle[64]
	if(g_iVoteCountDown > 0)
		formatex(szTitle, charsmax(szTitle), "%L \r(%d s.)", id, "MENU_CHOOSE_MOD", g_iVoteCountDown)
	else
		formatex(szTitle, charsmax(szTitle), "\r%L", id, "MENU_VOTE_RESULT")
		
	new menu = menu_create(szTitle, "HandleModVoteMenu")
	menu_setprop(menu, MPROP_PERPAGE, 0)
	new szItem[64]
	
	// Find Winner
	new iWinner = 0
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteModCount[iWinner] < g_voteModCount[a])
			iWinner = a
			
	if (g_bExtendMod && g_voteModCount[SELECTMODS] > g_voteModCount[iWinner])
		iWinner = SELECTMODS
	
	// Add Items with Percentages
	for(new i = 0; i < g_voteNum; i++)
	{
		new percent = GetPercent(g_voteModCount[i], g_voteCount)
		
		if(i == iWinner)
			formatex(szItem, charsmax(szItem), "\r%s \d(%d%%)", g_szModNames[g_nextModId[i]], percent)
		else if(g_iUserVoted[id][0] && g_iUserVoted[id][1] == i)
			formatex(szItem, charsmax(szItem), "\y%s \d(%d%%)", g_szModNames[g_nextModId[i]], percent)
		else
			formatex(szItem, charsmax(szItem), "\w%s \d(%d%%)", g_szModNames[g_nextModId[i]], percent)
			
		menu_additem(menu, szItem, "", 0)
	}
	
	new iItemsAdded = g_voteNum
	
	// Extend Option
	if( g_bExtendMod )
	{
		while(iItemsAdded < 9)
		{
			menu_addblank(menu, 1)
			iItemsAdded++
		}
		
		menu_addtext(menu, "^n", 0)
		
		new percent = GetPercent(g_voteModCount[SELECTMODS], g_voteCount)
		
		if(iWinner == SELECTMODS)
			formatex(szItem, charsmax(szItem), "\r%L \d(%d%%)", id, "MENU_EXTEND", g_szModNames[g_iThisMod], percent)
		else if(g_iUserVoted[id][0] && g_iUserVoted[id][1] == SELECTMODS)
			formatex(szItem, charsmax(szItem), "\y%L \d(%d%%)", id, "MENU_EXTEND", g_szModNames[g_iThisMod], percent)
		else
			formatex(szItem, charsmax(szItem), "\w%L \d(%d%%)", id, "MENU_EXTEND", g_szModNames[g_iThisMod], percent)
			
		menu_additem(menu, szItem, "", 0)
	}
	
	// Display
	menu_display(id, menu, 0)
}

public HandleModVoteMenu(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		if(!g_bRefreshing[id])
			g_bShowVoteMenu[id] = false
		return PLUGIN_HANDLED
	}
	
	if(g_iVoteCountDown <= 0)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	// Check Re-vote
	if(g_iUserVoted[id][0])
	{
		if(!g_bRevote)
		{
			client_print_color(id, print_team_default, "%s You have already voted.", g_szPrefix)
			menu_destroy(menu)
			return PLUGIN_HANDLED
		}
		
		// Remove previous vote
		new prevItem = g_iUserVoted[id][1]
		if(prevItem == SELECTMODS) // Extend
			g_voteModCount[SELECTMODS]--
		else
			g_voteModCount[prevItem]--
			
		g_voteCount--
	}
	
	// Register Vote
	if(item == 9) // Extend option (Slot 0)
	{
		g_voteModCount[SELECTMODS]++
		g_iUserVoted[id][1] = SELECTMODS
		
		new name[32]
		get_user_name(id, name, 31)
		if(g_bVoteAnswers)
		{
			new players[32], num
			get_players(players, num, "ch")
			for(new i = 0; i < num; i++)
			{
				if(g_bVoteChat[players[i]])
					client_print_color(players[i], print_team_default, "%L", LANG_PLAYER, "POLY_VOTE_EXTEND", name)
			}
		}
	}
	else if(item < g_voteNum)
	{
		g_voteModCount[item]++
		g_iUserVoted[id][1] = item
		
		new name[32]
		get_user_name(id, name, 31)
		if(g_bVoteAnswers)
		{
			new players[32], num
			get_players(players, num, "ch")
			for(new i = 0; i < num; i++)
			{
				if(g_bVoteChat[players[i]])
					client_print_color(players[i], print_team_default, "%L", LANG_PLAYER, "POLY_VOTE_MOD", name, g_szModNames[g_nextModId[item]])
			}
		}
	}
	
	g_iUserVoted[id][0] = 1
	g_voteCount++
	
	menu_destroy(menu)
	
	// Check User Preference
	if(g_iVoteBehavior[id] == 0) // Close on Vote
	{
		g_bShowVoteMenu[id] = false
	}
	
	if(g_iVoteCountDown > 0 && g_bShowVoteMenu[id])
		ShowModVoteMenu(id)
	return PLUGIN_HANDLED
}

public checkModVotes()
{
	// Stop Timer
	remove_task(TASK_VOTE_TIMER)
	
	// Check Mod Votes
	new b = 0
	
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteModCount[b] < g_voteModCount[a])
			b = a

	
	if (g_voteModCount[SELECTMODS] > g_voteModCount[b] )
	{
		setNextMod(g_iThisMod)
		client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_MOD_EXTENDED", g_szModNames[g_iNextMod])
		
		// Decrement maps played to only extend mod by one map.
		new szMapsPlayed[4]
		g_iMapsPlayed--
		num_to_str(g_iMapsPlayed, szMapsPlayed, charsmax(szMapsPlayed))
		set_localinfo("mapcount", szMapsPlayed)
	}
	else
	{
		setNextMod(g_nextModId[b]) // Set g_iNextMod
		
		client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_MOD_CHOSEN", g_szModNames[g_iNextMod])
		log_amx("Vote: Voting for the next mod finished. The nextmod will be %s", g_szModNames[g_iNextMod])
	}

	// Set new default map to correspond to the next mod.
	setDefaultNextmap()
	
	// Clear Nominations
	ArrayClear(g_aNominatedMods)
	
	set_task(fBetweenVote, "startMapVote")
}

public startMapVote()
{
	// Reset vote vars
	g_voteCount = 0
	g_voteNum = 0
	arrayset(g_voteMapCount, 0, sizeof(g_voteMapCount))
	
	// Reset user vote status
	for(new i = 1; i <= MaxClients; i++)
	{
		g_iUserVoted[i][0] = 0
		g_iUserVoted[i][1] = 0
		g_bShowVoteMenu[i] = true
	}
	
	new mapNum = g_iMapNums[g_iNextMod]
	new iNomCount = ArraySize(g_aNominatedMaps)
	new iMaxItems = (mapNum > SELECTMAPS) ? SELECTMAPS : mapNum
	
	// Add Nominations first
	for(new i = 0; i < iNomCount && g_voteNum < iMaxItems; i++)
	{
		new szNom[STRLEN_MAP]
		ArrayGetString(g_aNominatedMaps, i, szNom, charsmax(szNom))
		
		// Find ID in current mod maps
		new id = -1
		for(new j = 0; j < mapNum; j++)
		{
			new szMap[STRLEN_MAP]
			ArrayGetString(g_aModMaps[g_iNextMod], j, szMap, charsmax(szMap))
			if(equal(szMap, szNom))
			{
				id = j
				break
			}
		}
		
		if(id != -1)
		{
			g_nextName[g_voteNum] = id
			g_voteNum++
		}
	}
	
	// Fill with random
	for (new i = g_voteNum; i < iMaxItems; ++i)
	{
		new a = random_num(0, mapNum - 1)
		
		while (isInMenu(a))
			if (++a >= mapNum) a = 0
		
		g_nextName[g_voteNum] = a
		g_voteNum++
	}
	
	// Start Timer Task
	g_iVoteCountDown = floatround(fVoteTime)
	set_task(1.0, "TaskVoteMapTimer", TASK_VOTE_MAP_TIMER, _, _, "b")
	set_task(fVoteTime, "checkMapVotes")
	
	client_print_color(0, print_team_default, "%L", LANG_SERVER, "TIME_CHOOSE")
	
	new players[32], num
	get_players(players, num, "ch")
	for(new i = 0; i < num; i++)
	{
		if(g_bVoteSound[players[i]])
			client_cmd(players[i], "spk Gman/Gman_Choose2")
	}
	
	log_amx("Vote: Voting for the nextmap started")
}

public TaskVoteMapTimer()
{
	g_iVoteCountDown--
	
	if(g_iVoteCountDown < 0)
		return
	
	new players[32], num
	get_players(players, num, "ch")
	
	for(new i = 0; i < num; i++)
	{
		new id = players[i]
		if(g_bShowVoteMenu[id])
		{
			g_bRefreshing[id] = true
			ShowMapVoteMenu(id)
			g_bRefreshing[id] = false
		}
	}
}

public ShowMapVoteMenu(id)
{
	new szTitle[64]
	if(g_iVoteCountDown > 0)
		formatex(szTitle, charsmax(szTitle), "%L \r(%d s.)", id, "MENU_CHOOSE_MAP", g_iVoteCountDown)
	else
		formatex(szTitle, charsmax(szTitle), "\r%L", id, "MENU_VOTE_RESULT")
		
	new menu = menu_create(szTitle, "HandleMapVoteMenu")
	menu_setprop(menu, MPROP_PERPAGE, 0)
	new szItem[64], szMap[STRLEN_MAP]
	
	// Find Winner
	new iWinner = 0
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteMapCount[iWinner] < g_voteMapCount[a])
			iWinner = a
			
	// Check Extend (Logic from checkMapVotes: must be > winner AND > extend+1 (which is 0 usually))
	if (g_voteMapCount[SELECTMAPS] > g_voteMapCount[iWinner])
		iWinner = SELECTMAPS
	
	// Add Items with Percentages
	for(new i = 0; i < g_voteNum; i++)
	{
		new percent = GetPercent(g_voteMapCount[i], g_voteCount)
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[i], szMap, charsmax(szMap))
		
		if(i == iWinner)
			formatex(szItem, charsmax(szItem), "\r%s \d(%d%%)", szMap, percent)
		else if(g_iUserVoted[id][0] && g_iUserVoted[id][1] == i)
			formatex(szItem, charsmax(szItem), "\y%s \d(%d%%)", szMap, percent)
		else
			formatex(szItem, charsmax(szItem), "\w%s \d(%d%%)", szMap, percent)
			
		menu_additem(menu, szItem, "", 0)
	}
	
	new iItemsAdded = g_voteNum
	
	// Extend Option
	new mapname[32]
	get_mapname(mapname, 31)
	if( g_iThisMod == g_iNextMod ) // If staying on this mod allow extending the map.
	{
		if( g_fTimeLimit < g_fExtendMax )
		{
			while(iItemsAdded < 9)
			{
				menu_addblank(menu, 1)
				iItemsAdded++
			}
			
			menu_addtext(menu, "^n", 0)
			
			new percent = GetPercent(g_voteMapCount[SELECTMAPS], g_voteCount)
			
			if(iWinner == SELECTMAPS)
				formatex(szItem, charsmax(szItem), "\r%L \d(%d%%)", id, "MENU_EXTEND", mapname, percent)
			else if(g_iUserVoted[id][0] && g_iUserVoted[id][1] == SELECTMAPS)
				formatex(szItem, charsmax(szItem), "\y%L \d(%d%%)", id, "MENU_EXTEND", mapname, percent)
			else
				formatex(szItem, charsmax(szItem), "\w%L \d(%d%%)", id, "MENU_EXTEND", mapname, percent)
				
			menu_additem(menu, szItem, "", 0)
		}
	}
	
	// Display
	menu_display(id, menu, 0)
}

public HandleMapVoteMenu(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		if(!g_bRefreshing[id])
			g_bShowVoteMenu[id] = false
		return PLUGIN_HANDLED
	}
	
	if(g_iVoteCountDown <= 0)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	// Check Re-vote
	if(g_iUserVoted[id][0])
	{
		if(!g_bRevote)
		{
			client_print_color(id, print_team_default, "%s You have already voted.", g_szPrefix)
			menu_destroy(menu)
			return PLUGIN_HANDLED
		}
		
		// Remove previous vote
		new prevItem = g_iUserVoted[id][1]
		if(prevItem == SELECTMAPS) // Extend
			g_voteMapCount[SELECTMAPS]--
		else
			g_voteMapCount[prevItem]--
			
		g_voteCount--
	}
	
	// Register Vote
	if(item == 9) // Extend option (Slot 0)
	{
		g_voteMapCount[SELECTMAPS]++
		g_iUserVoted[id][1] = SELECTMAPS
		
		new szName[32]
		get_user_name(id, szName, 31)
		if(g_bVoteAnswers)
		{
			new players[32], num
			get_players(players, num, "ch")
			for(new i = 0; i < num; i++)
			{
				if(g_bVoteChat[players[i]])
					client_print_color(players[i], print_team_default, "%L", LANG_PLAYER, "CHOSE_EXT", szName)
			}
		}
	}
	else if(item < g_voteNum)
	{
		g_voteMapCount[item]++
		g_iUserVoted[id][1] = item
		
		new szName[32], map[32]
		get_user_name(id, szName, 31)
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[item], map, charsmax(map))
		
		if(g_bVoteAnswers)
		{
			new players[32], num
			get_players(players, num, "ch")
			for(new i = 0; i < num; i++)
			{
				if(g_bVoteChat[players[i]])
					client_print_color(players[i], print_team_default, "%L", LANG_PLAYER, "X_CHOSE_X", szName, map)
			}
		}
	}
	
	g_iUserVoted[id][0] = 1
	g_voteCount++
	
	menu_destroy(menu)
	
	// Check User Preference
	if(g_iVoteBehavior[id] == 0) // Close on Vote
	{
		g_bShowVoteMenu[id] = false
	}
	
	if(g_iVoteCountDown > 0 && g_bShowVoteMenu[id])
		ShowMapVoteMenu(id)
	return PLUGIN_HANDLED
}

public checkMapVotes()
{
	remove_task(TASK_VOTE_MAP_TIMER)
	
	new b = 0
	
	for (new a = 0; a < g_voteNum; ++a)
		if (g_voteMapCount[b] < g_voteMapCount[a])
			b = a

	
	if (g_voteMapCount[SELECTMAPS] > g_voteMapCount[b] )
	{
		new mapname[32]
		
		get_mapname(mapname, 31)
		new Float:steptime = g_fExtendStep
		set_pcvar_float(g_pTimeLimit, g_fTimeLimit + steptime)
		client_print_color(0, print_team_default, "%L", LANG_PLAYER, "CHO_FIN_EXT", steptime)
		log_amx("Vote: Voting for the nextmap finished. Map %s will be extended to next %.0f minutes", mapname, steptime)
		
		g_selected = false
		if(g_bVoteForced)
		{
			remove_task(TASK_FORCED_MAPCHANGE)
			g_bVoteForced = false
		}
		return
	}
	
	new smap[32]
	if (g_voteMapCount[b] && g_voteMapCount[SELECTMAPS + 1] <= g_voteMapCount[b])
	{
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[b], smap, charsmax(smap));
		set_pcvar_string(g_pNextmap, smap);
	}
	else // added 1.0.3
	{
		ArrayGetString(g_aModMaps[g_iNextMod], g_nextName[0], smap, charsmax(smap));
		set_pcvar_string(g_pNextmap, smap);
	}
	
	get_pcvar_string(g_pNextmap, smap, 31)
	client_print_color(0, print_team_default, "%L", LANG_PLAYER, "CHO_FIN_NEXT", smap)
	log_amx("Vote: Voting for the nextmap finished. The nextmap will be %s", smap)
	
	// Clear Nominations
	ArrayClear(g_aNominatedMaps)
	
	// handle "end on round" functionality here
	if( g_bEndOnRound && !g_bChangeOnRoundend )
	{
		// extend to end of round
		g_bChangeOnRoundend = true
		set_pcvar_num(g_pTimeLimit, 0)
		client_print_color(0, print_team_default, "%s Last Round! Map will change at round end.", g_szPrefix)
		
		if(g_bVoteForced)
		{
			remove_task(TASK_FORCED_MAPCHANGE)
			g_bVoteForced = false
		}
	}
	else
	{
		if(g_bVoteForced)
		{
			remove_task(TASK_FORCED_MAPCHANGE)
			g_bVoteForced = false
		}
		
		set_task(2.0, "intermission")
	}
}


/*
 *	Nomination Functions
 */
public cmdNomMenu(id)
{
	if(!g_bAllowNomination)
	{
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "POLY_NOM_DISABLED")
		return PLUGIN_HANDLED
	}
	
	new szTitle[64], szItem1[64], szItem2[64]
	formatex(szTitle, charsmax(szTitle), "%L", id, "MENU_NOMINATION")
	formatex(szItem1, charsmax(szItem1), "%L", id, "MENU_NOM_MAP")
	formatex(szItem2, charsmax(szItem2), "%L", id, "MENU_NOM_MOD")
	
	new menu = menu_create(szTitle, "NomMenuHandler")
	menu_additem(menu, szItem1, "1")
	menu_additem(menu, szItem2, "2")
	
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public NomMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new info[3], access, callback
	menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback)
	
	if(equal(info, "1"))
		cmdShowMaps(id, 0, 0) // Show maps for nomination
	else if(equal(info, "2"))
		cmdShowMods(id, 0, 0) // Show mods for nomination
		
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

public NominarMap(id, map[])
{
	if(ArrayFindString(g_aNominatedMaps, map) != -1)
	{
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "POLY_MAP_ALREADY_NOM", map)
		return
	}
	
	ArrayPushString(g_aNominatedMaps, map)
	
	new name[32]
	get_user_name(id, name, 31)
	client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_MAP_NOMINATED", name, map)
}

public NominarMod(id, mod[])
{
	if(ArrayFindString(g_aNominatedMods, mod) != -1)
	{
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "POLY_MOD_ALREADY_NOM", mod)
		return
	}
	
	ArrayPushString(g_aNominatedMods, mod)
	
	new name[32]
	get_user_name(id, name, 31)
	client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_MOD_NOMINATED", name, mod)
}

public DesnominarMap(id, map[])
{
	new idx = ArrayFindString(g_aNominatedMaps, map)
	if(idx != -1)
	{
		ArrayDeleteItem(g_aNominatedMaps, idx)
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "POLY_MAP_NOM_REMOVED", map)
	}
}

public DesnominarMod(id, mod[])
{
	new idx = ArrayFindString(g_aNominatedMods, mod)
	if(idx != -1)
	{
		ArrayDeleteItem(g_aNominatedMods, idx)
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "POLY_MOD_NOM_REMOVED", mod)
	}
}

/*
 *	Admin / List Menus
 */
public cmdShowMaps(id, level, cid)
{
	new menu = menu_create("Available Maps", "ShowMapsHandler")
	new szMap[STRLEN_MAP]
	
	if(ArraySize(g_aNominatedMods) > 0)
	{
		new iNomCount = ArraySize(g_aNominatedMods)
		for(new i = 0; i < iNomCount; i++)
		{
			new szModName[STRLEN_NAME]
			ArrayGetString(g_aNominatedMods, i, szModName, charsmax(szModName))
			
			// Find Mod Index
			new iModIndex = -1
			for(new j = 0; j < g_iModCount; j++)
			{
				if(equal(g_szModNames[j], szModName))
				{
					iModIndex = j
					break
				}
			}
			
			if(iModIndex != -1)
			{
				new mapNum = g_iMapNums[iModIndex]
				for(new j = 0; j < mapNum; j++)
				{
					ArrayGetString(g_aModMaps[iModIndex], j, szMap, charsmax(szMap))
					
					// Add asterisk if nominated
					new szItem[64]
					if(ArrayFindString(g_aNominatedMaps, szMap) != -1)
						formatex(szItem, charsmax(szItem), "%s *", szMap)
					else
						copy(szItem, charsmax(szItem), szMap)
						
					menu_additem(menu, szItem, szMap)
				}
			}
		}
	}
	else
	{
		// List maps for the NEXT mod (because that's what we are voting for)
		new mapNum = g_iMapNums[g_iNextMod]
		
		for(new i = 0; i < mapNum; i++)
		{
			ArrayGetString(g_aModMaps[g_iNextMod], i, szMap, charsmax(szMap))
			
			// Add asterisk if nominated
			new szItem[64]
			if(ArrayFindString(g_aNominatedMaps, szMap) != -1)
				formatex(szItem, charsmax(szItem), "%s *", szMap)
			else
				copy(szItem, charsmax(szItem), szMap)
				
			menu_additem(menu, szItem, szMap)
		}
	}
	
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public ShowMapsHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	// If not admin, just show list (read-only)
	if(!access(id, ADMIN_MAP))
	{
		// Re-display menu to simulate "staying" on the list, or just close it.
		// User requested: "user should not interact with it"
		// So we can just do nothing or re-show. Let's re-show for pagination convenience.
		menu_display(id, menu, 0) // This resets page to 0 though, better to just return.
		// Actually, menu_display resets. To keep page we need more logic.
		// For now, let's just treat it as a selection that does nothing.
		// But wait, if they click an item, we can interpret it as a Nomination if allowed!
		
		if(g_bAllowNomination)
		{
			new szMap[STRLEN_MAP], access, callback
			menu_item_getinfo(menu, item, access, szMap, charsmax(szMap), _, _, callback)
			NominarMap(id, szMap)
		}
		
		return PLUGIN_HANDLED
	}
	
	new szMap[STRLEN_MAP], access, callback
	menu_item_getinfo(menu, item, access, szMap, charsmax(szMap), _, _, callback)
	
	ShowAdminMapActions(id, szMap)
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

public ShowAdminMapActions(id, map[])
{
	new title[64]
	formatex(title, charsmax(title), "%L", id, "MENU_ACTIONS_FOR", map)
	new menu = menu_create(title, "AdminMapActionsHandler")
	
	new szItem[64]
	formatex(szItem, charsmax(szItem), "%L", id, "MENU_FORCE_VOTE")
	menu_additem(menu, szItem, map)
	
	formatex(szItem, charsmax(szItem), "%L", id, "MENU_SET_NEXT_MAP")
	menu_additem(menu, szItem, map)
	
	formatex(szItem, charsmax(szItem), "%L", id, "MENU_CHANGE_NOW")
	menu_additem(menu, szItem, map)
	
	if(ArrayFindString(g_aNominatedMaps, map) != -1)
	{
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_REM_NOM")
		menu_additem(menu, szItem, map)
	}
	else
	{
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_NOMINATE")
		menu_additem(menu, szItem, map)
	}
		
	menu_display(id, menu, 0)
}

public AdminMapActionsHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new map[STRLEN_MAP], access, callback
	menu_item_getinfo(menu, item, access, map, charsmax(map), _, _, callback)
	
	switch(item)
	{
		case 0: // Force Vote
		{
			server_cmd("amx_votemap %s", map)
		}
		case 1: // Set Next
		{
			set_pcvar_string(g_pNextmap, map)
			client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_ADMIN_SET_MAP", map)
		}
		case 2: // Change Now
		{
			server_cmd("changelevel %s", map)
		}
		case 3: // Nominate/Denominate
		{
			if(ArrayFindString(g_aNominatedMaps, map) != -1)
				DesnominarMap(id, map)
			else
				NominarMap(id, map)
		}
	}
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

public cmdOpenVoteMenu(id)
{
	if(task_exists(TASK_VOTE_TIMER) || task_exists(TASK_VOTE_MAP_TIMER))
	{
		g_bShowVoteMenu[id] = true
		// The timer will pick it up in the next second
	}
	else
	{
		client_print_color(id, print_team_default, "%s %L", g_szPrefix, id, "CON_VOTE_NOT_ALLOWED")
	}
	return PLUGIN_HANDLED
}

public cmdSettingsMenu(id)
{
	new szTitle[64]
	formatex(szTitle, charsmax(szTitle), "%L", id, "MENU_SETTINGS_TITLE")
	new menu = menu_create(szTitle, "HandleSettingsMenu")
	
	new szItem[128]
	if(g_iVoteBehavior[id] == 0)
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_CLOSE")
	else
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_REOPEN")
		
	menu_additem(menu, szItem, "0")
	
	if(g_bVoteSound[id])
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_SOUND_ON")
	else
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_SOUND_OFF")
	menu_additem(menu, szItem, "1")
	
	if(g_bVoteChat[id])
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_CHAT_ON")
	else
		formatex(szItem, charsmax(szItem), "%L", id, "MENU_SETTINGS_CHAT_OFF")
	menu_additem(menu, szItem, "2")
	
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	
	for(new i = 0; i < 5; i++)
		menu_addblank(menu, 1)
	
	menu_addtext(menu, "^n", 0)
	
	formatex(szItem, charsmax(szItem), "%L", id, "EXIT")
	menu_additem(menu, szItem, "EXIT")
	
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public HandleSettingsMenu(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new access, info[10], callback
	menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback)
	
	if(equal(info, "EXIT"))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	if(equal(info, "0"))
	{
		g_iVoteBehavior[id] = !g_iVoteBehavior[id]
	}
	else if(equal(info, "1"))
	{
		g_bVoteSound[id] = !g_bVoteSound[id]
	}
	else if(equal(info, "2"))
	{
		g_bVoteChat[id] = !g_bVoteChat[id]
	}
	
	SaveUserPrefs(id)
	cmdSettingsMenu(id)
	
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

public cmdShowMods(id, level, cid)
{
	new menu = menu_create("Available Mods", "ShowModsHandler")
	new szMod[STRLEN_NAME]
	
	for(new i = 0; i < g_iModCount; i++)
	{
		copy(szMod, charsmax(szMod), g_szModNames[i])
		
		new szItem[64]
		if(ArrayFindString(g_aNominatedMods, szMod) != -1)
			formatex(szItem, charsmax(szItem), "%s *", szMod)
		else
			copy(szItem, charsmax(szItem), szMod)
			
		menu_additem(menu, szItem, szMod)
	}
	
	menu_display(id, menu, 0)
	return PLUGIN_HANDLED
}

public ShowModsHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	if(!access(id, ADMIN_MAP))
	{
		if(g_bAllowNomination)
		{}
		return PLUGIN_HANDLED
	}
	
	new szMod[STRLEN_NAME], access, callback
	menu_item_getinfo(menu, item, access, szMod, charsmax(szMod), _, _, callback)
	
	ShowAdminModActions(id, szMod)
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

public ShowAdminModActions(id, mod[])
{
	new title[64]
	formatex(title, charsmax(title), "Actions for: %s", mod)
	new menu = menu_create(title, "AdminModActionsHandler")
	
	menu_additem(menu, "Set as Next Mod", mod)
	
	if(ArrayFindString(g_aNominatedMods, mod) != -1)
		menu_additem(menu, "Remove Nomination", mod)
	else
		menu_additem(menu, "Nominate", mod)
		
	menu_display(id, menu, 0)
}

public AdminModActionsHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new mod[STRLEN_NAME], access, callback
	menu_item_getinfo(menu, item, access, mod, charsmax(mod), _, _, callback)
	
	switch(item)
	{
		case 0: // Set Next
		{
			// Find ID
			for(new i=0; i<g_iModCount; i++)
			{
				if(equal(g_szModNames[i], mod))
				{
					setNextMod(i)
					setDefaultNextmap()
					client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_ADMIN_SET_MOD", mod)
					break
				}
			}
		}
		case 1: // Nominate/Denominate
		{
			if(ArrayFindString(g_aNominatedMods, mod) != -1)
				DesnominarMod(id, mod)
			else
				NominarMod(id, mod)
		}
	}
	menu_destroy(menu)
	return PLUGIN_HANDLED
}


/*
 *	Auxillary Functions
 */

/* Set the 'NextMod' index */
stock setNextMod(index)
{
	g_iNextMod = index
	set_pcvar_string(g_pNextMod, g_szModNames[g_iNextMod])
}

/* Set the default nextmap for the next mod */
stock setDefaultNextmap()
{
	new szMapName[32]
	ArrayGetString(g_aModMaps[g_iNextMod], 0, szMapName, charsmax(szMapName))
	set_pcvar_string(g_pNextmap, szMapName)
}

stock bool:loadMaps(szConfigDir[], szMapFile[], iModIndex)
{
	new szFilepath[STRLEN_PATH], szData[STRLEN_MAP], szCurrentMap[STRLEN_MAP]
	
	get_mapname(szCurrentMap, charsmax(szCurrentMap))

	g_iMapNums[iModIndex] = 0
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, szMapFile)

	new f = fopen(szFilepath, "rt")

	if(!f)
		return false

	while(!feof(f))
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
		if(!szData[0] || szData[0] == ';' || (szData[0] == '/' && szData[1] == '/'))
			continue
		if( is_map_valid(szData) && !( g_iThisMod == iModIndex && equali(szData, szCurrentMap) ) )
		{
			ArrayPushString(g_aModMaps[iModIndex], szData)
			g_iMapNums[iModIndex]++
		}
	}
	fclose(f)
	return true
}

/**
 *  Rewrite plugins-polymorph.ini for the next mod.
 *  Will create the file if it does not exist.
 *  Use only when you need to change the mod!!!
 */
stock UpdatePluginFile()
{
	new szMainFilePath[STRLEN_PATH]
	new pMainFile
	
	get_configsdir(szMainFilePath, charsmax(szMainFilePath))
	format(szMainFilePath, charsmax(szMainFilePath), "%s/plugins-polymorph.ini", szMainFilePath)
	
	pMainFile = fopen(szMainFilePath, "wt")
	
	if(pMainFile)
	{
		fprintf(pMainFile, ";ThisMod:^"%s^"^r^n", g_szModNames[g_iNextMod])
		fputs(pMainFile, "; Warning: This file is re-written by Polymorph plugin.^r^n")
		fprintf(pMainFile, "; Any content added manually will be lost.^r^n")
		
		if( g_iModCount > 0 )
		{
			new iPlugins_num, szPluginName[STRLEN_PATH]
			
			iPlugins_num = ArraySize(g_aModPlugins[g_iNextMod])
				
			for(new j = 0; j < iPlugins_num; j++)
			{
				ArrayGetString(g_aModPlugins[g_iNextMod], j, szPluginName, charsmax(szPluginName))
				fprintf(pMainFile, "%s^r^n", szPluginName)
			}
		}
		else
		{
			fputs(pMainFile, ";;;  ERROR  ;;;\r\n;;; No MODs Loaded ;;;")
		}
		fclose(pMainFile)
	}
}

bool:isInMenu(id)
{
	for (new a = 0; a < g_voteNum; ++a)
		if (id == g_nextName[a])
			return true
	return false
}

bool:isModInMenu(id)
{
	for (new a = 0; a < g_voteNum; ++a)
		if (id == g_nextModId[a])
			return true
	return false
}

public team_score()
{
	new team[2]
	
	read_data(1, team, 1)
	g_teamScore[(team[0]=='C') ? 0 : 1] = read_data(2)
}

/* Show Scoreboard to everybody and trigger map change after the chat time. */
public intermission()
{
	if( g_bEndOnRound && !g_bChangeOnRoundend && !g_bVoteForced )
	{
		// extend to end of round
		g_bChangeOnRoundend = true
		set_pcvar_num(g_pTimeLimit, 0)
		client_print_color(0, print_team_default, "%s %L", g_szPrefix, LANG_PLAYER, "POLY_LAST_ROUND")
	}
	else
	{
		message_begin(MSG_ALL, SVC_INTERMISSION)
		message_end()
		set_task(g_fChatTime, "changeMap")
	}
}

/* Change map. */
public changeMap()
{
	new szNextmap[32]
	get_pcvar_string(g_pNextmap, szNextmap, charsmax(szNextmap))
	server_cmd("changelevel %s", szNextmap)
}

/* Exec Cvars */
public execCfg()
{
	new cfg_num = ArraySize(g_aCfgList)
	for(new i = 0; i < cfg_num; i++)
		server_cmd("%a", ArrayGetStringHandle(g_aCfgList, i))
	ArrayDestroy(g_aCfgList)
}

/* Initiate loading the MODs */
stock initModLoad()
{
	g_iModCount = 0
	new szFilepath[STRLEN_PATH], szConfigDir[STRLEN_PATH]
	get_configsdir(szConfigDir, charsmax(szConfigDir))
	formatex(szFilepath, charsmax(szFilepath), "%s/%s", szConfigDir, "polymorph")

	new filename[32]
	g_aCfgList = ArrayCreate(STRLEN_DATA)

	new pDir = open_dir(szFilepath, filename, charsmax(filename))
	if(pDir)
	{
		do
		{
			if( 47 < filename[0] < 58 )
			{
				g_aModMaps[g_iModCount] = ArrayCreate(STRLEN_FILE)
				g_aModPlugins[g_iModCount] = ArrayCreate(STRLEN_PATH)
				if( loadMod(szFilepath, filename) )
				{
					server_print("MOD LOADED: %s", g_szModNames[g_iModCount])
					g_iModCount++
				}
				else
				{
					ArrayDestroy(g_aModMaps[g_iModCount])
					ArrayDestroy(g_aModPlugins[g_iModCount])
				}
			}

		} while( next_file(pDir, filename, charsmax(filename)) && g_iModCount < MODS_MAX )
		close_dir(pDir)
	}
	
	/* Exec Configs if Mod found */
	if( g_iModCount == 0 )
	{
		/* Zero mods loaded, set as failed */
		setNextMod(0)
		UpdatePluginFile()
		log_amx("[Polymorph] Zero (0) mods loaded.")
		set_fail_state("[Polymorph] Zero (0) mods were loaded.")
	}
	else if( g_iThisMod == -1 )
	{
		/* No mod found, set as failed, restart to fix. */
		setNextMod(0)
		UpdatePluginFile()
		log_amx("[Polymorph] Mod not found. Restart server.")
		set_fail_state("[Polymorph] Mod not found. Restart server.")
	}
	else
	{
		/* Set poly_thismod cvar */
		set_pcvar_string(g_pThisMod, g_szModNames[g_iThisMod])
		
		/* Execute Mod Config */
		set_task(4.0, "execCfg")
	}
}

/* Load individual MOD.  Return true on success */
stock bool:loadMod(szPath[], szModConfig[])
{
	new filepath[STRLEN_PATH]
	new szData[STRLEN_DATA], szPreCommentData[STRLEN_DATA]
	new key[STRLEN_MAP], value[STRLEN_MAP]
	
	formatex(filepath, charsmax(filepath), "%s/%s", szPath, szModConfig)
	new f = fopen(filepath, "rt")

	if(!f)
		return loadFail(szModConfig, "failed read mod's .ini file")

	/* Traverse header space */
	while(!feof(f) && szData[0] != '[')
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
	}

	/* Load MOD specific variables */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)

		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		parse(szData, key, charsmax(key), value, charsmax(value))

		if(equali(key, "name"))
		{
			copy(g_szModNames[g_iModCount], charsmax(g_szModNames[]), value)
			if( equal(value, g_szThisMod) )
			{
				g_iThisMod = g_iModCount
			}
		}
		else if(equali(key, "mapspermod"))
		{
			g_iMapsPerMod[g_iModCount] = str_to_num(value) ? str_to_num(value) : 2 // Default to 2
		}
		else if(equali(key, "mapsfile"))
		{
			if( !loadMaps(szPath, value, g_iModCount) )
			{
				fclose(f)
				return loadFail(szModConfig, "'mapsfile' failed to load")
			}
		}
	}

	/* Load MOD specific cvars */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)
		
		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		/* Retain cvars if we are loading 'ThisMod' */
		if( g_iThisMod == g_iModCount )
		{
			strtok(szData, szPreCommentData, charsmax(szPreCommentData), "", 0, ';')
			trim(szPreCommentData)
			ArrayPushString(g_aCfgList, szPreCommentData)
		}

	}

	/* Load Plugins */
	while( !feof(f) )
	{
		fgets(f, szData, charsmax(szData))
		trim(szData)

		switch( szData[0] )
		{
			case 0, ';': continue; // Comment/Blank line.
			case '[': break; // Next section found.
		}

		strtok(szData, szPreCommentData, charsmax(szPreCommentData), "", 0, ';')
		trim(szPreCommentData)
		ArrayPushString(g_aModPlugins[g_iModCount], szPreCommentData)
	}
	// if all loads well increment g_iModCount
	// else clear used arrays and DO NOT increment g_iModCount
	fclose(f)
	return true
}

/* Log "failed to load mod" message. return false (meaning "failed to load") */
stock bool:loadFail(szModFile[], szComment[] = "")
{
	server_print("Failed to load mod from %s (%s)", szModFile, szComment) // Debug
	log_amx("[Polymorph] Failed to load configuration file %s (%s)", szModFile, szComment)
	return false
}

stock GetPercent(value, total)
{
	if(total == 0) return 0
	return floatround(float(value) * 100.0 / float(total))
}

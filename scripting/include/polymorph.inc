/*
 *	Include for Polymorph by Fysiks
 */

#if defined _polymorph_included
	#endinput
#endif
#define _polymorph_included

#pragma reqlib "polymorph"


/**
 * Executes the end of map vote.
 * Follows the restrictions set by poly_mode.
 *
 * @noreturn
 */
native polyn_endofmap()

/**
 * Gets the current mod's name and ID.
 *
 * @param modname   Buffer to store the mod name.
 * @param len       Maximum length of the buffer.
 *
 * @return          The ID of the current mod.
 */
native polyn_get_thismod(modname[], len)

/**
 * Gets the next mod's name and ID.
 *
 * @param modname   Buffer to store the mod name.
 * @param len       Maximum length of the buffer.
 *
 * @return          The ID of the next mod.
 */
native polyn_get_nextmod(modname[], len)

/**
 * Gets a specific mod's name by its ID.
 *
 * @param modId     The ID of the mod to retrieve.
 * @param buffer    Buffer to store the mod name.
 * @param len       Maximum length of the buffer.
 *
 * @return          1 on success, 0 if modId is invalid.
 */
native polyn_get_mod(modId, buffer[], len)

/**
 * Gets the total number of loaded mods.
 *
 * @return          The number of mods loaded.
 */
native polyn_get_modlist()

/**
 * Sets the next mod manually.
 *
 * @param id        The client index performing the action (0 for server/plugin).
 *                  If set, chat/console messages will be displayed to this user/all.
 * @param modId     The ID of the mod to set as next.
 *
 * @return          1 on success, 0 on failure (invalid modId or already set).
 */
native polyn_set_nextmod(id, modId)

/**
 * Starts a vote for the next mod and forces a map change afterwards.
 *
 * @noreturn
 */
native polyn_votemod()
 
--!strict
--[[
	Tags
	CollectionService tag names shared by server and client.
]]

return table.freeze({
	Creature = "Creature", -- creature models standing on pedestals
	OwnerOnlyPrompt = "OwnerOnlyPrompt", -- prompts only the owner (OwnerUserId attribute) should see
	StealPrompt = "StealPrompt", -- "Steal" prompts on adult creatures (shown to eligible raiders)
	ArenaPrompt = "ArenaPrompt", -- the lobby arena desk; opens the Arena window
})

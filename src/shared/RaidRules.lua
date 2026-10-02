--!strict
--[[
	RaidRules
	The fairness rules for night raids, in one pure module used by the server (to
	decide) and the client (to show or hide prompts and shields). The server is
	always the one that enforces them.

	  * New-player shield: protected until Config.NewPlayerShieldMinutes of total
	    playtime OR a base worth more than Config.NewPlayerShieldValue. Stealing
	    from someone ends your own protection.
	  * Value bracket: you may only raid bases worth RaidValueBracketMin..Max times
	    your own base value.
	  * Revenge: a victim may raid their thief for Config.RevengeWindowSec, even by
	    day and ignoring the bracket.
	  * Lock slot and steal cooldown are per-creature / per-player checks done by
	    RaidService.
]]

local Config = require(script.Parent.Config)

export type RaidCheck = {
	isNight: boolean,
	attackerValue: number,
	victimValue: number,
	victimProtected: boolean,
	hasRevenge: boolean,
}

local RaidRules = {}

function RaidRules.isProtected(playtimeSec: number, baseValue: number, hasStolen: boolean): boolean
	if hasStolen then
		return false
	end
	return playtimeSec < Config.NewPlayerShieldMinutes * 60 and baseValue <= Config.NewPlayerShieldValue
end

function RaidRules.inBracket(attackerValue: number, victimValue: number): boolean
	if attackerValue <= 0 or victimValue <= 0 then
		return false
	end
	local ratio = victimValue / attackerValue
	return ratio >= Config.RaidValueBracketMin and ratio <= Config.RaidValueBracketMax
end

-- Returns whether the raid is allowed and, if not, a short reason for the player.
function RaidRules.canRaid(check: RaidCheck): (boolean, string?)
	if check.hasRevenge then
		return true, nil
	end
	if not check.isNight then
		return false, "Raids only happen at night"
	end
	if check.victimProtected then
		return false, "This player is new and protected for now"
	end
	if not RaidRules.inBracket(check.attackerValue, check.victimValue) then
		return false, "That base is out of your league (value bracket)"
	end
	return true, nil
end

return table.freeze(RaidRules)

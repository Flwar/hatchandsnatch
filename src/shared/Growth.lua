--!strict
--[[
	Growth
	Pure growth math shared by server and client. Growth is always computed from
	timestamps (plantedAt = os.time() when placed), never from per-frame timers, so
	it keeps going while the player is offline and every machine agrees on it.

	  Egg   -> Baby  at Config.BabyAtFraction  of growTimeSec
	  Baby  -> Adult at Config.AdultAtFraction of growTimeSec
]]

local Config = require(script.Parent.Config)

export type Stage = "Egg" | "Baby" | "Adult"

local Growth = {}

local EGG: Stage = "Egg"
local BABY: Stage = "Baby"
local ADULT: Stage = "Adult"

-- 0..1 share of the full grow time that has passed.
function Growth.progress(growTimeSec: number, plantedAt: number, now: number): number
	if growTimeSec <= 0 then
		return 1
	end
	return math.clamp((now - plantedAt) / growTimeSec, 0, 1)
end

function Growth.stage(growTimeSec: number, plantedAt: number, now: number): Stage
	local progress = Growth.progress(growTimeSec, plantedAt, now)
	if progress >= Config.AdultAtFraction then
		return ADULT
	elseif progress >= Config.BabyAtFraction then
		return BABY
	end
	return EGG
end

-- Seconds until the next stage begins, or nil once the creature is an adult.
function Growth.secondsToNextStage(growTimeSec: number, plantedAt: number, now: number): number?
	local elapsed = now - plantedAt
	local hatchAt = growTimeSec * Config.BabyAtFraction
	local adultAt = growTimeSec * Config.AdultAtFraction
	if elapsed < hatchAt then
		return hatchAt - elapsed
	elseif elapsed < adultAt then
		return adultAt - elapsed
	end
	return nil
end

return table.freeze(Growth)

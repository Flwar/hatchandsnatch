--!strict
--[[
	Weather
	The four weather events and the rules for them, shared by the server (which runs
	them) and the client (which shows them). Numbers live in Config.WeatherEvents.

	  Golden Rain     -> Golden   x2
	  Lightning Storm -> Electric x3
	  Frost           -> Frozen   x1.5
	  Rainbow         -> Rainbow  x5

	While an event runs, every creature that is still growing (egg or baby) and has
	no mutation yet rolls `chance` every Config.WeatherTickSec seconds.
]]

local Config = require(script.Parent.Config)
local Types = require(script.Parent.Types)

export type Event = {
	id: string,
	name: string,
	icon: string,
	mutation: Types.Mutation,
	weight: number,
	chance: number,
	color: Color3, -- banner and HUD color
	tint: Color3, -- screen tint while it lasts
}

local Weather = {}

local ORDER = { "GoldenRain", "LightningStorm", "Frost", "Rainbow" }

local LOOKS: { [string]: { name: string, icon: string, color: Color3, tint: Color3 } } = {
	GoldenRain = {
		name = "Golden Rain",
		icon = "🌟",
		color = Color3.fromRGB(255, 204, 60),
		tint = Color3.fromRGB(255, 238, 196),
	},
	LightningStorm = {
		name = "Lightning Storm",
		icon = "⚡",
		color = Color3.fromRGB(110, 200, 255),
		tint = Color3.fromRGB(176, 190, 255),
	},
	Frost = {
		name = "Frost",
		icon = "❄️",
		color = Color3.fromRGB(190, 236, 255),
		tint = Color3.fromRGB(214, 234, 255),
	},
	Rainbow = {
		name = "Rainbow",
		icon = "🌈",
		color = Color3.fromRGB(255, 120, 220),
		tint = Color3.fromRGB(255, 240, 250),
	},
}

local LIST: { Event } = {}
local BY_ID: { [string]: Event } = {}
for _, id in ORDER do
	local numbers = (Config.WeatherEvents :: any)[id]
	local look = LOOKS[id]
	assert(numbers and look, `Weather: missing config or look for {id}`)
	local event: Event = {
		id = id,
		name = look.name,
		icon = look.icon,
		mutation = numbers.mutation,
		weight = numbers.weight,
		chance = numbers.chance,
		color = look.color,
		tint = look.tint,
	}
	table.freeze(event)
	table.insert(LIST, event)
	BY_ID[id] = event
end

Weather.Events = table.freeze(LIST)

function Weather.get(id: string): Event?
	return BY_ID[id]
end

-- The event that gives `mutation`, if any.
function Weather.forMutation(mutation: string): Event?
	for _, event in LIST do
		if event.mutation == mutation then
			return event
		end
	end
	return nil
end

-- Picks an event using the configured weights.
function Weather.pick(rng: Random): Event
	local total = 0
	for _, event in LIST do
		total += event.weight
	end
	local roll = rng:NextNumber() * total
	for _, event in LIST do
		roll -= event.weight
		if roll <= 0 then
			return event
		end
	end
	return LIST[#LIST]
end

-- Seconds until the next event, and how long an event lasts.
function Weather.gap(rng: Random): number
	if Config.Debug.FastWeather then
		return rng:NextInteger(30, 45)
	end
	return rng:NextInteger(Config.WeatherMinGapSec, Config.WeatherMaxGapSec)
end

function Weather.length(rng: Random): number
	return rng:NextInteger(Config.WeatherMinLengthSec, Config.WeatherMaxLengthSec)
end

-- One tick of an event for one creature: does it mutate now?
function Weather.rollMutation(rng: Random, event: Event, stage: string, mutation: string?): boolean
	if mutation ~= nil or stage == "Adult" then
		return false
	end
	return rng:NextNumber() < event.chance
end

return table.freeze(Weather)

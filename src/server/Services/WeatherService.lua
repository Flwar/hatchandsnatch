--!strict
--[[
	WeatherService
	Every few minutes (Config.WeatherMinGapSec..MaxGapSec) a random weather event
	starts and lasts Config.WeatherMinLengthSec..MaxLengthSec (see shared/Weather):
	Golden Rain, Lightning Storm, Frost or Rainbow.

	While it lasts, every creature that is still growing (egg or baby), standing on
	its pedestal and not mutated yet rolls the event's chance every
	Config.WeatherTickSec seconds. A hit gives it the event's mutation for good: the
	model is rebuilt with the new look and its income is multiplied (Economy).

	The current event is published as Workspace attributes so every client can show
	it: Weather (event id, "" when clear) and WeatherEndsAt (server clock).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CreatureData = require(Shared:WaitForChild("CreatureData"))
local Economy = require(Shared:WaitForChild("Economy"))
local Growth = require(Shared:WaitForChild("Growth"))
local Weather = require(Shared:WaitForChild("Weather"))
local Signal = require(Shared:WaitForChild("Util"):WaitForChild("Signal"))

local Util = script.Parent.Parent:WaitForChild("Util")
local Net = require(Util:WaitForChild("Net"))
local Ticker = require(Util:WaitForChild("Ticker"))

local CreatureService = require(script.Parent:WaitForChild("CreatureService"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local WeatherService = {}

-- Fired as (event) when weather starts and () when it clears; (player, record, mutation) on a mutation.
WeatherService.Started = Signal.new()
WeatherService.Ended = Signal.new()
WeatherService.Mutated = Signal.new()

local rng = Random.new()
local current: Weather.Event? = nil
local endsAt = 0 -- os.clock()
local nextAt = 0 -- os.clock()

function WeatherService.current(): Weather.Event?
	return current
end

local function publish()
	Workspace:SetAttribute("Weather", if current then current.id else "")
	Workspace:SetAttribute("WeatherEndsAt", if current then Workspace:GetServerTimeNow() + (endsAt - os.clock()) else 0)
end

-- Starts an event now (a random one unless `id` names one). Also used by tests in Studio.
function WeatherService.begin(id: string?)
	local event = if id then Weather.get(id) else nil
	event = event or Weather.pick(rng)
	if not event then
		return
	end
	current = event
	endsAt = os.clock() + Weather.length(rng)
	publish()
	WeatherService.Started:fire(event)
end

function WeatherService.finish()
	if not current then
		return
	end
	current = nil
	nextAt = os.clock() + Weather.gap(rng)
	publish()
	WeatherService.Ended:fire()
end

local function mutate(event: Weather.Event)
	local now = os.time()
	for uid, entry in CreatureService.all() do
		if entry.state ~= "Placed" then
			continue
		end
		local record = entry.record
		local def = CreatureData.get(record.id)
		if not def then
			continue
		end
		local stage = Growth.stage(def.growTimeSec, record.plantedAt, now)
		if not Weather.rollMutation(rng, event, stage, record.mutation) then
			continue
		end
		record.mutation = event.mutation
		CreatureService.rebuild(uid, true)
		local owner = entry.owner
		local multiplier = Economy.mutationMultiplier(event.mutation)
		Net.notify(
			owner,
			`{event.icon} Your {def.displayName} turned {string.upper(event.mutation)}! (x{multiplier} income)`,
			"success"
		)
		WeatherService.Mutated:fire(owner, record, event.mutation)
		DataService.save(owner)
	end
end

function WeatherService.init()
	nextAt = os.clock() + (if Config.Debug.FastWeather then 15 else Weather.gap(rng))
	publish()
end

function WeatherService.start()
	Ticker.every("Weather", 1, function()
		if current then
			if os.clock() >= endsAt then
				WeatherService.finish()
			end
		elseif os.clock() >= nextAt and #Players:GetPlayers() > 0 then
			WeatherService.begin()
		end
	end)
	Ticker.every("WeatherMutations", Config.WeatherTickSec, function()
		local event = current
		if event then
			mutate(event)
		end
	end)
end

return WeatherService

--!strict
--[[
	DataSchema
	The saved PlayerData shape: the default template for new players and migrate(),
	which upgrades any older save to Config.DataSchemaVersion and repairs bad
	values. Pure (no services), so it is unit-tested in tests/run.luau.

	When the schema changes: bump Config.DataSchemaVersion, add the new field to
	template(), and add a step in migrate() that converts old saves.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Types = require(Shared:WaitForChild("Types"))

type PlayerData = Types.PlayerData

local DataSchema = {}

function DataSchema.template(): PlayerData
	return {
		version = Config.DataSchemaVersion,
		coins = Config.StartingCoins,
		padCoins = 0,
		pedestals = Config.StartingPedestals,
		creatures = {},
		traps = {},
		discoveries = {},
		trophies = 0,
		totalPlaytime = 0,
		lastLogout = 0,
		receipts = {},
		funnel = {},
	}
end

local function number(value: any, fallback: number): number
	local n = tonumber(value)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return fallback
	end
	return n
end

-- Upgrades `raw` in place (and returns it) so it matches the current schema.
function DataSchema.migrate(raw: { [string]: any }): PlayerData
	local template = DataSchema.template() :: any
	for key, value in template do
		if type(value) == "number" then
			raw[key] = number(raw[key], value) -- keeps numeric strings, repairs NaN and garbage
		elseif raw[key] == nil or type(raw[key]) ~= type(value) then
			raw[key] = value
		end
	end
	local version = number(raw.version, 0)
	-- Future migrations go here, oldest first, e.g.:
	-- if version < 2 then raw.newField = ...; version = 2 end
	raw.version = math.max(version, Config.DataSchemaVersion)
	raw.coins = math.max(0, number(raw.coins, 0))
	raw.padCoins = math.max(0, number(raw.padCoins, 0))
	raw.trophies = math.max(0, math.floor(number(raw.trophies, 0)))
	raw.pedestals = math.clamp(
		math.floor(number(raw.pedestals, Config.StartingPedestals)),
		Config.StartingPedestals,
		Config.MaxPedestals
	)
	-- Drop malformed creature records rather than crash on them later.
	local creatures = {}
	for _, record in raw.creatures do
		if
			type(record) == "table"
			and type(record.uid) == "string"
			and type(record.id) == "string"
			and type(record.plantedAt) == "number"
		then
			record.slot = math.floor(number(record.slot, 0))
			record.locked = record.locked == true
			table.insert(creatures, record)
		end
	end
	raw.creatures = creatures
	return raw :: PlayerData
end

return table.freeze(DataSchema)

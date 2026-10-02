--!strict
--[[
	MyCreatures
	The local player's creatures, read from the attributes the server puts on every
	creature model, so menus always match what stands on the pedestals.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tags = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tags"))

local MyCreatures = {}

export type Row = {
	uid: string,
	id: string,
	slot: number,
	stage: string,
	locked: boolean,
	mutation: string?,
	home: boolean, -- standing on its pedestal (not being carried off by a raider)
	model: Model,
}

local player = Players.LocalPlayer

-- Every creature the local player owns, by pedestal slot.
function MyCreatures.list(): { Row }
	local rows: { Row } = {}
	for _, instance in CollectionService:GetTagged(Tags.Creature) do
		if not instance:IsA("Model") or instance:GetAttribute("OwnerUserId") ~= player.UserId then
			continue
		end
		local model = instance :: Model
		local uid, id, slot, stage =
			model:GetAttribute("Uid"),
			model:GetAttribute("CreatureId"),
			model:GetAttribute("Slot"),
			model:GetAttribute("Stage")
		local mutation = model:GetAttribute("Mutation")
		if
			typeof(uid) == "string"
			and typeof(id) == "string"
			and typeof(slot) == "number"
			and typeof(stage) == "string"
		then
			local parent = model.Parent
			table.insert(rows, {
				uid = uid,
				id = id,
				slot = slot,
				stage = stage,
				locked = model:GetAttribute("Locked") == true,
				mutation = if typeof(mutation) == "string" then mutation else nil,
				home = parent ~= nil and parent.Name == "Creatures",
				model = model,
			})
		end
	end
	table.sort(rows, function(a, b)
		return a.slot < b.slot
	end)
	return rows
end

return MyCreatures

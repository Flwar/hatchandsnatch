--!strict
--[[
	Character
	Server helpers for a player's character: its root part and distance checks.
	Every action that happens "near" something (buying, collecting, selling) checks
	the distance on the server; the client's word is never enough.
]]

local Character = {}

function Character.root(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root :: BasePart
	end
	return nil
end

-- Distance from the player's character to `position`, or math.huge without a character.
function Character.distanceTo(player: Player, position: Vector3): number
	local root = Character.root(player)
	if not root then
		return math.huge
	end
	return (root.Position - position).Magnitude
end

-- True if the player is alive and within `range` studs of `position`.
function Character.isNear(player: Player, position: Vector3, range: number): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if not humanoid or humanoid.Health <= 0 then
		return false
	end
	return Character.distanceTo(player, position) <= range
end

return table.freeze(Character)

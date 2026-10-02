--!strict
--[[
	Remotes
	The single registry of every RemoteEvent and RemoteFunction in the game.
	The server creates them under ReplicatedStorage.Remotes (Remotes.setup); both sides
	fetch them by name with Remotes.event / Remotes.func.

	Server code never listens to a remote directly: it goes through server/Util/Net,
	which validates argument types, rate-limits per player and catches errors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Kind = "Event" | "Function"

local Remotes = {}

-- Every remote, by name. Direction is documented next to each one.
local DEFINITIONS: { [string]: Kind } = {
	-- Server -> client
	Notify = "Event", -- (message: string, kind: string?) shows a toast
	OfflineEarnings = "Event", -- (coins: number, secondsAway: number) "While you were away" popup
	TheftAnnounced = "Event", -- (thief: string, victim: string, rarity: string, creature: string)
	RevengeStarted = "Event", -- (thiefUserId: number, expiresAt: number) sent to the victim
	HonkAlert = "Event", -- (raiderUserId: number) a Honk Egg went off in your base
	BatHit = "Event", -- (position: Vector3) play bonk effects
	TrapSprung = "Event", -- (trapType: string, position: Vector3) play trap effects
	-- Client -> server
	ClientReady = "Event", -- () the client finished loading its UI
	BatSwing = "Event", -- () swing the equipped bonk bat
	SetLocked = "Event", -- (uid: string, locked: boolean) lock/unlock one of your creatures
	BuyTrap = "Event", -- (trapType: string) buy a trap for your base
	BuyPedestal = "Event", -- () unlock your next pedestal (Shop)
	SellCreature = "Event", -- (uid: string) sell one of your creatures (Inventory)
	SaveSettings = "Event", -- (sfx: boolean, labels: boolean)
	TutorialAck = "Event", -- () finished reading the last tutorial note
	GetProfile = "Function", -- () -> ProfileSummary for menus
}
Remotes.Definitions = table.freeze(DEFINITIONS)

local FOLDER_NAME = "Remotes"

-- Server only: creates the Remotes folder and one instance per definition.
function Remotes.setup(): Folder
	assert(RunService:IsServer(), "Remotes.setup can only run on the server")
	local existing = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = FOLDER_NAME
	for name, kind in DEFINITIONS do
		local remote: Instance = if kind == "Function"
			then Instance.new("RemoteFunction")
			else Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

local function getRemote(name: string, kind: Kind): Instance
	assert(DEFINITIONS[name] == kind, `Remote "{name}" is not a defined {kind}`)
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name)
end

function Remotes.event(name: string): RemoteEvent
	return getRemote(name, "Event") :: RemoteEvent
end

function Remotes.func(name: string): RemoteFunction
	return getRemote(name, "Function") :: RemoteFunction
end

return table.freeze(Remotes)

--!strict
--[[
	Sounds
	Plays the sounds listed in Config.Sounds, locally only, respecting the player's
	sound-effects setting. 2D sounds for UI and personal events, 3D sounds at a
	position for things happening in the world (bonks, traps).
]]

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

type SoundSpec = { id: string, volume: number, pitch: number }

local Sounds = {}

Sounds.enabled = true

local cache: { [string]: Sound } = {}

local function spec(name: string): SoundSpec?
	return (Config.Sounds :: { [string]: SoundSpec })[name]
end

local function make(name: string): Sound?
	local s = spec(name)
	if not s then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = s.id
	sound.Volume = s.volume
	sound.PlaybackSpeed = s.pitch
	return sound
end

function Sounds.play(name: string)
	if not Sounds.enabled then
		return
	end
	local sound = cache[name]
	if not sound then
		local created = make(name)
		if not created then
			return
		end
		created.Parent = SoundService
		cache[name] = created
		sound = created
	end
	SoundService:PlayLocalSound(sound)
end

function Sounds.playAt(name: string, position: Vector3)
	if not Sounds.enabled then
		return
	end
	local sound = make(name)
	if not sound then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.WorldPosition = position
	attachment.Parent = Workspace.Terrain
	sound.RollOffMaxDistance = 120
	sound.Parent = attachment
	sound:Play()
	Debris:AddItem(attachment, 4)
end

return Sounds

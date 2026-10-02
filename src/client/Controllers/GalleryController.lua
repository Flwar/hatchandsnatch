--!strict
--[[
	GalleryController
	Development showroom (Config.Debug.ShowCreatureGallery): builds every creature
	model on podiums in the lobby, locally on this client, with a gentle idle bob
	and sway. Turn it off in Config before publishing.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Gallery = require(Shared:WaitForChild("Models"):WaitForChild("Gallery"))

local GalleryController = {}

local ANIMATE_DISTANCE = 110

function GalleryController.init() end

function GalleryController.start()
	if not Config.Debug.ShowCreatureGallery then
		return
	end
	local map = Workspace:WaitForChild("Map", 60)
	local lobby = if map then map:WaitForChild("Lobby", 30) else nil
	local anchorInstance = if lobby then lobby:WaitForChild("GalleryAnchor", 30) else nil
	if not anchorInstance or not anchorInstance:IsA("BasePart") then
		warn("[Gallery] GalleryAnchor not found; skipping showroom")
		return
	end
	local anchor = anchorInstance :: BasePart
	local folder = Instance.new("Folder")
	folder.Name = "CreatureGallery"
	folder.Parent = Workspace
	local entries = Gallery.build(anchor.CFrame, folder)

	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local now = os.clock()
		for index, entry in entries do
			if (camera.CFrame.Position - entry.home.Position).Magnitude < ANIMATE_DISTANCE then
				local phase = index * 0.7
				local bob = math.abs(math.sin(now * 2.2 + phase)) * 0.25
				local sway = math.sin(now * 0.8 + phase) * 0.35
				entry.model:PivotTo(entry.home * CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, 0))
			end
		end
	end)
end

return GalleryController

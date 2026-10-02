--!strict
--[[
	TutorialController
	Shows the onboarding step the server tracks (player attribute "TutorialStep"):
	a hint card, a spinning 3D arrow over the target and a glowing guide beam from
	the player to it. Steps: conveyor -> pedestal -> collect pad -> night note.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Tags = require(Shared:WaitForChild("Tags"))
local UI = script.Parent.Parent:WaitForChild("UI")
local Popup = require(UI:WaitForChild("Popup"))
local Theme = require(UI:WaitForChild("Theme"))

local TutorialController = {}

local player = Players.LocalPlayer
local ARROW_COLOR = Color3.fromRGB(255, 220, 60)
local HINTS = {
	[1] = "Step 1/4: Buy an egg from the conveyor! 🥚",
	[2] = "Step 2/4: Your egg is on a pedestal in your base. Watch it hatch!",
	[3] = "Step 3/4: Grown-ups earn coins. Step on your green collect pad! 💰",
}

local arrow: Model? = nil
local beam: Beam? = nil
local targetAttachment: Attachment? = nil
local hint: Frame
local hintLabel: TextLabel
local nightNoteShown = false

local function buildArrow(): Model
	local model = Instance.new("Model")
	model.Name = "TutorialArrow"
	local neon = { material = Enum.Material.Neon, castShadow = false }
	ModelKit.part(
		"Shaft",
		"Cylinder",
		Vector3.new(2.2, 0.55, 0.55),
		CFrame.new(0, 1.7, 0) * CFrame.Angles(0, 0, math.rad(90)),
		ARROW_COLOR,
		model,
		neon
	)
	ModelKit.part(
		"HeadL",
		"Wedge",
		Vector3.new(0.5, 1.3, 0.9),
		CFrame.new(-0.45, 0, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
		ARROW_COLOR,
		model,
		neon
	)
	ModelKit.part(
		"HeadR",
		"Wedge",
		Vector3.new(0.5, 1.3, 0.9),
		CFrame.new(0.45, 0, 0) * CFrame.Angles(0, math.rad(-90), 0) * CFrame.Angles(0, 0, math.pi),
		ARROW_COLOR,
		model,
		neon
	)
	model.Parent = Workspace
	return model
end

local function myBase(): Instance?
	local index = player:GetAttribute("BaseIndex")
	local map = Workspace:FindFirstChild("Map")
	local bases = if map then map:FindFirstChild("Bases") else nil
	return if bases and typeof(index) == "number" then bases:FindFirstChild(`Base{index}`) else nil
end

local function targetFor(step: number): Vector3?
	if step == 1 then
		local map = Workspace:FindFirstChild("Map")
		local lobby = if map then map:FindFirstChild("Lobby") else nil
		local conveyor = if lobby then lobby:FindFirstChild("Conveyor") else nil
		local belt = if conveyor then conveyor:FindFirstChild("Belt") else nil
		return if belt and belt:IsA("BasePart") then (belt :: BasePart).Position + Vector3.new(0, 4, 0) else nil
	elseif step == 2 then
		local best: BasePart? = nil
		local bestSlot = math.huge
		for _, model in CollectionService:GetTagged(Tags.Creature) do
			local slot = model:GetAttribute("Slot")
			if model:GetAttribute("OwnerUserId") == player.UserId and typeof(slot) == "number" and slot < bestSlot then
				local root = if model:IsA("Model") then (model :: Model).PrimaryPart else nil
				if root then
					best, bestSlot = root, slot
				end
			end
		end
		return if best then best.Position + Vector3.new(0, best.Size.Y / 2 + 1, 0) else nil
	elseif step == 3 then
		local base = myBase()
		local padModel = if base then base:FindFirstChild("CollectPad") else nil
		local pad = if padModel then padModel:FindFirstChild("Pad") else nil
		return if pad and pad:IsA("BasePart") then (pad :: BasePart).Position + Vector3.new(0, 1, 0) else nil
	end
	return nil
end

local function clearPointer()
	if arrow then
		arrow:Destroy()
		arrow = nil
	end
	if beam then
		beam:Destroy()
		beam = nil
	end
	if targetAttachment then
		targetAttachment:Destroy()
		targetAttachment = nil
	end
end

local function ensureBeam()
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root then
		return
	end
	if beam and beam.Attachment0 and beam.Attachment0.Parent == root then
		return
	end
	if beam then
		beam:Destroy()
	end
	local from = root:FindFirstChild("TutorialFrom") :: Attachment?
	if not from then
		local created = Instance.new("Attachment")
		created.Name = "TutorialFrom"
		created.Parent = root
		from = created
	end
	if not targetAttachment then
		local attachment = Instance.new("Attachment")
		attachment.Parent = Workspace.Terrain
		targetAttachment = attachment
	end
	local newBeam = Instance.new("Beam")
	newBeam.Attachment0 = from
	newBeam.Attachment1 = targetAttachment
	newBeam.Color = ColorSequence.new(ARROW_COLOR)
	newBeam.Transparency = NumberSequence.new(0.25, 0.6)
	newBeam.Width0 = 0.6
	newBeam.Width1 = 0.6
	newBeam.FaceCamera = true
	newBeam.LightEmission = 1
	newBeam.Segments = 24
	newBeam.CurveSize0 = 6
	newBeam.CurveSize1 = -2
	newBeam.Parent = Workspace.Terrain
	beam = newBeam
end

local function showNightNote()
	if nightNoteShown then
		return
	end
	nightNoteShown = true
	Popup.show({
		icon = "🌙",
		title = "When night falls...",
		body = "Shields drop! Sneak into bases near your level and steal adult creatures. Bonk raiders out of your base with your bat, and lock your best creature in the Inventory.",
		buttons = {
			{
				text = "Got it!",
				callback = function()
					Remotes.event("TutorialAck"):FireServer()
				end,
			},
		},
	})
end

local function render()
	local step = player:GetAttribute("TutorialStep")
	local current = if typeof(step) == "number" then step else 5
	local text = HINTS[current]
	hint.Visible = text ~= nil
	if text then
		hintLabel.Text = text
	end
	if current == 4 then
		showNightNote()
	end
	if not text then
		clearPointer()
	end
end

local function step(dt: number)
	local current = player:GetAttribute("TutorialStep")
	local target = if typeof(current) == "number" then targetFor(current) else nil
	if not target then
		clearPointer()
		return
	end
	if not arrow then
		arrow = buildArrow()
	end
	ensureBeam()
	if targetAttachment then
		targetAttachment.WorldPosition = target
	end
	local bob = math.sin(os.clock() * 3) * 0.5
	local spin = os.clock() * 1.5
	if arrow then
		arrow:PivotTo(CFrame.new(target + Vector3.new(0, 2.2 + bob, 0)) * CFrame.Angles(0, spin, 0))
	end
	local _ = dt
end

function TutorialController.init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	Theme.autoScale(gui)
	hint = Instance.new("Frame")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -96)
	hint.Size = UDim2.fromOffset(520, 64)
	hint.BackgroundColor3 = Theme.Colors.Panel
	hint.Visible = false
	hint.Parent = gui
	Theme.corner(hint, 18)
	Theme.stroke(hint, 4, ARROW_COLOR)
	hintLabel = Theme.text("Text", "", hint)
	hintLabel.Position = UDim2.fromOffset(14, 8)
	hintLabel.Size = UDim2.new(1, -28, 1, -16)
	hintLabel.TextWrapped = true
end

function TutorialController.start()
	player:GetAttributeChangedSignal("TutorialStep"):Connect(render)
	render()
	RunService.RenderStepped:Connect(step)
end

return TutorialController

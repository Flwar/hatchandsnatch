--!strict
--[[
	FusionMachine
	Builds the Fusion Machine that stands at the back of every base: two glass pods
	for the creatures going in, pipes into a glass reactor dome where the hybrid
	appears, a control desk and a "FUSION LAB" sign. Like the rest of the map it only
	creates Instances, so tools/preview can render it.

	  FusionMachine (Model)        attributes: State "Idle" | "Fusing" | "Ready",
	                               FusionEndsAt (server clock), ResultName
	    PodL / PodR (Model)        each with a Socket part where a parent's mini model stands
	    Reactor (Model)            Core (neon ball, animated by the client), ResultSocket, Beacon
	    Panel (Part)               the owner's ProximityPrompt goes here
	    Reactor.Beacon             BillboardGui "StatusGui" > TextLabel "Status"

	`cf` is the floor point under the middle of the machine, facing the way players
	walk up to it (-Z).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ModelKit = require(Shared:WaitForChild("Models"):WaitForChild("ModelKit"))
local Props = require(script.Parent.Props)

local FusionMachine = {}

local v3 = Vector3.new

local STEEL = Color3.fromRGB(84, 98, 130)
local STEEL_DARK = Color3.fromRGB(58, 66, 92)
local STEEL_LIGHT = Color3.fromRGB(176, 186, 206)
local GLASS = Color3.fromRGB(196, 236, 255)
local POD_GLOW = Color3.fromRGB(110, 236, 255)
local CORE = Color3.fromRGB(255, 92, 220)
local HAZARD = Color3.fromRGB(255, 206, 60)

-- Footprint of the machine (studs), for layout code that needs to keep clear of it.
FusionMachine.Size = v3(15, 8, 8)

local function newModel(name: string, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

-- Cylinder CFrames are along X; this stands one upright.
local function upright(cf: CFrame): CFrame
	return cf * CFrame.Angles(0, 0, math.rad(90))
end

function FusionMachine.build(cf: CFrame, accent: Color3, parent: Instance): Model
	local machine = newModel("FusionMachine", parent)
	machine:SetAttribute("State", "Idle")
	machine:SetAttribute("FusionEndsAt", 0)
	machine:SetAttribute("ResultName", "")

	local function at(x: number, y: number, z: number): CFrame
		return cf * CFrame.new(x, y, z)
	end
	local function part(
		name: string,
		shape: ModelKit.Shape,
		size: Vector3,
		where: CFrame,
		color: Color3,
		into: Instance?,
		opts: ModelKit.PartOptions?
	): BasePart
		return ModelKit.part(name, shape, size, where, color, into or machine, opts)
	end
	local solid = { collide = true }
	local neon = { material = Enum.Material.Neon, castShadow = false }
	local metal = { material = Enum.Material.DiamondPlate, collide = true }

	-- Platform with an accent trim and a hazard stripe along the front edge.
	part("Platform", "Block", v3(15, 0.5, 7.6), at(0, 0.25, 0.2), STEEL_DARK, nil, metal)
	part("Trim", "Block", v3(15.3, 0.24, 7.9), at(0, 0.36, 0.2), accent, nil, solid)
	part("Hazard", "Block", v3(14.6, 0.08, 0.5), at(0, 0.53, -3.25), HAZARD, nil, { castShadow = false })
	for i = -3, 3 do
		part(
			`HazardStripe{i}`,
			"Block",
			v3(0.32, 0.09, 0.62),
			at(i * 2, 0.54, -3.25) * CFrame.Angles(0, math.rad(35), 0),
			Color3.fromRGB(40, 36, 48),
			nil,
			{ castShadow = false }
		)
	end

	-- Two input pods.
	for side = -1, 1, 2 do
		local name = if side < 0 then "PodL" else "PodR"
		local pod = newModel(name, machine)
		local x = 4.7 * side
		part("Base", "Cylinder", v3(0.9, 3.8, 3.8), upright(at(x, 0.95, 0.4)), STEEL, pod, solid)
		part("FloorGlow", "Cylinder", v3(0.06, 2.8, 2.8), upright(at(x, 1.42, 0.4)), POD_GLOW, pod, neon)
		part("Glass", "Cylinder", v3(3.6, 3.3, 3.3), upright(at(x, 3.2, 0.4)), GLASS, pod, {
			material = Enum.Material.Glass,
			transparency = 0.62,
			collide = true,
		})
		part("Ring", "Cylinder", v3(0.16, 3.55, 3.55), upright(at(x, 4.95, 0.4)), accent, pod, neon)
		part("Cap", "Cylinder", v3(0.65, 3.8, 3.8), upright(at(x, 5.3, 0.4)), STEEL, pod, solid)
		part("CapTop", "Cylinder", v3(0.3, 2.4, 2.4), upright(at(x, 5.75, 0.4)), STEEL_LIGHT, pod, solid)
		for i = 0, 2 do
			local a = math.rad(i * 120 + 30)
			part(
				"Strut",
				"Block",
				v3(0.24, 3.6, 0.24),
				at(x + math.cos(a) * 1.68, 3.2, 0.4 + math.sin(a) * 1.68),
				STEEL_LIGHT,
				pod,
				{ material = Enum.Material.Metal }
			)
		end
		part("Socket", "Block", v3(1, 0.2, 1), at(x, 1.45, 0.4), Color3.new(1, 1, 1), pod, {
			transparency = 1,
			castShadow = false,
		})
		-- Pipe from the pod cap into the reactor dome.
		local from, to = at(x * 0.86, 5.5, 0.45).Position, at(2.05 * side, 4.55, 0.7).Position
		local pipeCf, pipeLength = ModelKit.between(from, to)
		part("Pipe", "Cylinder", v3(pipeLength, 0.6, 0.6), pipeCf, STEEL_LIGHT, pod, { material = Enum.Material.Metal })
		part("PipeGlow", "Cylinder", v3(pipeLength * 0.8, 0.66, 0.66), pipeCf, accent, pod, neon)
	end

	-- The reactor: a steel drum with a glass dome where the hybrid appears.
	local reactor = newModel("Reactor", machine)
	part("Drum", "Cylinder", v3(2.7, 4.8, 4.8), upright(at(0, 1.85, 0.7)), STEEL, reactor, solid)
	part("Band", "Cylinder", v3(0.24, 4.9, 4.9), upright(at(0, 2.5, 0.7)), accent, reactor, neon)
	part("Lip", "Cylinder", v3(0.3, 5.0, 5.0), upright(at(0, 3.2, 0.7)), STEEL_LIGHT, reactor, solid)
	part("Dome", "Ellipsoid", v3(4.6, 4.6, 4.6), at(0, 3.3, 0.7), GLASS, reactor, {
		material = Enum.Material.Glass,
		transparency = 0.6,
		collide = true,
	})
	part("Core", "Ball", v3(1.3, 1.3, 1.3), at(0, 4.35, 0.7), CORE, reactor, neon)
	part("ResultSocket", "Block", v3(1, 0.2, 1), at(0, 3.35, 0.7), Color3.new(1, 1, 1), reactor, {
		transparency = 1,
		castShadow = false,
	})
	part("Antenna", "Cylinder", v3(1.4, 0.22, 0.22), upright(at(0, 6.2, 0.7)), STEEL_LIGHT, reactor, {
		material = Enum.Material.Metal,
	})
	part("Beacon", "Ball", v3(0.6, 0.6, 0.6), at(0, 7.0, 0.7), CORE, reactor, neon)

	-- Control desk in front with big buttons and a lever.
	part("Desk", "Block", v3(4.2, 1.5, 1.4), at(0, 1.25, -2.35), STEEL, nil, solid)
	local panel = part("Panel", "Wedge", v3(4.2, 0.7, 1.4), at(0, 2.35, -2.35), STEEL_LIGHT, nil, solid)
	panel.CanQuery = true
	part("ButtonRed", "Ball", v3(0.7, 0.7, 0.7), at(-1.1, 2.45, -2.4), Color3.fromRGB(240, 60, 70), nil, {
		reflectance = 0.1,
	})
	part("ButtonGreen", "Ball", v3(0.55, 0.55, 0.55), at(-0.3, 2.35, -2.55), Color3.fromRGB(80, 220, 110), nil, {
		reflectance = 0.1,
	})
	part(
		"Lever",
		"Cylinder",
		v3(1.2, 0.18, 0.18),
		upright(at(1.2, 2.85, -2.2)) * CFrame.Angles(0, 0, math.rad(-20)),
		STEEL_LIGHT,
		nil,
		{
			material = Enum.Material.Metal,
		}
	)
	part("LeverKnob", "Ball", v3(0.5, 0.5, 0.5), at(1.4, 3.4, -2.2), Color3.fromRGB(240, 60, 70))

	-- A floating status label over the machine (the client fills it in), and the lab sign.
	local status = Instance.new("BillboardGui")
	status.Name = "StatusGui"
	status.Size = UDim2.fromScale(9, 2)
	status.StudsOffsetWorldSpace = v3(0, 3.2, 0)
	status.MaxDistance = 90
	status.LightInfluence = 0
	status.Parent = reactor:FindFirstChild("Beacon")
	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.Text = "Fuse two adults!"
	label.TextColor3 = Color3.fromRGB(150, 255, 240)
	label.TextScaled = true
	label.Parent = status
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Color3.fromRGB(26, 30, 60)
	stroke.Parent = label
	Props.sign(
		"Sign",
		v3(7, 1.5, 0.35),
		at(0, 8.0, 0.7),
		machine,
		"FUSION LAB",
		accent,
		Color3.fromRGB(255, 255, 255),
		true
	)
	for side = -1, 1, 2 do
		part("SignPost", "Cylinder", v3(1.6, 0.25, 0.25), upright(at(2.4 * side, 6.65, 0.7)), STEEL_LIGHT, nil, {
			material = Enum.Material.Metal,
		})
	end
	return machine
end

return table.freeze(FusionMachine)

--[[
	export.luau
	Builds models with the game's real builder code and writes them as JSON part lists
	for render.mjs. Run from the repo root:

	  lune run tools/preview/export.luau creatures [creatureId ...]
	  lune run tools/preview/export.luau map
	  lune run tools/preview/export.luau rbxm      -- writes build/Creatures.rbxm for Studio

	Output goes to tools/preview/out/*.json (scenes) and build/*.rbxm.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Loader = require("./loader")
local roblox = Loader.roblox

local OUT = "tools/preview/out"

local function round(n: number): number
	return math.floor(n * 1000 + 0.5) / 1000
end

local function exportParts(root: any, relativeTo: any?): { any }
	local parts = {}
	local inverse = if relativeTo then relativeTo:Inverse() else nil
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") and inst.Transparency < 1 then
			local shape = "Block"
			if inst.ClassName == "WedgePart" then
				shape = "Wedge"
			elseif inst.ClassName == "CornerWedgePart" then
				shape = "CornerWedge"
			elseif inst.ClassName == "Part" or inst.ClassName == "SpawnLocation" then
				shape = inst.Shape.Name
			elseif inst.ClassName == "TrussPart" then
				shape = "Block"
			end
			local mesh = inst:FindFirstChildOfClass("SpecialMesh")
			if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
				shape = "Ellipsoid"
			end
			local cf = if inverse then inverse * inst.CFrame else inst.CFrame
			local comps = { cf:GetComponents() }
			for i, v in comps do
				comps[i] = round(v)
			end
			table.insert(parts, {
				name = inst.Name,
				shape = shape,
				size = { round(inst.Size.X), round(inst.Size.Y), round(inst.Size.Z) },
				cf = comps,
				color = { round(inst.Color.R), round(inst.Color.G), round(inst.Color.B) },
				material = inst.Material.Name,
				transparency = round(inst.Transparency),
				reflectance = round(inst.Reflectance),
			})
		end
	end
	return parts
end

local function countParts(root: any): number
	local n = 0
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function writeScene(name: string, scene: any)
	fs.writeDir(OUT)
	fs.writeFile(`{OUT}/{name}.json`, serde.encode("json", scene, false))
end

local mode = process.args[1] or "creatures"

if mode == "creatures" then
	local CreatureData = Loader.require("src/shared/CreatureData")
	local CreatureModels = Loader.require("src/shared/Models/CreatureModels")
	local filter: { [string]: boolean } = {}
	local hasFilter = false
	for i = 2, #process.args do
		filter[process.args[i]] = true
		hasFilter = true
	end
	local origin = roblox.CFrame.new()
	local summary = {}
	for _, def in CreatureData.List do
		if hasFilter and not filter[def.id] then
			continue
		end
		local models = {}
		for _, stage in { "Egg", "Baby", "Adult" } do
			local model = CreatureModels.build(def.id, { stage = stage, origin = origin })
			table.insert(models, { label = stage, parts = exportParts(model, origin), count = countParts(model) })
		end
		writeScene(`creature-{def.id}`, {
			title = `{def.displayName} ({def.rarity})`,
			kind = "creature",
			models = models,
		})
		table.insert(summary, `{def.id}: egg {models[1].count}, baby {models[2].count}, adult {models[3].count} parts`)
	end
	print(table.concat(summary, "\n"))
elseif mode == "map" then
	local MapBuilder = Loader.require("src/server/World/MapBuilder")
	local workspace = roblox.Instance.new("Folder")
	workspace.Name = "Workspace"
	local map = MapBuilder.build(workspace)
	writeScene("map", { title = "Map", kind = "map", models = { { label = "Map", parts = exportParts(map) } } })
	local base = map:FindFirstChild("Bases"):FindFirstChild("Base1")
	local pivot = base:GetAttribute("BaseCFrame") or roblox.CFrame.new()
	-- Preview a lived-in base: unlock the starting pedestals and put creatures on them.
	local CreatureModels = Loader.require("src/shared/Models/CreatureModels")
	local showcase = {
		{ "blobbit", "Adult" },
		{ "waddlecake", "Adult" },
		{ "cactopus", "Baby" },
		{ "jellyknight", "Adult" },
		{ "pebblepup", "Egg" },
		{ "croissaur", "Adult" },
		{ "toastshark", "Adult" },
	}
	for slot, entry in showcase do
		local pedestal = base:FindFirstChild("Pedestals"):FindFirstChild(`Pedestal{slot}`)
		MapBuilder.setPedestalUnlocked(pedestal, true)
		local socket = pedestal:FindFirstChild("Top"):FindFirstChild("Socket")
		local model =
			CreatureModels.build(entry[1], { stage = entry[2], origin = socket.Parent.CFrame * socket.CFrame })
		model.Parent = base
	end
	MapBuilder.setSignText(base, "Sam's Base")
	writeScene(
		"base",
		{ title = "Base 1", kind = "base", models = { { label = "Base1", parts = exportParts(base, pivot) } } }
	)
	local lobby = map:FindFirstChild("Lobby")
	writeScene(
		"lobby",
		{ title = "Lobby", kind = "lobby", models = { { label = "Lobby", parts = exportParts(lobby) } } }
	)
	print(`map parts: {countParts(map)}  base: {countParts(base)}  lobby: {countParts(lobby)}`)
elseif mode == "sheets" then
	-- One image with every adult, one with every egg, for docs and quick reviews.
	local CreatureData = Loader.require("src/shared/CreatureData")
	local CreatureModels = Loader.require("src/shared/Models/CreatureModels")
	for _, stage in { "Adult", "Egg", "Baby" } do
		local models = {}
		for _, def in CreatureData.List do
			local origin = roblox.CFrame.new()
			local model = CreatureModels.build(def.id, { stage = stage, origin = origin })
			table.insert(models, { label = `{def.displayName} - {def.rarity}`, parts = exportParts(model, origin) })
		end
		writeScene(
			`sheet-{string.lower(stage)}`,
			{ title = `All creatures: {stage}`, kind = "gallery", models = models }
		)
	end
	print("wrote creature sheets")
elseif mode == "traps" then
	local TrapModels = Loader.require("src/shared/Models/TrapModels")
	local models = {}
	for _, trapType in { "BananaPeel", "StickyFloor", "HonkEgg" } do
		local origin = roblox.CFrame.new()
		table.insert(models, { label = trapType, parts = exportParts(TrapModels.build(trapType, origin), origin) })
	end
	writeScene("traps", { title = "Traps", kind = "gallery", models = models })
	print("wrote traps")
elseif mode == "rbxm" then
	local CreatureData = Loader.require("src/shared/CreatureData")
	local CreatureModels = Loader.require("src/shared/Models/CreatureModels")
	local folder = roblox.Instance.new("Folder")
	folder.Name = "CreaturePreviews"
	local x = 0
	for _, def in CreatureData.List do
		for _, stage in { "Egg", "Baby", "Adult" } do
			local model = CreatureModels.build(def.id, { stage = stage, origin = roblox.CFrame.new(x, 0, 0) })
			model.Name = `{def.modelName}_{stage}`
			model.Parent = folder
			x += 8
		end
	end
	fs.writeDir("build")
	fs.writeFile("build/Creatures.rbxm", roblox.serializeModel({ folder }))
	print("wrote build/Creatures.rbxm")
end

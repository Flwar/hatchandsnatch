--[[
	loader.luau
	Runs the game's Luau modules outside Roblox (in Lune) so models can be built and
	exported for preview renders. It emulates just enough of Roblox:

	  * Roblox datatypes and Instances come from Lune's @lune/roblox library, which
	    validates every property name against the real API dump.
	  * `script`, `script.Parent.X`, `:WaitForChild()` and `require()` are mapped onto
	    the Rojo folder layout from default.project.json.
	  * game:GetService("ReplicatedStorage"/"ServerScriptService") point at the synced folders.

	Only pure builder modules are meant to run here (no Players, RunService, etc.).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any

local Loader = {}

type Node = {
	kind: "dir" | "module",
	path: string, -- filesystem path (directory, or .lua/.luau file)
	name: string,
	parent: Node?,
}

local MOUNTS: { [string]: string } = {
	ReplicatedStorage = "src/shared", -- mounted as ReplicatedStorage.Shared
	ServerScriptService = "src/server",
}

local nodeProxies: { [string]: any } = {}
local moduleCache: { [string]: any } = {}
local loading: { [string]: boolean } = {}

local makeProxy: (node: Node) -> any

-- fs calls yield, which is not allowed inside metamethods, so the source tree is scanned once up front.
local knownFiles: { [string]: boolean } = {}
local knownDirs: { [string]: boolean } = {}
local function scan(dir: string)
	knownDirs[dir] = true
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			scan(path)
		else
			knownFiles[path] = true
		end
	end
end
for _, root in { "src/shared", "src/server", "src/client" } do
	if fs.isDir(root) then
		scan(root)
	end
end
-- Parent folders of the mounts count as directories too.
knownDirs["src"] = true

local function moduleFile(dir: string, name: string): string?
	for _, ext in { ".lua", ".luau" } do
		local candidate = `{dir}/{name}{ext}`
		if knownFiles[candidate] then
			return candidate
		end
	end
	return nil
end

local function childOf(node: Node, name: string): Node?
	if node.kind ~= "dir" then
		return nil
	end
	local file = moduleFile(node.path, name)
	if file then
		return { kind = "module", path = file, name = name, parent = node }
	end
	local dirPath = `{node.path}/{name}`
	if knownDirs[dirPath] then
		local init = moduleFile(dirPath, "init")
		if init then
			return { kind = "module", path = init, name = name, parent = node }
		end
		return { kind = "dir", path = dirPath, name = name, parent = node }
	end
	return nil
end

local function dataModelNode(): Node
	return { kind = "dir", path = "<game>", name = "game", parent = nil }
end

local function serviceNode(serviceName: string): Node
	local root = MOUNTS[serviceName]
	assert(root, `Loader: service {serviceName} is not mounted`)
	if serviceName == "ReplicatedStorage" then
		-- ReplicatedStorage itself is virtual; its only child we sync is Shared.
		return { kind = "dir", path = "<ReplicatedStorage>", name = "ReplicatedStorage", parent = dataModelNode() }
	end
	return { kind = "dir", path = root, name = serviceName, parent = dataModelNode() }
end

local function resolveChild(node: Node, name: string): Node?
	if node.path == "<ReplicatedStorage>" then
		if name == "Shared" then
			return { kind = "dir", path = MOUNTS.ReplicatedStorage, name = "Shared", parent = node }
		end
		return nil
	end
	return childOf(node, name)
end

makeProxy = function(node: Node): any
	local key = `{node.kind}:{node.path}`
	if nodeProxies[key] then
		return nodeProxies[key]
	end
	local proxy = setmetatable({}, {
		__index = function(_, index: string)
			if index == "Parent" then
				return if node.parent then makeProxy(node.parent) else nil
			elseif index == "Name" then
				return node.name
			elseif index == "WaitForChild" or index == "FindFirstChild" then
				return function(_self: any, childName: string)
					local child = resolveChild(node, childName)
					if not child then
						if index == "FindFirstChild" then
							return nil
						end
						error(`Loader: {node.path} has no child "{childName}"`)
					end
					return makeProxy(child)
				end
			end
			local child = resolveChild(node, index)
			if not child then
				error(`Loader: {node.path} has no child "{index}"`)
			end
			return makeProxy(child)
		end,
		__tostring = function()
			return `LoaderNode({node.path})`
		end,
	})
	rawset(proxy, "__node", node)
	nodeProxies[key] = proxy
	return proxy
end

local fakeGame = {
	GetService = function(_self: any, serviceName: string)
		return makeProxy(serviceNode(serviceName))
	end,
}

-- Minimal Random shim (Lune has no Roblox Random datatype).
local RandomShim = {}
RandomShim.__index = RandomShim
function RandomShim.new(seed: number?)
	local state = seed or os.clock() * 1e6
	return setmetatable({ state = math.floor(state) % 2147483647 + 1 }, RandomShim)
end
function RandomShim:NextNumber(min: number?, max: number?): number
	self.state = (self.state * 48271) % 2147483647
	local unit = self.state / 2147483647
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * unit
end
function RandomShim:NextInteger(min: number, max: number): number
	return math.floor(self:NextNumber(min, max + 1 - 1e-9))
end

local requireModule: (target: any) -> any

local function makeEnvironment(scriptNode: Node): { [string]: any }
	local env: { [string]: any } = {
		script = makeProxy(scriptNode),
		game = fakeGame,
		require = function(target: any)
			return requireModule(target)
		end,
		Random = RandomShim,
	}
	for _, name in
		{
			"Instance",
			"Vector3",
			"Vector2",
			"CFrame",
			"Color3",
			"BrickColor",
			"UDim",
			"UDim2",
			"Enum",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"NumberRange",
			"Rect",
			"Ray",
			"Font",
			"PhysicalProperties",
		}
	do
		env[name] = roblox[name]
	end
	return env
end

requireModule = function(target: any): any
	local node: Node? = if type(target) == "table" then rawget(target, "__node") else nil
	assert(node and node.kind == "module", `Loader: require() expects a module node, got {tostring(target)}`)
	local path = node.path
	if moduleCache[path] ~= nil then
		return moduleCache[path]
	end
	assert(not loading[path], `Loader: cyclic require of {path}`)
	loading[path] = true
	local source = fs.readFile(path)
	local chunk = luau.load(source, {
		debugName = path,
		environment = makeEnvironment(node),
		injectGlobals = true,
	})
	local result = chunk()
	loading[path] = nil
	moduleCache[path] = result
	return result
end

-- Requires a module by its repo path, e.g. "src/shared/Models/CreatureModels".
function Loader.require(repoPath: string): any
	local parts = string.split(repoPath, "/")
	local name = parts[#parts]
	table.remove(parts)
	local dir = table.concat(parts, "/")
	local file = moduleFile(dir, name)
	assert(file, `Loader: no module at {repoPath}`)
	local parentNode: Node = { kind = "dir", path = dir, name = parts[#parts] or "", parent = nil }
	-- Rebuild the real parent chain so script.Parent.Parent works.
	local chain: { string } = {}
	for _, segment in parts do
		table.insert(chain, segment)
	end
	local current: Node? = nil
	for index = 1, #chain do
		local path = table.concat(chain, "/", 1, index)
		current = { kind = "dir", path = path, name = chain[index], parent = current }
	end
	parentNode = current or parentNode
	return requireModule(makeProxy({ kind = "module", path = file, name = name, parent = parentNode }))
end

Loader.roblox = roblox
Loader.Random = RandomShim

return Loader

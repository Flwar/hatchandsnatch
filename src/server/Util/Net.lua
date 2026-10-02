--!strict
--[[
	Net
	The only way server code listens to remotes. Every incoming call is:
	  1. rate-limited per player (RateLimiter),
	  2. checked for the exact argument count and each argument's validator (Guard),
	  3. run inside pcall so a bad request can never break the server.
	Rejected calls are dropped silently for the client and logged (throttled) here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))
local Guard = require(script.Parent:WaitForChild("Guard"))
local RateLimiter = require(script.Parent:WaitForChild("RateLimiter"))

local Net = {}

local lastWarn: { [string]: number } = {}

local function reject(player: Player, name: string, reason: string)
	local key = `{player.UserId}:{name}:{reason}`
	local now = os.clock()
	if (lastWarn[key] or 0) + 10 < now then
		lastWarn[key] = now
		warn(`[Net] rejected {name} from {player.Name}: {reason}`)
	end
end

local function validate(player: Player, name: string, validators: { Guard.Validator }, ...: any): boolean
	if not RateLimiter.allow(player, name) then
		reject(player, name, "rate limited")
		return false
	end
	local count = select("#", ...)
	if count > #validators then
		reject(player, name, "too many arguments")
		return false
	end
	for index, validator in validators do
		local value = select(index, ...)
		if not validator(value) then
			reject(player, name, `bad argument #{index}`)
			return false
		end
	end
	return true
end

-- Listen to a client -> server RemoteEvent.
function Net.onEvent(name: string, validators: { Guard.Validator }, handler: (player: Player, ...any) -> ())
	Remotes.event(name).OnServerEvent:Connect(function(player: Player, ...: any)
		if not validate(player, name, validators, ...) then
			return
		end
		xpcall(handler, function(err: any)
			warn(`[Net] {name} handler error: {err}\n{debug.traceback()}`)
		end, player, ...)
	end)
end

-- Answer a client -> server RemoteFunction. Rejected or failed calls return nil.
function Net.onInvoke(name: string, validators: { Guard.Validator }, handler: (player: Player, ...any) -> any)
	Remotes.func(name).OnServerInvoke = function(player: Player, ...: any): any
		if not validate(player, name, validators, ...) then
			return nil
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn(`[Net] {name} handler error: {result}`)
			return nil
		end
		return result
	end
end

function Net.fire(player: Player, name: string, ...: any)
	Remotes.event(name):FireClient(player, ...)
end

function Net.fireAll(name: string, ...: any)
	Remotes.event(name):FireAllClients(...)
end

-- Shows a toast on one client. `kind` styles it: "info", "success", "warning".
function Net.notify(player: Player, message: string, kind: string?)
	Net.fire(player, "Notify", message, kind or "info")
end

return table.freeze(Net)

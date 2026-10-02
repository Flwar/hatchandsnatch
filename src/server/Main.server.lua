--!strict
--[[
	Main (server bootstrap)
	Creates the remotes, then initialises every service in order and starts them.
	init() runs synchronously (set up state, no yielding); start() runs after every
	service is initialised (connect events, begin loops).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

Remotes.setup()

local Services = script.Parent:WaitForChild("Services")
local Net = require(script.Parent:WaitForChild("Util"):WaitForChild("Net"))

type Service = { init: () -> (), start: () -> () }

-- Order matters: data first, then the world, then systems that depend on both.
local ORDER: { { name: string, service: Service } } = {
	{ name = "DataService", service = require(Services:WaitForChild("DataService")) :: any },
	{ name = "MapService", service = require(Services:WaitForChild("MapService")) :: any },
	{ name = "BaseService", service = require(Services:WaitForChild("BaseService")) :: any },
}

for _, entry in ORDER do
	local ok = xpcall(entry.service.init, function(err: any)
		warn(`[Main] {entry.name}.init failed: {err}\n{debug.traceback()}`)
	end)
	if not ok then
		error(`[Main] cannot continue without {entry.name}`)
	end
end

-- Remote handlers that don't belong to a specific service yet.
Net.onEvent("ClientReady", {}, function(player: Player)
	Net.notify(player, `Welcome to Hatch & Snatch, {player.DisplayName}!`, "success")
end)

for _, entry in ORDER do
	task.spawn(xpcall, entry.service.start, function(err: any)
		warn(`[Main] {entry.name}.start failed: {err}\n{debug.traceback()}`)
	end)
end

print("[Main] Hatch & Snatch server started")

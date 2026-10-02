--!strict
--[[
	Main (client bootstrap)
	Initialises and starts every client controller in order, then tells the server
	the client is ready. Controllers only build UI and visuals; the server decides
	everything that matters.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Controllers = script.Parent:WaitForChild("Controllers")

type Controller = { init: () -> (), start: () -> () }

local ORDER: { { name: string, controller: Controller } } = {
	{ name = "HudController", controller = require(Controllers:WaitForChild("HudController")) :: any },
	{ name = "BaseController", controller = require(Controllers:WaitForChild("BaseController")) :: any },
	{ name = "GalleryController", controller = require(Controllers:WaitForChild("GalleryController")) :: any },
	{ name = "CreatureController", controller = require(Controllers:WaitForChild("CreatureController")) :: any },
	{ name = "PromptController", controller = require(Controllers:WaitForChild("PromptController")) :: any },
	{ name = "ConveyorController", controller = require(Controllers:WaitForChild("ConveyorController")) :: any },
}

for _, entry in ORDER do
	xpcall(entry.controller.init, function(err: any)
		warn(`[Main] {entry.name}.init failed: {err}\n{debug.traceback()}`)
	end)
end

for _, entry in ORDER do
	task.spawn(xpcall, entry.controller.start, function(err: any)
		warn(`[Main] {entry.name}.start failed: {err}\n{debug.traceback()}`)
	end)
end

Remotes.event("ClientReady"):FireServer()

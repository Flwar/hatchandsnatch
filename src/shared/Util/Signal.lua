--!strict
--[[
	Signal
	A tiny event object for communication between modules on the same machine
	(for example DataService.Loaded -> BaseService). Handlers run in their own
	thread, so one failing handler cannot break the others.
]]

export type Handler = (...any) -> ()

export type Signal = {
	connect: (self: Signal, handler: Handler) -> () -> (),
	fire: (self: Signal, ...any) -> (),
	_handlers: { Handler },
}

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({ _handlers = {} }, Signal)
	return (self :: any) :: Signal
end

-- Returns a function that disconnects the handler.
function Signal.connect(self: Signal, handler: Handler): () -> ()
	table.insert(self._handlers, handler)
	return function()
		local index = table.find(self._handlers, handler)
		if index then
			table.remove(self._handlers, index)
		end
	end
end

function Signal.fire(self: Signal, ...: any)
	for _, handler in table.clone(self._handlers) do
		task.spawn(handler, ...)
	end
end

return Signal

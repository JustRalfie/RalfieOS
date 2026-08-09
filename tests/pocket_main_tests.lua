local Protocol = dofile("src/ralfie/services/platform/mining_protocol.lua")

local function terminal()
  local screen, frames, cursor = {}, {}, { 1, 1 }
  return {
    clear = function() screen = {}; table.insert(frames, screen) end,
    getSize = function() return 26, 20 end,
    setCursorPos = function(x, y) cursor = { x, y } end,
    write = function(text) screen[cursor[2]] = tostring(text) end,
    frames = function() return frames end,
  }
end

local function frameHas(frames, first, second)
  for _, frame in ipairs(frames) do
    local foundFirst, foundSecond = false, false
    for _, line in pairs(frame) do
      foundFirst = foundFirst or line:find(first, 1, true) ~= nil
      foundSecond = foundSecond or line:find(second, 1, true) ~= nil
    end
    if foundFirst and foundSecond then return true end
  end
  return false
end

local keys = { enter = 1, b = 2, backspace = 3, escape = 4, y = 5, n = 6, d = 7, up = 8, down = 9, m = 10, a = 11, r = 12, u = 13, p = 14, c = 15 }
local queued = {}
local function event(kind, a, b, c) table.insert(queued, { kind, a, b, c }) end
local ready = Protocol.message(Protocol.types.HELLO_ACK, { id = 17, label = "Jack" }, {
  turtle_id = 17, label = "Jack", state = "READY", fuel_level = 0, inventory_used = 3, inventory_slots = 16, software_version = "0.3.8", protocol_version = 1,
})
event("rednet_message", 17, ready, Protocol.id)
event("key", keys.enter) -- Fleet -> Jack detail.
event("timer", 1) -- Re-render the READY detail while its status remains unchanged.
event("key", keys.enter) -- New Job.
event("key", keys.enter) -- 3x3.
event("char", "5")
event("key", keys.enter) -- Distance.
event("key", keys.enter) -- Confirm Start.
event("stop") -- Intentional harness stop, caught by the normal runtime error screen.
event("key", keys.b)

local sent, screen = {}, terminal()
local environment = {}
environment.keys = keys
environment.term = screen
environment.peripheral = { getNames = function() return { "left" } end, wrap = function() return { isWireless = function() return true end } end }
environment.rednet = {
  open = function() return true end, broadcast = function() return true end,
  send = function(id, message, protocol) table.insert(sent, { id = id, message = message, protocol = protocol }); return true end,
}
environment.os = {
  getComputerID = function() return 42 end, getComputerLabel = function() return "Command" end,
  epoch = function() return 1000 end, startTimer = function() return 1 end,
  pullEvent = function()
    local nextEvent = table.remove(queued, 1)
    if nextEvent[1] == "stop" then error("test complete") end
    return nextEvent[1], nextEvent[2], nextEvent[3], nextEvent[4]
  end,
}
environment.dofile = function(path)
  local localPath = path:gsub("^/ralfie/", "src/ralfie/")
  return assert(loadfile(localPath, "t", environment))()
end
setmetatable(environment, { __index = _G })
local result = assert(loadfile("src/ralfie/pocket/main.lua", "t", environment))()
assert(result == false, "the intentional harness stop must leave through Pocket error handling")
assert(frameHas(screen.frames(), "Jack", "READY"), "READY worker detail must render without crashing")
assert(frameHas(screen.frames(), "New Job", "Settings"), "READY worker actions must remain valid across detail redraws")
assert(frameHas(screen.frames(), "Tunnel Size", "3x3"), "New Job must construct the tunnel-size picker")
assert(frameHas(screen.frames(), "Tunnel: 3x3", "Distance"), "selected tunnel size must reach the distance screen")
local assignment
for _, delivery in ipairs(sent) do if delivery.message.type == Protocol.types.JOB_ASSIGN then assignment = delivery.message.payload end end
assert(assignment and assignment.job.tunnel_size == 3 and assignment.job.distance == 5, "Pocket job assignment must preserve the selected tunnel size and distance")
assert(frameHas(screen.frames(), "RALFIEOS ERROR", "Fleet Command"), "an uncaught Fleet Command failure must not be clipped into a normal device screen")

print("pocket main tests passed")

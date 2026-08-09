local savedOs, savedKeys = _G.os, _G.keys
_G.keys = { up = 1, down = 2, enter = 3, b = 4, backspace = 5, escape = 6 }
local queued = {}
_G.os = { pullEvent = function()
  local nextEvent = table.remove(queued, 1)
  return nextEvent[1], nextEvent[2]
end }

local HubUi = dofile("src/ralfie/interfaces/terminal/hub_ui.lua")
local terminal = {
  getSize = function() return 26, 12 end, clear = function() end, setCursorPos = function() end, write = function() end,
  isColor = function() return false end,
}
local function choose(events, entries)
  queued = events
  return HubUi.new(terminal, {}):choose("Nested", entries)
end
assert(choose({ { "key", keys.escape } }, { { id = "one", label = "One" }, { id = "back", label = "Back" } }) == "back")
assert(choose({ { "key", keys.backspace } }, { { id = "one", label = "One" }, { id = "back", label = "Back" } }) == "back")
assert(choose({ { "key", keys.b } }, { { id = "one", label = "One" }, { id = "back", label = "Back" } }) == "back")
assert(choose({ { "key", keys.escape } }, { { id = "exit", label = "Exit" } }) == nil, "root Back must not select Exit")

_G.os, _G.keys = savedOs, savedKeys
print("hub UI tests passed")

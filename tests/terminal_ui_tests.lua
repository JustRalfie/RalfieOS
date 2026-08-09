local savedOs, savedKeys = _G.os, _G.keys
_G.keys = { enter = 1, b = 2, backspace = 3, escape = 4 }
local events = { { "key", keys.escape } }
_G.os = { pullEvent = function() local event = table.remove(events, 1); return event[1], event[2] end }

local Ui = dofile("src/ralfie/interfaces/terminal/ui.lua")
local cursor = { 1, 1 }
local terminal = {
  getSize = function() return 26, 12 end,
  getCursorPos = function() return cursor[1], cursor[2] end,
  setCursorPos = function(x, y) cursor = { x, y } end,
  clear = function() end, write = function() end,
}
assert(Ui.new({ terminal = terminal, reader = function() return "" end }):waitBack())

_G.os, _G.keys = savedOs, savedKeys
print("terminal UI tests passed")

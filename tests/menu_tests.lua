local Menu = dofile("src/ralfie/interfaces/terminal/menu.lua")

local invalidUi = {
  clear = function() end, heading = function() end, line = function() end,
  prompt = function() return "no" end,
  status = function(self, label) self.label = label end,
}
assert(Menu.choose(invalidUi, "Test", { { id = "one", label = "One" } }) == nil)
assert(invalidUi.label == "INVALID")

local validUi = {
  clear = function() end, heading = function() end, line = function() end,
  prompt = function() return "2" end,
  status = function() end,
}
assert(Menu.choose(validUi, "Test", { { id = "one", label = "One" }, { id = "two", label = "Two" } }) == "two")

print("menu tests passed")

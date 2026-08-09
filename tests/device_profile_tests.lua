local Result = dofile("src/ralfie/core/result.lua")
local Fsx = dofile("src/ralfie/lib/fsx.lua")
local Device = dofile("src/ralfie/services/platform/device.lua")
local Profile = dofile("src/ralfie/services/platform/device_profile.lua")

local files = {}
local fs = {
  exists = function(path) return files[path] ~= nil end,
  getDir = function(path) return path:match("^(.*)/[^/]+$") or "" end,
  makeDir = function() end,
  delete = function(path) files[path], files[path .. ".tmp"], files[path .. ".bak"] = nil, nil, nil end,
  move = function(from, to) files[to], files[from] = files[from], nil end,
  open = function(path, mode)
    if mode == "r" then if not files[path] then return nil, "missing" end; return { readAll = function() return files[path] end, close = function() end } end
    local value = ""; return { write = function(text) value = value .. text end, close = function() files[path] = value end }
  end,
}
local serialization = { encode = function(value) return "profile:" .. value.device_name .. ":" .. value.role .. ":" .. tostring(value.auto_start) .. ":" .. (value.fleet_name or "") end,
  decode = function(value)
    local name, role, auto, fleet = value:match("^profile:([^:]+):([^:]+):([^:]+):(.*)$")
    if not name then return nil, "bad profile" end
    return { device_name = name, role = role, auto_start = auto == "true", fleet_name = fleet }
  end }

local turtle = Device.detect({ turtle = { forward = function() end }, terminal = { isColor = function() return false end }, peripheral = { getNames = function() return { "left" } end, wrap = function() return { isWireless = function() return true end } end } })
assert(turtle.type == "TURTLE" and turtle.capabilities.wireless_modem)
assert(Device.supportsRole(turtle, "MINING_WORKER") and not Device.supportsRole(turtle, "FLEET_CONTROLLER"))
local pocket = Device.detect({ pocket = {}, terminal = { isColor = function() return true end }, peripheral = { getNames = function() return {} end } })
assert(pocket.type == "POCKET" and Device.supportsRole(pocket, "FLEET_CONTROLLER") and not Device.supportsRole(pocket, "MINING_WORKER"))

local profiles = Profile.new({ filesystem = fs, fsx = Fsx, serialization = serialization, result = Result, device = Device, path = "/ralfie-data/device_profile.lua" })
assert(profiles:load(turtle).ok and profiles:load(turtle).value == nil)
local saved = profiles:save({ device_name = "Steve", role = "MINING_WORKER", auto_start = true, fleet_name = "Main" }, turtle)
assert(saved.ok)
local restored = profiles:load(turtle)
assert(restored.ok and restored.value.device_name == "Steve" and restored.value.role == "MINING_WORKER")
assert(not profiles:save({ device_name = "Steve", role = "FLEET_CONTROLLER", auto_start = false }, turtle).ok)
files["/ralfie-data/device_profile.lua"] = "corrupt"
assert(profiles:load(turtle).ok and profiles:load(turtle).value == nil)
print("device profile tests passed")

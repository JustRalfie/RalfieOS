local Dashboard = dofile("src/ralfie/interfaces/terminal/miner_dashboard.lua")
local function terminal(width, color)
  local state = { rows = {}, width = width, height = 12 }
  return {
    getSize = function() return state.width, state.height end, isColor = function() return color end,
    setCursorPos = function(_, y) state.row = y end, write = function(text) state.rows[state.row] = text end,
    clear = function() state.rows = {} end, setTextColor = function() end,
  }, state
end
local term, state = terminal(39, true)
local dashboard = Dashboard.new({ terminal = term, colors = { white = 1 } })
dashboard:reset(); dashboard:render({ status = "MINING", slice = 50, distance = 100, fuel = 900, inventory_fuel = 37, inventory_fuel_label = "minecraft:coal", loot = 4, capacity = 13, torches = 20, filler = 64, ores = 8, veins = 2, unloads = 1, ore = "Diamond Ore" })
assert(state.rows[1]:find("RalfieOS Miner") and state.rows[3]:find("50%%") and state.rows[5]:find("Inventory: 37 minecraft:coal") and state.rows[9]:find("Diamond Ore"))
local narrow, narrowState = terminal(16, false)
Dashboard.new({ terminal = narrow }):render({ status = "ERROR", error = "failed", slice = 2, distance = 1 })
assert(#narrowState.rows[3] <= 16 and narrowState.rows[2]:find("ERROR"))
local exhausted, exhaustedState = terminal(39, false)
Dashboard.new({ terminal = exhausted }):render({ status = "OUT_OF_FUEL", error = "No usable fuel", fuel = 0, inventory_fuel = 37, slice = 6, distance = 20 })
assert(exhaustedState.rows[2]:find("OUT_OF_FUEL") and exhaustedState.rows[5]:find("Inventory: 37"))
print("miner dashboard tests passed")

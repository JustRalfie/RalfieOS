local Result = dofile("src/ralfie/core/result.lua")
local TurtleAdapter = dofile("src/ralfie/adapters/turtle.lua")
local Inventory = dofile("src/ralfie/services/operations/inventory.lua")
local Fuel = dofile("src/ralfie/services/operations/fuel.lua")

local function build(options)
  options = options or {}
  local state = { selected = 1, fuel = options.fuel or 0, consumed = {}, items = options.items or {}, fuel_slots = options.fuel_slots or {}, details = options.details or {} }
  local turtle = {
    select = function(slot) state.selected = slot; return true end,
    getSelectedSlot = function() return state.selected end,
    getItemCount = function(slot) return state.items[slot] or 0 end,
    getItemDetail = function(slot) return state.details[slot] end,
    getFuelLevel = function() return state.fuel end,
    getFuelLimit = function() return 10000 end,
    refuel = function(count)
      if count == 0 then return state.fuel_slots[state.selected] == true and (state.items[state.selected] or 0) > 0 end
      if state.fuel_slots[state.selected] ~= true or (state.items[state.selected] or 0) < count then return false, "not fuel" end
      state.items[state.selected] = state.items[state.selected] - count
      state.consumed[state.selected] = (state.consumed[state.selected] or 0) + count
      state.fuel = state.fuel + (count * 80)
      return true
    end,
  }
  local adapter = TurtleAdapter.new({ turtle = turtle, result = Result })
  local inventory = Inventory.new({ adapter = adapter, result = Result })
  return Fuel.new({ adapter = adapter, inventory = inventory, result = Result }), state
end

local coal, coalState = build({
  items = { [2] = 37, [14] = 64, [15] = 1, [16] = 32 }, fuel_slots = { [2] = true, [14] = true, [15] = true },
  details = { [2] = { name = "minecraft:coal" }, [14] = { name = "minecraft:coal" }, [15] = { name = "minecraft:coal" }, [16] = { name = "minecraft:torch" } },
})
local runtime = coal:ensureRuntime({ minimum = 1, reserve = 20, fuel_slot = 15, protected_slots = { 14, 16 } })
assert(runtime.ok and coalState.fuel == 80 and coalState.items[15] == 0, "runtime refuel must use the reserved fuel slot first")
assert(coalState.items[2] == 37 and coalState.items[14] == 64 and coalState.items[16] == 32, "runtime refuel must preserve other fuel, filler, and torches")
local available = coal:inventoryFuel({ fuel_slot = 15, protected_slots = { 14, 16 } })
assert(available.ok and available.value.count == 37 and available.value.items["minecraft:coal"] == 37 and available.value.label == "minecraft:coal")

local outside, outsideState = build({ items = { [2] = 2, [5] = 7 }, fuel_slots = { [2] = true }, details = { [2] = { name = "minecraft:coal" }, [5] = { name = "minecraft:diamond" } } })
assert(outside:ensureRuntime({ minimum = 1, reserve = 20, fuel_slot = 15, protected_slots = { 14, 16 } }).ok)
assert(outsideState.items[2] == 1 and outsideState.items[5] == 7, "valid coal is consumed and non-fuel is preserved")

local empty = build({ items = { [5] = 7 }, details = { [5] = { name = "minecraft:diamond" } } })
local noFuel = empty:ensureRuntime({ minimum = 1, reserve = 20, fuel_slot = 15, protected_slots = { 14, 16 } })
assert(not noFuel.ok and noFuel.error.code == "FUEL.OUT_OF_FUEL" and noFuel.error.context.inventory_fuel == 0)

print("fuel tests passed")

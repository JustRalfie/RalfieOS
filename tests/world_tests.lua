local Result = dofile("src/ralfie/core/result.lua")
local World = dofile("src/ralfie/services/operations/world.lua")

local function build(options)
  options = options or {}
  local state = { present = options.present, data = options.data, inspections = 0, digs = 0, moves = 0, pauses = 0, x = 0 }
  local adapter = {
    inspect = function()
      state.inspections = state.inspections + 1
      return Result.ok({ present = state.present == true, data = state.data })
    end,
    dig = function() state.digs = state.digs + 1; state.present = false; return Result.ok(true) end,
  }
  local navigation = {
    move = function()
      state.moves = state.moves + 1
      if options.blocked and state.moves <= options.blocked then return Result.fail("TURTLE.ACTION_FAILED", "blocked") end
      state.x = state.x + 1
      return Result.ok(true)
    end,
  }
  local fluid = options.fluid and {
    isFluid = function(_, data) return data and data.name == "minecraft:lava" end,
    secure = function() state.present = false; state.secured = true; return Result.ok(true) end,
  } or nil
  return World.new({ adapter = adapter, navigation = navigation, result = Result, fluid = fluid, pause = function() state.pauses = state.pauses + 1 end }), state
end

local air, airState = build()
assert(air:move("forward").ok and airState.inspections == 1 and airState.digs == 0 and airState.pauses == 0 and airState.x == 1)

local blocked, blockedState = build({ blocked = 1 })
assert(blocked:move("forward", 2).ok and blockedState.moves == 2 and blockedState.x == 1)

local solid, solidState = build({ present = true, data = { name = "minecraft:stone" } })
assert(solid:move("forward").ok and solidState.digs == 1 and solidState.x == 1)

local lava, lavaState = build({ present = true, data = { name = "minecraft:lava" }, fluid = true })
assert(lava:move("forward").ok and lavaState.secured and lavaState.digs == 0 and lavaState.x == 1)

local known, knownState = build()
assert(known:move("forward", nil, false).ok and knownState.inspections == 0 and knownState.x == 1)

print("world tests passed")

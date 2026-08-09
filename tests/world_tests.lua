local Result = dofile("src/ralfie/core/result.lua")
local World = dofile("src/ralfie/services/operations/world.lua")

local function build(options)
  options = options or {}
  local state = { present = options.present, data = options.data, inspections = 0, digs = 0, moves = 0, pauses = 0, x = 0, heading = 0, selected = 16, placements = 0 }
  local adapter = {
    inspect = function()
      state.inspections = state.inspections + 1
      return Result.ok({ present = state.present == true, data = state.data })
    end,
    dig = function() state.digs = state.digs + 1; state.present = false; return Result.ok(true) end,
    itemCount = function(_, slot) return slot == 16 and 8 or 0 end,
    itemDetail = function(_, slot) return slot == 16 and { name = "minecraft:torch" } or nil end,
    selectedSlot = function() return state.selected end,
    select = function(_, slot) state.selected = slot; return Result.ok(true) end,
    place = function() state.placements = state.placements + 1; return Result.ok(true) end,
  }
  local navigation = {
    position = function() return { x = state.x, y = 0, z = 0, heading = state.heading } end,
    face = function(_, heading) state.heading = heading; return Result.ok(true) end,
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

local torchPath, torchState = build({ present = true, data = { name = "minecraft:torch" } })
torchPath = World.new({
  adapter = ({ inspect = function() torchState.inspections = torchState.inspections + 1; return Result.ok({ present = torchState.present == true, data = torchState.data }) end,
    dig = function() torchState.digs = torchState.digs + 1; torchState.present = false; return Result.ok(true) end,
    itemCount = function(_, slot) return slot == 16 and 8 or 0 end, itemDetail = function(_, slot) return slot == 16 and { name = "minecraft:torch" } or nil end,
    selectedSlot = function() return 16 end, select = function() return Result.ok(true) end, place = function() torchState.placements = torchState.placements + 1; return Result.ok(true) end }),
  navigation = ({ position = function() return { x = torchState.x, y = 0, z = 0, heading = torchState.heading } end, face = function(_, h) torchState.heading = h; return Result.ok(true) end, move = function() torchState.moves = torchState.moves + 1; torchState.x = torchState.x + 1; return Result.ok(true) end }),
  result = Result, torch_positions = { ["1:0:0"] = true }, torch_slot = 16,
})
assert(torchPath:move("forward", nil, false).ok and torchState.digs == 1 and torchState.placements == 1 and torchState.x == 1 and torchState.heading == 0)

print("world tests passed")

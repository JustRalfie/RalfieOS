local Result = dofile("src/ralfie/core/result.lua")
local Miner = dofile("src/ralfie/apps/miner/miner.lua")

local function moduleLoader(overrides)
  return {
    load = function(_, name)
      if overrides and overrides[name] then return Result.ok(overrides[name]) end
      local path = "src/" .. name:gsub("%.", "/") .. ".lua"
      local loaded, value = pcall(dofile, path)
      if not loaded then return Result.fail("TEST.LOAD", tostring(value)) end
      return Result.ok(value)
    end,
  }
end

local function mockTurtle(options)
  options = options or {}
  local state = {
    selected = 1, fuel = options.fuel or 1000, fuel_per_item = options.fuel_per_item or 20,
    items = options.items or { [1] = 12, [15] = 10, [16] = 8 }, moves = 0, digs = 0,
    torch_placements = 0, dropped = {}, forward_failures = options.forward_failures or 0,
    permanent_failure = options.permanent_failure, falling_blocks = options.falling_blocks or 0,
    torch_place_failures = options.torch_place_failures or 0, heading = 0, turns = 0, x = 0, y = 0, z = 0,
    torch_positions = {}, fuel_slots = options.fuel_slots or { [15] = true }, fuel_probes = 0,
  }
  local function move(direction)
    state.moves = state.moves + 1
    if state.permanent_failure then return false, "blocked" end
    if state.forward_failures > 0 then
      state.forward_failures = state.forward_failures - 1
      return false, "blocked"
    end
    state.fuel = state.fuel - 1
    if direction == "up" then
      state.y = state.y + 1
    elseif direction == "down" then
      state.y = state.y - 1
    elseif state.heading == 0 then
      state.x = state.x + 1
    elseif state.heading == 1 then
      state.z = state.z + 1
    elseif state.heading == 2 then
      state.x = state.x - 1
    else
      state.z = state.z - 1
    end
    return true
  end
  local function placeTorch()
    local before = { x = state.x, y = state.y, z = state.z, heading = state.heading }
    local target = { x = before.x, y = before.y, z = before.z }
    if state.heading == 0 then target.x = target.x + 1
    elseif state.heading == 1 then target.z = target.z + 1
    elseif state.heading == 2 then target.x = target.x - 1
    else target.z = target.z - 1 end
    if state.torch_place_failures > 0 then
      state.torch_place_failures = state.torch_place_failures - 1
      table.insert(state.torch_positions, { before = before, target = target, after = { x = state.x, y = state.y, z = state.z, heading = state.heading }, placed = false })
      return false, "Cannot place block here"
    end
    if not state.items[state.selected] or state.items[state.selected] == 0 then return false, "no item" end
    state.items[state.selected] = state.items[state.selected] - 1
    state.torch_placements = state.torch_placements + 1
    table.insert(state.torch_positions, { before = before, target = target, after = { x = state.x, y = state.y, z = state.z, heading = state.heading }, placed = true })
    return true
  end
  local turtle = {
    forward = function() return move("forward") end, up = function() return move("up") end, down = function() return move("down") end,
    turnLeft = function() state.heading = (state.heading + 3) % 4; state.turns = state.turns + 1; return true end,
    turnRight = function() state.heading = (state.heading + 1) % 4; state.turns = state.turns + 1; return true end,
    inspect = function() return state.falling_blocks > 0 end,
    inspectUp = function() return false end, inspectDown = function() return false end,
    dig = function() state.digs = state.digs + 1; if state.falling_blocks > 0 then state.falling_blocks = state.falling_blocks - 1 end; return true end,
    digUp = function() state.digs = state.digs + 1; return true end,
    digDown = function() state.digs = state.digs + 1; return true end,
    place = placeTorch, placeUp = function() return true end, placeDown = function() return true end,
    select = function(slot) state.selected = slot; return true end,
    getSelectedSlot = function() return state.selected end,
    getItemCount = function(slot) return state.items[slot] or 0 end,
    getFuelLevel = function() return state.fuel end,
    getFuelLimit = function() return 10000 end,
    refuel = function(count)
      if count == 0 then
        state.fuel_probes = state.fuel_probes + 1
        return state.fuel_slots[state.selected] == true and (state.items[state.selected] or 0) > 0
      end
      if not state.items[state.selected] or state.items[state.selected] < count then return false, "no fuel" end
      state.items[state.selected] = state.items[state.selected] - count
      state.fuel = state.fuel + (count * state.fuel_per_item)
      return true
    end,
    drop = function()
      local count = state.items[state.selected] or 0
      if count == 0 then return true end
      state.dropped[state.selected] = (state.dropped[state.selected] or 0) + count
      state.items[state.selected] = 0
      return true
    end,
    dropUp = function() return true end, dropDown = function() return true end,
  }
  return turtle, state
end

local function context(turtle, events, overrides)
  events = events or { warnings = 0, logs = {} }
  local ui = {
    heading = function() end,
    status = function(_, label) if label == "WARN" then events.warnings = events.warnings + 1 end end,
    prompt = function() return "1" end,
  }
  local logger = {
    info = function(_, event) table.insert(events.logs, event) end,
    warn = function(_, event) table.insert(events.logs, event) end,
    debug = function() end,
  }
  return { turtle = turtle, module_loader = moduleLoader(overrides), ui = ui, logger = logger, configuration = { get = function(_, _, fallback) return fallback end } }
end

local function run(options)
  local turtle, state = mockTurtle(options)
  local events = { warnings = 0, logs = {} }
  local outcome = Miner.start(context(turtle, events, options.module_overrides), {
    distance = options.distance or 1, torch_interval = options.torch_interval or 10,
    torch_slot = 16, fuel_slot = 15, safety_margin = options.safety_margin or 20,
    movement_retries = options.movement_retries or 3,
  })
  return outcome, state, events
end

local successful, successfulState = run({ distance = 2, items = { [1] = 12, [15] = 10, [16] = 8 } })
assert(successful.ok, successful.error and successful.error.message)
assert(successful.value.position.x == 0 and successful.value.position.y == 0 and successful.value.position.z == 0)
assert(successful.value.position.heading == 0)
assert(successfulState.moves >= 40)
assert(successfulState.dropped[1] == 12)
assert(successfulState.items[15] == 10 and successfulState.items[16] == 8)

local noTorches, noTorchState = run({ distance = 3, torch_interval = 10, items = { [15] = 10, [16] = 5 } })
assert(noTorches.ok)

local torches, torchState = run({ distance = 3, torch_interval = 1, items = { [15] = 10, [16] = 5 } })
assert(torches.ok)
assert(torchState.torch_placements == 3)
assert(torchState.items[16] == 2)
assert(torchState.heading == 0)
assert(torchState.turns == noTorchState.turns + 12)
for _, placement in ipairs(torchState.torch_positions) do
  assert(placement.placed and placement.before.heading == 2)
  assert(placement.target.x == placement.before.x - 1 and placement.target.y == placement.before.y and placement.target.z == placement.before.z)
  assert(placement.before.x == placement.after.x and placement.before.y == placement.after.y and placement.before.z == placement.after.z)
end

local missingWall, missingWallState, missingWallEvents = run({ distance = 1, torch_interval = 1, torch_place_failures = 1, items = { [15] = 10, [16] = 2 } })
assert(missingWall.ok)
assert(missingWallState.torch_placements == 0)
assert(missingWallState.heading == 0)
assert(missingWallState.torch_positions[1].before.heading == 2)
assert(missingWallEvents.warnings == 1)
assert(missingWallEvents.logs[#missingWallEvents.logs] == "miner.completed")

local insufficient, insufficientState = run({ distance = 1, fuel = 0, fuel_per_item = 20, items = { [15] = 1, [16] = 2 } })
assert(not insufficient.ok and insufficient.error.code == "FUEL.INSUFFICIENT")
assert(insufficientState.moves == 0)

local refuelled, refuelledState = run({ distance = 1, fuel = 0, fuel_per_item = 20, items = { [15] = 3, [16] = 2 } })
assert(refuelled.ok)
assert(refuelledState.items[15] == 1)

local mixedFuel, mixedFuelState = run({ distance = 1, fuel = 0, fuel_per_item = 20, items = { [2] = 3, [15] = 0, [16] = 2 }, fuel_slots = { [2] = true } })
assert(mixedFuel.ok)
assert(mixedFuelState.items[2] == 1)

local fuelPreserved, fuelPreservedState = run({
  distance = 1, items = { [1] = 9, [2] = 4, [3] = 5, [4] = 6, [15] = 7, [16] = 2 },
  fuel_slots = { [2] = true, [3] = true, [4] = true, [15] = true },
})
assert(fuelPreserved.ok)
assert(fuelPreservedState.items[2] == 4) -- coal outside the configured fuel slot
assert(fuelPreservedState.items[3] == 5) -- charcoal
assert(fuelPreservedState.items[4] == 6) -- another valid burnable fuel
assert(fuelPreservedState.dropped[1] == 9) -- non-fuel mined loot
assert(fuelPreservedState.items[15] == 7) -- configured fuel slot
assert(fuelPreservedState.items[16] == 2) -- torch slot
assert(fuelPreservedState.fuel_probes >= 4)

local falling, fallingState = run({ distance = 1, falling_blocks = 2, items = { [15] = 10, [16] = 2 } })
assert(falling.ok and fallingState.digs >= 2)

local retried, retryState = run({ distance = 1, forward_failures = 1, items = { [15] = 10, [16] = 2 } })
assert(retried.ok and retryState.moves > 12)

local blocked, blockedState = run({ distance = 1, permanent_failure = true, items = { [15] = 10, [16] = 2 } })
assert(not blocked.ok and blocked.error.code == "WORLD.MOVE_BLOCKED")
assert(blockedState.moves == 3)

local sliceBoundaryCalls = 0
local fakeOre = {
  new = function()
    return {
      mineExposed = function()
        error("Miner must not use per-column ore scans after slice discovery is enabled")
      end,
      mineSliceBoundary = function()
        sliceBoundaryCalls = sliceBoundaryCalls + 1
        return Result.ok({ collected = 0, ore_type = nil, limit_reached = false, inventory_full = false, abandoned = false })
      end,
    }
  end,
}
local minerCompatibility = run({
  distance = 1, items = { [15] = 10, [16] = 2 }, module_overrides = { ["ralfie.services.operations.ore"] = fakeOre },
})
assert(minerCompatibility.ok and sliceBoundaryCalls == 1, "Miner must use one slice-level ore discovery call per completed tunnel slice")

print("miner tests passed")

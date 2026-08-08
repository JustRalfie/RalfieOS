local Result = dofile("src/ralfie/core/result.lua")
local Unloading = dofile("src/ralfie/services/operations/unloading.lua")

local vectors = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

local function build(options)
  options = options or {}
  local state = {
    position = options.position or { x = 2, y = 0, z = 1, heading = 1 }, moves = 0, dumps = 0,
    free_slots = options.free_slots == nil and 1 or options.free_slots, statuses = {}, reserved = nil, fuel_required = nil,
    torch_count = 8, fuel_count = 6, outside_fuel_count = 4,
  }
  local navigation = {
    position = function() return { x = state.position.x, y = state.position.y, z = state.position.z, heading = state.position.heading } end,
    face = function(_, heading) state.position.heading = heading; return Result.ok(true) end,
  }
  local world = {
    move = function(_, direction)
      state.moves = state.moves + 1
      if options.fail_on_move and state.moves == options.fail_on_move then return Result.fail("WORLD.MOVE_BLOCKED", "blocked") end
      if direction == "up" then state.position.y = state.position.y + 1
      elseif direction == "down" then state.position.y = state.position.y - 1
      else
        local vector = vectors[state.position.heading]
        state.position.x = state.position.x + vector.x
        state.position.z = state.position.z + vector.z
      end
      return Result.ok(true)
    end,
  }
  local inventory = { freeSlots = function() return state.free_slots end }
  local fuel = {
    ensure = function(_, required)
      state.fuel_required = required
      if options.fuel_failure then return Result.fail("FUEL.INSUFFICIENT", "not enough fuel") end
      return Result.ok(required)
    end,
  }
  local storage = {
    dumpBehind = function(_, reserved)
      state.reserved = reserved
      if options.dump_failure then return Result.fail("TURTLE.ACTION_FAILED", options.dump_failure) end
      state.dumps = state.dumps + 1
      return Result.ok({ dumped = 12 })
    end,
  }
  local ui = { status = function(_, label, message) table.insert(state.statuses, label .. ":" .. message) end }
  local logger = { info = function() end, warn = function() end, error = function() end }
  local unloader = Unloading.new({
    navigation = navigation, world = world, storage = storage, inventory = inventory, fuel = fuel, result = Result,
    ui = ui, logger = logger, reserved_slots = { 16, 15 }, free_slot_margin = options.margin or 1, fuel_safety_margin = 20,
  })
  return unloader, state, navigation
end

local unloader, state, navigation = build()
assert(unloader:isNearlyFull())
local saved = navigation:position()
local first = unloader:run({ position = saved, slice = 7, mode = "tunnel" })
assert(first.ok and first.value.trip == 1 and first.value.state.slice == 7)
assert(state.position.x == saved.x and state.position.y == saved.y and state.position.z == saved.z and state.position.heading == saved.heading)
assert(state.dumps == 1 and state.reserved[1] == 16 and state.reserved[2] == 15)
assert(state.torch_count == 8 and state.fuel_count == 6 and state.outside_fuel_count == 4)
assert(state.fuel_required == ((math.abs(saved.x) + math.abs(saved.y) + math.abs(saved.z)) * 2) + 20)

local second = unloader:run({ position = saved, slice = 7, mode = "tunnel" })
assert(second.ok and second.value.trip == 2 and state.dumps == 2)

local room, roomState = build({ free_slots = 2, margin = 1 })
assert(not room:isNearlyFull())
roomState.free_slots = 1
assert(room:isNearlyFull())

for _, reason in ipairs({ "chest missing", "chest full", "drop failed" }) do
  local failed, failedState = build({ dump_failure = reason })
  local outcome = failed:run({ position = failedState.position, slice = 3, mode = "tunnel" })
  assert(not outcome.ok and outcome.error.code == "UNLOAD.DUMP_FAILED")
  assert(failedState.position.x == 0 and failedState.position.y == 0 and failedState.position.z == 0)
end

local homeFailure, homeState = build({ fail_on_move = 1 })
local failedHome = homeFailure:run({ position = homeState.position, slice = 2, mode = "tunnel" })
assert(not failedHome.ok and failedHome.error.code == "UNLOAD.HOME_RETURN_FAILED")

local resumeFailure, resumeState = build({ fail_on_move = 4 })
local failedResume = resumeFailure:run({ position = resumeState.position, slice = 2, mode = "ore" })
assert(not failedResume.ok and failedResume.error.code == "UNLOAD.RESUME_FAILED")
assert(resumeState.position.x == 0 and resumeState.position.y == 0 and resumeState.position.z == 0)

local lowFuel, lowFuelState = build({ fuel_failure = true })
local failedFuel = lowFuel:run({ position = lowFuelState.position, slice = 4, mode = "tunnel" })
assert(not failedFuel.ok and failedFuel.error.code == "FUEL.INSUFFICIENT")
assert(lowFuelState.moves == 0 and lowFuelState.dumps == 0)

print("unloading tests passed")

local Result = dofile("src/ralfie/core/result.lua")
local Fluid = dofile("src/ralfie/services/operations/fluid.lua")

local function build(options)
  options = options or {}
  local state = { selected = 1, position = { x = 0, y = 0, z = 0 }, placed = 0, targets = {}, items = options.items or { [14] = 8 } }
  local names = options.names or { [14] = "minecraft:cobblestone" }
  for direction, name in pairs(options.fluids or {}) do state.targets[direction] = { name = name } end
  local adapter = {
    itemDetail = function(_, slot) return names[slot] and { name = names[slot] } or nil end,
    itemCount = function(_, slot) return state.items[slot] or 0 end,
    selectedSlot = function() return state.selected end,
    select = function(_, slot) state.selected = slot; return Result.ok(true) end,
    transferTo = function(_, slot, count)
      local source = state.selected
      if not names[source] or (names[slot] and names[slot] ~= names[source]) then return Result.fail("TURTLE.ACTION_FAILED", "cannot transfer") end
      local moved = math.min(count, state.items[source] or 0)
      state.items[source] = (state.items[source] or 0) - moved
      state.items[slot] = (state.items[slot] or 0) + moved
      names[slot] = names[source]
      return Result.ok(true)
    end,
    place = function(_, direction)
      state.placed = state.placed + 1
      if options.place_failure then return Result.fail("TURTLE.ACTION_FAILED", "cannot place") end
      if not options.remain_fluid then state.targets[direction] = { name = names[state.selected] } end
      return Result.ok(true)
    end,
    inspect = function(_, direction)
      local data = state.targets[direction]
      return Result.ok({ present = data ~= nil, data = data })
    end,
  }
  local inventory = {
    count = function(_, slot) return adapter:itemCount(slot) end,
    withSlot = function(_, slot, action)
      local old = adapter:selectedSlot(); adapter:select(slot); local outcome = action(); adapter:select(old); return outcome
    end,
  }
  local events = {}
  local fluid = Fluid.new({ adapter = adapter, inventory = inventory, result = Result, filler_slot = 14, ui = { status = function(_, label, message) table.insert(events, label .. ":" .. message) end }, logger = { info = function() end, error = function() end } })
  return fluid, state, events
end

local lava, lavaState = build({ fluids = { forward = "minecraft:lava" } })
local lavaResult = lava:secure("forward", { name = "minecraft:lava" })
assert(lavaResult.ok and lavaState.placed == 1 and lavaState.position.x == 0)

for _, direction in ipairs({ "up", "down" }) do
  local fluid, state = build({ fluids = { [direction] = "minecraft:lava" } })
  assert(fluid:secure(direction, { name = "minecraft:lava" }).ok and state.placed == 1)
end

local water, waterState = build({ fluids = { forward = "minecraft:water" } })
assert(water:secure("forward", { name = "minecraft:water" }).ok and waterState.placed == 1)

local harmless, harmlessState = build({ fluids = { left = "minecraft:water" } })
assert(harmless:isFluid(harmlessState.targets.left) and harmlessState.placed == 0)

local replenished, replenishedState = build({ items = { [1] = 12, [2] = 12, [14] = 0 }, names = { [1] = "minecraft:cobbled_deepslate", [2] = "minecraft:dirt" } })
assert(replenished:replenish().ok and replenishedState.items[14] == 12 and replenishedState.items[1] == 0)

local invalid = build({ items = { [14] = 2 }, names = { [14] = "minecraft:diamond" } })
assert(not invalid:secure("forward", { name = "minecraft:lava" }).ok)

local empty = build({ items = { [14] = 0 }, names = {} })
assert(not empty:secure("forward", { name = "minecraft:lava" }).ok)

local failed = build({ fluids = { forward = "minecraft:lava" }, place_failure = true })
assert(not failed:secure("forward", { name = "minecraft:lava" }).ok)

local unverified = build({ fluids = { forward = "minecraft:lava" }, remain_fluid = true })
assert(not unverified:secure("forward", { name = "minecraft:lava" }).ok)

print("fluid tests passed")

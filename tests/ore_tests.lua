local Result = dofile("src/ralfie/core/result.lua")
local TurtleAdapter = dofile("src/ralfie/adapters/turtle.lua")
local Navigation = dofile("src/ralfie/services/operations/navigation.lua")
local World = dofile("src/ralfie/services/operations/world.lua")
local Ore = dofile("src/ralfie/services/operations/ore.lua")

local vectors = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

local function key(x, y, z) return x .. ":" .. y .. ":" .. z end

local function run(blocks, options)
  options = options or {}
  local state = { x = 0, y = 0, z = 0, heading = 0, moves = 0, digs = 0, blocks = {}, events = {} }
  for _, block in ipairs(blocks) do state.blocks[key(block.x, block.y, block.z)] = block.name end

  local function target(direction)
    if direction == "up" then return state.x, state.y + 1, state.z end
    if direction == "down" then return state.x, state.y - 1, state.z end
    local vector = vectors[state.heading]
    return state.x + vector.x, state.y, state.z + vector.z
  end
  local function inspect(direction)
    local x, y, z = target(direction)
    local name = state.blocks[key(x, y, z)]
    if name then return true, { name = name } end
    return false
  end
  local function move(direction)
    state.moves = state.moves + 1
    if options.fail_from_move and state.moves >= options.fail_from_move then return false, "blocked" end
    local x, y, z = target(direction)
    if state.blocks[key(x, y, z)] then return false, "blocked" end
    state.x, state.y, state.z = x, y, z
    return true
  end
  local function dig(direction)
    local x, y, z = target(direction)
    local location = key(x, y, z)
    if not state.blocks[location] then return false, "nothing to dig" end
    state.blocks[location] = nil
    state.digs = state.digs + 1
    return true
  end

  local turtle = {
    forward = function() return move("forward") end, up = function() return move("up") end, down = function() return move("down") end,
    turnLeft = function() state.heading = (state.heading + 3) % 4; return true end,
    turnRight = function() state.heading = (state.heading + 1) % 4; return true end,
    inspect = function() return inspect("forward") end, inspectUp = function() return inspect("up") end, inspectDown = function() return inspect("down") end,
    dig = function() return dig("forward") end, digUp = function() return dig("up") end, digDown = function() return dig("down") end,
  }
  local adapter = TurtleAdapter.new({ turtle = turtle, result = Result })
  local navigation = Navigation.new({ adapter = adapter, result = Result })
  local world = World.new({ adapter = adapter, navigation = navigation, result = Result })
  local logger = {
    info = function(_, event) table.insert(state.events, event) end,
    warn = function(_, event) table.insert(state.events, event) end,
    error = function(_, event) table.insert(state.events, event) end,
  }
  local ui = { status = function(_, label, message) table.insert(state.events, label .. ":" .. message) end }
  local inventory = options.full_after_digs and { isFull = function() return state.digs >= options.full_after_digs end } or nil
  local ore = Ore.new({
    adapter = adapter, navigation = navigation, world = world, inventory = inventory, result = Result, logger = logger, ui = ui,
    max_size = options.max_size or 64, movement_retries = options.movement_retries or 3,
  })
  local outcome = ore:mineExposed()
  return outcome, state, navigation
end

local function restored(state, navigation)
  local position = navigation:position()
  assert(state.x == 0 and state.y == 0 and state.z == 0 and state.heading == 0)
  assert(position.x == 0 and position.y == 0 and position.z == 0 and position.heading == 0)
end

local single, singleState, singleNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } })
assert(single.ok and single.value.collected == 1)
restored(singleState, singleNavigation)

local horizontal, horizontalState, horizontalNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:iron_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:iron_ore" },
})
assert(horizontal.ok and horizontal.value.collected == 2)
restored(horizontalState, horizontalNavigation)

local vertical, verticalState, verticalNavigation = run({
  { x = 0, y = 1, z = 0, name = "minecraft:deepslate_gold_ore" }, { x = 0, y = 2, z = 0, name = "minecraft:deepslate_gold_ore" },
})
assert(vertical.ok and vertical.value.collected == 2)
restored(verticalState, verticalNavigation)

local branching, branchingState, branchingNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:redstone_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:redstone_ore" },
  { x = 1, y = 1, z = 0, name = "minecraft:redstone_ore" }, { x = 1, y = 0, z = 1, name = "minecraft:redstone_ore" },
})
assert(branching.ok and branching.value.collected == 4)
restored(branchingState, branchingNavigation)

local behind, behindState, behindNavigation = run({
  { x = -1, y = 0, z = 0, name = "minecraft:coal_ore" }, { x = -2, y = 0, z = 0, name = "minecraft:coal_ore" },
})
assert(behind.ok and behind.value.collected == 2)
restored(behindState, behindNavigation)

local none, noneState, noneNavigation = run({})
assert(none.ok and none.value.collected == 0)
restored(noneState, noneNavigation)

local multiple, multipleState, multipleNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:copper_ore" }, { x = 0, y = 0, z = 1, name = "minecraft:lapis_ore" },
})
assert(multiple.ok and multiple.value.collected == 2)
restored(multipleState, multipleNavigation)

local loop, loopState, loopNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:emerald_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:emerald_ore" },
  { x = 1, y = 0, z = 1, name = "minecraft:emerald_ore" }, { x = 2, y = 0, z = 1, name = "minecraft:emerald_ore" },
})
assert(loop.ok and loop.value.collected == 4)
restored(loopState, loopNavigation)

local limited, limitedState, limitedNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:nether_gold_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:nether_gold_ore" },
  { x = 3, y = 0, z = 0, name = "minecraft:nether_gold_ore" },
}, { max_size = 2 })
assert(limited.ok and limited.value.collected == 2 and limited.value.limit_reached)
assert(limitedState.blocks[key(3, 0, 0)] == "minecraft:nether_gold_ore")
restored(limitedState, limitedNavigation)

local full, fullState, fullNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:nether_quartz_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:nether_quartz_ore" },
}, { full_after_digs = 1 })
assert(full.ok and full.value.collected == 1 and full.value.inventory_full)
assert(fullState.blocks[key(2, 0, 0)] == "minecraft:nether_quartz_ore")
restored(fullState, fullNavigation)

local ignored, ignoredState, ignoredNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:stone" } })
assert(ignored.ok and ignored.value.collected == 0)
assert(ignoredState.blocks[key(1, 0, 0)] == "minecraft:stone")
restored(ignoredState, ignoredNavigation)

local debris, debrisState, debrisNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:ancient_debris" } })
assert(debris.ok and debris.value.collected == 1)
restored(debrisState, debrisNavigation)

local chaseFailure, chaseFailureState, chaseFailureNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { fail_from_move = 1 })
assert(not chaseFailure.ok)
restored(chaseFailureState, chaseFailureNavigation)

local returnFailure, returnFailureState = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { fail_from_move = 2 })
assert(not returnFailure.ok and returnFailure.error.code == "ORE.RETURN_FAILED")
assert(returnFailureState.x == 1 and returnFailureState.y == 0 and returnFailureState.z == 0)

print("ore tests passed")

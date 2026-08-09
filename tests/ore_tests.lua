local Result = dofile("src/ralfie/core/result.lua")
local TurtleAdapter = dofile("src/ralfie/adapters/turtle.lua")
local Navigation = dofile("src/ralfie/services/operations/navigation.lua")
local World = dofile("src/ralfie/services/operations/world.lua")
local Ore = dofile("src/ralfie/services/operations/ore.lua")

local vectors = {
  [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
  [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
}

local chaseDirections = {
  forward = { name = "forward", heading = 0, x = 1, y = 0, z = 0 },
  right = { name = "right", heading = 1, x = 0, y = 0, z = 1 },
  backward = { name = "backward", heading = 2, x = -1, y = 0, z = 0 },
  left = { name = "left", heading = 3, x = 0, y = 0, z = -1 },
  up = { name = "up", move = "up", x = 0, y = 1, z = 0 },
  down = { name = "down", move = "down", x = 0, y = -1, z = 0 },
}

local function key(x, y, z) return x .. ":" .. y .. ":" .. z end

local function run(blocks, options)
  options = options or {}
  local state = { x = 0, y = 0, z = 0, heading = 0, moves = 0, move_positions = {}, digs = 0, turns = 0, inspected_directions = {}, blocks = {}, events = {}, excursions = {} }
  for _, block in ipairs(blocks) do state.blocks[key(block.x, block.y, block.z)] = { name = block.name, tags = block.tags } end

  local function target(direction)
    if direction == "up" then return state.x, state.y + 1, state.z end
    if direction == "down" then return state.x, state.y - 1, state.z end
    local vector = vectors[state.heading]
    return state.x + vector.x, state.y, state.z + vector.z
  end
  local function inspect(direction)
    table.insert(state.inspected_directions, direction)
    local x, y, z = target(direction)
    local data = state.blocks[key(x, y, z)]
    if data then return true, data end
    return false
  end
  local function move(direction)
    state.moves = state.moves + 1
    if options.fail_from_move and state.moves >= options.fail_from_move then return false, "blocked" end
    if options.fail_moves and options.fail_moves[state.moves] then return false, "blocked" end
    local x, y, z = target(direction)
    if state.blocks[key(x, y, z)] then return false, "blocked" end
    state.x, state.y, state.z = x, y, z
    table.insert(state.move_positions, { x = x, y = y, z = z })
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
    turnLeft = function() state.heading = (state.heading + 3) % 4; state.turns = state.turns + 1; return true end,
    turnRight = function() state.heading = (state.heading + 1) % 4; state.turns = state.turns + 1; return true end,
    inspect = function() return inspect("forward") end, inspectUp = function() return inspect("up") end, inspectDown = function() return inspect("down") end,
    dig = function() return dig("forward") end, digUp = function() return dig("up") end, digDown = function() return dig("down") end,
  }
  local adapter = TurtleAdapter.new({ turtle = turtle, result = Result })
  local navigation = Navigation.new({ adapter = adapter, result = Result })
  local world = World.new({ adapter = adapter, navigation = navigation, result = Result })
  if options.fluid_failure then
    world.move = function() return Result.fail("FLUID.UNSAFE", "lava cannot be sealed") end
  end
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
    additional_ids = options.additional_ids, excluded_ids = options.excluded_ids,
    should_stop = options.stop_after_digs and function() return state.digs >= options.stop_after_digs end or nil,
    on_excursion = function(excursion) table.insert(state.excursions, excursion or false) end,
  })
  local outcome
  if options.slice_boundary then
    outcome = ore:discoverTunnelBoundary({ width = options.width, height = options.height })
  elseif options.mine_slice_boundary then
    outcome = ore:mineSliceBoundary()
  elseif options.chase_direction then
    local direction = chaseDirections[options.chase_direction]
    local target = {
      key = key(direction.x, direction.y, direction.z),
      position = { x = direction.x, y = direction.y, z = direction.z },
      direction = direction,
      data = { name = options.chase_name },
    }
    outcome = ore:chase(target, options.chase_options)
  else
    outcome = ore:mineExposed()
  end
  return outcome, state, navigation
end

local function restored(state, navigation)
  local position = navigation:position()
  assert(state.x == 0 and state.y == 0 and state.z == 0 and state.heading == 0)
  assert(position.x == 0 and position.y == 0 and position.z == 0 and position.heading == 0)
end

local function resultShape(outcome)
  assert(outcome.ok and type(outcome.value) == "table")
  assert(type(outcome.value.collected) == "number")
  assert(outcome.value.ore_type == nil or type(outcome.value.ore_type) == "string")
  assert(type(outcome.value.limit_reached) == "boolean")
  assert(type(outcome.value.inventory_full) == "boolean")
  assert(type(outcome.value.abandoned) == "boolean")
end

local function eventOrder(events, expected)
  local index = 1
  for _, event in ipairs(events) do
    if event == expected[index] then index = index + 1 end
  end
  assert(index == #expected + 1, "ore UI/log event ordering changed")
end

local single, singleState, singleNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } })
assert(single.ok and single.value.collected == 1)
resultShape(single)
eventOrder(singleState.events, {
  "ORE:minecraft:diamond_ore detected", "ORE:Following vein", "ore.detected", "ORE:Collected 1 blocks",
  "ORE:Returning to tunnel", "ore.returned", "ore.completed", "ORE:Resuming",
})
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
assert(noneState.turns == 4 and noneState.moves == 0 and noneState.digs == 0)
assert(#noneState.inspected_directions == 6, "ore-free traversal must preserve the six-direction inspection pass")
restored(noneState, noneNavigation)

local preStopped, preStoppedState, preStoppedNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { stop_after_digs = 0 })
assert(preStopped.ok and preStopped.value.inventory_full and preStopped.value.collected == 0)
assert(preStoppedState.turns == 0 and preStoppedState.moves == 0 and preStoppedState.digs == 0)
restored(preStoppedState, preStoppedNavigation)

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
assert(limitedState.blocks[key(3, 0, 0)].name == "minecraft:nether_gold_ore")
restored(limitedState, limitedNavigation)

local full, fullState, fullNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:nether_quartz_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:nether_quartz_ore" },
}, { full_after_digs = 1 })
assert(full.ok and full.value.collected == 1 and full.value.inventory_full)
resultShape(full)
assert(fullState.blocks[key(2, 0, 0)].name == "minecraft:nether_quartz_ore")
restored(fullState, fullNavigation)

local ignored, ignoredState, ignoredNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:stone" } })
assert(ignored.ok and ignored.value.collected == 0)
assert(ignoredState.blocks[key(1, 0, 0)].name == "minecraft:stone")
restored(ignoredState, ignoredNavigation)

local debris, debrisState, debrisNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:ancient_debris" } })
assert(debris.ok and debris.value.collected == 1)
restored(debrisState, debrisNavigation)

for _, name in ipairs({
  "alltheores:uranium_ore", "alltheores:fluorite_ore", "alltheores:osmium_ore", "alltheores:platinum_ore",
  "allthemodium:allthemodium_ore", "allthemodium:vibranium_ore", "allthemodium:unobtainium_ore",
}) do
  local atmOre, atmState, atmNavigation = run({ { x = 1, y = 0, z = 0, name = name } })
  assert(atmOre.ok and atmOre.value.collected == 1)
  restored(atmState, atmNavigation)
end

local tagged, taggedState, taggedNavigation = run({
  { x = 1, y = 0, z = 0, name = "modded:deep_mineral", tags = { ["c:ores/uranium"] = true } },
})
assert(tagged.ok and tagged.value.collected == 1)
restored(taggedState, taggedNavigation)

for _, tags in ipairs({ { ["c:ores"] = true }, { "neoforge:ores" }, { ["forge:ores"] = true } }) do
  local namespaceOre, namespaceState, namespaceNavigation = run({ { x = 1, y = 0, z = 0, name = "modded:tagged_mineral", tags = tags } })
  assert(namespaceOre.ok and namespaceOre.value.collected == 1)
  restored(namespaceState, namespaceNavigation)
end

local excluded, excludedState, excludedNavigation = run({
  { x = 1, y = 0, z = 0, name = "alltheores:uranium_ore", tags = { ["neoforge:ores"] = true } },
}, { excluded_ids = { "alltheores:uranium_ore" } })
assert(excluded.ok and excluded.value.collected == 0)
assert(excludedState.blocks[key(1, 0, 0)].name == "alltheores:uranium_ore")
restored(excludedState, excludedNavigation)

local additional, additionalState, additionalNavigation = run({ { x = 1, y = 0, z = 0, name = "modded:vein_block" } }, { additional_ids = { "modded:vein_block" } })
assert(additional.ok and additional.value.collected == 1)
restored(additionalState, additionalNavigation)

local unrelated, unrelatedState, unrelatedNavigation = run({ { x = 1, y = 0, z = 0, name = "modded:oreberry_bush" } })
assert(unrelated.ok and unrelated.value.collected == 0)
assert(unrelatedState.blocks[key(1, 0, 0)].name == "modded:oreberry_bush")
restored(unrelatedState, unrelatedNavigation)

local chaseFailure, chaseFailureState, chaseFailureNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { fail_from_move = 1 })
assert(not chaseFailure.ok)
restored(chaseFailureState, chaseFailureNavigation)

local returnFailure, returnFailureState = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { fail_from_move = 2 })
assert(not returnFailure.ok and returnFailure.error.code == "ORE.RETURN_FAILED")
assert(returnFailureState.x == 1 and returnFailureState.y == 0 and returnFailureState.z == 0)

local unsafeBranch, unsafeState, unsafeNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, { fluid_failure = true })
assert(unsafeBranch.ok and unsafeBranch.value.abandoned)
resultShape(unsafeBranch)
restored(unsafeState, unsafeNavigation)

local chasedSingle, chasedSingleState, chasedSingleNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", chase_options = { anchor = { x = 0, y = 0, z = 0, heading = 0 } },
})
assert(chasedSingle.ok and chasedSingle.value.collected == 1 and chasedSingleState.digs == 1)
restored(chasedSingleState, chasedSingleNavigation)

local chasedHorizontal, chasedHorizontalState, chasedHorizontalNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:iron_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:iron_ore" },
}, { chase_direction = "forward", chase_name = "minecraft:iron_ore" })
assert(chasedHorizontal.ok and chasedHorizontal.value.collected == 2)
restored(chasedHorizontalState, chasedHorizontalNavigation)
local sawTwoStepTrail, sawCollapsedTrail = false, false
for _, excursion in ipairs(chasedHorizontalState.excursions) do
  if excursion and #excursion.breadcrumbs == 2 then sawTwoStepTrail = true end
  if excursion and #excursion.breadcrumbs == 1 then sawCollapsedTrail = true end
end
assert(sawTwoStepTrail and sawCollapsedTrail and chasedHorizontalState.excursions[#chasedHorizontalState.excursions] == false, "DFS backtracking must collapse the active breadcrumb trail")

local chasedVertical, chasedVerticalState, chasedVerticalNavigation = run({
  { x = 0, y = 1, z = 0, name = "minecraft:gold_ore" }, { x = 0, y = 2, z = 0, name = "minecraft:gold_ore" },
}, { chase_direction = "up", chase_name = "minecraft:gold_ore" })
assert(chasedVertical.ok and chasedVertical.value.collected == 2)
restored(chasedVerticalState, chasedVerticalNavigation)

local chasedBranching, chasedBranchingState, chasedBranchingNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:redstone_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:redstone_ore" },
  { x = 1, y = 1, z = 0, name = "minecraft:redstone_ore" }, { x = 1, y = 0, z = 1, name = "minecraft:redstone_ore" },
}, { chase_direction = "forward", chase_name = "minecraft:redstone_ore" })
assert(chasedBranching.ok and chasedBranching.value.collected == 4)
restored(chasedBranchingState, chasedBranchingNavigation)

local chasedLimit, chasedLimitState, chasedLimitNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:nether_gold_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:nether_gold_ore" },
}, { chase_direction = "forward", chase_name = "minecraft:nether_gold_ore", max_size = 1 })
assert(chasedLimit.ok and chasedLimit.value.collected == 1 and chasedLimit.value.limit_reached)
restored(chasedLimitState, chasedLimitNavigation)

local chasedFull, chasedFullState, chasedFullNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:nether_quartz_ore" }, { x = 2, y = 0, z = 0, name = "minecraft:nether_quartz_ore" },
}, { chase_direction = "forward", chase_name = "minecraft:nether_quartz_ore", full_after_digs = 1 })
assert(chasedFull.ok and chasedFull.value.collected == 1 and chasedFull.value.inventory_full)
restored(chasedFullState, chasedFullNavigation)

local chasedStopped, chasedStoppedState, chasedStoppedNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:coal_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:coal_ore", stop_after_digs = 0,
})
assert(chasedStopped.ok and chasedStopped.value.collected == 0 and chasedStopped.value.inventory_full)
restored(chasedStoppedState, chasedStoppedNavigation)

local chasedUnsafe, chasedUnsafeState, chasedUnsafeNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", fluid_failure = true,
})
assert(chasedUnsafe.ok and chasedUnsafe.value.abandoned)
restored(chasedUnsafeState, chasedUnsafeNavigation)

local chasedMoveFailure, chasedMoveFailureState, chasedMoveFailureNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", fail_from_move = 1,
})
assert(not chasedMoveFailure.ok)
restored(chasedMoveFailureState, chasedMoveFailureNavigation)

local chasedReturnFailure, chasedReturnFailureState = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", fail_from_move = 2,
})
assert(not chasedReturnFailure.ok and chasedReturnFailure.error.code == "ORE.RETURN_FAILED")
assert(chasedReturnFailureState.x == 1 and chasedReturnFailureState.y == 0 and chasedReturnFailureState.z == 0)
local failedTrail = chasedReturnFailureState.excursions[#chasedReturnFailureState.excursions]
assert(failedTrail and failedTrail.active and #failedTrail.breadcrumbs == 1, "failed breadcrumb return must retain the remaining route")

local fallbackReturn, fallbackState, fallbackNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", fail_moves = { [2] = true },
})
assert(fallbackReturn.ok and fallbackState.x == 0 and fallbackState.y == 0 and fallbackState.z == 0, "coordinate fallback must recover after a transient breadcrumb failure")
restored(fallbackState, fallbackNavigation)

local sharedProcessed = { ["1:0:0"] = true }
local skippedChase, skippedChaseState, skippedChaseNavigation = run({ { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" } }, {
  chase_direction = "forward", chase_name = "minecraft:diamond_ore", chase_options = { processed = sharedProcessed },
})
assert(skippedChase.ok and skippedChase.value.collected == 0 and skippedChaseState.digs == 0)
restored(skippedChaseState, skippedChaseNavigation)

local sliceBoundary, sliceState, sliceNavigation = run({
  { x = 1, y = 0, z = 0, name = "minecraft:diamond_ore" }, -- front-facing
  { x = 0, y = 1, z = -2, name = "minecraft:redstone_ore" }, -- left wall
  { x = 0, y = 1, z = 2, name = "minecraft:deepslate_redstone_ore" }, -- right wall
  { x = 0, y = 3, z = 0, name = "minecraft:coal_ore" }, -- ceiling center
  { x = 0, y = 2, z = -2, name = "minecraft:emerald_ore" }, -- upper-left boundary
  { x = 0, y = 2, z = 2, name = "minecraft:lapis_ore" }, -- upper-right boundary
  { x = 0, y = 0, z = -2, name = "minecraft:copper_ore" }, -- lower-left side edge
  { x = 0, y = 0, z = 2, name = "minecraft:iron_ore" }, -- lower-right side edge
  { x = 0, y = 3, z = -1, name = "minecraft:gold_ore" }, -- upper-left ceiling
  { x = 0, y = 3, z = 1, name = "minecraft:nether_gold_ore" }, -- upper-right ceiling
}, { slice_boundary = true })
assert(sliceBoundary.ok and #sliceBoundary.value.targets == 10)
assert(sliceState.digs == 0 and #sliceState.inspected_directions == 18)
assert(sliceState.moves > 0 and sliceState.turns > 0)
for _, position in ipairs(sliceState.move_positions) do
  assert(position.x == 0 and position.y >= 0 and position.y <= 2 and position.z >= -1 and position.z <= 1, "slice scan moved outside cleared 3x3 interior")
end
local sliceKeys, sliceNames = {}, {}
for _, target in ipairs(sliceBoundary.value.targets) do
  assert(not sliceKeys[target.key], "slice discovery returned a duplicate coordinate")
  sliceKeys[target.key], sliceNames[target.data.name] = true, true
end
assert(sliceNames["minecraft:redstone_ore"] and sliceNames["minecraft:deepslate_redstone_ore"])
assert(sliceNames["minecraft:diamond_ore"] and sliceNames["minecraft:coal_ore"])
restored(sliceState, sliceNavigation)

local largeBoundary, largeState, largeNavigation = run({
  { x = 1, y = 0, z = -2, name = "minecraft:redstone_ore" },
  { x = 1, y = 4, z = 2, name = "minecraft:deepslate_redstone_ore" },
  { x = 0, y = 0, z = -3, name = "alltheores:uranium_ore" },
  { x = 0, y = 2, z = -3, name = "minecraft:diamond_ore" },
  { x = 0, y = 4, z = -3, name = "minecraft:emerald_ore" },
  { x = 0, y = 0, z = 3, name = "minecraft:iron_ore" },
  { x = 0, y = 2, z = 3, name = "minecraft:gold_ore" },
  { x = 0, y = 4, z = 3, name = "minecraft:lapis_ore" },
  { x = 0, y = 5, z = -2, name = "minecraft:copper_ore" },
  { x = 0, y = 5, z = 0, name = "minecraft:coal_ore" },
  { x = 0, y = 5, z = 2, name = "minecraft:nether_gold_ore" },
}, { slice_boundary = true, width = 5, height = 5 })
assert(largeBoundary.ok and #largeBoundary.value.targets == 11 and largeState.digs == 0)
assert(#largeState.inspected_directions == 40, "5x5 boundary inspection count must cover front, walls, and ceiling")
for _, position in ipairs(largeState.move_positions) do
  assert(position.x == 0 and position.y >= 0 and position.y <= 4 and position.z >= -2 and position.z <= 2, "5x5 scanner moved outside cleared interior")
end
restored(largeState, largeNavigation)

local hugeBoundary, hugeState, hugeNavigation = run({
  { x = 1, y = 0, z = -4, name = "minecraft:redstone_ore" },
  { x = 1, y = 8, z = 4, name = "minecraft:deepslate_redstone_ore" },
  { x = 0, y = 0, z = -5, name = "alltheores:uranium_ore" },
  { x = 0, y = 8, z = -5, name = "minecraft:diamond_ore" },
  { x = 0, y = 0, z = 5, name = "minecraft:iron_ore" },
  { x = 0, y = 8, z = 5, name = "minecraft:emerald_ore" },
  { x = 0, y = 9, z = -4, name = "minecraft:lapis_ore" },
  { x = 0, y = 9, z = 0, name = "minecraft:coal_ore" },
  { x = 0, y = 9, z = 4, name = "minecraft:gold_ore" },
}, { slice_boundary = true, width = 9, height = 9 })
assert(hugeBoundary.ok and #hugeBoundary.value.targets == 9 and hugeState.digs == 0)
assert(#hugeState.inspected_directions == 108, "9x9 scanner must inspect front, wall, and ceiling boundary positions")
for _, position in ipairs(hugeState.move_positions) do
  assert(position.x == 0 and position.y >= 0 and position.y <= 8 and position.z >= -4 and position.z <= 4, "9x9 scanner moved outside cleared interior")
end
restored(hugeState, hugeNavigation)

local boundaryChase, boundaryChaseState, boundaryChaseNavigation = run({
  { x = 0, y = 1, z = -2, name = "minecraft:redstone_ore" },
}, { mine_slice_boundary = true })
assert(boundaryChase.ok and boundaryChase.value.collected == 1 and boundaryChaseState.digs == 1)
restored(boundaryChaseState, boundaryChaseNavigation)

print("ore tests passed")

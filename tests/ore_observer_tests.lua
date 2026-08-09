local Result = dofile("src/ralfie/core/result.lua")
local Ore = dofile("src/ralfie/services/operations/ore.lua")

local function key(position)
  return math.floor(position.x) .. ":" .. math.floor(position.y) .. ":" .. math.floor(position.z)
end

local function build(options)
  options = options or {}
  local state = { moves = 0, turns = 0, digs = 0, inspections = 0 }
  local adapter = {
    inspect = function() state.inspections = state.inspections + 1; error("observer must not inspect turtle hardware") end,
    move = function() state.moves = state.moves + 1; error("observer must not move turtle hardware") end,
    dig = function() state.digs = state.digs + 1; error("observer must not dig") end,
  }
  local navigation = {
    position = function() return { x = 0, y = 0, z = 0, heading = 0 } end,
    face = function() state.turns = state.turns + 1; error("observer must not turn turtle hardware") end,
  }
  local world = { move = function() state.moves = state.moves + 1; error("observer must not move through world") end }
  return Ore.new({ adapter = adapter, navigation = navigation, world = world, result = Result, additional_ids = options.additional_ids, excluded_ids = options.excluded_ids, matcher = options.matcher }), state
end

local directions = {
  forward = { name = "forward", heading = 0, x = 1, y = 0, z = 0 },
  right = { name = "right", heading = 1, x = 0, y = 0, z = 1 },
  left = { name = "left", heading = 3, x = 0, y = 0, z = -1 },
  up = { name = "up", move = "up", x = 0, y = 1, z = 0 },
}

local names = {
  { name = "minecraft:redstone_ore" },
  { name = "minecraft:deepslate_redstone_ore" },
  { name = "alltheores:uranium_ore" },
  { name = "modded:tagged_resource", tags = { ["c:ores/test"] = true } },
}

local function boundaryObservations(size)
  local half, observations, expected, index = (size - 1) / 2, {}, {}, 1
  local function add(origin, direction)
    local data = names[index]
    index = (index % #names) + 1
    table.insert(observations, { origin = origin, direction = direction, data = data })
    table.insert(expected, key({ x = origin.x + direction.x, y = origin.y + direction.y, z = origin.z + direction.z }))
  end
  for y = 0, size - 1 do
    for z = -half, half do add({ x = 0, y = y, z = z, heading = 0 }, directions.forward) end
    add({ x = 0, y = y, z = -half, heading = 0 }, directions.left)
    add({ x = 0, y = y, z = half, heading = 0 }, directions.right)
  end
  for z = -half, half do add({ x = 0, y = size - 1, z = z, heading = 0 }, directions.up) end
  return observations, expected
end

for _, size in ipairs({ 3, 5, 9 }) do
  local ore, state = build()
  local anchor = { x = 0, y = 0, z = 0, heading = 0 }
  local started = ore:beginTunnelBoundaryDiscovery({ width = size, height = size, anchor = anchor })
  assert(started.ok)
  local observations, expected = boundaryObservations(size)
  for _, observation in ipairs(observations) do assert(started.value:observe(observation).ok) end
  local finished = started.value:finish()
  assert(finished.ok and finished.value.observations == #observations)
  assert(finished.value.anchor.x == 0 and finished.value.anchor.y == 0 and finished.value.anchor.z == 0 and finished.value.anchor.heading == 0)
  assert(#finished.value.targets == #expected)
  for index, target in ipairs(finished.value.targets) do
    assert(key(target.position) == expected[index], "observer ordering/coverage changed for " .. size .. "x" .. size)
    assert(target.position and target.origin and target.direction and target.data, "observer targets must remain chase-compatible")
  end
  local repeated = ore:beginTunnelBoundaryDiscovery({ width = size, height = size, anchor = anchor }).value
  for _, observation in ipairs(observations) do repeated:observe(observation) end
  for index, target in ipairs(repeated:finish().value.targets) do
    assert(key(target.position) == key(finished.value.targets[index].position), "observer ordering must be deterministic")
  end
  assert(state.moves == 0 and state.turns == 0 and state.digs == 0 and state.inspections == 0, "observer must have zero turtle side effects")
end

local dedupeOre = build()
local dedupe = dedupeOre:beginTunnelBoundaryDiscovery({ width = 3, height = 3, anchor = { x = 0, y = 0, z = 0, heading = 0 } }).value
assert(dedupe:observe({ origin = { x = 0, y = 0, z = 0 }, direction = directions.forward, data = { name = "minecraft:diamond_ore" } }).value)
assert(not dedupe:observe({ origin = { x = 1, y = 0, z = 1 }, direction = directions.left, data = { name = "minecraft:diamond_ore" } }).value)
assert(#dedupe:finish().value.targets == 1)

local matcherOre = build({ additional_ids = { "modded:explicit" }, excluded_ids = { "minecraft:diamond_ore" } })
local matcher = matcherOre:beginTunnelBoundaryDiscovery({ width = 3, height = 3, anchor = { x = 0, y = 0, z = 0, heading = 0 } }).value
assert(not matcher:observe({ origin = { x = 0, y = 0, z = 0 }, direction = directions.forward, data = { name = "minecraft:stone" } }).value)
assert(not matcher:observe({ origin = { x = 0, y = 0, z = 1 }, direction = directions.forward, data = { name = "minecraft:diamond_ore" } }).value)
assert(matcher:observe({ origin = { x = 0, y = 0, z = -1 }, direction = directions.forward, data = { name = "modded:explicit" } }).value)
assert(matcher:observe({ origin = { x = 0, y = 1, z = 0 }, direction = directions.forward, data = { name = "modded:not_named_like_ore", tags = { ["neoforge:ores/test"] = true } } }).value)

local customOre = build({ matcher = function(name) return name == "custom:ore_block" end })
local custom = customOre:beginTunnelBoundaryDiscovery({ width = 3, height = 3, anchor = { x = 0, y = 0, z = 0, heading = 0 } }).value
assert(custom:observe({ origin = { x = 0, y = 0, z = 0 }, direction = directions.forward, data = { present = true, data = { name = "custom:ore_block" } } }).value)
assert(not custom:observe({ origin = { x = 0, y = 1, z = 0 }, direction = directions.forward, data = { present = false } }).value)

print("ore observer tests passed")

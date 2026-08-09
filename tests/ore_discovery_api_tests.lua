local Result = dofile("src/ralfie/core/result.lua")
local Ore = dofile("src/ralfie/services/operations/ore.lua")

-- Contract tests for Step 2. This suite is intentionally expected to fail until
-- Ore exposes discoverExposed() without digging or moving the turtle.
local expected = {
  forward = "minecraft:redstone_ore",
  left = "minecraft:deepslate_redstone_ore",
  right = "minecraft:diamond_ore",
  backward = "minecraft:iron_ore",
  up = "minecraft:coal_ore",
  down = "minecraft:stone", -- Non-ore: discovery must ignore it.
}
local expectedDirectionByName = {
  [expected.forward] = "forward",
  [expected.right] = "right",
  [expected.backward] = "backward",
  [expected.left] = "left",
  [expected.up] = "up",
}
local horizontal = { [0] = "forward", [1] = "right", [2] = "backward", [3] = "left" }
local state = { x = 0, y = 0, z = 0, heading = 0, moves = 0, digs = 0, turns = 0, inspected_directions = {} }
local adapter = {
  inspect = function(_, direction)
    table.insert(state.inspected_directions, direction)
    local worldDirection = direction == "forward" and horizontal[state.heading] or direction
    local name = expected[worldDirection]
    if name then return Result.ok({ present = true, data = { name = name } }) end
    return Result.ok({ present = false })
  end,
  dig = function() state.digs = state.digs + 1; return Result.ok(true) end,
  turnLeft = function() state.turns = state.turns + 1; state.heading = (state.heading + 3) % 4; return Result.ok(true) end,
  turnRight = function() state.turns = state.turns + 1; state.heading = (state.heading + 1) % 4; return Result.ok(true) end,
}
local navigation = {
  position = function() return { x = state.x, y = state.y, z = state.z, heading = state.heading } end,
  face = function(_, heading)
    while state.heading ~= heading do
      local delta = (heading - state.heading) % 4
      local turned = delta == 3 and adapter:turnLeft() or adapter:turnRight()
      if not turned.ok then return turned end
    end
    return Result.ok(true)
  end,
  move = function() state.moves = state.moves + 1; return Result.ok(true) end,
}
local ore = Ore.new({ adapter = adapter, navigation = navigation, world = { move = function() return Result.ok(true) end }, result = Result })
assert(type(ore.discoverExposed) == "function", "discoverExposed() is not implemented")
local discovered = ore:discoverExposed()
assert(discovered.ok)
assert(discovered.value.anchor.x == 0 and discovered.value.anchor.y == 0 and discovered.value.anchor.z == 0 and discovered.value.anchor.heading == 0)
assert(#discovered.value.targets == 5, "non-ore must be ignored and each discovered coordinate deduplicated")
assert(#state.inspected_directions == 6, "forward, right, backward, left, up, and down must be inspected")
local seen = {}
local found = {}
for _, target in ipairs(discovered.value.targets) do
  local targetKey = target.position.x .. ":" .. target.position.y .. ":" .. target.position.z
  assert(not seen[targetKey], "discovery must not return duplicate coordinates")
  assert(target.key == targetKey, "target key must describe the target position")
  assert(type(target.direction) == "table" and type(target.direction.name) == "string")
  assert(type(target.data) == "table" and type(target.data.name) == "string")
  assert(target.direction.name == expectedDirectionByName[target.data.name], "target direction must match the inspected ore")
  seen[targetKey] = true
  found[target.data.name] = true
end
assert(found[expected.forward] and found[expected.left] and found[expected.right] and found[expected.backward])
assert(found[expected.up] and not found[expected.down], "all horizontal, upward, and only matching targets must be discovered")
assert(state.digs == 0 and state.moves == 0 and state.heading == 0)
assert(state.turns == 8, "discovery must retain the current six-direction turn baseline")
print("ore discovery API tests passed")

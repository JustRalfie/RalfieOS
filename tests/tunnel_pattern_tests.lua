local Result = dofile("src/ralfie/core/result.lua")
local TunnelPattern = dofile("src/ralfie/services/operations/tunnel_pattern.lua")

local state = { x = 0, y = 0, z = 0, heading = 0, moves = {} }
local vectors = { [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 }, [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 } }
local navigation = {
  position = function() return { x = state.x, y = state.y, z = state.z, heading = state.heading } end,
  face = function(_, heading) state.heading = heading; return Result.ok(true) end,
}
local world = {
  move = function(_, direction)
    if direction == "up" then state.y = state.y + 1
    elseif direction == "down" then state.y = state.y - 1
    else local vector = vectors[state.heading]; state.x, state.z = state.x + vector.x, state.z + vector.z end
    table.insert(state.moves, { x = state.x, y = state.y, z = state.z })
    return Result.ok(true)
  end,
}
local pattern = TunnelPattern.new({ navigation = navigation, world = world, result = Result })
local cleared = pattern:clearSlice(5, 5)
assert(cleared.ok and state.x == 0 and state.y == 0 and state.z == 0 and state.heading == 0)
local highest, left, right = 0, 0, 0
for _, position in ipairs(state.moves) do
  highest = math.max(highest, position.y)
  left, right = math.min(left, position.z), math.max(right, position.z)
end
assert(highest == 4 and left == -2 and right == 2, "5x5 pattern must traverse every column height and side offset")
assert(pattern:movementEstimate(5, 5) > pattern:movementEstimate(3, 3))
state.x, state.y, state.z, state.heading, state.moves = 0, 0, 0, 0, {}
local large = pattern:clearSlice(9, 9)
assert(large.ok and state.x == 0 and state.y == 0 and state.z == 0 and state.heading == 0)
local highest9, left9, right9 = 0, 0, 0
for _, position in ipairs(state.moves) do highest9 = math.max(highest9, position.y); left9, right9 = math.min(left9, position.z), math.max(right9, position.z) end
assert(highest9 == 8 and left9 == -4 and right9 == 4, "9x9 pattern must traverse all nine columns and heights")
assert(pattern:movementEstimate(9, 9) > pattern:movementEstimate(5, 5))
assert(not pattern:clearSlice(4, 5).ok)
print("tunnel pattern tests passed")

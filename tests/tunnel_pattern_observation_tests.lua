local Result = dofile("src/ralfie/core/result.lua")
local TunnelPattern = dofile("src/ralfie/services/operations/tunnel_pattern.lua")

local vectors = { [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 }, [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 } }
local function key(position) return math.floor(position.x) .. ":" .. math.floor(position.y) .. ":" .. math.floor(position.z) end

local function build(withAdapter)
  local state = { x = 0, y = 0, z = 0, heading = 0, moves = 0, turns = 0, digs = 0, inspections = 0, observations = {} }
  local navigation = {
    position = function() return { x = state.x, y = state.y, z = state.z, heading = state.heading } end,
    face = function(_, heading)
      local delta = (heading - state.heading) % 4
      if delta > 0 then state.turns = state.turns + math.min(delta, 4 - delta) end
      state.heading = heading
      return Result.ok(true)
    end,
  }
  local world = {
    move = function(_, direction)
      state.moves = state.moves + 1
      if direction == "up" then state.y = state.y + 1
      elseif direction == "down" then state.y = state.y - 1
      else local vector = vectors[state.heading]; state.x, state.z = state.x + vector.x, state.z + vector.z end
      return Result.ok(true)
    end,
  }
  local adapter
  if withAdapter then
    adapter = {
      inspect = function(_, direction)
        state.inspections = state.inspections + 1
        local target = { x = state.x, y = state.y, z = state.z }
        if direction == "up" then target.y = target.y + 1
        else local vector = vectors[state.heading]; target.x, target.z = target.x + vector.x, target.z + vector.z end
        return Result.ok({ present = true, data = { name = "test:" .. key(target) } })
      end,
    }
  end
  local pattern = TunnelPattern.new({ navigation = navigation, world = world, result = Result, adapter = adapter })
  return pattern, state
end

local function expectedBoundary(size)
  local half, expected = (size - 1) / 2, {}
  local function add(x, y, z) table.insert(expected, key({ x = x, y = y, z = z })) end
  for y = 0, size - 1 do
    for z = -half, half do add(1, y, z) end
    add(0, y, -half - 1)
    add(0, y, half + 1)
  end
  for z = -half, half do add(0, size, z) end
  return expected
end

for _, size in ipairs({ 3, 5, 9 }) do
  local baseline, baselineState = build(false)
  assert(baseline:clearSlice(size, size).ok)
  local pattern, state = build(true)
  local observer = {
    observe = function(_, observation)
      table.insert(state.observations, observation)
      return Result.ok(true)
    end,
  }
  local cleared = pattern:clearSlice(size, size, { observer = observer })
  assert(cleared.ok)
  assert(state.moves == baselineState.moves, "observer must not add moves for " .. size .. "x" .. size)
  assert(state.digs == 0 and state.inspections == (size * size) + (size * 3))
  assert(state.x == 0 and state.y == 0 and state.z == 0 and state.heading == 0)
  local expected, seen = expectedBoundary(size), {}
  assert(#state.observations == #expected)
  for _, observation in ipairs(state.observations) do
    local direction, origin = observation.direction, observation.origin
    local target = { x = origin.x + direction.x, y = origin.y + direction.y, z = origin.z + direction.z }
    local targetKey = key(target)
    assert(not seen[targetKey], "pattern emitted duplicate boundary observation")
    seen[targetKey] = true
    assert(observation.data.present and observation.data.data.name == "test:" .. targetKey, "inspection data must pass through unchanged")
  end
  for _, targetKey in ipairs(expected) do assert(seen[targetKey], "pattern missed boundary target " .. targetKey) end

  local repeated, repeatedState = build(true)
  local repeatedObserver = { observe = function(_, observation) table.insert(repeatedState.observations, observation); return Result.ok(true) end }
  assert(repeated:clearSlice(size, size, { observer = repeatedObserver }).ok)
  for index, observation in ipairs(state.observations) do
    local direction, origin = observation.direction, observation.origin
    local otherDirection, otherOrigin = repeatedState.observations[index].direction, repeatedState.observations[index].origin
    assert(key({ x = origin.x + direction.x, y = origin.y + direction.y, z = origin.z + direction.z }) == key({ x = otherOrigin.x + otherDirection.x, y = otherOrigin.y + otherDirection.y, z = otherOrigin.z + otherDirection.z }), "observation ordering must be deterministic")
  end
end

local unavailable = build(false)
local missingAdapter = unavailable:clearSlice(3, 3, { observer = { observe = function() return Result.ok(true) end } })
assert(not missingAdapter.ok and missingAdapter.error.code == "TUNNEL.OBSERVER_UNAVAILABLE")

local failedPattern, failedState = build(true)
local failed = failedPattern:clearSlice(3, 3, { observer = { observe = function() return Result.fail("TEST.OBSERVER_FAILED", "observer rejected observation") end } })
assert(not failed.ok and failed.error.code == "TEST.OBSERVER_FAILED" and failedState.moves == 0, "observer failure must stop before excavation movement")

print("tunnel pattern observation tests passed")

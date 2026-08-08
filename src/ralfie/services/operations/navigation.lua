local Navigation = {}

function Navigation.new(options)
  local adapter = assert(options.adapter, "navigation requires turtle adapter")
  local result = assert(options.result, "navigation requires result")
  local state = { x = 0, y = 0, z = 0, heading = 0 }
  local navigation = {}

  local vectors = {
    [0] = { x = 1, z = 0 },
    [1] = { x = 0, z = 1 },
    [2] = { x = -1, z = 0 },
    [3] = { x = 0, z = -1 },
  }

  function navigation:position()
    return { x = state.x, y = state.y, z = state.z, heading = state.heading }
  end

  function navigation:turnRight()
    local turned = adapter:turnRight()
    if turned.ok then state.heading = (state.heading + 1) % 4 end
    return turned
  end

  function navigation:turnLeft()
    local turned = adapter:turnLeft()
    if turned.ok then state.heading = (state.heading + 3) % 4 end
    return turned
  end

  function navigation:face(heading)
    while state.heading ~= heading do
      local delta = (heading - state.heading) % 4
      local turned = delta == 3 and self:turnLeft() or self:turnRight()
      if not turned.ok then return turned end
    end
    return result.ok(true)
  end

  function navigation:move(direction)
    local moved = adapter:move(direction)
    if not moved.ok then return moved end
    if direction == "up" then
      state.y = state.y + 1
    elseif direction == "down" then
      state.y = state.y - 1
    else
      local vector = vectors[state.heading]
      state.x = state.x + vector.x
      state.z = state.z + vector.z
    end
    return result.ok(self:position())
  end

  return navigation
end

return Navigation

local TunnelPattern = {}

function TunnelPattern.new(options)
  local navigation = assert(options.navigation, "tunnel pattern requires navigation")
  local world = assert(options.world, "tunnel pattern requires world")
  local result = assert(options.result, "tunnel pattern requires result")
  local adapter = options.adapter
  local retries = options.movement_retries or 3
  local pattern = {}

  local function faceAndMove(heading, clearPath)
    local faced = navigation:face(heading)
    if not faced.ok then return faced end
    return world:move("forward", retries, clearPath)
  end

  local directions = {
    forward = { name = "forward", heading = 0, x = 1, y = 0, z = 0 },
    right = { name = "right", heading = 1, x = 0, y = 0, z = 1 },
    left = { name = "left", heading = 3, x = 0, y = 0, z = -1 },
    up = { name = "up", move = "up", x = 0, y = 1, z = 0 },
  }

  local function copy(position)
    return { x = position.x, y = position.y, z = position.z, heading = position.heading }
  end

  local function observe(observer, direction)
    if not observer then return result.ok(false) end
    if not adapter then return result.fail("TUNNEL.OBSERVER_UNAVAILABLE", "Tunnel observation requires a turtle adapter") end
    local origin = copy(navigation:position())
    local inspected
    if direction.move then
      inspected = adapter:inspect(direction.move)
    else
      local faced = navigation:face(direction.heading)
      if not faced.ok then return faced end
      inspected = adapter:inspect("forward")
      local restored = navigation:face(origin.heading)
      if not restored.ok then return restored end
    end
    if not inspected.ok then return inspected end
    local observed = observer:observe({ origin = origin, direction = direction, data = inspected.value })
    if not observed.ok then return observed end
    return result.ok(true)
  end

  local function observeCell(observer, outerDirection, atTop)
    local front = observe(observer, directions.forward)
    if not front.ok then return front end
    if outerDirection then
      local wall = observe(observer, outerDirection)
      if not wall.ok then return wall end
    end
    if atTop then
      local ceiling = observe(observer, directions.up)
      if not ceiling.ok then return ceiling end
    end
    return result.ok(true)
  end

  local function clearColumn(height, observer, outerDirection)
    local bottom = observeCell(observer, outerDirection, height == 1)
    if not bottom.ok then return bottom end
    for level = 1, height - 1 do
      local moved = world:move("up", retries)
      if not moved.ok then return moved end
      local observed = observeCell(observer, outerDirection, level == height - 1)
      if not observed.ok then return observed end
    end
    for _ = 1, height - 1 do
      local moved = world:move("down", retries, false)
      if not moved.ok then return moved end
    end
    return result.ok(true)
  end

  function pattern:clearSlice(width, height, options)
    options = options or {}
    if type(width) ~= "number" or type(height) ~= "number" or width < 3 or height < 3 or width % 2 ~= 1 or height % 2 ~= 1 then
      return result.fail("TUNNEL.INVALID_PATTERN", "Tunnel width and height must be odd whole numbers of at least three")
    end
    local anchor = navigation:position()
    local center = clearColumn(height, options.observer)
    if not center.ok then return center end
    local half = (width - 1) / 2
    for _, heading in ipairs({ 3, 1 }) do
      for offset = 1, half do
        local entered = faceAndMove(heading, true)
        if not entered.ok then return entered end
        local outer = offset == half and (heading == 3 and directions.left or directions.right) or nil
        local column = clearColumn(height, options.observer, outer)
        if not column.ok then return column end
      end
      for _ = 1, half do
        local returned = faceAndMove((heading + 2) % 4, false)
        if not returned.ok then return returned end
      end
    end
    local restored = navigation:face(anchor.heading)
    if not restored.ok then return restored end
    local position = navigation:position()
    if position.x ~= anchor.x or position.y ~= anchor.y or position.z ~= anchor.z or position.heading ~= anchor.heading then
      return result.fail("TUNNEL.PATTERN_MISMATCH", "Tunnel pattern did not return to the center lane")
    end
    return result.ok(true)
  end

  function pattern:movementEstimate(width, height)
    local half = (width - 1) / 2
    return (height - 1) * 2 * width + width * 2 + half * 2
  end

  return pattern
end

return TunnelPattern

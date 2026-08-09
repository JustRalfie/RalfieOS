local TunnelPattern = {}

function TunnelPattern.new(options)
  local navigation = assert(options.navigation, "tunnel pattern requires navigation")
  local world = assert(options.world, "tunnel pattern requires world")
  local result = assert(options.result, "tunnel pattern requires result")
  local retries = options.movement_retries or 3
  local pattern = {}

  local function faceAndMove(heading, clearPath)
    local faced = navigation:face(heading)
    if not faced.ok then return faced end
    return world:move("forward", retries, clearPath)
  end

  local function clearColumn(height)
    for _ = 1, height - 1 do
      local moved = world:move("up", retries)
      if not moved.ok then return moved end
    end
    for _ = 1, height - 1 do
      local moved = world:move("down", retries, false)
      if not moved.ok then return moved end
    end
    return result.ok(true)
  end

  function pattern:clearSlice(width, height)
    if type(width) ~= "number" or type(height) ~= "number" or width < 3 or height < 3 or width % 2 ~= 1 or height % 2 ~= 1 then
      return result.fail("TUNNEL.INVALID_PATTERN", "Tunnel width and height must be odd whole numbers of at least three")
    end
    local anchor = navigation:position()
    local center = clearColumn(height)
    if not center.ok then return center end
    local half = (width - 1) / 2
    for _, heading in ipairs({ 3, 1 }) do
      for offset = 1, half do
        local entered = faceAndMove(heading, true)
        if not entered.ok then return entered end
        local column = clearColumn(height)
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

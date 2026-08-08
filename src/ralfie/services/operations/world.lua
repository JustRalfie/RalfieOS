local World = {}

function World.new(options)
  local adapter = assert(options.adapter, "world requires turtle adapter")
  local navigation = assert(options.navigation, "world requires navigation")
  local result = assert(options.result, "world requires result")
  local logger = options.logger
  local fluid = options.fluid
  local pause = options.pause or function() end
  local world = {}

  function world:clear(direction, limit)
    limit = limit or 8
    for _ = 1, limit do
      local inspected = adapter:inspect(direction)
      if not inspected.ok then return inspected end
      if not inspected.value.present then return result.ok(true) end
      if fluid and fluid:isFluid(inspected.value.data) then
        local secured = fluid:secure(direction, inspected.value.data)
        if not secured.ok then return secured end
      else
        local dug = adapter:dig(direction)
        if not dug.ok then return dug end
        if logger then logger:debug("world.block_dug", { direction = direction }) end
      end
      pause()
    end
    return result.fail("WORLD.UNSTABLE_BLOCK", "Block kept falling into the path", { retryable = false, context = { direction = direction } })
  end

  function world:move(direction, retries, clearPath)
    retries = retries or 3
    if clearPath == nil then clearPath = true end
    local lastFailure
    for attempt = 1, retries do
      if clearPath then
        local cleared = self:clear(direction)
        if not cleared.ok then return cleared end
      end
      local moved = navigation:move(direction)
      if moved.ok then return moved end
      lastFailure = moved
      if logger then logger:warn("world.move_retry", { direction = direction, attempt = attempt, reason = moved.error.message }) end
      pause()
    end
    return result.fail("WORLD.MOVE_BLOCKED", "Movement failed after retries", {
      context = { direction = direction, reason = lastFailure and lastFailure.error.message },
    })
  end

  function world:clearColumn()
    local cleared = self:clear("up")
    if not cleared.ok then return cleared end
    local moved = self:move("up")
    if not moved.ok then return moved end
    cleared = self:clear("up")
    if not cleared.ok then return cleared end
    moved = self:move("down", nil, false)
    if not moved.ok then return moved end
    return result.ok(true)
  end

  return world
end

return World

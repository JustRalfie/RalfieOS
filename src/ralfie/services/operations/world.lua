local World = {}

function World.new(options)
  local adapter = assert(options.adapter, "world requires turtle adapter")
  local navigation = assert(options.navigation, "world requires navigation")
  local result = assert(options.result, "world requires result")
  local logger = options.logger
  local fluid = options.fluid
  local pause = options.pause or function() end
  local torchPositions = options.torch_positions or {}
  local torchSlot = options.torch_slot
  local onTorchChanged = options.on_torch_changed
  local world = {}

  local vectors = {
    [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 },
    [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 },
  }

  local function copy(position)
    return { x = position.x, y = position.y, z = position.z, heading = position.heading }
  end

  local function key(position)
    return position.x .. ":" .. position.y .. ":" .. position.z
  end

  local function destination(direction)
    local position = navigation:position()
    if direction == "up" then return { x = position.x, y = position.y + 1, z = position.z } end
    if direction == "down" then return { x = position.x, y = position.y - 1, z = position.z } end
    local vector = vectors[position.heading]
    return { x = position.x + vector.x, y = position.y, z = position.z }
  end

  local function isTorch(data)
    return type(data) == "table" and data.name == "minecraft:torch"
  end

  local function torchSlotToPlace()
    if torchSlot and adapter:itemCount(torchSlot) > 0 then return torchSlot end
    for slot = 1, 16 do
      local detail = adapter:itemDetail(slot)
      if detail and detail.name == "minecraft:torch" and adapter:itemCount(slot) > 0 then return slot end
    end
    return nil
  end

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

  function world:move(direction, retries, clearPath, skipTorchPath)
    retries = retries or 3
    if clearPath == nil then clearPath = true end
    local target = destination(direction)
    local targetKey = key(target)
    if not skipTorchPath and torchPositions[targetKey] then
      local inspected = adapter:inspect(direction)
      if not inspected.ok then return inspected end
      if isTorch(inspected.value.data) then
        local previous = copy(navigation:position())
        local travelHeading = previous.heading
        local dug = adapter:dig(direction)
        if not dug.ok then return dug end
        local moved = self:move(direction, retries, false, true)
        if not moved.ok then
          local replacement = torchSlotToPlace()
          if replacement then adapter:select(replacement); adapter:place(direction) end
          return moved
        end
        local faced = navigation:face((travelHeading + 2) % 4)
        if not faced.ok then return faced end
        local replacement = torchSlotToPlace()
        local placed = replacement and adapter:select(replacement) or nil
        if placed and placed.ok then placed = adapter:place("forward") end
        local restored = navigation:face(travelHeading)
        if not restored.ok then return restored end
        torchPositions[targetKey] = nil
        if placed and placed.ok then
          torchPositions[key(previous)] = true
          if onTorchChanged then onTorchChanged(torchPositions) end
          if logger then logger:info("world.torch_replaced", { from = target, to = previous }) end
        elseif logger then
          logger:warn("world.torch_replace_failed", { from = target, to = previous, reason = placed and placed.error and placed.error.message or "no torch item available" })
        end
        return moved
      end
      if logger then logger:warn("world.torch_missing", { position = target, block = inspected.value.data and inspected.value.data.name }) end
    end
    if clearPath then
      local inspected = adapter:inspect(direction)
      if not inspected.ok then return inspected end
      if not inspected.value.present then clearPath = false else
        local cleared = self:clear(direction)
        if not cleared.ok then return cleared end
        clearPath = false
      end
    end
    local lastFailure
    for attempt = 1, retries do
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

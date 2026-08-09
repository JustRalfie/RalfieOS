local Ore = {}

local directions = {
  { name = "forward", heading = 0, x = 1, y = 0, z = 0 },
  { name = "right", heading = 1, x = 0, y = 0, z = 1 },
  { name = "backward", heading = 2, x = -1, y = 0, z = 0 },
  { name = "left", heading = 3, x = 0, y = 0, z = -1 },
  { name = "up", move = "up", x = 0, y = 1, z = 0 },
  { name = "down", move = "down", x = 0, y = -1, z = 0 },
}

local function copy(position)
  return { x = position.x, y = position.y, z = position.z, heading = position.heading }
end

local function key(position)
  return position.x .. ":" .. position.y .. ":" .. position.z
end

local function samePosition(left, right)
  return left.x == right.x and left.y == right.y and left.z == right.z and left.heading == right.heading
end

local function sameCoordinates(left, right)
  return left.x == right.x and left.y == right.y and left.z == right.z
end

local function copyDirection(direction)
  return {
    name = direction.name,
    heading = direction.heading,
    move = direction.move,
    x = direction.x,
    y = direction.y,
    z = direction.z,
  }
end

local function inverseDirection(from, to)
  local x, y, z = from.x - to.x, from.y - to.y, from.z - to.z
  for _, direction in ipairs(directions) do
    if direction.x == x and direction.y == y and direction.z == z then return copyDirection(direction) end
  end
  return nil
end

local function copyBreadcrumbs(breadcrumbs)
  local copied = {}
  for index, crumb in ipairs(breadcrumbs or {}) do
    copied[index] = { from = copy(crumb.from), to = copy(crumb.to), return_direction = copyDirection(crumb.return_direction) }
  end
  return copied
end

function Ore.new(options)
  local adapter = assert(options.adapter, "ore operation requires turtle adapter")
  local navigation = assert(options.navigation, "ore operation requires navigation")
  local world = assert(options.world, "ore operation requires world")
  local inventory = options.inventory
  local result = assert(options.result, "ore operation requires result")
  local logger = options.logger
  local ui = options.ui
  local maxSize = options.max_size or 64
  local retries = options.movement_retries or 3
  local additional = options.additional_ids or {}
  local excluded = options.excluded_ids or {}
  local matcher = options.matcher
  local shouldStop = options.should_stop
  local fluid = options.fluid
  local onExcursion = options.on_excursion
  local ore = {}

  assert(type(maxSize) == "number" and maxSize >= 1 and maxSize % 1 == 0, "ore maximum size must be a positive whole number")

  local function contains(ids, name)
    for _, id in ipairs(ids) do if name == id then return true end end
    return false
  end

  local function hasOreTag(tags)
    if type(tags) ~= "table" then return false end
    for tag, value in pairs(tags) do
      local name = type(tag) == "string" and tag or value
      if type(name) == "string" and (
        name == "c:ores" or name:sub(1, 7) == "c:ores/" or
        name == "neoforge:ores" or name:sub(1, 14) == "neoforge:ores/" or
        name == "forge:ores" or name:sub(1, 11) == "forge:ores/"
      ) then return true end
    end
    return false
  end

  local function matches(data)
    if type(data) ~= "table" or type(data.name) ~= "string" then return false end
    if contains(excluded, data.name) then return false end
    if contains(additional, data.name) then return true end
    if hasOreTag(data.tags) then return true end
    if matcher and matcher(data.name, data) == true then return true end
    if data.name:find("_ore", 1, true) then return true end
    if data.name == "minecraft:ancient_debris" then return true end
    return false
  end

  local function move(direction, clearPath)
    if direction.move then return world:move(direction.move, retries, clearPath) end
    local faced = navigation:face(direction.heading)
    if not faced.ok then return faced end
    return world:move("forward", retries, clearPath)
  end

  local function inspect(direction)
    if direction.move then return adapter:inspect(direction.move) end
    local originalHeading = navigation:position().heading
    local faced = navigation:face(direction.heading)
    if not faced.ok then return faced end
    local inspected = adapter:inspect("forward")
    local restored = navigation:face(originalHeading)
    if not restored.ok then return restored end
    return inspected
  end

  local function returnTo(target)
    while navigation:position().y < target.y do
      local moved = world:move("up", retries, false)
      if not moved.ok then return moved end
    end
    while navigation:position().y > target.y do
      local moved = world:move("down", retries, false)
      if not moved.ok then return moved end
    end
    while navigation:position().x < target.x do
      local moved = move(directions[1], false)
      if not moved.ok then return moved end
    end
    while navigation:position().x > target.x do
      local moved = move(directions[3], false)
      if not moved.ok then return moved end
    end
    while navigation:position().z < target.z do
      local moved = move(directions[2], false)
      if not moved.ok then return moved end
    end
    while navigation:position().z > target.z do
      local moved = move(directions[4], false)
      if not moved.ok then return moved end
    end
    return result.ok(true)
  end

  local function breadcrumbFailure(saved, breadcrumbs, failedDirection, failed)
    local current = navigation:position()
    local cause = failed and failed.error and failed.error.message or "unknown movement failure"
    local message = "ORE RETURN FAILED. Anchor: " .. saved.x .. "," .. saved.y .. "," .. saved.z ..
      ". Current: " .. current.x .. "," .. current.y .. "," .. current.z ..
      ". Breadcrumbs remaining: " .. #breadcrumbs .. ". Failed return step: " ..
      (failedDirection and failedDirection.name or "unknown") .. ". Cause: " .. cause
    if logger then logger:error("ore.breadcrumb_return_failed", { anchor = saved, current = current, breadcrumbs_remaining = #breadcrumbs, failed_step = failedDirection and failedDirection.name, cause = cause }) end
    if ui then ui:status("ORE", message, true) end
    return message
  end

  local function moveBreadcrumb(direction)
    local inspected = inspect(direction)
    if not inspected.ok then return inspected end
    if inspected.value.present then
      if fluid and fluid:isFluid(inspected.value.data) then return move(direction, true) end
      if inspected.value.data and inspected.value.data.name == "minecraft:torch" then return move(direction, false) end
      return result.fail("ORE.BREADCRUMB_BLOCKED", "Known return path is obstructed by " .. (inspected.value.data and inspected.value.data.name or "an unknown block"), { context = { direction = direction.name } })
    end
    return move(direction, false)
  end

  local function returnBreadcrumb(breadcrumbs, saved)
    local crumb = breadcrumbs[#breadcrumbs]
    if not crumb then return result.ok(false) end
    if not sameCoordinates(navigation:position(), crumb.to) then
      return result.fail("ORE.BREADCRUMB_MISMATCH", "Current position does not match the recorded breadcrumb", { context = { expected = crumb.to, current = navigation:position() } })
    end
    local returned = moveBreadcrumb(crumb.return_direction)
    if not returned.ok then return returned end
    if not sameCoordinates(navigation:position(), crumb.from) then
      return result.fail("ORE.BREADCRUMB_MISMATCH", "Breadcrumb return reached an unexpected position", { context = { expected = crumb.from, current = navigation:position() } })
    end
    table.remove(breadcrumbs)
    if onExcursion then onExcursion({ active = true, anchor = copy(saved), breadcrumbs = copyBreadcrumbs(breadcrumbs), position = copy(navigation:position()) }) end
    return result.ok(true)
  end

  local function restoreTunnel(saved, breadcrumbs)
    if ui then ui:status("ORE", "Returning to tunnel", false) end
    local breadcrumbFailureResult
    while breadcrumbs and #breadcrumbs > 0 do
      local returned = returnBreadcrumb(breadcrumbs, saved)
      if not returned.ok then
        breadcrumbFailureResult = returned
        breadcrumbFailure(saved, breadcrumbs, breadcrumbs[#breadcrumbs] and breadcrumbs[#breadcrumbs].return_direction, returned)
        break
      end
    end
    local returned = returnTo(saved)
    if not returned.ok then
      if returned.error and returned.error.code == "FUEL.OUT_OF_FUEL" then return returned end
      local reason = breadcrumbFailureResult and breadcrumbFailure(saved, breadcrumbs or {}, nil, returned) or returned.error.message
      if logger then logger:error("ore.return_failed", { position = navigation:position(), reason = reason }) end
      return result.fail("ORE.RETURN_FAILED", "Unable to return safely to the tunnel: " .. reason, { context = returned.error.context })
    end
    local faced = navigation:face(saved.heading)
    if not faced.ok then
      if logger then logger:error("ore.heading_restore_failed", { reason = faced.error.message }) end
      return result.fail("ORE.RETURN_FAILED", "Unable to restore tunnel heading: " .. faced.error.message, { context = faced.error.context })
    end
    if not samePosition(navigation:position(), saved) then
      return result.fail("ORE.RETURN_MISMATCH", "Returned position did not match the tunnel state")
    end
    if breadcrumbFailureResult and logger then logger:warn("ore.breadcrumb_fallback_succeeded", { position = saved }) end
    if onExcursion then onExcursion(nil) end
    if logger then logger:info("ore.returned", { position = saved }) end
    return result.ok(true)
  end

  function ore:discoverExposed()
    local anchor = copy(navigation:position())
    local discovered, targets = {}, {}
    local horizontal = {}

    local function addTarget(direction, inspected)
      if inspected.value.present and matches(inspected.value.data) then
        local position = {
          x = anchor.x + direction.x,
          y = anchor.y + direction.y,
          z = anchor.z + direction.z,
        }
        local targetKey = key(position)
        if not discovered[targetKey] then
          discovered[targetKey] = true
          table.insert(targets, {
            key = targetKey,
            position = position,
            direction = copyDirection(direction),
            data = inspected.value.data,
          })
        end
      end
    end

    local function restoreHeading(failure)
      local restored = navigation:face(anchor.heading)
      if not restored.ok then return restored end
      return failure
    end

    for offset = 0, 3 do
      local index = ((anchor.heading + offset) % 4) + 1
      local direction = directions[index]
      local faced = navigation:face(direction.heading)
      if not faced.ok then return restoreHeading(faced) end
      local inspected = adapter:inspect("forward")
      if not inspected.ok then return restoreHeading(inspected) end
      horizontal[index] = inspected
    end

    local restored = navigation:face(anchor.heading)
    if not restored.ok then return restored end

    for index = 1, 4 do
      addTarget(directions[index], horizontal[index])
    end

    for index = 5, 6 do
      local direction = directions[index]
      local inspected = inspect(direction)
      if not inspected.ok then return inspected end
      addTarget(direction, inspected)
    end

    if not samePosition(navigation:position(), anchor) then
      return result.fail("ORE.DISCOVERY_MISMATCH", "Discovery did not restore the original position and heading")
    end
    return result.ok({ anchor = anchor, targets = targets })
  end

  function ore:discoverTunnelBoundary(options)
    options = options or {}
    local anchor = copy(options.anchor or navigation:position())
    local width, height = options.width or 3, options.height or 3
    if width < 3 or height < 3 or width % 2 ~= 1 or height % 2 ~= 1 then return result.fail("ORE.INVALID_TUNNEL_PATTERN", "Tunnel boundary dimensions must be odd whole numbers of at least three") end
    local half, discovered, targets = (width - 1) / 2, {}, {}
    local function restore(failure)
      local restored = restoreTunnel(anchor)
      return restored.ok and failure or restored
    end
    local function add(origin, direction, inspected)
      if not inspected.value.present or not matches(inspected.value.data) then return end
      local position = { x = origin.x + direction.x, y = origin.y + direction.y, z = origin.z + direction.z }
      local targetKey = key(position)
      if discovered[targetKey] then return end
      discovered[targetKey] = true
      table.insert(targets, { key = targetKey, position = position, origin = copy(origin), direction = copyDirection(direction), data = inspected.value.data })
    end
    local function scan(y, z, direction)
      local positioned = returnTo({ x = anchor.x, y = anchor.y + y, z = anchor.z + z })
      if not positioned.ok then return positioned end
      local origin = copy(navigation:position())
      local inspected
      if direction.move then inspected = adapter:inspect(direction.move)
      else
        local faced = navigation:face(direction.heading)
        if not faced.ok then return faced end
        inspected = adapter:inspect("forward")
      end
      if not inspected.ok then return inspected end
      add(origin, direction, inspected)
      return result.ok(true)
    end
    local function scanRow(direction, y, first, last)
      for z = first, last do local scanned = scan(y, z, direction); if not scanned.ok then return scanned end end
      return result.ok(true)
    end
    for y = 0, height - 1 do
      local front = scanRow(directions[1], y, -half, half); if not front.ok then return restore(front) end
      local left = scan(y, -half, directions[4]); if not left.ok then return restore(left) end
      local right = scan(y, half, directions[2]); if not right.ok then return restore(right) end
    end
    local ceiling = scanRow(directions[5], height - 1, -half, half)
    if not ceiling.ok then return restore(ceiling) end
    local restored = restoreTunnel(anchor)
    if not restored.ok then return restored end
    return result.ok({ anchor = anchor, targets = targets })
  end

  function ore:discoverSliceBoundary(options)
    return self:discoverTunnelBoundary(options)
  end

  function ore:boundaryMovementEstimate(width, height)
    if type(width) ~= "number" or type(height) ~= "number" or width < 3 or height < 3 or width % 2 ~= 1 or height % 2 ~= 1 then
      return nil
    end
    local half = (width - 1) / 2
    return (8 * half * height) + (4 * half) + (2 * width) - 2
  end

  function ore:chase(target, options)
    options = options or {}
    local anchor = copy(options.anchor or navigation:position())
    local processed = options.processed or {}
    local sizeLimit = options.max_size or maxSize
    local stop = options.should_stop or shouldStop
    local collected, detectedName, limitReached, inventoryFull, abandoned = 0, nil, false, false, false
    local failure
    local breadcrumbs = copyBreadcrumbs(options.breadcrumbs)

    if type(target) ~= "table" or type(target.position) ~= "table" or type(target.direction) ~= "table" or type(target.data) ~= "table" then
      return result.fail("ORE.INVALID_TARGET", "Ore chase target is invalid")
    end

    local stack = {}

    local function checkpointExcursion()
      if onExcursion then onExcursion({ active = true, anchor = copy(anchor), breadcrumbs = copyBreadcrumbs(breadcrumbs), position = copy(navigation:position()) }) end
    end

    local function moveTracked(direction, clearPath)
      local from = copy(navigation:position())
      local moved = move(direction, clearPath)
      if not moved.ok then return moved end
      local to = copy(navigation:position())
      local inverse = inverseDirection(from, to)
      if not inverse then return result.fail("ORE.BREADCRUMB_INVALID", "Successful ore movement was not adjacent to its origin") end
      table.insert(breadcrumbs, { from = from, to = to, return_direction = inverse })
      checkpointExcursion()
      return moved
    end

    local function enter(position, direction, data)
      local positionKey = key(position)
      if processed[positionKey] then return result.ok(false) end
      if collected >= sizeLimit then
        limitReached = true
        return result.ok(false)
      end

      processed[positionKey] = true
      detectedName = detectedName or data.name
      if ui then
        ui:status("ORE", data.name .. " detected", false)
        ui:status("ORE", "Following vein", false)
      end
      if logger then logger:info("ore.detected", { ore_type = data.name, tunnel_position = anchor }) end
      if not direction.move then
        local faced = navigation:face(direction.heading)
        if not faced.ok then return faced end
      end
      local dug = adapter:dig(direction.move or "forward")
      if not dug.ok then return dug end
      local entered = moveTracked(direction, true)
      if not entered.ok then return entered end
      collected = collected + 1
      table.insert(stack, { position = copy(navigation:position()), next_direction = 1 })
      return result.ok(true)
    end

    if (stop and stop()) or (inventory and inventory:isFull()) then
      inventoryFull = true
    elseif not processed[key(target.position)] then
      local entered = enter(target.position, target.direction, target.data)
      if not entered.ok then
        if entered.error and entered.error.code and entered.error.code:sub(1, 5) == "FLUID" then
          if ui then ui:status("ORE", "Abandoning unsafe branch", false) end
          abandoned = true
        else
          failure = entered
        end
      end
    end

    while #stack > 0 and not failure and not limitReached and not abandoned do
      if (stop and stop()) or (inventory and inventory:isFull()) then
        inventoryFull = true
        break
      end
      local frame = stack[#stack]
      if frame.next_direction > #directions then
        table.remove(stack)
        if #stack > 0 then
          local returned = returnBreadcrumb(breadcrumbs, anchor)
          if not returned.ok then failure = returned end
        end
      else
        local direction = directions[frame.next_direction]
        frame.next_direction = frame.next_direction + 1
        local inspected = inspect(direction)
        if not inspected.ok then
          failure = inspected
        elseif inspected.value.present and matches(inspected.value.data) then
          local position = {
            x = frame.position.x + direction.x,
            y = frame.position.y + direction.y,
            z = frame.position.z + direction.z,
          }
          if not processed[key(position)] then
            local entered = enter(position, direction, inspected.value.data)
            if not entered.ok then
              if entered.error and entered.error.code and entered.error.code:sub(1, 5) == "FLUID" then
                if ui then ui:status("ORE", "Abandoning unsafe branch", false) end
                abandoned = true
              else
                failure = entered
              end
            end
          end
        end
      end
    end

    if limitReached and logger then logger:warn("ore.limit_reached", { limit = sizeLimit, collected = collected, tunnel_position = anchor }) end
    if inventoryFull then
      if logger then logger:warn("ore.inventory_full", { collected = collected, tunnel_position = anchor }) end
      if ui then ui:status("ORE", "Inventory full; returning to tunnel", false) end
    end
    if abandoned and logger then logger:warn("ore.branch_abandoned", { ore_type = detectedName, collected = collected, tunnel_position = anchor }) end
    if ui and collected > 0 then ui:status("ORE", "Collected " .. collected .. " blocks", false) end
    local restored = restoreTunnel(anchor, breadcrumbs)
    if not restored.ok then return restored end
    if failure then
      if logger then logger:error("ore.chase_failed", { ore_type = detectedName, collected = collected, reason = failure.error.message }) end
      return failure
    end
    if logger then logger:info("ore.completed", { ore_type = detectedName, collected = collected, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned }) end
    if ui and collected > 0 then ui:status("ORE", "Resuming", false) end
    return result.ok({ collected = collected, ore_type = detectedName, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned })
  end

  function ore:recoverExcursion(excursion)
    if type(excursion) ~= "table" or type(excursion.anchor) ~= "table" or type(excursion.breadcrumbs) ~= "table" then
      return result.fail("ORE.INVALID_EXCURSION", "Saved ore excursion is invalid")
    end
    local anchor = copy(excursion.anchor)
    local breadcrumbs = copyBreadcrumbs(excursion.breadcrumbs)
    local restored = restoreTunnel(anchor, breadcrumbs)
    if not restored.ok then return restored end
    return result.ok({ anchor = anchor })
  end

  function ore:mineExposed()
    local anchor = copy(navigation:position())
    if (shouldStop and shouldStop()) or (inventory and inventory:isFull()) then
      if logger then logger:warn("ore.inventory_full", { collected = 0, tunnel_position = anchor }) end
      if ui then ui:status("ORE", "Inventory full; returning to tunnel", false) end
      local restored = restoreTunnel(anchor)
      if not restored.ok then return restored end
      if logger then logger:info("ore.completed", { ore_type = nil, collected = 0, limit_reached = false, inventory_full = true, abandoned = false }) end
      return result.ok({ collected = 0, ore_type = nil, limit_reached = false, inventory_full = true, abandoned = false })
    end
    local discovered = ore:discoverExposed()
    if not discovered.ok then
      local restored = restoreTunnel(anchor)
      if not restored.ok then return restored end
      return discovered
    end

    local processed = {}
    local collected, detectedName, limitReached, inventoryFull, abandoned = 0, nil, false, false, false
    for _, target in ipairs(discovered.value.targets) do
      local chased = ore:chase(target, { anchor = anchor, processed = processed })
      if not chased.ok then return chased end
      collected = collected + chased.value.collected
      detectedName = detectedName or chased.value.ore_type
      limitReached = limitReached or chased.value.limit_reached
      inventoryFull = inventoryFull or chased.value.inventory_full
      abandoned = abandoned or chased.value.abandoned
      if limitReached or inventoryFull or abandoned then break end
    end
    if #discovered.value.targets == 0 then
      local restored = restoreTunnel(anchor)
      if not restored.ok then return restored end
      if logger then logger:info("ore.completed", { ore_type = nil, collected = 0, limit_reached = false, inventory_full = false, abandoned = false }) end
    end
    return result.ok({ collected = collected, ore_type = detectedName, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned })
  end

  function ore:mineSliceBoundary(options)
    options = options or {}
    local anchor = copy(options.anchor or navigation:position())
    if (shouldStop and shouldStop()) or (inventory and inventory:isFull()) then
      if logger then logger:warn("ore.inventory_full", { collected = 0, tunnel_position = anchor }) end
      if ui then ui:status("ORE", "Inventory full; returning to tunnel", false) end
      local restored = restoreTunnel(anchor)
      if not restored.ok then return restored end
      return result.ok({ collected = 0, ore_type = nil, limit_reached = false, inventory_full = true, abandoned = false })
    end

    local discovered = ore:discoverTunnelBoundary({ anchor = anchor, width = options.width, height = options.height, movement_retries = options.movement_retries })
    if not discovered.ok then return discovered end

    local processed = options.processed or {}
    local collected, detectedName, limitReached, inventoryFull, abandoned = 0, nil, false, false, false
    for _, target in ipairs(discovered.value.targets) do
      if not processed[target.key] then
        local positioned = returnTo(target.origin)
        if not positioned.ok then
          local restored = restoreTunnel(anchor)
          if not restored.ok then return restored end
          return positioned
        end
        local chased = ore:chase(target, { anchor = anchor, processed = processed, max_size = options.max_size, should_stop = options.should_stop })
        if not chased.ok then return chased end
        collected = collected + chased.value.collected
        detectedName = detectedName or chased.value.ore_type
        limitReached = limitReached or chased.value.limit_reached
        inventoryFull = inventoryFull or chased.value.inventory_full
        abandoned = abandoned or chased.value.abandoned
        if limitReached or inventoryFull or abandoned then break end
      end
    end
    return result.ok({ collected = collected, ore_type = detectedName, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned })
  end

  function ore:mineTunnelBoundary(options)
    return self:mineSliceBoundary(options)
  end

  return ore
end

return Ore

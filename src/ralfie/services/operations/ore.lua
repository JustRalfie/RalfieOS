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

  local function restoreTunnel(saved)
    if ui then ui:status("ORE", "Returning to tunnel", false) end
    local returned = returnTo(saved)
    if not returned.ok then
      if logger then logger:error("ore.return_failed", { position = navigation:position(), reason = returned.error.message }) end
      return result.fail("ORE.RETURN_FAILED", "Unable to return safely to the tunnel: " .. returned.error.message, { context = returned.error.context })
    end
    local faced = navigation:face(saved.heading)
    if not faced.ok then
      if logger then logger:error("ore.heading_restore_failed", { reason = faced.error.message }) end
      return result.fail("ORE.RETURN_FAILED", "Unable to restore tunnel heading: " .. faced.error.message, { context = faced.error.context })
    end
    if not samePosition(navigation:position(), saved) then
      return result.fail("ORE.RETURN_MISMATCH", "Returned position did not match the tunnel state")
    end
    if logger then logger:info("ore.returned", { position = saved }) end
    return result.ok(true)
  end

  function ore:discoverExposed()
    local anchor = copy(navigation:position())
    local discovered, targets = {}, {}

    for _, direction in ipairs(directions) do
      local inspected = inspect(direction)
      if not inspected.ok then return inspected end
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

    if not samePosition(navigation:position(), anchor) then
      return result.fail("ORE.DISCOVERY_MISMATCH", "Discovery did not restore the original position and heading")
    end
    return result.ok({ anchor = anchor, targets = targets })
  end

  function ore:mineExposed()
    local saved = copy(navigation:position())
    local visited, stack = {}, { { position = copy(saved), next_direction = 1 } }
    local collected, detectedName, limitReached, inventoryFull, abandoned = 0, nil, false, false, false
    local failure

    while #stack > 0 and not failure and not limitReached do
      if (shouldStop and shouldStop()) or (inventory and inventory:isFull()) then
        inventoryFull = true
        break
      end
      local frame = stack[#stack]
      if frame.next_direction > #directions then
        table.remove(stack)
        if #stack > 0 then
          local returned = returnTo(stack[#stack].position)
          if not returned.ok then failure = returned end
        end
      else
        local direction = directions[frame.next_direction]
        frame.next_direction = frame.next_direction + 1
        local inspected = inspect(direction)
        if not inspected.ok then
          failure = inspected
        elseif inspected.value.present and matches(inspected.value.data) then
          local target = {
            x = frame.position.x + direction.x,
            y = frame.position.y + direction.y,
            z = frame.position.z + direction.z,
          }
          local targetKey = key(target)
          if not visited[targetKey] then
            if collected >= maxSize then
              limitReached = true
            else
              visited[targetKey] = true
              detectedName = detectedName or inspected.value.data.name
              if ui then
                ui:status("ORE", inspected.value.data.name .. " detected", false)
                ui:status("ORE", "Following vein", false)
              end
              if logger then logger:info("ore.detected", { ore_type = inspected.value.data.name, tunnel_position = saved }) end
              if not direction.move then
                local faced = navigation:face(direction.heading)
                if not faced.ok then
                  failure = faced
                end
              end
              local dug = failure or adapter:dig(direction.move or "forward")
              if not dug.ok then
                failure = dug
              else
                local entered = move(direction, true)
                if not entered.ok then
                  if entered.error and entered.error.code and entered.error.code:sub(1, 5) == "FLUID" then
                    if ui then ui:status("ORE", "Abandoning unsafe branch", false) end
                    abandoned = true
                    break
                  end
                  failure = entered
                else
                  collected = collected + 1
                  table.insert(stack, { position = copy(navigation:position()), next_direction = 1 })
                end
              end
            end
          end
        end
      end
    end

    if limitReached and logger then logger:warn("ore.limit_reached", { limit = maxSize, collected = collected, tunnel_position = saved }) end
    if inventoryFull then
      if logger then logger:warn("ore.inventory_full", { collected = collected, tunnel_position = saved }) end
      if ui then ui:status("ORE", "Inventory full; returning to tunnel", false) end
    end
    if abandoned and logger then logger:warn("ore.branch_abandoned", { ore_type = detectedName, collected = collected, tunnel_position = saved }) end
    if ui and collected > 0 then ui:status("ORE", "Collected " .. collected .. " blocks", false) end
    local restored = restoreTunnel(saved)
    if not restored.ok then return restored end
    if failure then
      if logger then logger:error("ore.chase_failed", { ore_type = detectedName, collected = collected, reason = failure.error.message }) end
      return failure
    end
    if logger then logger:info("ore.completed", { ore_type = detectedName, collected = collected, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned }) end
    if ui and collected > 0 then ui:status("ORE", "Resuming", false) end
    return result.ok({ collected = collected, ore_type = detectedName, limit_reached = limitReached, inventory_full = inventoryFull, abandoned = abandoned })
  end

  return ore
end

return Ore

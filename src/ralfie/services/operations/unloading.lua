local Unloading = {}

local directions = {
  east = { heading = 0 }, south = { heading = 1 }, west = { heading = 2 }, north = { heading = 3 },
}

local function copy(position)
  return { x = position.x, y = position.y, z = position.z, heading = position.heading }
end

local function same(left, right)
  return left.x == right.x and left.y == right.y and left.z == right.z and left.heading == right.heading
end

function Unloading.new(options)
  local navigation = assert(options.navigation, "unloading requires navigation")
  local world = assert(options.world, "unloading requires world")
  local storage = assert(options.storage, "unloading requires storage")
  local inventory = assert(options.inventory, "unloading requires inventory")
  local fuel = assert(options.fuel, "unloading requires fuel service")
  local result = assert(options.result, "unloading requires result")
  local ui, logger = options.ui, options.logger
  local retries = options.movement_retries or 3
  local safetyMargin = options.fuel_safety_margin or 20
  local reservedSlots = assert(options.reserved_slots, "unloading requires reserved slots")
  local freeMargin = options.free_slot_margin or 1
  local unload = { trips = 0 }

  assert(type(freeMargin) == "number" and freeMargin >= 0 and freeMargin % 1 == 0, "unloading free slot margin must be a whole number")

  local function moveHorizontal(direction)
    local faced = navigation:face(direction.heading)
    if not faced.ok then return faced end
    return world:move("forward", retries, false)
  end

  local function moveTo(target, heading)
    while navigation:position().y < target.y do
      local moved = world:move("up", retries, false)
      if not moved.ok then return moved end
    end
    while navigation:position().y > target.y do
      local moved = world:move("down", retries, false)
      if not moved.ok then return moved end
    end
    while navigation:position().x < target.x do
      local moved = moveHorizontal(directions.east)
      if not moved.ok then return moved end
    end
    while navigation:position().x > target.x do
      local moved = moveHorizontal(directions.west)
      if not moved.ok then return moved end
    end
    while navigation:position().z < target.z do
      local moved = moveHorizontal(directions.south)
      if not moved.ok then return moved end
    end
    while navigation:position().z > target.z do
      local moved = moveHorizontal(directions.north)
      if not moved.ok then return moved end
    end
    local faced = navigation:face(heading)
    if not faced.ok then return faced end
    if not same(navigation:position(), { x = target.x, y = target.y, z = target.z, heading = heading }) then
      return result.fail("UNLOAD.POSITION_MISMATCH", "Navigation did not reach the saved position")
    end
    return result.ok(true)
  end

  function unload:isNearlyFull()
    return inventory:freeSlots(reservedSlots) <= freeMargin
  end

  function unload:run(state)
    local saved = { position = copy(assert(state.position, "unload state requires position")), slice = state.slice, mode = state.mode }
    if ui then ui:status("INVENTORY", "Nearly full", false) end
    if logger then logger:warn("unload.triggered", { position = saved.position, heading = saved.position.heading, slice = saved.slice, mode = saved.mode }) end
    local distance = math.abs(saved.position.x) + math.abs(saved.position.y) + math.abs(saved.position.z)
    local fuelReady = fuel:ensure((distance * 2) + safetyMargin, reservedSlots[1], reservedSlots[2])
    if not fuelReady.ok then
      if logger then logger:error("unload.fuel_insufficient", { position = saved.position, reason = fuelReady.error.message }) end
      return fuelReady
    end
    if ui then ui:status("RETURN", "Returning home to unload", false) end
    local home = moveTo({ x = 0, y = 0, z = 0 }, 0)
    if not home.ok then
      if logger then logger:error("unload.home_return_failed", { position = navigation:position(), reason = home.error.message }) end
      return result.fail("UNLOAD.HOME_RETURN_FAILED", "Unable to return home to unload: " .. home.error.message, { context = home.error.context })
    end
    if ui then ui:status("DUMP", "Depositing items", false) end
    local dumped = storage:dumpBehind(reservedSlots)
    if not dumped.ok then
      if logger then logger:error("unload.dump_failed", { reason = dumped.error.message }) end
      return result.fail("UNLOAD.DUMP_FAILED", "Unable to deposit items: " .. dumped.error.message, { context = dumped.error.context })
    end
    self.trips = self.trips + 1
    if ui then ui:status("DUMP", "Complete", false) end
    if logger then logger:info("unload.completed", { trip = self.trips, dumped = dumped.value.dumped, slice = saved.slice }) end
    if self:isNearlyFull() then
      if logger then logger:error("unload.no_space", { trip = self.trips, position = navigation:position() }) end
      return result.fail("UNLOAD.NO_SPACE", "Inventory remains nearly full after depositing items; cannot resume safely")
    end
    if ui then ui:status("RESUME", "Returning to saved position", false) end
    local resumed = moveTo(saved.position, saved.position.heading)
    if not resumed.ok then
      if logger then logger:error("unload.resume_failed", { position = navigation:position(), reason = resumed.error.message }) end
      return result.fail("UNLOAD.RESUME_FAILED", "Unable to return to saved mining position: " .. resumed.error.message, { context = resumed.error.context })
    end
    if ui then ui:status("RESUME", "Position restored", false) end
    if logger then logger:info("unload.resumed", { trip = self.trips, position = saved.position, slice = saved.slice, mode = saved.mode }) end
    return result.ok({ trip = self.trips, state = saved })
  end

  return unload
end

return Unloading

local Fuel = {}

function Fuel.new(options)
  local adapter = assert(options.adapter, "fuel requires turtle adapter")
  local inventory = assert(options.inventory, "fuel requires inventory")
  local result = assert(options.result, "fuel requires result")
  local logger = options.logger
  local fuel = {}

  function fuel:level()
    return adapter:fuelLevel()
  end

  local function protectedSlots(options)
    local protected = {}
    for _, slot in ipairs((options and options.protected_slots) or {}) do protected[slot] = true end
    return protected
  end

  local function orderedSlots(options)
    local protected = protectedSlots(options)
    local ordered, fuelSlot = {}, options and options.fuel_slot
    if fuelSlot and not protected[fuelSlot] then table.insert(ordered, fuelSlot) end
    for slot = 1, 16 do
      if slot ~= fuelSlot and not protected[slot] then table.insert(ordered, slot) end
    end
    return ordered
  end

  function fuel:inventoryFuel(options)
    local count, items, label = 0, {}, nil
    for _, slot in ipairs(orderedSlots(options)) do
      if inventory:count(slot) > 0 then
        local valid = inventory:isFuel(slot)
        if not valid.ok then return valid end
        if valid.value then
          count = count + inventory:count(slot)
          local detail = adapter:itemDetail(slot)
          if detail and detail.name then
            items[detail.name] = (items[detail.name] or 0) + inventory:count(slot)
            label = label or detail.name
          end
        end
      end
    end
    return result.ok({ count = count, items = items, label = label })
  end

  local function refill(required, options, failureCode, failureMessage)
    if adapter:fuelLimit() == "unlimited" then return result.ok("unlimited") end
    if adapter:fuelLevel() >= required then return result.ok(adapter:fuelLevel()) end
    for _, slot in ipairs(orderedSlots(options)) do
      if inventory:count(slot) > 0 then
        local refuelled = inventory:withSlot(slot, function()
          if not adapter:canRefuel() then return result.ok(false) end
          return adapter:refuel(1)
        end)
        if not refuelled.ok then return refuelled end
        if refuelled.value and logger then logger:info("fuel.consumed", { slot = slot, level = adapter:fuelLevel() }) end
        while adapter:fuelLevel() < required and inventory:count(slot) > 0 do
          local nextFuel = inventory:withSlot(slot, function()
            if not adapter:canRefuel() then return result.ok(false) end
            return adapter:refuel(1)
          end)
          if not nextFuel.ok or not nextFuel.value then break end
          if logger then logger:info("fuel.consumed", { slot = slot, level = adapter:fuelLevel() }) end
        end
        if adapter:fuelLevel() >= required then return result.ok(adapter:fuelLevel()) end
      end
    end
    local available = fuel:inventoryFuel(options)
    return result.fail(failureCode, failureMessage, {
      context = { required = required, available = adapter:fuelLevel(), inventory_fuel = available.ok and available.value.count or nil },
    })
  end

  function fuel:ensure(required, torchSlot, fuelSlot, fillerSlot)
    return refill(required, { fuel_slot = fuelSlot, protected_slots = { torchSlot, fillerSlot } }, "FUEL.INSUFFICIENT", "Not enough fuel for the planned tunnel and safe return")
  end

  function fuel:ensureRuntime(options)
    options = options or {}
    local minimum = options.minimum or 1
    local reserve = options.reserve or minimum
    if adapter:fuelLimit() == "unlimited" then return result.ok("unlimited") end
    if adapter:fuelLevel() >= minimum then
      if adapter:fuelLevel() >= reserve then return result.ok(adapter:fuelLevel()) end
      local toppedUp = refill(reserve, options, "FUEL.OUT_OF_FUEL", "No usable fuel is available for movement")
      if toppedUp.ok then return toppedUp end
      return result.ok(adapter:fuelLevel())
    end
    return refill(minimum, options, "FUEL.OUT_OF_FUEL", "No usable fuel is available for movement")
  end

  return fuel
end

return Fuel

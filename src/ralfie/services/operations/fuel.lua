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

  function fuel:ensure(required, torchSlot, fuelSlot)
    if adapter:fuelLimit() == "unlimited" then return result.ok("unlimited") end
    if adapter:fuelLevel() >= required then return result.ok(adapter:fuelLevel()) end
    local ordered = { fuelSlot }
    for slot = 1, 16 do if slot ~= fuelSlot and slot ~= torchSlot then table.insert(ordered, slot) end end
    for _, slot in ipairs(ordered) do
      if slot and inventory:count(slot) > 0 then
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
    return result.fail("FUEL.INSUFFICIENT", "Not enough fuel for the planned tunnel and safe return", {
      context = { required = required, available = adapter:fuelLevel() },
    })
  end

  return fuel
end

return Fuel

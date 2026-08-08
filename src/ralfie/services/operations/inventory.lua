local Inventory = {}

function Inventory.new(options)
  local adapter = assert(options.adapter, "inventory requires turtle adapter")
  local result = assert(options.result, "inventory requires result")
  local inventory = {}

  function inventory:count(slot)
    return adapter:itemCount(slot)
  end

  function inventory:reserve(slot)
    if type(slot) ~= "number" or slot < 1 or slot > 16 or slot % 1 ~= 0 then
      return result.fail("INVENTORY.INVALID_SLOT", "Reserved slot must be between 1 and 16")
    end
    return result.ok(slot)
  end

  function inventory:withSlot(slot, action)
    local previous = adapter:selectedSlot()
    local selected = adapter:select(slot)
    if not selected.ok then return selected end
    local outcome = action()
    adapter:select(previous)
    return outcome
  end

  function inventory:isFuel(slot)
    if self:count(slot) == 0 then return result.ok(false) end
    return self:withSlot(slot, function() return result.ok(adapter:canRefuel()) end)
  end

  function inventory:isFull()
    for slot = 1, 16 do
      local space = adapter:itemSpace(slot)
      if space == nil or space > 0 then return false end
    end
    return true
  end

  function inventory:freeSlots(reservedSlots)
    local reserved, free = {}, 0
    for _, slot in ipairs(reservedSlots or {}) do reserved[slot] = true end
    for slot = 1, 16 do
      if not reserved[slot] and self:count(slot) == 0 then free = free + 1 end
    end
    return free
  end

  return inventory
end

return Inventory

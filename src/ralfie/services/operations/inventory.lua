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

  return inventory
end

return Inventory

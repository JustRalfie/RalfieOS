local Storage = {}

function Storage.new(options)
  local adapter = assert(options.adapter, "storage requires turtle adapter")
  local inventory = assert(options.inventory, "storage requires inventory")
  local navigation = assert(options.navigation, "storage requires navigation")
  local result = assert(options.result, "storage requires result")
  local logger = options.logger
  local storage = {}

  function storage:dumpBehind(reservedSlots)
    local reserved = {}
    for _, slot in ipairs(reservedSlots) do reserved[slot] = true end
    local originalHeading = navigation:position().heading
    local faced = navigation:face((originalHeading + 2) % 4)
    if not faced.ok then return faced end
    local failedDrop, dumped = nil, 0
    for slot = 1, 16 do
      if not reserved[slot] and inventory:count(slot) > 0 then
        local fuel = inventory:isFuel(slot)
        if not fuel.ok then
          if logger then logger:warn("storage.fuel_probe_failed", { slot = slot, reason = fuel.error.message }) end
        elseif not fuel.value then
          local count = inventory:count(slot)
          local dropped = inventory:withSlot(slot, function() return adapter:drop("forward") end)
          if not dropped.ok then
            failedDrop = dropped
            if logger then logger:warn("storage.drop_failed", { slot = slot, reason = dropped.error.message }) end
          else
            dumped = dumped + count
          end
        end
      end
    end
    local restored = navigation:face(originalHeading)
    if not restored.ok then return restored end
    if failedDrop then return failedDrop end
    return result.ok({ dumped = dumped })
  end

  return storage
end

return Storage

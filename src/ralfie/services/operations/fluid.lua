local Fluid = {}

local defaults = {
  "minecraft:cobblestone", "minecraft:cobbled_deepslate", "minecraft:stone", "minecraft:dirt", "minecraft:netherrack",
}

function Fluid.new(options)
  local adapter = assert(options.adapter, "fluid safety requires turtle adapter")
  local inventory = assert(options.inventory, "fluid safety requires inventory")
  local result = assert(options.result, "fluid safety requires result")
  local logger, ui = options.logger, options.ui
  local fillerSlot = options.filler_slot or 14
  local desiredReserve = options.desired_reserve or 64
  local allowed = options.allowed_fillers or defaults
  local fluids = options.fluids or { "minecraft:lava", "minecraft:water" }
  local fluid = {}

  local function contains(items, value)
    for _, item in ipairs(items) do if item == value then return true end end
    return false
  end
  local function fluidType(data)
    if type(data) ~= "table" or not contains(fluids, data.name) then return nil end
    return data.name == "minecraft:lava" and "lava" or "water"
  end
  local function fillerName(slot)
    local detail = adapter:itemDetail(slot)
    return detail and detail.name or nil
  end

  function fluid:isFluid(data) return fluidType(data) ~= nil end

  function fluid:replenish()
    local current = fillerName(fillerSlot)
    local count = inventory:count(fillerSlot)
    if count > 0 and not contains(allowed, current) then return result.ok(false) end
    if count >= desiredReserve then return result.ok(false) end
    if ui then ui:status("FLUID", "Filler low", false) end
    local source
    for _, preferred in ipairs(allowed) do
      if current == nil or current == preferred then
        for slot = 1, 16 do
          if slot ~= fillerSlot and fillerName(slot) == preferred and inventory:count(slot) > 0 then source = slot; break end
        end
      end
      if source then break end
    end
    if not source then return result.ok(false) end
    local moved = inventory:withSlot(source, function() return adapter:transferTo(fillerSlot, desiredReserve - count) end)
    if moved.ok and logger then logger:info("fluid.filler_replenished", { filler = fillerName(fillerSlot), slot = fillerSlot }) end
    return moved
  end

  function fluid:secure(direction, data)
    local kind = fluidType(data)
    if not kind then return result.ok(false) end
    if ui then ui:status("FLUID", kind == "lava" and "Lava detected" or "Water blocking path", false) end
    if ui then ui:status("FLUID", kind == "lava" and "Securing path" or "Sealing water", false) end
    local refilled = self:replenish()
    if not refilled.ok then return refilled end
    local name = fillerName(fillerSlot)
    if not name or not contains(allowed, name) or inventory:count(fillerSlot) == 0 then
      if ui then ui:status("FLUID", "No filler blocks available", true) end
      if logger then logger:error("fluid.no_filler", { fluid = data.name }) end
      return result.fail("FLUID.NO_FILLER", "No valid filler blocks are available to secure " .. data.name)
    end
    local placed = inventory:withSlot(fillerSlot, function() return adapter:place(direction) end)
    if not placed.ok then
      if ui then ui:status("FLUID", "Unable to secure " .. kind, true) end
      if logger then logger:error("fluid.seal_failed", { fluid = data.name, reason = placed.error.message }) end
      return result.fail("FLUID.UNSAFE", "Unable to secure " .. kind .. ": " .. placed.error.message, { context = placed.error.context })
    end
    local verified = adapter:inspect(direction)
    if not verified.ok then return verified end
    if verified.value.present and fluidType(verified.value.data) then
      if ui then ui:status("FLUID", "Unable to secure " .. kind, true) end
      return result.fail("FLUID.UNSAFE", "Fluid remained after sealing attempt")
    end
    if ui then ui:status("FLUID", "Path secured", false) end
    if logger then logger:info("fluid.sealed", { fluid = data.name, filler = name }) end
    return result.ok(true)
  end

  return fluid
end

return Fluid

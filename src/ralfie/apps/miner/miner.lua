local Miner = {}

local function load(context, name)
  local module = context.module_loader:load(name)
  if not module.ok then return nil, module end
  return module.value
end

function Miner.start(context, options)
  options = options or {}
  local resultModule, failed = load(context, "ralfie.core.result")
  if not resultModule then return failed end
  local TurtleAdapter; TurtleAdapter, failed = load(context, "ralfie.adapters.turtle")
  if not TurtleAdapter then return failed end
  local Navigation; Navigation, failed = load(context, "ralfie.services.operations.navigation")
  if not Navigation then return failed end
  local World; World, failed = load(context, "ralfie.services.operations.world")
  if not World then return failed end
  local Inventory; Inventory, failed = load(context, "ralfie.services.operations.inventory")
  if not Inventory then return failed end
  local Fuel; Fuel, failed = load(context, "ralfie.services.operations.fuel")
  if not Fuel then return failed end
  local Storage; Storage, failed = load(context, "ralfie.services.operations.storage")
  if not Storage then return failed end
  local Ore; Ore, failed = load(context, "ralfie.services.operations.ore")
  if not Ore then return failed end
  local Unloading; Unloading, failed = load(context, "ralfie.services.operations.unloading")
  if not Unloading then return failed end
  local Fluid; Fluid, failed = load(context, "ralfie.services.operations.fluid")
  if not Fluid then return failed end
  local Dashboard; Dashboard, failed = load(context, "ralfie.interfaces.terminal.miner_dashboard")
  if not Dashboard then return failed end
  local Jobs; Jobs, failed = load(context, "ralfie.services.platform.jobs")
  if not Jobs then return failed end

  local distance = options.distance
  if distance == nil then distance = tonumber(context.ui:prompt("Tunnel distance:")) end
  if type(distance) ~= "number" or distance < 1 or distance % 1 ~= 0 then
    return resultModule.fail("MINER.INVALID_DISTANCE", "Tunnel distance must be a positive whole number")
  end

  local config = context.configuration
  local torchSlot = options.torch_slot or config:get("miner.torch_slot", 16)
  local fuelSlot = options.fuel_slot or config:get("miner.fuel_slot", 15)
  local fillerSlot = options.filler_slot or config:get("miner.filler_slot", 14)
  local torchInterval = options.torch_interval or config:get("miner.torch_interval", 10)
  local safetyMargin = options.safety_margin or config:get("miner.safety_margin", 20)
  local movementRetries = options.movement_retries or config:get("miner.movement_retries", 3)
  local maxVeinSize = options.max_vein_size or config:get("miner.max_vein_size", 64)
  local additionalOreIds = options.additional_ore_ids or config:get("miner.additional_ore_ids", {})
  local excludedOreIds = options.excluded_ore_ids or config:get("miner.excluded_ore_ids", {})
  local inventoryFreeSlotMargin = options.inventory_free_slot_margin or config:get("miner.inventory_free_slot_margin", 1)
  if torchSlot == fuelSlot or torchSlot == fillerSlot or fuelSlot == fillerSlot or torchInterval < 1 then
    return resultModule.fail("MINER.INVALID_CONFIGURATION", "Filler, torch, and fuel slots must differ and torch interval must be positive")
  end

  local job
  local jobState = options.recovery
  if context.filesystem and context.fsx and context.serialization then
    job = Jobs.new({ filesystem = context.filesystem, fsx = context.fsx, serialization = context.serialization, result = resultModule, clock = context.clock })
    if not jobState then jobState = { job_type = "tunnel_miner", id = tostring((context.clock or os.time)()), distance = distance, slice = 1, position = { x = 0, y = 0, z = 0, heading = 0 }, operation = "mining", configuration = { torch_slot = torchSlot, fuel_slot = fuelSlot, filler_slot = fillerSlot } } end
  end
  local function checkpoint(position)
    if not job then return end
    jobState.position = position
    job:save(jobState)
  end
  local adapter = TurtleAdapter.new({ turtle = assert(context.turtle, "miner requires turtle hardware"), result = resultModule })
  local navigation = Navigation.new({ adapter = adapter, result = resultModule, on_change = checkpoint })
  if options.recovery then
    local restoredState = navigation:restore(options.recovery.position)
    if not restoredState.ok then return restoredState end
    context.ui:status("RECOVERY", "Restored slice " .. options.recovery.slice .. "/" .. distance, false)
  else
    checkpoint(navigation:position())
  end
  local inventory = Inventory.new({ adapter = adapter, result = resultModule })
  local torchReservation = inventory:reserve(torchSlot)
  local fuelReservation = inventory:reserve(fuelSlot)
  local fillerReservation = inventory:reserve(fillerSlot)
  if not torchReservation.ok then return torchReservation end
  if not fuelReservation.ok then return fuelReservation end
  if not fillerReservation.ok then return fillerReservation end
  local view = { distance = distance, slice = 0, capacity = 13, status = "MINING", ores = 0, veins = 0, unloads = 0 }
  local terminal = context.ui.terminal or { getSize = function() return 51, 19 end, isColor = function() return false end, setCursorPos = function() end, write = function() end, clear = function() end }
  local dashboard = Dashboard.new({ terminal = terminal, colors = context.ui.colors })
  local minerUi = {
    status = function(_, label, message, isError)
      local map = { MINE = "MINING", ORE = "CHASING ORE", FLUID = "SECURING FLUID", RETURN = "RETURNING HOME", DUMP = "UNLOADING", RESUME = "RESUMING", DONE = "COMPLETE" }
      view.status = isError and "ERROR" or (map[label] or view.status)
      if label == "ORE" and message and message:find(" detected", 1, true) then view.ore = message:gsub(" detected", "") end
      view.fuel, view.torches, view.filler = adapter:fuelLevel(), inventory:count(torchSlot), inventory:count(fillerSlot)
      view.loot = 13 - inventory:freeSlots({ fillerSlot, torchSlot, fuelSlot })
      dashboard:render(view)
      if not context.ui.terminal then context.ui:status(label, message, isError) end
    end,
    heading = function() end, line = function(_, text) context.ui:line(text) end,
    prompt = function(_, label, reader) return context.ui:prompt(label, reader) end,
    clear = function() dashboard:reset() end,
  }
  local fluid = Fluid.new({
    adapter = adapter, inventory = inventory, result = resultModule, logger = context.logger, ui = minerUi, filler_slot = fillerSlot,
    allowed_fillers = options.allowed_fillers or config:get("miner.allowed_fillers", nil), desired_reserve = options.filler_reserve or config:get("miner.filler_reserve", 64),
  })
  local world = World.new({ adapter = adapter, navigation = navigation, result = resultModule, logger = context.logger, pause = options.pause, fluid = fluid })
  local fuel = Fuel.new({ adapter = adapter, inventory = inventory, result = resultModule, logger = context.logger })
  local storage = Storage.new({ adapter = adapter, inventory = inventory, navigation = navigation, result = resultModule, logger = context.logger })
  local unloader = Unloading.new({
    navigation = navigation, world = world, storage = storage, inventory = inventory, fuel = fuel, result = resultModule,
    ui = minerUi, logger = context.logger, movement_retries = movementRetries, fuel_safety_margin = safetyMargin,
    reserved_slots = { fillerSlot, torchSlot, fuelSlot }, torch_slot = torchSlot, fuel_slot = fuelSlot, free_slot_margin = inventoryFreeSlotMargin,
    before_dump = function() return fluid:replenish() end,
  })
  local ore = Ore.new({
    adapter = adapter, navigation = navigation, world = world, inventory = inventory, result = resultModule, logger = context.logger, ui = minerUi,
    max_size = maxVeinSize, additional_ids = additionalOreIds, excluded_ids = excludedOreIds, matcher = options.ore_matcher, movement_retries = movementRetries,
    should_stop = function() return unloader:isNearlyFull() end,
  })

  local torchCount = inventory:count(torchSlot)
  local torchesNeeded = math.floor(distance / torchInterval)
  if torchCount < torchesNeeded then
    return resultModule.fail("MINER.INSUFFICIENT_TORCHES", "Reserved torch slot does not contain enough torches", {
      context = { required = torchesNeeded, available = torchCount },
    })
  end
  local fuelRequired = (distance * 12) + safetyMargin
  context.ui:status("CHECK", "Fuel required: " .. fuelRequired, false)
  local fuelReady = fuel:ensure(fuelRequired, torchSlot, fuelSlot)
  if not fuelReady.ok then return fuelReady end
  local refilled = fluid:replenish()
  if not refilled.ok then return refilled end

  local function faceAndMove(heading)
    local faced = navigation:face(heading)
    if not faced.ok then return faced end
    return world:move("forward", movementRetries)
  end

  local function unloadIfNeeded(slice, mode)
    if not unloader:isNearlyFull() then return resultModule.ok(false) end
    local unloaded = unloader:run({ position = navigation:position(), slice = slice, mode = mode })
    if not unloaded.ok then return unloaded end
    minerUi:status("MINE", "Continuing", false)
    return resultModule.ok(true)
  end

  local function excavateSide(heading, slice)
    local entered = faceAndMove(heading)
    if not entered.ok then return entered end
    local column = world:clearColumn()
    if not column.ok then return column end
    local chased = ore:mineExposed()
    if not chased.ok then return chased end
    local unloaded = unloadIfNeeded(slice, chased.value.inventory_full and "ore" or "tunnel")
    if not unloaded.ok then return unloaded end
    return faceAndMove((heading + 2) % 4)
  end

  local function placeTorch()
    local originalHeading = navigation:position().heading
    local faced = navigation:face((originalHeading + 2) % 4)
    if not faced.ok then return faced end
    local placed = inventory:withSlot(torchSlot, function() return adapter:place("forward") end)
    local restored = navigation:face(originalHeading)
    if not restored.ok then return restored end
    if not placed.ok then
      context.logger:warn("miner.torch_failed", { position = navigation:position(), reason = placed.error.message })
      minerUi:status("WARN", "Torch could not be placed; continuing.", false)
      return resultModule.ok(false)
    end
    context.logger:info("miner.torch_placed", { position = navigation:position() })
    return placed
  end

  context.logger:info("miner.started", { distance = distance, torch_interval = torchInterval, fuel_required = fuelRequired })
  dashboard:reset(); minerUi:status("MINE", "Starting", false)
  for step = (jobState and jobState.slice or 1), distance do
    local beforeSlice = unloadIfNeeded(step, "tunnel")
    if not beforeSlice.ok then return beforeSlice end
    view.slice = step - 1; minerUi:status("MINE", "Slice " .. step .. "/" .. distance, false)
    local advanced = world:move("forward", movementRetries)
    if not advanced.ok then return advanced end
    local center = world:clearColumn()
    if not center.ok then return center end
    local chased = ore:mineExposed()
    if not chased.ok then return chased end
    local unloaded = unloadIfNeeded(step, chased.value.inventory_full and "ore" or "tunnel")
    if not unloaded.ok then return unloaded end
    local left = excavateSide(3, step)
    if not left.ok then return left end
    local right = excavateSide(1, step)
    if not right.ok then return right end
    local original = navigation:face(0)
    if not original.ok then return original end
    if step % torchInterval == 0 then
      local torch = placeTorch()
      if not torch.ok then return torch end
    end
    if job then jobState.slice = step + 1; jobState.operation = "mining"; checkpoint(navigation:position()) end
  end

  view.slice = distance; minerUi:status("RETURN", "Returning to start", false)
  local backward = navigation:face(2)
  if not backward.ok then return backward end
  for _ = 1, distance do
    local moved = world:move("forward", movementRetries)
    if not moved.ok then return moved end
  end
  local restored = navigation:face(0)
  if not restored.ok then return restored end
  local fillerReady = fluid:replenish()
  if not fillerReady.ok then return fillerReady end
  local dumped = storage:dumpBehind({ fillerSlot, torchSlot, fuelSlot })
  if not dumped.ok then return dumped end
  if job then jobState.operation = "completing"; checkpoint(navigation:position()) end
  local position = navigation:position()
  context.logger:info("miner.completed", { position = position, distance = distance })
  minerUi:status("DONE", "Tunnel complete; items deposited behind start.", false)
  if job then job:clear(true) end
  return resultModule.ok({ position = position, distance = distance })
end

return Miner

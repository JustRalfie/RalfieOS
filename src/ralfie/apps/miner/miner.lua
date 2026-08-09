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
  local MiningStatus; MiningStatus, failed = load(context, "ralfie.services.platform.mining_status")
  if not MiningStatus then return failed end
  local MiningProtocol; MiningProtocol, failed = load(context, "ralfie.services.platform.mining_protocol")
  if not MiningProtocol then return failed end
  local MiningNetwork; MiningNetwork, failed = load(context, "ralfie.services.platform.mining_network")
  if not MiningNetwork then return failed end

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
    if not jobState then jobState = { job_type = "tunnel_miner", id = tostring((context.clock or os.time)()), distance = distance, slice = 1, position = { x = 0, y = 0, z = 0, heading = 0 }, operation = "mining", placed_torches = {}, configuration = { torch_slot = torchSlot, fuel_slot = fuelSlot, filler_slot = fillerSlot } } end
  end
  local placedTorches = (jobState and jobState.placed_torches) or {}
  if jobState then jobState.placed_torches = placedTorches end
  local network
  local function checkpoint(position)
    if job then
      jobState.position = position
      job:save(jobState)
    end
    if network then pcall(network.tick, network) end
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
  local commandHistory, commandOrder, pendingReturn, pendingUnload, pendingPause, paused, returnCommands, unloadCommands, pauseCommands = {}, {}, nil, false, false, false, {}, {}, {}
  local finalizeCommand, completeCommands
  local function remember(commandId, record)
    commandHistory[commandId] = record; table.insert(commandOrder, commandId)
    if #commandOrder > 20 then commandHistory[table.remove(commandOrder, 1)] = nil end
  end
  local function commandAck(payload, status, reason)
    return { command_id = payload.command_id, command = payload.command, target_id = payload.target_id, status = status, reason = reason }
  end
  local function handleCommand(sender, payload)
    local previous = commandHistory[payload.command_id]
    if previous then return previous.ack, previous.result end
    local ack
    if payload.target_id ~= context.os.getComputerID() then
      ack = commandAck(payload, "REJECTED", "command is for a different turtle")
    elseif payload.command == "UNLOAD" and (pendingReturn or view.status == "RETURNING HOME" or paused) then
      ack = commandAck(payload, "BUSY", "return home is pending or active")
    elseif payload.command == "PAUSE" and (pendingReturn or view.status == "RETURNING HOME") then
      ack = commandAck(payload, "BUSY", "return home is pending or active")
    elseif payload.command == "PAUSE" and paused then
      ack = commandAck(payload, "REJECTED", "already paused")
    elseif payload.command == "RESUME" and not paused then
      ack = commandAck(payload, "REJECTED", "not paused")
    elseif payload.command ~= "RETURN_HOME" and payload.command ~= "UNLOAD" and payload.command ~= "PAUSE" and payload.command ~= "RESUME" then
      ack = commandAck(payload, "INVALID", "unknown command")
    elseif view.status == "COMPLETE" or view.status == "ERROR" then
      ack = commandAck(payload, "BUSY", "miner is not running")
    else
      ack = commandAck(payload, "ACCEPTED")
      if payload.command == "RETURN_HOME" then
        for _, command in ipairs(unloadCommands) do finalizeCommand(command, "CANCELLED", "return home takes precedence") end
        pendingUnload = false
        pendingPause = false
        completeCommands(pauseCommands, "CANCELLED", "return home takes precedence")
        if view.status ~= "RETURNING HOME" then pendingReturn = payload.command_id end
        table.insert(returnCommands, { command_id = payload.command_id, command = payload.command, recipient = sender, ack = ack })
      else
        if payload.command == "UNLOAD" then
          if view.status ~= "UNLOADING" then pendingUnload = true end
          table.insert(unloadCommands, { command_id = payload.command_id, command = payload.command, recipient = sender, ack = ack })
        elseif payload.command == "PAUSE" then
          pendingPause = true
          table.insert(pauseCommands, { command_id = payload.command_id, command = payload.command, recipient = sender, ack = ack })
        else
          paused = false; pendingPause = false; view.status = "MINING"
          local result = { command_id = payload.command_id, command = "RESUME", target_id = payload.target_id, status = "SUCCESS" }
          ack = commandAck(payload, "ACCEPTED")
          local record = { ack = ack, result = result }; remember(payload.command_id, record)
          return ack, result
        end
      end
    end
    local record = { ack = ack }
    remember(payload.command_id, record)
    if ack.status == "ACCEPTED" then
      local commands = payload.command == "RETURN_HOME" and returnCommands or (payload.command == "UNLOAD" and unloadCommands or pauseCommands)
      commands[#commands].record = record
    end
    return ack
  end
  finalizeCommand = function(command, status, reason)
    if command.record.result then return false end
    command.record.result = { command_id = command.command_id, command = command.command, target_id = context.os.getComputerID(), status = status, reason = reason }
    network:send(command.recipient, MiningProtocol.types.COMMAND_RESULT, command.record.result)
    return true
  end
  completeCommands = function(commands, status, reason)
    for _, command in ipairs(commands) do finalizeCommand(command, status, reason) end
  end
  local function completeReturn(success, reason)
    completeCommands(returnCommands, success and "SUCCESS" or "FAILED", reason)
  end
  local function finishMiner(outcome)
    if #returnCommands > 0 then
      local reason = outcome.ok and nil or (outcome.error and outcome.error.message) or "miner stopped before return completed"
      completeReturn(outcome.ok, reason)
    end
    if #unloadCommands > 0 and pendingUnload then completeCommands(unloadCommands, "FAILED", (outcome.error and outcome.error.message) or "miner stopped before unload completed") end
    return outcome
  end
  local statusReader = MiningStatus.new({
    turtle = context.turtle, inventory = inventory, gps = context.gps,
    get_state = function() return view.status end,
    get_job = function() return jobState and jobState.id or nil end,
    get_pending_command = function() return pendingReturn and "RETURN_HOME" or (pendingUnload and "UNLOAD" or (pendingPause and "PAUSE" or nil)) end,
  })
  network = MiningNetwork.new({
    protocol = MiningProtocol, status = statusReader, rednet = context.rednet, peripheral = context.peripheral,
    os = context.os, logger = context.logger, command_handler = handleCommand,
  })
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
      pcall(network.tick, network)
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
  local world = World.new({
    adapter = adapter, navigation = navigation, result = resultModule, logger = context.logger, pause = options.pause, fluid = fluid,
    torch_positions = placedTorches, torch_slot = torchSlot, on_torch_changed = function() checkpoint(navigation:position()) end,
  })
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
    should_stop = function() return unloader:isNearlyFull() end, fluid = fluid,
    on_excursion = function(excursion)
      if not job then return end
      jobState.ore_excursion = excursion
      jobState.operation = excursion and "ore_chasing" or "mining"
      checkpoint(navigation:position())
    end,
  })

  local torchCount = inventory:count(torchSlot)
  local torchesNeeded = math.floor(distance / torchInterval)
  if torchCount < torchesNeeded then
    return finishMiner(resultModule.fail("MINER.INSUFFICIENT_TORCHES", "Reserved torch slot does not contain enough torches", {
      context = { required = torchesNeeded, available = torchCount },
    }))
  end
  local fuelRequired = (distance * 12) + safetyMargin
  context.ui:status("CHECK", "Fuel required: " .. fuelRequired, false)
  local fuelReady = fuel:ensure(fuelRequired, torchSlot, fuelSlot)
  if not fuelReady.ok then return finishMiner(fuelReady) end
  local refilled = fluid:replenish()
  if not refilled.ok then return finishMiner(refilled) end
  if options.recovery and jobState and jobState.ore_excursion then
    minerUi:status("RECOVERY", "Returning to saved ore anchor", false)
    local recovered = ore:recoverExcursion(jobState.ore_excursion)
    if not recovered.ok then return finishMiner(recovered) end
    jobState.ore_excursion = nil
    jobState.operation = "mining"
    checkpoint(navigation:position())
    minerUi:status("RECOVERY", "Ore anchor restored", false)
  end

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

  local function excavateSide(heading)
    local entered = faceAndMove(heading)
    if not entered.ok then return entered end
    local column = world:clearColumn()
    if not column.ok then return column end
    return faceAndMove((heading + 2) % 4)
  end

  local function placeTorch()
    local original = navigation:position()
    local originalHeading = original.heading
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
    local vector = ({ [0] = { x = 1, z = 0 }, [1] = { x = 0, z = 1 }, [2] = { x = -1, z = 0 }, [3] = { x = 0, z = -1 } })[originalHeading]
    local torchPosition = { x = original.x - vector.x, y = original.y, z = original.z - vector.z }
    placedTorches[torchPosition.x .. ":" .. torchPosition.y .. ":" .. torchPosition.z] = true
    checkpoint(navigation:position())
    context.logger:info("miner.torch_placed", { position = navigation:position() })
    return placed
  end

  context.logger:info("miner.started", { distance = distance, torch_interval = torchInterval, fuel_required = fuelRequired })
  dashboard:reset(); minerUi:status("MINE", "Starting", false)
  for step = (jobState and jobState.slice or 1), distance do
    if pendingReturn then break end
    local beforeSlice = unloadIfNeeded(step, "tunnel")
    if not beforeSlice.ok then return finishMiner(beforeSlice) end
    view.slice = step - 1; minerUi:status("MINE", "Slice " .. step .. "/" .. distance, false)
    local advanced = world:move("forward", movementRetries)
    if not advanced.ok then return finishMiner(advanced) end
    local center = world:clearColumn()
    if not center.ok then return finishMiner(center) end
    local left = excavateSide(3)
    if not left.ok then return finishMiner(left) end
    local right = excavateSide(1)
    if not right.ok then return finishMiner(right) end
    local original = navigation:face(0)
    if not original.ok then return finishMiner(original) end
    local chased = ore:mineSliceBoundary({ movement_retries = movementRetries })
    if not chased.ok then return finishMiner(chased) end
    local unloaded = unloadIfNeeded(step, chased.value.inventory_full and "ore" or "tunnel")
    if not unloaded.ok then return finishMiner(unloaded) end
    if pendingReturn then break end
    if #unloadCommands > 0 and not pendingUnload then completeCommands(unloadCommands, "SUCCESS") end
    if pendingUnload then
      pendingUnload = false
      local remoteUnload = unloader:run({ position = navigation:position(), slice = step, mode = "remote" })
      if not remoteUnload.ok then completeCommands(unloadCommands, "FAILED", remoteUnload.error.message); return finishMiner(remoteUnload) end
      completeCommands(unloadCommands, "SUCCESS")
      minerUi:status("MINE", "Continuing", false)
    end
    if pendingPause and not pendingReturn then
      pendingPause, paused, view.status = false, true, "PAUSED"
      completeCommands(pauseCommands, "SUCCESS")
      while paused and not pendingReturn do network:wait(1) end
      if pendingReturn then break end
      minerUi:status("MINE", "Resuming", false)
    end
    if step % torchInterval == 0 then
      local torch = placeTorch()
      if not torch.ok then return finishMiner(torch) end
    end
    if job then jobState.slice = step + 1; jobState.operation = "mining"; checkpoint(navigation:position()) end
  end

  view.slice = distance; minerUi:status("RETURN", "Returning to start", false)
  local backward = navigation:face(2)
  if not backward.ok then return finishMiner(backward) end
  for _ = 1, distance do
    local moved = world:move("forward", movementRetries)
    if not moved.ok then return finishMiner(moved) end
  end
  local restored = navigation:face(0)
  if not restored.ok then return finishMiner(restored) end
  local fillerReady = fluid:replenish()
  if not fillerReady.ok then return finishMiner(fillerReady) end
  local dumped = storage:dumpBehind({ fillerSlot, torchSlot, fuelSlot })
  if not dumped.ok then return finishMiner(dumped) end
  if job then jobState.operation = "completing"; checkpoint(navigation:position()) end
  local position = navigation:position()
  context.logger:info("miner.completed", { position = position, distance = distance })
  minerUi:status("DONE", "Tunnel complete; items deposited behind start.", false)
  if job then job:clear(true) end
  return finishMiner(resultModule.ok({ position = position, distance = distance }))
end

return Miner

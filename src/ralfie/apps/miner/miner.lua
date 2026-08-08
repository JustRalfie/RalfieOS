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

  local distance = options.distance
  if distance == nil then distance = tonumber(context.ui:prompt("Tunnel distance:")) end
  if type(distance) ~= "number" or distance < 1 or distance % 1 ~= 0 then
    return resultModule.fail("MINER.INVALID_DISTANCE", "Tunnel distance must be a positive whole number")
  end

  local config = context.configuration
  local torchSlot = options.torch_slot or config:get("miner.torch_slot", 16)
  local fuelSlot = options.fuel_slot or config:get("miner.fuel_slot", 15)
  local torchInterval = options.torch_interval or config:get("miner.torch_interval", 10)
  local safetyMargin = options.safety_margin or config:get("miner.safety_margin", 20)
  local movementRetries = options.movement_retries or config:get("miner.movement_retries", 3)
  if torchSlot == fuelSlot or torchInterval < 1 then
    return resultModule.fail("MINER.INVALID_CONFIGURATION", "Torch and fuel slots must differ and torch interval must be positive")
  end

  local adapter = TurtleAdapter.new({ turtle = assert(context.turtle, "miner requires turtle hardware"), result = resultModule })
  local navigation = Navigation.new({ adapter = adapter, result = resultModule })
  local inventory = Inventory.new({ adapter = adapter, result = resultModule })
  local torchReservation = inventory:reserve(torchSlot)
  local fuelReservation = inventory:reserve(fuelSlot)
  if not torchReservation.ok then return torchReservation end
  if not fuelReservation.ok then return fuelReservation end
  local world = World.new({ adapter = adapter, navigation = navigation, result = resultModule, logger = context.logger, pause = options.pause })
  local fuel = Fuel.new({ adapter = adapter, inventory = inventory, result = resultModule, logger = context.logger })
  local storage = Storage.new({ adapter = adapter, inventory = inventory, navigation = navigation, result = resultModule, logger = context.logger })

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

  local function faceAndMove(heading)
    local faced = navigation:face(heading)
    if not faced.ok then return faced end
    return world:move("forward", movementRetries)
  end

  local function excavateSide(heading)
    local entered = faceAndMove(heading)
    if not entered.ok then return entered end
    local column = world:clearColumn()
    if not column.ok then return column end
    return faceAndMove((heading + 2) % 4)
  end

  local function placeTorch()
    local placed = inventory:withSlot(torchSlot, function() return adapter:place("down") end)
    if not placed.ok then return placed end
    context.logger:info("miner.torch_placed", { position = navigation:position() })
    return placed
  end

  context.logger:info("miner.started", { distance = distance, torch_interval = torchInterval, fuel_required = fuelRequired })
  context.ui:heading("Miner v0.1")
  for step = 1, distance do
    context.ui:status("MINE", "Slice " .. step .. "/" .. distance, false)
    local advanced = world:move("forward", movementRetries)
    if not advanced.ok then return advanced end
    local center = world:clearColumn()
    if not center.ok then return center end
    local left = excavateSide(3)
    if not left.ok then return left end
    local right = excavateSide(1)
    if not right.ok then return right end
    local original = navigation:face(0)
    if not original.ok then return original end
    if step % torchInterval == 0 then
      local torch = placeTorch()
      if not torch.ok then return torch end
    end
  end

  context.ui:status("RETURN", "Returning to start", false)
  local backward = navigation:face(2)
  if not backward.ok then return backward end
  for _ = 1, distance do
    local moved = world:move("forward", movementRetries)
    if not moved.ok then return moved end
  end
  local restored = navigation:face(0)
  if not restored.ok then return restored end
  local dumped = storage:dumpBehind({ torchSlot, fuelSlot })
  if not dumped.ok then return dumped end
  local position = navigation:position()
  context.logger:info("miner.completed", { position = position, distance = distance })
  context.ui:status("DONE", "Tunnel complete; items deposited behind start.", false)
  return resultModule.ok({ position = position, distance = distance })
end

return Miner

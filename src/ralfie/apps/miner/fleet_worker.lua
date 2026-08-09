local FleetWorker = {}

local function safeReason(outcome, fallback)
  return outcome and outcome.error and outcome.error.message or fallback
end

function FleetWorker.new(context, options)
  options = options or {}
  local Result = assert(options.result, "fleet worker requires result module")
  local Protocol = assert(options.protocol, "fleet worker requires mining protocol")
  local Network = assert(options.network, "fleet worker requires mining network")
  local Miner = assert(options.miner, "fleet worker requires miner")
  local worker = { state = "READY", active = nil, history = {}, order = {}, history_limit = options.history_limit or 20, update_history = {}, update_order = {} }

  local function remember(id, record)
    worker.history[id] = record
    table.insert(worker.order, id)
    if #worker.order > worker.history_limit then worker.history[table.remove(worker.order, 1)] = nil end
  end
  local function jobStatus(record)
    return { job_id = record.id, job_type = "MINING", lifecycle = record.lifecycle, distance = record.distance }
  end
  local function statusReader()
    local occupied = 0
    for slot = 1, 16 do if context.turtle.getItemCount(slot) > 0 then occupied = occupied + 1 end end
    local record = worker.active
    local version = context.software_version
    if type(version) == "function" then
      local read, value = pcall(version)
      version = read and value or "unknown"
    end
    return {
      state = worker.state, fuel_level = context.turtle.getFuelLevel(), inventory_used = occupied, inventory_slots = 16,
      job_id = record and record.id or nil, job_type = record and "MINING" or nil,
      job_lifecycle = record and record.lifecycle or nil, job_distance = record and record.distance or nil,
      software_version = version or "unknown",
    }
  end
  local network = Network.new({ protocol = Protocol, rednet = context.rednet, peripheral = context.peripheral, os = context.os,
    logger = context.logger, status = { read = statusReader }, job_handler = function(sender, payload) return worker:handleJob(sender, payload) end,
    device_handler = context.device_manager and function(kind, sender, payload) return context.device_manager:handle(kind, sender, payload) end,
    update_handler = function(sender, payload) return worker:handleUpdate(sender, payload) end,
    label_reader = context.device_manager and function() return context.device_manager:deviceName() end })

  local function sendStatus(record)
    if record then network:send(record.recipient, Protocol.types.JOB_STATUS, jobStatus(record)) end
  end
  local function finalize(record, status, reason)
    if not record or record.result then return false end
    record.lifecycle = status == "SUCCESS" and "COMPLETED" or status
    record.result = { job_id = record.id, target_id = context.os.getComputerID(), status = status, reason = reason }
    network:send(record.recipient, Protocol.types.JOB_RESULT, record.result)
    return true
  end
  local function ack(payload, status, reason)
    return { job_id = payload.job_id, target_id = payload.target_id, status = status, reason = reason }
  end

  local function performUpdate(sender, payload)
    if options.perform_update then return options.perform_update(context) end
    local loaded = context.module_loader:load("ralfie.services.platform.remote_update")
    if not loaded.ok then return loaded end
    if not http or type(http.get) ~= "function" then return Result.fail("FLEET_WORKER.HTTP_REQUIRED", "HTTP is required to update this device") end
    return loaded.value.new({ filesystem = context.filesystem, fsx = context.fsx, result = Result, updater = context.updater,
      http = http, load = load, output = function() end, progress = function(progress)
        network:send(sender, Protocol.types.DEVICE_UPDATE_PROGRESS, { request_id = payload.request_id, target_id = payload.target_id,
          stage = progress.stage, completed_files = progress.completed_files, total_files = progress.total_files, version = progress.version })
      end }):install("https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/", context.runtime_root)
  end

  function worker:handleUpdate(sender, payload)
    local previous = self.update_history[payload.request_id]
    if previous then return previous end
    local response = { request_id = payload.request_id, target_id = payload.target_id }
    if payload.target_id ~= context.os.getComputerID() then
      response.status, response.reason = "REJECTED", "request is for a different device"
    elseif self.state ~= "READY" and self.state ~= "PAUSED" then
      response.status, response.reason = "BUSY", "worker is " .. tostring(self.state):lower()
    else
      network:send(sender, Protocol.types.DEVICE_UPDATE_PROGRESS, { request_id = payload.request_id, target_id = payload.target_id, stage = "ACCEPTED" })
      local outcome = performUpdate(sender, payload)
      if outcome and outcome.ok then response.status, response.restart_required, response.version = "SUCCESS", true, outcome.value and outcome.value.version
      else response.status, response.reason = "FAILED", safeReason(outcome, "update failed") end
    end
    self.update_history[payload.request_id] = response
    table.insert(self.update_order, payload.request_id)
    if #self.update_order > self.history_limit then self.update_history[table.remove(self.update_order, 1)] = nil end
    return response
  end

  function worker:handleJob(sender, payload)
    local previous = self.history[payload.job_id]
    if previous then return previous.ack, previous.result end
    if payload.target_id ~= context.os.getComputerID() then return ack(payload, "REJECTED", "job is for a different turtle") end
    if payload.job.type ~= "MINING" then return ack(payload, "REJECTED", "unsupported job type") end
    if type(payload.job.distance) ~= "number" or payload.job.distance < 1 or payload.job.distance % 1 ~= 0 then return ack(payload, "INVALID", "distance must be a positive whole number") end
    if self.state ~= "READY" or self.active then return ack(payload, "BUSY", "worker is not ready") end
    local record = { id = payload.job_id, distance = payload.job.distance, recipient = sender, lifecycle = "ACCEPTED" }
    record.ack = ack(payload, "ACCEPTED")
    remember(record.id, record)
    self.active, self.state = record, "STARTING"; context.worker_state, context.active_job_id = self.state, record.id
    sendStatus(record)
    return record.ack
  end

  local function runActive()
    local record = worker.active
    if not record then return end
    record.lifecycle, worker.state = "RUNNING", "RUNNING"; context.worker_state, context.active_job_id = worker.state, record.id; sendStatus(record)
    local cancelled = false
    local outcome = Miner.start(context, {
      distance = record.distance, job_id = record.id,
      get_job_details = function() return { type = "MINING", lifecycle = record.lifecycle, distance = record.distance } end,
      job_handler = function(sender, payload) return worker:handleJob(sender, payload) end,
      device_handler = context.device_manager and function(kind, sender, payload) return context.device_manager:handle(kind, sender, payload) end,
      update_handler = function(sender, payload) return worker:handleUpdate(sender, payload) end,
      label_reader = context.device_manager and function() return context.device_manager:deviceName() end,
      on_state_change = function(state)
        if state == "PAUSED" then record.lifecycle = "PAUSED"
        elseif state == "RETURNING HOME" then record.lifecycle = cancelled and "CANCELLED" or "RETURNING"
        elseif state == "UNLOADING" then record.lifecycle = "UNLOADING"
        elseif state == "MINING" and not cancelled then record.lifecycle = "RUNNING" end
        worker.state = state; context.worker_state, context.active_job_id = state, record.id; sendStatus(record)
      end,
      on_return_home = function()
        if not cancelled then cancelled = true; finalize(record, "CANCELLED", "return home requested") end
      end,
    })
    if not record.result then finalize(record, outcome.ok and "SUCCESS" or "FAILED", outcome.ok and nil or safeReason(outcome, "miner failed")) end
    if outcome.ok then worker.active, worker.state = nil, "READY" else worker.active, worker.state = nil, "ERROR" end
    context.worker_state, context.active_job_id = worker.state, nil
  end

  function worker:run(shouldStop)
    if not network:start() then return Result.fail("FLEET_WORKER.MODEM_REQUIRED", "Fleet Worker requires a wireless modem") end
    while not shouldStop or not shouldStop(self) do
      if self.active and self.state == "STARTING" then runActive() else network:wait(1) end
    end
    return Result.ok({ state = self.state })
  end
  function worker:network() return network end
  function worker:status() return statusReader() end
  return worker
end

function FleetWorker.start(context, options)
  local load = function(name)
    local loaded = context.module_loader:load(name)
    return loaded.ok and loaded.value or nil, loaded
  end
  local Result, failed = load("ralfie.core.result"); if not Result then return failed end
  local Protocol; Protocol, failed = load("ralfie.services.platform.mining_protocol"); if not Protocol then return failed end
  local Network; Network, failed = load("ralfie.services.platform.mining_network"); if not Network then return failed end
  local Miner; Miner, failed = load("ralfie.apps.miner.miner"); if not Miner then return failed end
  return FleetWorker.new(context, { result = Result, protocol = Protocol, network = Network, miner = Miner, history_limit = options and options.history_limit,
    perform_update = options and options.perform_update }):run(options and options.should_stop)
end

return FleetWorker

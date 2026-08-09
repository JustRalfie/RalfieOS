local root = "/ralfie"
local Protocol = dofile(root .. "/services/platform/mining_protocol.lua")
local Fleet = dofile(root .. "/pocket/fleet.lua")
local UpdateBatch = dofile(root .. "/pocket/update_batch.lua")
local Network = dofile(root .. "/pocket/network.lua")
local Ui = dofile(root .. "/pocket/ui.lua")
local manifest = dofile(root .. "/manifest.lua")

local network = Network.new({ protocol = Protocol, rednet = rednet, peripheral = peripheral, os = os })
if not network:open() then print("A wireless modem is required."); return false end
local fleet, selected, screen, detailSelection, settingsSelection, controllerSelection, command, job, updateBatch = Fleet.new({ offline_timeout = 45, protocol = Protocol }), nil, "fleet", 1, 1, 1, nil, nil, nil
local function now() return (os.epoch and os.epoch("utc") / 1000) or os.clock() end
local function selectOnline()
  -- Keep a selected offline device visible so its cached Details screen remains reachable.
  if selected and fleet.miners[selected] then return end
  for _, miner in ipairs(fleet:list()) do if miner.online then selected = miner.id; return end end
  selected = nil
end
local function redraw()
  selectOnline()
  local miner = selected and fleet.miners[selected]
  if screen == "detail" and miner then Ui.command(term, miner, detailSelection, command and command.state)
  elseif screen == "details" and miner then Ui.details(term, miner)
  elseif screen == "settings" and miner then Ui.settings(term, miner, settingsSelection)
  elseif screen == "update" then Ui.update(term, fleet, updateBatch, 1)
  elseif screen == "controller" then Ui.controllerMenu(term, controllerSelection)
  else Ui.render(term, fleet, selected) end
end

local function observeUpdateStatus(id)
  if not updateBatch then return end
  local miner = fleet.miners[id]
  if miner and miner.status then UpdateBatch.observeVersion(updateBatch, id, miner.status.software_version) end
end
local function finishFleetUpdate()
  if not updateBatch or updateBatch.local_started then return end
  updateBatch.local_started = true
  updateBatch.local_result = "Updating Pocket..."
  local updated = dofile(root .. "/update.lua")
  if updated and updated.ok then
    updateBatch.local_result = "Pocket updated. Restarting..."
    if os.reboot then os.reboot() end
  else
    updateBatch.local_result = "Pocket update failed."
  end
end
local function requestFleetUpdate()
  updateBatch = UpdateBatch.new(manifest.version)
  local issuedBy = network:identity().id
  local requestedAt = now()
  UpdateBatch.request(updateBatch, fleet:list(), Ui.userState, function(id, requestId)
    return network:send(id, Protocol.types.DEVICE_UPDATE_REQUEST, { request_id = requestId, target_id = id, issued_by = issuedBy })
  end, issuedBy, requestedAt, function(miner) return "update-" .. tostring(os.epoch("utc")) .. "-" .. miner.id end)
end
local function receive(sender, message)
  local time = now()
  if message.type == Protocol.types.HELLO_ACK or message.type == Protocol.types.STATUS or message.type == Protocol.types.PONG then
    fleet:record(message.sender, message.payload, time); observeUpdateStatus(message.sender.id)
  end
  if message.type == Protocol.types.JOB_STATUS and fleet.miners[message.sender.id] then
    local status = fleet.miners[message.sender.id].status or {}; status.job_id, status.job_type, status.job_lifecycle, status.job_distance = message.payload.job_id, message.payload.job_type, message.payload.lifecycle, message.payload.distance
  end
  if message.type == Protocol.types.DEVICE_INFO and fleet.miners[message.sender.id] then fleet.miners[message.sender.id].device_info = message.payload end
  if updateBatch and message.type == Protocol.types.DEVICE_UPDATE_PROGRESS then
    local pending = updateBatch.pending[message.sender.id]
    if pending and pending.id == message.payload.request_id then
      pending.stage, pending.completed_files, pending.total_files, pending.last_seen = message.payload.stage, message.payload.completed_files, message.payload.total_files, time
      UpdateBatch.progress(updateBatch, message.sender.id, pending)
    end
  end
  if updateBatch and message.type == Protocol.types.DEVICE_UPDATE_RESULT then
    local pending = updateBatch.pending[message.sender.id]
    if pending and pending.id == message.payload.request_id then
      if message.payload.status == "SUCCESS" and message.payload.version then updateBatch.target_version = message.payload.version end
      UpdateBatch.result(updateBatch, message.sender.id, {
        status = message.payload.status == "SUCCESS" and "UPDATED" or message.payload.status,
        reason = message.payload.reason, restart_required = message.payload.restart_required, version = message.payload.version,
        verification_required = message.payload.status == "SUCCESS", verified_by = message.payload.status == "SUCCESS" and (time + 60) or nil,
      })
      observeUpdateStatus(message.sender.id)
    end
  end
  if command and message.sender.id == command.target_id and command.state == "RESULT UNKNOWN" and fleet:canCommand(command.target_id) then
    network:send(command.target_id, Protocol.types.COMMAND, { command_id = command.id, command = command.kind, target_id = command.target_id, issued_by = network:identity().id })
    command.state = "IN_PROGRESS"
  end
  if command and message.sender.id == command.target_id and message.payload.command_id == command.id then
    if message.type == Protocol.types.COMMAND_ACK then command.state = message.payload.status == "ACCEPTED" and "IN_PROGRESS" or message.payload.status
    elseif message.type == Protocol.types.COMMAND_RESULT then command.state = message.payload.status .. (message.payload.reason and (": " .. message.payload.reason) or "") end
  end
  if job and message.sender.id == job.target_id and message.payload.job_id == job.id then
    if message.type == Protocol.types.JOB_ACK then job.state = message.payload.status == "ACCEPTED" and "IN_PROGRESS" or message.payload.status
    elseif message.type == Protocol.types.JOB_RESULT then job.state = message.payload.status .. (message.payload.reason and (": " .. message.payload.reason) or "") end
  end
end
local function requestDeviceInfo()
  if selected and fleet:canCommand(selected) then
    network:send(selected, Protocol.types.DEVICE_INFO_REQUEST, { target_id = selected, issued_by = network:identity().id })
  end
end
local function configureDevice(choice)
  local miner = selected and fleet.miners[selected]
  if not miner or not miner.online or not miner.device_info then return end
  local key = choice == 1 and "device_name" or (choice == 2 and "fleet_name" or (choice == 3 and "auto_start" or nil))
  if not key then return end
  local raw = Ui.input(term, "DEVICE SETUP", key == "auto_start" and "Auto-start [Y/N]" or "New value", "")
  if raw == nil then return end
  local value = key == "auto_start" and raw:lower() == "y" or raw
  if key ~= "auto_start" and value == "" then return end
  if not Ui.confirm(term, "SAVE DEVICE SETUP?", { key .. ": " .. tostring(value) }) then return end
  local id = "config-" .. tostring(os.epoch("utc")) .. "-" .. selected
  network:send(selected, Protocol.types.DEVICE_CONFIG_SET, { request_id = id, target_id = selected, issued_by = network:identity().id,
    expected_revision = miner.device_info.config_revision, changes = { [key] = value } })
end
local function assignJob()
  local miner = selected and fleet.miners[selected]
  if not miner or not miner.online or miner.status.state ~= "READY" then return end
  local distance = tonumber(Ui.input(term, "NEW MINING JOB", "Distance (whole number)", ""))
  if not distance or distance < 1 or distance % 1 ~= 0 then
    Ui.confirm(term, "INVALID DISTANCE", { "Use a positive whole number." })
    return
  end
  if not Ui.confirm(term, "ASSIGN MINING JOB?", { "Miner: " .. (miner.label or ("#" .. miner.id)), "Distance: " .. distance }) then return end
  local id = "job-" .. tostring(os.epoch("utc")) .. "-" .. selected
  job = { id = id, target_id = selected, state = "SENT" }
  network:send(selected, Protocol.types.JOB_ASSIGN, { job_id = id, target_id = selected, issued_by = network:identity().id, job = { type = "MINING", distance = distance } })
end
network:broadcast(Protocol.types.HELLO)
local timer = os.startTimer(1)
redraw()
while true do
  local event, a, b, c = os.pullEvent()
  if event == "rednet_message" then
    local sender, message = network:accept(a, b, c)
    if sender then receive(sender, message) end
  elseif event == "timer" and a == timer then
    local time = now(); fleet:refresh(time)
    if command and command.state == "SENT" and time - command.sent_at >= 10 then command.state = "ACK TIMEOUT" end
    if command and command.state ~= "SUCCESS" and command.state ~= "FAILED" and command.state ~= "CANCELLED" and not fleet:canCommand(command.target_id) then command.state = "RESULT UNKNOWN" end
    if math.floor(time) % 30 == 0 then network:broadcast(Protocol.types.HELLO) end
    if updateBatch and not updateBatch.local_started then
      for id, pending in pairs(updateBatch.pending) do
        if time - pending.last_seen >= 45 then UpdateBatch.result(updateBatch, id, { status = "RESULT UNKNOWN", reason = "update response timed out" }) end
      end
      for _, result in pairs(updateBatch.results) do
        if result.status == "UPDATED" and result.verified_by and time >= result.verified_by then result.status, result.reason = "RESULT UNKNOWN", "updated device did not report the target version" end
      end
      UpdateBatch.refresh(updateBatch)
    end
    timer = os.startTimer(1)
  elseif event == "key" then
    if screen == "fleet" and a == keys.m then screen, controllerSelection = "controller", 1
    elseif screen == "fleet" and a == keys.a then if not updateBatch then requestFleetUpdate() end; screen = "update"
    elseif screen == "update" and Ui.isBackKey(a) then screen = "fleet"
    elseif screen == "update" and a == keys.enter and updateBatch and updateBatch.resolved then finishFleetUpdate()
    elseif screen == "controller" and Ui.isBackKey(a) then screen = "fleet"
    elseif screen == "controller" and (a == keys.up or a == keys.down) then controllerSelection = math.max(1, math.min(3, controllerSelection + (a == keys.up and -1 or 1)))
    elseif screen == "controller" and a == keys.enter then
      if controllerSelection == 1 or controllerSelection == 3 then screen = "fleet"
      elseif controllerSelection == 2 then if not updateBatch then requestFleetUpdate() end; screen = "update" end
    elseif screen == "details" and Ui.isBackKey(a) then screen = "detail"
    elseif screen == "settings" and Ui.isBackKey(a) then screen = "detail"
    elseif screen == "settings" and (a == keys.up or a == keys.down) then settingsSelection = math.max(1, math.min(4, settingsSelection + (a == keys.up and -1 or 1)))
    elseif screen == "settings" and a == keys.enter then if settingsSelection == 4 then screen = "detail" else configureDevice(settingsSelection) end
    elseif screen == "detail" and Ui.isBackKey(a) then screen = "fleet"
    elseif screen == "detail" and (a == keys.up or a == keys.down) then
      local count = #Ui.deviceActions(selected and fleet.miners[selected]); detailSelection = math.max(1, math.min(count, detailSelection + (a == keys.up and -1 or 1)))
    elseif screen == "detail" and a == keys.enter then
      local action = Ui.deviceActions(fleet.miners[selected])[detailSelection]
      if action.id == "back" then screen = "fleet"
      elseif action.id == "details" then screen = "details"; requestDeviceInfo()
      elseif action.id == "settings" then screen = "settings"; settingsSelection = 1; requestDeviceInfo()
      elseif action.id == "job" then assignJob()
      elseif fleet:canCommand(selected) then
        local id = tostring(os.epoch("utc")) .. "-" .. selected
        command = { id = id, kind = action.id, target_id = selected, sent_at = now(), state = "SENT" }
        network:send(selected, Protocol.types.COMMAND, { command_id = id, command = action.id, target_id = selected, issued_by = network:identity().id })
      end
    elseif screen == "detail" and selected and fleet:canCommand(selected) then
      local keyNames = { [keys.r] = "r", [keys.u] = "u", [keys.p] = "p", [keys.c] = "c" }
      local kind = Ui.commandForKey(fleet.miners[selected], keyNames[a])
      if kind then
        local id = tostring(os.epoch("utc")) .. "-" .. selected
        command = { id = id, kind = kind, target_id = selected, sent_at = now(), state = "SENT" }
        network:send(selected, Protocol.types.COMMAND, { command_id = id, command = kind, target_id = selected, issued_by = network:identity().id })
      end
    elseif screen == "fleet" and a == keys.enter and selected then screen = "detail"; detailSelection = 1
    elseif screen == "fleet" and (a == keys.up or a == keys.down) then
      local miners = fleet:list(); local index = 1
      for i, miner in ipairs(miners) do if miner.id == selected then index = i end end
      index = math.max(1, math.min(#miners, index + (a == keys.up and -1 or 1))); selected = miners[index] and miners[index].id
    end
  end
  redraw()
end

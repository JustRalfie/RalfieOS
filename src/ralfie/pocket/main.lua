local root = "/ralfie"
local Protocol = dofile(root .. "/services/platform/mining_protocol.lua")
local Fleet = dofile(root .. "/pocket/fleet.lua")
local Network = dofile(root .. "/pocket/network.lua")
local Ui = dofile(root .. "/pocket/ui.lua")

local network = Network.new({ protocol = Protocol, rednet = rednet, peripheral = peripheral, os = os })
if not network:open() then print("A wireless modem is required."); return false end
local fleet, selected, detail, info, command, job, updateBatch = Fleet.new({ offline_timeout = 45, protocol = Protocol }), nil, false, false, nil, nil, nil
local function now() return (os.epoch and os.epoch("utc") / 1000) or os.clock() end
local function selectOnline()
  if selected and fleet:canCommand(selected) then return end
  for _, miner in ipairs(fleet:list()) do if miner.online then selected = miner.id; return end end
  selected = nil
end
local function redraw()
  selectOnline()
  if detail and selected and fleet.miners[selected] then
    if info then Ui.info(term, fleet.miners[selected]) else Ui.command(term, fleet.miners[selected], command and command.state) end
  else Ui.render(term, fleet, selected, updateBatch) end
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
  updateBatch = { pending = {}, results = {} }
  local issuedBy = network:identity().id
  for _, miner in ipairs(fleet:list()) do
    if miner.online then
      local state = Ui.userState(miner)
      if state == "READY" or state == "PAUSED" then
        local requestId = "update-" .. tostring(os.epoch("utc")) .. "-" .. miner.id
        updateBatch.pending[miner.id] = { id = requestId, sent_at = now() }
        if not network:send(miner.id, Protocol.types.DEVICE_UPDATE_REQUEST, { request_id = requestId, target_id = miner.id, issued_by = issuedBy }) then
          updateBatch.pending[miner.id] = nil; updateBatch.results[miner.id] = { status = "FAILED", reason = "could not send request" }
        end
      else
        updateBatch.results[miner.id] = { status = "BUSY", reason = "worker is " .. state:lower() }
      end
    end
  end
  if next(updateBatch.pending) == nil then finishFleetUpdate() end
end
local function receive(sender, message)
  local time = now()
  if message.type == Protocol.types.HELLO_ACK or message.type == Protocol.types.STATUS or message.type == Protocol.types.PONG then fleet:record(message.sender, message.payload, time) end
  if message.type == Protocol.types.JOB_STATUS and fleet.miners[message.sender.id] then
    local status = fleet.miners[message.sender.id].status or {}; status.job_id, status.job_type, status.job_lifecycle, status.job_distance = message.payload.job_id, message.payload.job_type, message.payload.lifecycle, message.payload.distance
  end
  if message.type == Protocol.types.DEVICE_INFO and fleet.miners[message.sender.id] then fleet.miners[message.sender.id].device_info = message.payload end
  if updateBatch and message.type == Protocol.types.DEVICE_UPDATE_RESULT then
    local pending = updateBatch.pending[message.sender.id]
    if pending and pending.id == message.payload.request_id then
      updateBatch.pending[message.sender.id] = nil
      updateBatch.results[message.sender.id] = { status = message.payload.status, reason = message.payload.reason, restart_required = message.payload.restart_required }
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
local function configureDevice()
  local miner = selected and fleet.miners[selected]
  if not miner or not miner.online or not miner.device_info then return end
  term.clear(); term.setCursorPos(1, 1); term.write("DEVICE SETUP")
  term.setCursorPos(1, 3); term.write("1 Name  2 Fleet  3 Auto")
  term.setCursorPos(1, 5); term.write("Edit: ")
  local choice = read()
  local key = choice == "1" and "device_name" or (choice == "2" and "fleet_name" or (choice == "3" and "auto_start" or nil))
  if not key then return end
  term.setCursorPos(1, 7); term.write(key == "auto_start" and "Auto-start [Y/N]: " or "New value: ")
  local raw = read()
  local value = key == "auto_start" and raw:lower() == "y" or raw
  if key ~= "auto_start" and value == "" then return end
  term.setCursorPos(1, 9); term.write("Confirm [Y/N]: ")
  if read():lower() ~= "y" then return end
  local id = "config-" .. tostring(os.epoch("utc")) .. "-" .. selected
  network:send(selected, Protocol.types.DEVICE_CONFIG_SET, { request_id = id, target_id = selected, issued_by = network:identity().id,
    expected_revision = miner.device_info.config_revision, changes = { [key] = value } })
end
local function assignJob()
  local miner = selected and fleet.miners[selected]
  if not miner or not miner.online or miner.status.state ~= "READY" then return end
  local width = select(1, term.getSize())
  local function line(number, text) term.setCursorPos(1, number); term.write(tostring(text):sub(1, width)) end
  term.clear(); line(1, "NEW MINING JOB")
  line(3, miner.label or ("Miner #" .. miner.id))
  line(5, "Distance (whole number):")
  line(6, "> ")
  local distance = tonumber(read())
  if not distance or distance < 1 or distance % 1 ~= 0 then
    line(8, "Invalid distance.")
    line(9, "Press any key."); os.pullEvent("key")
    return
  end
  term.clear(); line(1, "ASSIGN MINING JOB?")
  line(3, "Miner: " .. (miner.label or ("#" .. miner.id)))
  line(4, "Distance: " .. distance)
  line(6, "Confirm [Y/N]: ")
  if read():lower() ~= "y" then return end
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
        if time - pending.sent_at >= 30 then updateBatch.pending[id] = nil; updateBatch.results[id] = { status = "FAILED", reason = "update request timed out" } end
      end
      if next(updateBatch.pending) == nil then finishFleetUpdate() end
    end
    timer = os.startTimer(1)
  elseif event == "key" then
    if detail and a == keys.b then
      if info then info = false else detail = false end
    elseif detail and info and a == keys.e then configureDevice()
    elseif detail and not info and a == keys.s and Ui.userState(selected and fleet.miners[selected]) == "READY" then
      info = true; requestDeviceInfo()
    elseif detail and not info and a == keys.i then
      info = true; requestDeviceInfo()
    elseif detail and not info and a == keys.j then assignJob()
    elseif detail and not info and selected and fleet:canCommand(selected) then
      local keyNames = { [keys.r] = "r", [keys.u] = "u", [keys.p] = "p", [keys.c] = "c" }
      local kind = Ui.commandForKey(fleet.miners[selected], keyNames[a])
      if kind then
        local id = tostring(os.epoch("utc")) .. "-" .. selected
        command = { id = id, kind = kind, target_id = selected, sent_at = now(), state = "SENT" }
        network:send(selected, Protocol.types.COMMAND, { command_id = id, command = kind, target_id = selected, issued_by = network:identity().id })
      end
    elseif not detail and a == keys.a and not updateBatch then requestFleetUpdate()
    elseif not detail and a == keys.enter and selected then detail = true
    elseif not detail and (a == keys.up or a == keys.down) then
      local miners = fleet:list(); local index = 1
      for i, miner in ipairs(miners) do if miner.id == selected then index = i end end
      index = math.max(1, math.min(#miners, index + (a == keys.up and -1 or 1))); selected = miners[index] and miners[index].id
    end
  end
  redraw()
end

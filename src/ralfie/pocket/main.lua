local root = "/ralfie"
local Protocol = dofile(root .. "/services/platform/mining_protocol.lua")
local Fleet = dofile(root .. "/pocket/fleet.lua")
local Network = dofile(root .. "/pocket/network.lua")
local Ui = dofile(root .. "/pocket/ui.lua")

local network = Network.new({ protocol = Protocol, rednet = rednet, peripheral = peripheral, os = os })
if not network:open() then print("A wireless modem is required."); return false end
local fleet, selected, detail, command, job = Fleet.new({ offline_timeout = 45, protocol = Protocol }), nil, false, nil, nil
local function now() return (os.epoch and os.epoch("utc") / 1000) or os.clock() end
local function selectOnline()
  if selected and fleet:canCommand(selected) then return end
  for _, miner in ipairs(fleet:list()) do if miner.online then selected = miner.id; return end end
  selected = nil
end
local function redraw()
  selectOnline()
  if detail and selected and fleet.miners[selected] then Ui.command(term, fleet.miners[selected], command and command.state) else Ui.render(term, fleet, selected) end
end
local function receive(sender, message)
  local time = now()
  if message.type == Protocol.types.HELLO_ACK or message.type == Protocol.types.STATUS or message.type == Protocol.types.PONG then fleet:record(message.sender, message.payload, time) end
  if message.type == Protocol.types.JOB_STATUS and fleet.miners[message.sender.id] then
    local status = fleet.miners[message.sender.id].status or {}; status.job_id, status.job_type, status.job_lifecycle, status.job_distance = message.payload.job_id, message.payload.job_type, message.payload.lifecycle, message.payload.distance
  end
  if message.type == Protocol.types.DEVICE_INFO and fleet.miners[message.sender.id] then fleet.miners[message.sender.id].device_info = message.payload end
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
    timer = os.startTimer(1)
  elseif event == "key" then
    if detail and a == keys.b then detail = false
    elseif detail and a == keys.s then requestDeviceInfo()
    elseif detail and a == keys.e then configureDevice()
    elseif detail and a == keys.j then assignJob()
    elseif detail and (a == keys.r or a == keys.u or a == keys.p or a == keys.c) and selected and fleet:canCommand(selected) then
      local id = tostring(os.epoch("utc")) .. "-" .. selected
      local kind = a == keys.r and "RETURN_HOME" or (a == keys.u and "UNLOAD" or (a == keys.p and "PAUSE" or "RESUME"))
      command = { id = id, kind = kind, target_id = selected, sent_at = now(), state = "SENT" }
      network:send(selected, Protocol.types.COMMAND, { command_id = id, command = kind, target_id = selected, issued_by = network:identity().id })
    elseif not detail and a == keys.enter and selected then detail = true
    elseif not detail and (a == keys.up or a == keys.down) then
      local miners = fleet:list(); local index = 1
      for i, miner in ipairs(miners) do if miner.id == selected then index = i end end
      index = math.max(1, math.min(#miners, index + (a == keys.up and -1 or 1))); selected = miners[index] and miners[index].id
    end
  end
  redraw()
end

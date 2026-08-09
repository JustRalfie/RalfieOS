local Protocol = dofile("src/ralfie/services/platform/mining_protocol.lua")
local MiningNetwork = dofile("src/ralfie/services/platform/mining_network.lua")
local MiningStatus = dofile("src/ralfie/services/platform/mining_status.lua")
local Fleet = dofile("src/ralfie/pocket/fleet.lua")

local identity = { id = 17, label = "Miner-01" }
local hello = assert(Protocol.message(Protocol.types.HELLO, { id = 42, label = "Command" }, {}))
assert(Protocol.valid(hello))
assert(not Protocol.valid({ protocol = Protocol.id, version = 99, type = "HELLO", sender = identity }))
assert(not Protocol.valid("HELLO"))
assert(not Protocol.valid({ protocol = Protocol.id, version = 1, sender = identity, payload = {} }))
assert(not Protocol.valid({ protocol = Protocol.id, version = 1, type = "STATUS", sender = identity, payload = {} }))
assert(Protocol.message("UNKNOWN", identity) == nil)
local commandPayload = { command_id = "return-1", command = "RETURN_HOME", target_id = 17, issued_by = 42 }
local commandMessage = assert(Protocol.message(Protocol.types.COMMAND, { id = 42, label = "Command" }, commandPayload))
assert(Protocol.valid(commandMessage))
local unloadMessage = assert(Protocol.message(Protocol.types.COMMAND, { id = 42 }, { command_id = "unload-1", command = "UNLOAD", target_id = 17, issued_by = 42 }))
assert(Protocol.valid(unloadMessage))
local pauseMessage = assert(Protocol.message(Protocol.types.COMMAND, { id = 42 }, { command_id = "pause-1", command = "PAUSE", target_id = 17, issued_by = 42 }))
assert(Protocol.valid(pauseMessage))
local resumeMessage = assert(Protocol.message(Protocol.types.COMMAND, { id = 42 }, { command_id = "resume-1", command = "RESUME", target_id = 17, issued_by = 42 }))
assert(Protocol.valid(resumeMessage))
assert(not Protocol.valid(Protocol.message(Protocol.types.COMMAND, { id = 42 }, { command = "RETURN_HOME", target_id = 17, issued_by = 42 })))
local jobPayload = { job_id = "job-1", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 10 } }
local jobMessage = assert(Protocol.message(Protocol.types.JOB_ASSIGN, { id = 42 }, jobPayload))
assert(Protocol.valid(jobMessage))
assert(not Protocol.valid(Protocol.message(Protocol.types.JOB_ASSIGN, { id = 42 }, { job_id = "bad", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 0 } })))
assert(Protocol.jobAckValid({ job_id = "job-1", target_id = 17, status = "ACCEPTED" }))
assert(Protocol.jobStatusValid({ job_id = "job-1", job_type = "MINING", lifecycle = "RUNNING", distance = 10 }))
assert(Protocol.jobResultValid({ job_id = "job-1", target_id = 17, status = "SUCCESS" }))
local updatePayload = { request_id = "update-1", target_id = 17, issued_by = 42 }
local updateMessage = assert(Protocol.message(Protocol.types.DEVICE_UPDATE_REQUEST, { id = 42 }, updatePayload))
assert(Protocol.valid(updateMessage))
assert(not Protocol.valid(Protocol.message(Protocol.types.DEVICE_UPDATE_REQUEST, { id = 42 }, { target_id = 17, issued_by = 42 })))
local updateProgress = assert(Protocol.message(Protocol.types.DEVICE_UPDATE_PROGRESS, { id = 17 }, { request_id = "update-1", target_id = 17, stage = "DOWNLOADING", completed_files = 14, total_files = 20, version = "0.3.6" }))
assert(Protocol.valid(updateProgress))
assert(not Protocol.valid(Protocol.message(Protocol.types.DEVICE_UPDATE_PROGRESS, { id = 17 }, { request_id = "update-1", target_id = 17, completed_files = 14 })))

local statusReader = MiningStatus.new({
  turtle = { getFuelLevel = function() return "unlimited" end },
  inventory = { count = function(_, slot) return (slot == 1 or slot == 16) and 1 or 0 end },
  get_state = function() return "IDLE" end, get_job = function() return nil end,
  get_software_version = function() return "0.3.6" end,
  gps = { locate = function() return nil end },
})
local localStatus = statusReader:read()
assert(localStatus.fuel_level == "unlimited" and localStatus.inventory_used == 2 and localStatus.position == nil and localStatus.job_id == nil and localStatus.software_version == "0.3.6")
assert(Protocol.statusValid({ turtle_id = 17, state = "PAUSED", fuel_level = 500, inventory_used = 3, inventory_slots = 16, pending_command = "PAUSE", software_version = "0.1.0", protocol_version = 1 }))

local sent, broadcasts = {}, {}
local received = { 42, hello }
local rednet = {
  open = function() end,
  send = function(id, message, protocol) table.insert(sent, { id = id, message = message, protocol = protocol }) end,
  broadcast = function(message, protocol) table.insert(broadcasts, { message = message, protocol = protocol }) end,
  receive = function() local value = received; received = nil; if value then return value[1], value[2] end end,
}
local client = MiningNetwork.new({
  protocol = Protocol, rednet = rednet,
  peripheral = { getNames = function() return { "left" } end, wrap = function() return { isWireless = function() return true end } end },
  os = { getComputerID = function() return 17 end, getComputerLabel = function() return "Miner-01" end, clock = function() return 0 end },
  status = { read = function() return { state = "MINING", fuel_level = 500, inventory_used = 3, inventory_slots = 16 } end },
})
assert(client:tick(10))
assert(#sent == 2 and sent[1].message.type == Protocol.types.HELLO_ACK and sent[2].message.type == Protocol.types.STATUS)
assert(sent[2].message.payload.turtle_id == 17 and sent[2].message.payload.protocol_version == 1)
assert(#broadcasts == 1 and broadcasts[1].message.type == Protocol.types.STATUS)
client:tick(25)
assert(#broadcasts == 2, "active miner polling must emit the next heartbeat without a UI status change")
received = { 42, { protocol = "elsewhere", version = 1, type = "HELLO", sender = identity } }
client:tick(11)
assert(#sent == 2, "unrelated messages must be ignored")

local commandCalls, commandRecords = 0, {}
client.command_handler = function(sender, payload)
  commandCalls = commandCalls + 1
  local record = commandRecords[payload.command_id]
  if not record then
    local status = payload.target_id ~= 17 and "REJECTED" or (payload.command == "RETURN_HOME" and "ACCEPTED" or "INVALID")
    record = { ack = { command_id = payload.command_id, command = payload.command, target_id = payload.target_id, status = status } }
    commandRecords[payload.command_id] = record
  end
  return record.ack, record.result
end
received = { 42, commandMessage }
client:tick(30)
assert(sent[#sent].message.type == Protocol.types.COMMAND_ACK and sent[#sent].message.payload.status == "ACCEPTED")
received = { 42, commandMessage }
client:tick(31)
assert(commandCalls == 2 and sent[#sent].message.type == Protocol.types.COMMAND_ACK, "duplicate commands must be safe for an idempotent handler")
commandRecords["return-1"].result = { command_id = "return-1", command = "RETURN_HOME", target_id = 17, status = "SUCCESS" }
received = { 42, commandMessage }
client:tick(32)
assert(sent[#sent - 1].message.type == Protocol.types.COMMAND_ACK and sent[#sent].message.type == Protocol.types.COMMAND_RESULT)
local resultCount = #sent
received = { 42, commandMessage }; client:tick(33)
assert(#sent == resultCount + 2 and sent[#sent].message.type == Protocol.types.COMMAND_RESULT, "completed command must replay its one stored result")
assert(commandRecords["return-1"].result.status == "SUCCESS", "a terminal result is immutable")
local wrongTarget = assert(Protocol.message(Protocol.types.COMMAND, { id = 42 }, { command_id = "wrong-target", command = "RETURN_HOME", target_id = 99, issued_by = 42 }))
received = { 42, wrongTarget }; client:tick(33)
assert(sent[#sent].message.payload.status == "REJECTED", "wrong-target commands must be rejected")
client.update_handler = function(sender, payload)
  return { request_id = payload.request_id, target_id = payload.target_id, status = "SUCCESS", restart_required = true }
end
received = { 42, updateMessage }; client:tick(34)
assert(sent[#sent].message.type == Protocol.types.DEVICE_UPDATE_RESULT and sent[#sent].message.payload.status == "SUCCESS")

local unloadRecord = { command_id = "unload-1", command = "UNLOAD", target_id = 17, status = "SUCCESS" }
local pauseRecord = { command_id = "pause-1", command = "PAUSE", target_id = 17, status = "SUCCESS" }
assert(Protocol.commandResultValid(unloadRecord))
assert(Protocol.commandResultValid(pauseRecord))

local fleet = Fleet.new({ offline_timeout = 45, protocol = Protocol })
local status = { turtle_id = 17, label = "Miner-01", state = "MINING", fuel_level = 500, inventory_used = 3, inventory_slots = 16, software_version = "0.1.0", protocol_version = 1 }
assert(fleet:record(identity, status, 100))
assert(fleet:record(identity, { turtle_id = 17, state = "IDLE", fuel_level = "unlimited", inventory_used = 1, inventory_slots = 16, software_version = "0.1.0", protocol_version = 1 }, 110))
assert(#fleet:list() == 1 and fleet.miners[17].status.state == "IDLE" and fleet.miners[17].last_seen == 110)
assert(not fleet:record({}, status, 111))
assert(not fleet:record(identity, { turtle_id = 17, state = "IDLE" }, 112), "malformed status must not refresh last_seen")
assert(fleet.miners[17].last_seen == 110)
fleet:refresh(154); assert(fleet.miners[17].online)
fleet:refresh(156); assert(not fleet.miners[17].online)
assert(fleet:record(identity, status, 160) and fleet.miners[17].online, "a reconnect must restore the existing miner")
print("mining network tests passed")

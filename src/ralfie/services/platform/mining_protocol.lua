local Protocol = {
  id = "ralfie:mining:v1",
  version = 1,
  types = {
    HELLO = "HELLO", HELLO_ACK = "HELLO_ACK", STATUS_REQUEST = "STATUS_REQUEST",
    STATUS = "STATUS", PING = "PING", PONG = "PONG", COMMAND = "COMMAND",
    COMMAND_ACK = "COMMAND_ACK", COMMAND_RESULT = "COMMAND_RESULT",
    JOB_ASSIGN = "JOB_ASSIGN", JOB_ACK = "JOB_ACK", JOB_STATUS = "JOB_STATUS", JOB_RESULT = "JOB_RESULT",
    DEVICE_INFO_REQUEST = "DEVICE_INFO_REQUEST", DEVICE_INFO = "DEVICE_INFO", DEVICE_CONFIG_SET = "DEVICE_CONFIG_SET", DEVICE_CONFIG_ACK = "DEVICE_CONFIG_ACK",
    DEVICE_UPDATE_REQUEST = "DEVICE_UPDATE_REQUEST", DEVICE_UPDATE_RESULT = "DEVICE_UPDATE_RESULT",
  },
}

local known = {}
for _, value in pairs(Protocol.types) do known[value] = true end

local function identity(value)
  return type(value) == "table" and type(value.id) == "number" and value.id % 1 == 0
end
local function commandId(value) return type(value) == "string" and #value > 0 and #value <= 64 end

function Protocol.statusValid(payload)
  if type(payload) ~= "table" or type(payload.turtle_id) ~= "number" or payload.turtle_id % 1 ~= 0 then return false end
  if payload.label ~= nil and type(payload.label) ~= "string" then return false end
  if type(payload.state) ~= "string" or (type(payload.fuel_level) ~= "number" and payload.fuel_level ~= "unlimited") then return false end
  if type(payload.inventory_used) ~= "number" or payload.inventory_used < 0 or payload.inventory_used % 1 ~= 0 then return false end
  if type(payload.inventory_slots) ~= "number" or payload.inventory_slots < payload.inventory_used or payload.inventory_slots % 1 ~= 0 then return false end
  if payload.position ~= nil and (type(payload.position) ~= "table" or type(payload.position.x) ~= "number" or type(payload.position.y) ~= "number" or type(payload.position.z) ~= "number") then return false end
  if payload.job_id ~= nil and type(payload.job_id) ~= "string" then return false end
  if payload.job_type ~= nil and payload.job_type ~= "MINING" then return false end
  if payload.job_lifecycle ~= nil and type(payload.job_lifecycle) ~= "string" then return false end
  if payload.job_distance ~= nil and (type(payload.job_distance) ~= "number" or payload.job_distance < 1 or payload.job_distance % 1 ~= 0) then return false end
  if payload.pending_command ~= nil and payload.pending_command ~= "RETURN_HOME" and payload.pending_command ~= "UNLOAD" and payload.pending_command ~= "PAUSE" and payload.pending_command ~= "RESUME" then return false end
  return type(payload.software_version) == "string" and type(payload.protocol_version) == "number"
end

function Protocol.jobAssignValid(payload)
  return type(payload) == "table" and commandId(payload.job_id) and type(payload.target_id) == "number" and payload.target_id % 1 == 0 and
    type(payload.issued_by) == "number" and payload.issued_by % 1 == 0 and type(payload.job) == "table" and payload.job.type == "MINING" and
    type(payload.job.distance) == "number" and payload.job.distance > 0 and payload.job.distance % 1 == 0
end
function Protocol.jobAckValid(payload)
  return type(payload) == "table" and commandId(payload.job_id) and type(payload.target_id) == "number" and
    (payload.status == "ACCEPTED" or payload.status == "REJECTED" or payload.status == "BUSY" or payload.status == "INVALID") and
    (payload.reason == nil or type(payload.reason) == "string")
end
function Protocol.jobStatusValid(payload)
  return type(payload) == "table" and commandId(payload.job_id) and payload.job_type == "MINING" and type(payload.lifecycle) == "string" and
    type(payload.distance) == "number" and payload.distance > 0 and payload.distance % 1 == 0
end
function Protocol.jobResultValid(payload)
  return type(payload) == "table" and commandId(payload.job_id) and type(payload.target_id) == "number" and
    (payload.status == "SUCCESS" or payload.status == "FAILED" or payload.status == "CANCELLED") and
    (payload.reason == nil or type(payload.reason) == "string")
end
function Protocol.deviceInfoRequestValid(payload)
  return type(payload) == "table" and type(payload.target_id) == "number" and type(payload.issued_by) == "number"
end
function Protocol.deviceInfoValid(payload)
  return type(payload) == "table" and type(payload.computer_id) == "number" and type(payload.device_name) == "string" and type(payload.device_type) == "string" and
    type(payload.role) == "string" and type(payload.auto_start) == "boolean" and type(payload.software_version) == "string" and type(payload.config_revision) == "number"
end
function Protocol.deviceConfigSetValid(payload)
  return type(payload) == "table" and commandId(payload.request_id) and type(payload.target_id) == "number" and type(payload.issued_by) == "number" and type(payload.changes) == "table" and
    (payload.expected_revision == nil or type(payload.expected_revision) == "number")
end
function Protocol.deviceConfigAckValid(payload)
  return type(payload) == "table" and commandId(payload.request_id) and type(payload.target_id) == "number" and
    (payload.status == "SUCCESS" or payload.status == "INVALID" or payload.status == "BUSY" or payload.status == "FAILED" or payload.status == "REJECTED") and
    (payload.reason == nil or type(payload.reason) == "string")
end
function Protocol.deviceUpdateRequestValid(payload)
  return type(payload) == "table" and commandId(payload.request_id) and type(payload.target_id) == "number" and type(payload.issued_by) == "number"
end
function Protocol.deviceUpdateResultValid(payload)
  return type(payload) == "table" and commandId(payload.request_id) and type(payload.target_id) == "number" and
    (payload.status == "SUCCESS" or payload.status == "FAILED" or payload.status == "BUSY" or payload.status == "REJECTED") and
    (payload.reason == nil or type(payload.reason) == "string") and (payload.restart_required == nil or type(payload.restart_required) == "boolean")
end

function Protocol.commandValid(payload)
  return type(payload) == "table" and commandId(payload.command_id) and (payload.command == "RETURN_HOME" or payload.command == "UNLOAD" or payload.command == "PAUSE" or payload.command == "RESUME") and
    type(payload.target_id) == "number" and payload.target_id % 1 == 0 and type(payload.issued_by) == "number" and payload.issued_by % 1 == 0
end
function Protocol.commandAckValid(payload)
  return type(payload) == "table" and commandId(payload.command_id) and (payload.command == "RETURN_HOME" or payload.command == "UNLOAD" or payload.command == "PAUSE" or payload.command == "RESUME") and
    type(payload.target_id) == "number" and (payload.status == "ACCEPTED" or payload.status == "REJECTED" or payload.status == "BUSY" or payload.status == "INVALID") and
    (payload.reason == nil or type(payload.reason) == "string")
end
function Protocol.commandResultValid(payload)
  return type(payload) == "table" and commandId(payload.command_id) and (payload.command == "RETURN_HOME" or payload.command == "UNLOAD" or payload.command == "PAUSE" or payload.command == "RESUME") and
    type(payload.target_id) == "number" and (payload.status == "SUCCESS" or payload.status == "FAILED" or payload.status == "CANCELLED") and
    (payload.reason == nil or type(payload.reason) == "string")
end

function Protocol.message(kind, sender, payload)
  if not known[kind] then return nil, "unknown message type" end
  if not identity(sender) then return nil, "sender id is required" end
  return { protocol = Protocol.id, version = Protocol.version, type = kind, sender = { id = sender.id, label = sender.label }, payload = payload }
end

function Protocol.valid(message)
  if type(message) ~= "table" or message.protocol ~= Protocol.id or message.version ~= Protocol.version then return false end
  if not known[message.type] or not identity(message.sender) then return false end
  if message.sender.label ~= nil and type(message.sender.label) ~= "string" then return false end
  if type(message.payload) ~= "table" then return false end
  if message.type == Protocol.types.STATUS or message.type == Protocol.types.HELLO_ACK or message.type == Protocol.types.PONG then return Protocol.statusValid(message.payload) end
  if message.type == Protocol.types.COMMAND then return Protocol.commandValid(message.payload) end
  if message.type == Protocol.types.COMMAND_ACK then return Protocol.commandAckValid(message.payload) end
  if message.type == Protocol.types.COMMAND_RESULT then return Protocol.commandResultValid(message.payload) end
  if message.type == Protocol.types.JOB_ASSIGN then return Protocol.jobAssignValid(message.payload) end
  if message.type == Protocol.types.JOB_ACK then return Protocol.jobAckValid(message.payload) end
  if message.type == Protocol.types.JOB_STATUS then return Protocol.jobStatusValid(message.payload) end
  if message.type == Protocol.types.JOB_RESULT then return Protocol.jobResultValid(message.payload) end
  if message.type == Protocol.types.DEVICE_INFO_REQUEST then return Protocol.deviceInfoRequestValid(message.payload) end
  if message.type == Protocol.types.DEVICE_INFO then return Protocol.deviceInfoValid(message.payload) end
  if message.type == Protocol.types.DEVICE_CONFIG_SET then return Protocol.deviceConfigSetValid(message.payload) end
  if message.type == Protocol.types.DEVICE_CONFIG_ACK then return Protocol.deviceConfigAckValid(message.payload) end
  if message.type == Protocol.types.DEVICE_UPDATE_REQUEST then return Protocol.deviceUpdateRequestValid(message.payload) end
  if message.type == Protocol.types.DEVICE_UPDATE_RESULT then return Protocol.deviceUpdateResultValid(message.payload) end
  return true
end

return Protocol

local Protocol = {
  id = "ralfie:mining:v1",
  version = 1,
  types = {
    HELLO = "HELLO", HELLO_ACK = "HELLO_ACK", STATUS_REQUEST = "STATUS_REQUEST",
    STATUS = "STATUS", PING = "PING", PONG = "PONG", COMMAND = "COMMAND",
    COMMAND_ACK = "COMMAND_ACK", COMMAND_RESULT = "COMMAND_RESULT",
  },
}

local known = {}
for _, value in pairs(Protocol.types) do known[value] = true end

local function identity(value)
  return type(value) == "table" and type(value.id) == "number" and value.id % 1 == 0
end

function Protocol.statusValid(payload)
  if type(payload) ~= "table" or type(payload.turtle_id) ~= "number" or payload.turtle_id % 1 ~= 0 then return false end
  if payload.label ~= nil and type(payload.label) ~= "string" then return false end
  if type(payload.state) ~= "string" or (type(payload.fuel_level) ~= "number" and payload.fuel_level ~= "unlimited") then return false end
  if type(payload.inventory_used) ~= "number" or payload.inventory_used < 0 or payload.inventory_used % 1 ~= 0 then return false end
  if type(payload.inventory_slots) ~= "number" or payload.inventory_slots < payload.inventory_used or payload.inventory_slots % 1 ~= 0 then return false end
  if payload.position ~= nil and (type(payload.position) ~= "table" or type(payload.position.x) ~= "number" or type(payload.position.y) ~= "number" or type(payload.position.z) ~= "number") then return false end
  if payload.job_id ~= nil and type(payload.job_id) ~= "string" then return false end
  if payload.pending_command ~= nil and payload.pending_command ~= "RETURN_HOME" and payload.pending_command ~= "UNLOAD" and payload.pending_command ~= "PAUSE" and payload.pending_command ~= "RESUME" then return false end
  return type(payload.software_version) == "string" and type(payload.protocol_version) == "number"
end

local function commandId(value) return type(value) == "string" and #value > 0 and #value <= 64 end
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
  return true
end

return Protocol

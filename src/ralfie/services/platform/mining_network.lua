local MiningNetwork = {}

function MiningNetwork.new(options)
  local network = {
    protocol = assert(options.protocol, "mining network requires protocol"), rednet = options.rednet,
    peripheral = options.peripheral, os = options.os or os, status = assert(options.status, "mining network requires status"),
    logger = options.logger, heartbeat_interval = options.heartbeat_interval or 15, opened = false, last_heartbeat = nil,
    command_handler = options.command_handler, job_handler = options.job_handler, device_handler = options.device_handler, label_reader = options.label_reader,
  }

  local function log(level, event, context)
    if network.logger and network.logger[level] then pcall(network.logger[level], network.logger, event, context) end
  end
  function network:identity()
    local label = self.label_reader and self.label_reader() or (self.os.getComputerLabel and self.os.getComputerLabel() or nil)
    return { id = self.os.getComputerID(), label = label }
  end
  function network:send(recipient, kind, payload)
    if not self.opened then return false end
    local message = self.protocol.message(kind, self:identity(), payload)
    if not message then return false end
    local called, sent = pcall(self.rednet.send, recipient, message, self.protocol.id)
    return called and sent == true
  end
  function network:statusPayload()
    local payload = self.status:read()
    payload.turtle_id = self:identity().id
    payload.label = self:identity().label
    payload.protocol_version = self.protocol.version
    return payload
  end
  function network:start()
    if self.opened then return true end
    if not self.rednet or not self.peripheral or type(self.peripheral.getNames) ~= "function" then return false end
    local listed, names = pcall(self.peripheral.getNames)
    if not listed or type(names) ~= "table" then return false end
    for _, side in ipairs(names) do
      local wrapped, modem = pcall(self.peripheral.wrap, side)
      local checked, wireless = false, false
      if wrapped and modem and type(modem.isWireless) == "function" then checked, wireless = pcall(modem.isWireless) end
      if checked and wireless then
        local opened = pcall(self.rednet.open, side)
        if opened then self.opened = true; log("info", "mining_network.opened", { side = side }); return true end
      end
    end
    return false
  end
  function network:handle(sender, message)
    if not self.protocol.valid(message) or sender ~= message.sender.id or sender == self:identity().id then return false end
    if message.type == self.protocol.types.HELLO then
      self:send(sender, self.protocol.types.HELLO_ACK, self:statusPayload())
      self:send(sender, self.protocol.types.STATUS, self:statusPayload())
    elseif message.type == self.protocol.types.STATUS_REQUEST then
      self:send(sender, self.protocol.types.STATUS, self:statusPayload())
    elseif message.type == self.protocol.types.PING then
      self:send(sender, self.protocol.types.PONG, self:statusPayload())
    elseif message.type == self.protocol.types.COMMAND then
      if message.payload.issued_by ~= sender then return false end
      if not self.command_handler then return false end
      local handled, ack, commandResult = pcall(self.command_handler, sender, message.payload)
      if not handled or type(ack) ~= "table" then return false end
      self:send(sender, self.protocol.types.COMMAND_ACK, ack)
      if type(commandResult) == "table" then self:send(sender, self.protocol.types.COMMAND_RESULT, commandResult) end
    elseif message.type == self.protocol.types.JOB_ASSIGN then
      if message.payload.issued_by ~= sender or not self.job_handler then return false end
      local handled, ack, jobResult = pcall(self.job_handler, sender, message.payload)
      if not handled or type(ack) ~= "table" then return false end
      self:send(sender, self.protocol.types.JOB_ACK, ack)
      if type(jobResult) == "table" then self:send(sender, self.protocol.types.JOB_RESULT, jobResult) end
    elseif message.type == self.protocol.types.DEVICE_INFO_REQUEST then
      if message.payload.issued_by ~= sender or not self.device_handler then return false end
      local handled, info = pcall(self.device_handler, "INFO", sender, message.payload)
      if not handled or type(info) ~= "table" then return false end
      self:send(sender, self.protocol.types.DEVICE_INFO, info)
    elseif message.type == self.protocol.types.DEVICE_CONFIG_SET then
      if message.payload.issued_by ~= sender or not self.device_handler then return false end
      local handled, ack = pcall(self.device_handler, "CONFIG", sender, message.payload)
      if not handled or type(ack) ~= "table" then return false end
      self:send(sender, self.protocol.types.DEVICE_CONFIG_ACK, ack)
    else return false end
    return true
  end
  function network:tick(now)
    if not self:start() then return false end
    now = now or (self.os.epoch and self.os.epoch("utc") / 1000) or self.os.clock()
    local received, sender, message = pcall(self.rednet.receive, self.protocol.id, 0)
    if received and sender and message then self:handle(sender, message) end
    if not self.last_heartbeat or now - self.last_heartbeat >= self.heartbeat_interval then
      pcall(self.rednet.broadcast, self.protocol.message(self.protocol.types.STATUS, self:identity(), self:statusPayload()), self.protocol.id)
      self.last_heartbeat = now
    end
    return true
  end
  function network:wait(timeout)
    if not self:start() then return false end
    local received, sender, message = pcall(self.rednet.receive, self.protocol.id, timeout or 1)
    if received and sender and message then self:handle(sender, message) end
    return self:tick()
  end
  return network
end

return MiningNetwork

local Network = {}

function Network.new(options)
  local network = { protocol = assert(options.protocol), rednet = assert(options.rednet), peripheral = assert(options.peripheral), os = options.os or os, opened = false }
  function network:identity()
    return { id = self.os.getComputerID(), label = self.os.getComputerLabel and self.os.getComputerLabel() or nil }
  end
  function network:open()
    if self.opened then return true end
    local listed, names = pcall(self.peripheral.getNames)
    if not listed or type(names) ~= "table" then return false end
    for _, side in ipairs(names) do
      local wrapped, modem = pcall(self.peripheral.wrap, side)
      local checked, wireless = false, false
      if wrapped and modem and type(modem.isWireless) == "function" then checked, wireless = pcall(modem.isWireless) end
      if checked and wireless and pcall(self.rednet.open, side) then self.opened = true; return true end
    end
    return false
  end
  function network:broadcast(kind)
    local message = self.protocol.message(kind, self:identity(), {})
    return message and pcall(self.rednet.broadcast, message, self.protocol.id)
  end
  function network:send(recipient, kind, payload)
    if not self.opened then return false end
    local message = self.protocol.message(kind, self:identity(), payload)
    if not message then return false end
    local called, sent = pcall(self.rednet.send, recipient, message, self.protocol.id)
    return called and sent == true
  end
  function network:receive(timeout)
    local received, sender, message = pcall(self.rednet.receive, self.protocol.id, timeout or 0)
    if not received then return nil end
    return self:accept(sender, message, self.protocol.id)
  end
  function network:accept(sender, message, protocol)
    if protocol ~= self.protocol.id or not self.protocol.valid(message) or sender ~= message.sender.id or sender == self:identity().id then return nil end
    return sender, message
  end
  return network
end

return Network

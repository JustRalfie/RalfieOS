local Fleet = {}

function Fleet.new(options)
  local fleet = { miners = {}, offline_timeout = (options and options.offline_timeout) or 45, protocol = options and options.protocol }
  function fleet:record(sender, payload, now)
    if type(sender) ~= "table" or type(sender.id) ~= "number" or type(payload) ~= "table" then return false end
    if self.protocol and (not self.protocol.statusValid(payload) or payload.turtle_id ~= sender.id) then return false end
    local miner = self.miners[sender.id] or { id = sender.id }
    miner.label = payload.label or sender.label or miner.label
    miner.status = payload
    miner.last_seen = now
    miner.online = true
    self.miners[sender.id] = miner
    return true
  end
  function fleet:refresh(now)
    for _, miner in pairs(self.miners) do miner.online = now - miner.last_seen <= self.offline_timeout end
  end
  function fleet:onlineCount()
    local count = 0
    for _, miner in pairs(self.miners) do if miner.online then count = count + 1 end end
    return count
  end
  function fleet:canCommand(id)
    return self.miners[id] ~= nil and self.miners[id].online == true
  end
  function fleet:list()
    local miners = {}
    for _, miner in pairs(self.miners) do table.insert(miners, miner) end
    table.sort(miners, function(left, right) return left.id < right.id end)
    return miners
  end
  return fleet
end

return Fleet

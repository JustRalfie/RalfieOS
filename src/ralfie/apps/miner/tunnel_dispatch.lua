local TunnelDispatch = {}

local moduleNames = {
  [3] = "ralfie.apps.miner.miner",
  [5] = "ralfie.apps.miner.miner_5x5",
  [9] = "ralfie.apps.miner.miner_9x9",
}

function TunnelDispatch.validSize(size)
  return moduleNames[size] ~= nil
end

function TunnelDispatch.new(options)
  local dispatch = { module_loader = assert(options.module_loader, "tunnel dispatch requires module loader"), result = assert(options.result, "tunnel dispatch requires result") }

  function dispatch:moduleName(size)
    return moduleNames[size]
  end

  function dispatch:start(context, size, minerOptions)
    local name = self:moduleName(size)
    if not name then return self.result.fail("TUNNEL.INVALID_SIZE", "Tunnel size must be 3, 5, or 9") end
    local loaded = self.module_loader:load(name)
    if not loaded.ok then return loaded end
    return loaded.value.start(context, minerOptions or {})
  end

  return dispatch
end

return TunnelDispatch

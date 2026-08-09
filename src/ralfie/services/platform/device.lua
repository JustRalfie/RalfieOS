local Device = {}

function Device.detect(options)
  options = options or {}
  local turtleApi, pocketApi = options.turtle, options.pocket
  local terminal, peripheral, gps = options.terminal, options.peripheral, options.gps
  local kind = "COMPUTER"
  if type(turtleApi) == "table" and type(turtleApi.forward) == "function" then
    kind = terminal and terminal.isColor and terminal.isColor() and "ADVANCED_TURTLE" or "TURTLE"
  elseif type(pocketApi) == "table" then kind = "POCKET" end
  local capabilities = { wireless_modem = false, ender_modem = false, gps = type(gps) == "table" and type(gps.locate) == "function" }
  if peripheral and type(peripheral.getNames) == "function" then
    local ok, names = pcall(peripheral.getNames)
    if ok and type(names) == "table" then
      for _, side in ipairs(names) do
        local wrapped, modem = pcall(peripheral.wrap, side)
        if wrapped and modem and type(modem.isWireless) == "function" then
          local checked, wireless = pcall(modem.isWireless)
          if checked and wireless then capabilities.wireless_modem = true end
        end
      end
    end
  end
  return { type = kind, capabilities = capabilities }
end

function Device.roles(device)
  if device.type == "TURTLE" or device.type == "ADVANCED_TURTLE" then return { "MINING_WORKER", "STANDALONE_MINER", "UNCONFIGURED" } end
  if device.type == "POCKET" then return { "FLEET_CONTROLLER", "GENERAL" } end
  return { "FLEET_CONTROLLER", "GENERAL" }
end

function Device.supportsRole(device, role)
  for _, candidate in ipairs(Device.roles(device)) do if candidate == role then return true end end
  return false
end

return Device

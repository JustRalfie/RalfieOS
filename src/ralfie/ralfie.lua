local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({ turtle = turtle })
if not started.ok then
  print("RalfieOS menu could not start: " .. started.error.message)
  return started
end

local context = started.value
local function errorMessage(result, fallback)
  if type(result) == "table" and type(result.error) == "table" and type(result.error.message) == "string" then
    return result.error.message
  end
  return fallback
end

local function waitForEnter()
  context.ui:prompt("Press Enter to return:")
end

local function showResult(label, message, isError)
  context.ui:status(label, message, isError)
  waitForEnter()
end

local function safeLoad(name)
  local loaded, module = pcall(function() return context.module_loader:load(name) end)
  if not loaded then return nil, "Unable to load " .. name .. ": " .. tostring(module) end
  if type(module) ~= "table" or module.ok ~= true then
    return nil, errorMessage(module, "Unable to load " .. name)
  end
  return module.value
end

local menu, menuError = safeLoad("ralfie.interfaces.terminal.menu")
if not menu then
  showResult("ERROR", "RalfieOS menu failed to load: " .. menuError, true)
  return false
end

local deviceInfo = context.device.detect({ turtle = context.turtle, pocket = context.pocket, terminal = context.ui.terminal, peripheral = context.peripheral, gps = context.gps })
local loadedProfile = context.device_profile:load(deviceInfo)
local profile = loadedProfile.ok and loadedProfile.value or nil
local managementModule = context.module_loader:load("ralfie.services.platform.device_management")
if managementModule.ok and profile then
  context.device_manager = managementModule.value.new({ profile_service = context.device_profile, profile = profile, device = context.device, device_info = deviceInfo, os = context.os,
    get_state = function() return context.worker_state or "READY" end, get_job = function() return context.active_job_id end })
end

local function setupDevice()
  context.ui:clear(); context.ui:heading("RALFIE OS SETUP")
  context.ui:line("Detected: " .. deviceInfo.type)
  context.ui:line(deviceInfo.capabilities.wireless_modem and "Wireless Modem" or "No wireless modem")
  local entries = {}
  for _, role in ipairs(context.device.roles(deviceInfo)) do table.insert(entries, { id = role, label = role:gsub("_", " ") }) end
  table.insert(entries, { id = "cancel", label = "Cancel" })
  local role = menu.choose(context.ui, "Choose role", entries)
  if not role or role == "cancel" then return false end
  local name = context.ui:prompt("Device Name:")
  if not name or name == "" then context.ui:status("INVALID", "A device name is required.", true); return false end
  local auto = context.ui:prompt("Auto-start role? [Y/N]:"):lower() == "y"
  local saved = context.device_profile:save({ device_name = name, role = role, auto_start = auto, fleet_name = profile and profile.fleet_name or "Main", settings = {} }, deviceInfo)
  if not saved.ok then showResult("ERROR", saved.error.message, true); return false end
  profile = saved.value
  if managementModule.ok then context.device_manager = managementModule.value.new({ profile_service = context.device_profile, profile = profile, device = context.device, device_info = deviceInfo, os = context.os,
    get_state = function() return context.worker_state or "READY" end, get_job = function() return context.active_job_id end }) end
  return true
end

if not profile then setupDevice() end

local function runMiner()
  context.ui:clear()
  context.ui:heading("Tunnel Miner")
  if not context.turtle then
    showResult("UNAVAILABLE", "Tunnel Miner requires a turtle.", true)
    return
  end

  context.ui:status("START", "Starting Tunnel Miner...", false)
  local miner, loadError = safeLoad("ralfie.apps.miner.miner")
  if not miner then
    showResult("ERROR", "Tunnel Miner failed to load: " .. loadError, true)
    return
  end

  local ran, mined = xpcall(function() return miner.start(context) end, function(err) return tostring(err) end)
  if not ran then
    showResult("ERROR", "Tunnel Miner crashed: " .. mined, true)
    return
  end
  if type(mined) ~= "table" or type(mined.ok) ~= "boolean" then
    showResult("ERROR", "Tunnel Miner returned an invalid result.", true)
    return
  end
  if not mined.ok then
    showResult("STOPPED", errorMessage(mined, "Tunnel Miner failed."), true)
    return
  end
  showResult("DONE", "Tunnel Miner finished.", false)
end

local function runMiner5x5()
  context.ui:clear()
  context.ui:heading("5x5 Tunnel Miner")
  if not context.turtle then showResult("UNAVAILABLE", "5x5 Tunnel Miner requires a turtle.", true); return end
  local miner, loadError = safeLoad("ralfie.apps.miner.miner_5x5")
  if not miner then showResult("ERROR", "5x5 Tunnel Miner failed to load: " .. loadError, true); return end
  local ran, mined = xpcall(function() return miner.start(context) end, function(err) return tostring(err) end)
  if not ran then showResult("ERROR", "5x5 Tunnel Miner crashed: " .. mined, true)
  elseif not mined.ok then showResult("STOPPED", errorMessage(mined, "5x5 Tunnel Miner failed."), true)
  else showResult("DONE", "5x5 Tunnel Miner finished.", false) end
end

local function miningMenu()
  while true do
    local choice = menu.choose(context.ui, "Mining", {
      {
        id = "tunnel_miner",
        label = "Tunnel Miner",
        description = {
          "Digs a 3x3 tunnel and places torches.",
          "Returns home and dumps items into the",
          "chest behind the turtle.",
        },
      },
      {
        id = "tunnel_miner_5x5",
        label = "5x5 Tunnel Miner",
        description = {
          "Digs a large 5x5 tunnel with ore chasing,",
          "fluid safety, unloading, and recovery.",
        },
      },
      {
        id = "fleet_worker",
        label = "Fleet Worker",
        description = {
          "Waits for a Pocket Computer to assign",
          "one remote mining-distance job at a time.",
        },
      },
      { id = "back", label = "Back" },
    })
    if choice == "tunnel_miner" then runMiner() end
    if choice == "tunnel_miner_5x5" then runMiner5x5() end
    if choice == "fleet_worker" then
      local worker, loadError = safeLoad("ralfie.apps.miner.fleet_worker")
      if not worker then showResult("ERROR", "Fleet Worker failed to load: " .. loadError, true)
      else
        context.ui:status("READY", "Fleet Worker waiting for jobs.", false)
        local ran, result = xpcall(function() return worker.start(context) end, function(err) return tostring(err) end)
        if not ran then showResult("ERROR", "Fleet Worker crashed: " .. result, true)
        elseif not result.ok then showResult("STOPPED", errorMessage(result, "Fleet Worker stopped."), true) end
      end
    end
    if choice == "back" then return end
  end
end

local function runFleetWorker()
  if not context.turtle then showResult("UNAVAILABLE", "Fleet Worker requires a turtle.", true); return end
  local worker, loadError = safeLoad("ralfie.apps.miner.fleet_worker")
  if not worker then showResult("ERROR", "Fleet Worker failed to load: " .. loadError, true); return end
  local ran, result = xpcall(function() return worker.start(context) end, function(err) return tostring(err) end)
  if not ran then showResult("ERROR", "Fleet Worker crashed: " .. result, true)
  elseif not result.ok then showResult("STOPPED", errorMessage(result, "Fleet Worker stopped."), true) end
end

local function runFleetCommand()
  if not deviceInfo.capabilities.wireless_modem then showResult("NO MODEM", "Fleet Command requires a wireless modem.", true); return end
  local ran, result = xpcall(function() return dofile(context.runtime_root .. "/pocket/main.lua") end, function(err) return tostring(err) end)
  if not ran then showResult("ERROR", "Fleet Command crashed: " .. result, true) end
end

local function dashboard()
  context.ui:clear(); context.ui:heading("DEVICE DASHBOARD")
  context.ui:line("Device: " .. (profile and profile.device_name or "Unconfigured"))
  context.ui:line("Type: " .. deviceInfo.type)
  context.ui:line("Role: " .. (profile and profile.role or "UNCONFIGURED"))
  context.ui:line("Network: " .. (deviceInfo.capabilities.wireless_modem and "ONLINE" or "NO MODEM"))
  waitForEnter()
end

local function updateSystem()
  local updated = dofile(context.runtime_root .. "/update.lua")
  if not updated or not updated.ok then context.ui:status("UPDATE", "Update failed; see message above.", true) end
end

if profile and profile.role == "MINING_WORKER" and profile.auto_start then
  runFleetWorker()
end

while true do
  local controller = profile and profile.role == "FLEET_CONTROLLER"
  local title = "RALFIE OS 0.3 - " .. (profile and profile.device_name or deviceInfo.type)
  local choice = menu.choose(context.ui, title, controller and {
    { id = "fleet", label = "Fleet" }, { id = "setup", label = "Device Setup" }, { id = "dashboard", label = "Devices" }, { id = "update", label = "Update" }, { id = "exit", label = "Exit" },
  } or {
    { id = "dashboard", label = "Dashboard" }, { id = "mining", label = "Mining" }, { id = "fleet", label = "Fleet" }, { id = "setup", label = "Device Setup" }, { id = "update", label = "Update" }, { id = "exit", label = "Exit" },
  })
  if choice == "dashboard" then dashboard() end
  if choice == "mining" then miningMenu() end
  if choice == "fleet" then
    if profile and profile.role == "MINING_WORKER" then runFleetWorker() else runFleetCommand() end
  end
  if choice == "setup" then setupDevice() end
  if choice == "update" then updateSystem() end
  if choice == "exit" then return true end
end

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
  if context.ui.waitBack then return context.ui:waitBack() end
  context.ui:prompt("[Enter/B] Back:")
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
local profileExistedAtBoot = profile ~= nil
local managementModule = context.module_loader:load("ralfie.services.platform.device_management")
if managementModule.ok and profile then
  context.device_manager = managementModule.value.new({ profile_service = context.device_profile, profile = profile, device = context.device, device_info = deviceInfo, os = context.os,
    get_state = function() return context.worker_state or "READY" end, get_job = function() return context.active_job_id end, get_software_version = context.software_version })
end

local function setupDevice()
  local isTurtle = deviceInfo.type == "TURTLE" or deviceInfo.type == "ADVANCED_TURTLE"
  local function ask(label, initial)
    if context.ui.input then return context.ui:input("RALFIE OS SETUP", label, initial) end
    return context.ui:prompt(label)
  end
  local name, workerEnabled, auto, fleet = "", false, false, "Main"
  local step = 1
  local lastStep = isTurtle and 4 or 2
  while step <= lastStep do
    local value
    if step == 1 then
      value = ask("Device Name:", name)
      if value == nil then return false end
      if value == "" then context.ui:status("INVALID", "A device name is required.", true) else name = value; step = step + 1 end
    elseif isTurtle and step == 2 then
      value = ask("Enable Fleet Worker? [Y/N]:", workerEnabled and "Y" or "N")
      if value == nil then step = step - 1 else workerEnabled = value:lower() == "y"; step = workerEnabled and step + 1 or 4 end
    elseif isTurtle and step == 3 then
      value = ask("Auto-start Worker next boot? [Y/N]:", auto and "Y" or "N")
      if value == nil then step = step - 1 else auto = value:lower() == "y"; step = step + 1 end
    else
      value = ask("Fleet Name [Main]:", fleet)
      if value == nil then step = isTurtle and (workerEnabled and 3 or 2) or 1 else fleet = value == "" and "Main" or value; step = step + 1 end
    end
  end
  if fleet == "" then fleet = "Main" end
  local role = workerEnabled and "MINING_WORKER" or (isTurtle and "UNCONFIGURED" or (deviceInfo.type == "POCKET" and "FLEET_CONTROLLER" or "GENERAL"))
  local saved = context.device_profile:save({ device_name = name, role = role, auto_start = auto, fleet_name = fleet, settings = {}, config_revision = 0 }, deviceInfo)
  if not saved.ok then showResult("ERROR", saved.error.message, true); return false end
  profile = saved.value
  if managementModule.ok then context.device_manager = managementModule.value.new({ profile_service = context.device_profile, profile = profile, device = context.device, device_info = deviceInfo, os = context.os,
    get_state = function() return context.worker_state or "READY" end, get_job = function() return context.active_job_id end, get_software_version = context.software_version }) end
  return true
end

if not profile then setupDevice() end

local dashboard

local function runTunnelMiner(size, distance)
  context.ui:clear()
  context.ui:heading(size .. "x" .. size .. " Tunnel Miner")
  if not context.turtle then
    showResult("UNAVAILABLE", "Tunnel Miner requires a turtle.", true)
    return
  end

  context.ui:status("START", "Starting " .. size .. "x" .. size .. " Tunnel Miner...", false)
  local moduleName = size == 3 and "ralfie.apps.miner.miner" or (size == 5 and "ralfie.apps.miner.miner_5x5" or "ralfie.apps.miner.miner_9x9")
  local miner, loadError = safeLoad(moduleName)
  if not miner then
    showResult("ERROR", "Tunnel Miner failed to load: " .. loadError, true)
    return
  end

  local ran, mined = xpcall(function() return miner.start(context, { distance = distance }) end, function(err) return tostring(err) end)
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
  showResult("DONE", size .. "x" .. size .. " Tunnel Miner finished.", false)
end

local function tunnelMenu()
  while true do
    local choice = menu.choose(context.ui, "NEW TUNNEL", {
      { id = "3", label = "3x3" }, { id = "5", label = "5x5" }, { id = "9", label = "9x9" },
      { id = "back", label = "Back" },
    }, { header = { "Choose Size" } })
    local size = tonumber(choice)
    if choice == "back" or not size then return end
    local raw
    if context.ui.input then raw = context.ui:input("NEW TUNNEL", "Size: " .. size .. "x" .. size .. "  Distance:", "")
    else raw = context.ui:prompt("Tunnel distance:") end
    if raw ~= nil then
      local distance = tonumber(raw)
      if not distance or distance < 1 or distance % 1 ~= 0 then
        showResult("INVALID", "Distance must be a positive whole number.", true)
      else
        local confirmed = menu.choose(context.ui, "START TUNNEL?", { { id = "start", label = "Start" }, { id = "back", label = "Back" } }, {
          header = { "Size: " .. size .. "x" .. size, "Distance: " .. distance },
        })
        if confirmed == "start" then runTunnelMiner(size, distance); return end
      end
    end
  end
end

local function miningMenu()
  while true do
    local choice = menu.choose(context.ui, "MINING", {
      {
        id = "tunnel_miner",
        label = "New Tunnel",
        description = {
          "Choose a 3x3, 5x5, or 9x9 tunnel.",
          "Each uses the existing mining engine.",
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
      { id = "status", label = "Miner Status" },
      { id = "back", label = "Back" },
    })
    if choice == "tunnel_miner" then tunnelMenu() end
    if choice == "status" then dashboard() end
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

dashboard = function()
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

local function settingsMenu()
  while true do
    local choice = menu.choose(context.ui, "SETTINGS", { { id = "device", label = "Device" }, { id = "worker", label = "Worker" }, { id = "back", label = "Back" } })
    if choice == "device" then setupDevice() end
    if choice == "worker" then showResult("SETTINGS", "Worker configuration is managed by the active worker profile.", false) end
    if choice == "back" then return end
  end
end

local function systemMenu()
  while true do
    local choice = menu.choose(context.ui, "SYSTEM", { { id = "update", label = "Update" }, { id = "info", label = "Device Information" }, { id = "setup", label = "Reconfigure" }, { id = "about", label = "About RalfieOS" }, { id = "back", label = "Back" } })
    if choice == "update" then updateSystem() end
    if choice == "info" then dashboard() end
    if choice == "setup" then setupDevice() end
    if choice == "about" then showResult("RALFIE OS", "RalfieOS 0.3", false) end
    if choice == "back" then return end
  end
end

local function friendlyRole(role)
  if role == "MINING_WORKER" then return "Mining Worker" end
  if role == "FLEET_CONTROLLER" then return "Fleet Controller" end
  if role == "UNCONFIGURED" then return "Unconfigured" end
  return "General"
end

local function rootMenuOptions(controller)
  local network = deviceInfo.capabilities.wireless_modem and "ONLINE" or "NO MODEM"
  local headers = {
    (profile and profile.device_name or deviceInfo.type) .. "  " .. friendlyRole(profile and profile.role),
    "Network: " .. network,
  }
  local footer = "Up/Down Enter"
  if not controller and context.turtle and context.turtle.getFuelLevel then
    local fuel = select(2, pcall(context.turtle.getFuelLevel))
    local used = 0
    if context.turtle.getItemCount then
      for slot = 1, 16 do
        local ok, count = pcall(context.turtle.getItemCount, slot)
        if ok and count > 0 then used = used + 1 end
      end
    end
    footer = "Fuel " .. tostring(fuel or "?") .. "  Inv " .. used .. "/16"
  end
  return { header = headers, footer = footer }
end

if profileExistedAtBoot and profile and profile.role == "MINING_WORKER" and profile.auto_start then
  runFleetWorker()
end

if profile and profile.role == "FLEET_CONTROLLER" then runFleetCommand() end

while true do
  local controller = profile and profile.role == "FLEET_CONTROLLER"
  local title = "RALFIE OS 0.3 - " .. (profile and profile.device_name or deviceInfo.type)
  local choice = menu.choose(context.ui, title, controller and {
    { id = "fleet", label = "Fleet" }, { id = "settings", label = "Controller Settings" }, { id = "system", label = "System" }, { id = "exit", label = "Exit" },
  } or {
    { id = "mining", label = "Mining" }, { id = "fleet", label = "Fleet" }, { id = "settings", label = "Settings" }, { id = "system", label = "System" }, { id = "exit", label = "Exit" },
  }, rootMenuOptions(controller))
  if choice == "mining" then miningMenu() end
  if choice == "fleet" then
    if profile and profile.role == "MINING_WORKER" then runFleetWorker() else runFleetCommand() end
  end
  if choice == "settings" then settingsMenu() end
  if choice == "system" then systemMenu() end
  if choice == "exit" then return true end
end

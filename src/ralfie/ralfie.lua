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
      { id = "back", label = "Back" },
    })
    if choice == "tunnel_miner" then runMiner() end
    if choice == "back" then return end
  end
end

while true do
  local choice = menu.choose(context.ui, "RalfieOS", {
    { id = "mining", label = "Mining" },
    { id = "update", label = "Update" },
    { id = "exit", label = "Exit" },
  })
  if choice == "mining" then miningMenu() end
  if choice == "update" then
    local updated = dofile("/ralfie/update.lua")
    if not updated or not updated.ok then context.ui:status("UPDATE", "Update failed; see message above.", true) end
  end
  if choice == "exit" then return true end
end

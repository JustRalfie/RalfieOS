local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({ turtle = turtle })
if not started.ok then
  print("RalfieOS menu could not start: " .. started.error.message)
  return started
end

local context = started.value
local menuModule = context.module_loader:load("ralfie.interfaces.terminal.menu")
if not menuModule.ok then
  print("RalfieOS menu failed to load: " .. menuModule.error.message)
  return menuModule
end
local menu = menuModule.value

local function runMiner()
  if not context.turtle then
    context.ui:status("UNAVAILABLE", "Tunnel Miner requires a turtle.", true)
    return
  end
  local minerModule = context.module_loader:load("ralfie.apps.miner.miner")
  if not minerModule.ok then
    context.ui:status("ERROR", minerModule.error.message, true)
    return
  end
  local mined = minerModule.value.start(context)
  if not mined.ok then context.ui:status("STOPPED", mined.error.message, true) end
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

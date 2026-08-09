local Ui = dofile("src/ralfie/pocket/ui.lua")

local function terminal(width, height)
  local lines, cursor = {}, { 1, 1 }
  return {
    clear = function() lines = {} end,
    getSize = function() return width, height end,
    setCursorPos = function(x, y) cursor = { x, y } end,
    write = function(text) lines[cursor[2]] = tostring(text) end,
    lines = function() return lines end,
  }
end

local function has(lines, text)
  for _, line in pairs(lines) do if line:find(text, 1, true) then return true end end
  return false
end

local savedOs, savedKeys = _G.os, _G.keys
_G.keys = { enter = 1, escape = 2, backspace = 3, b = 4, n = 5, y = 6, up = 7, down = 8 }
local events = { { "char", "B" }, { "char", "1" }, { "key", keys.backspace }, { "char", "2" }, { "key", keys.enter } }
_G.os = { pullEvent = function() local event = table.remove(events, 1); return event[1], event[2] end }
local inputScreen = terminal(26, 12)
assert(Ui.input(inputScreen, "INPUT", "Value", "") == "B2", "Backspace must edit input while B remains ordinary text")
events = { { "key", keys.escape } }
assert(Ui.input(inputScreen, "INPUT", "Value", "") == nil, "Escape must cancel input")
events = { { "key", keys.escape } }
assert(Ui.confirm(inputScreen, "CONFIRM", {}) == false, "Escape must cancel confirmation")
events = { { "key", keys.down }, { "key", keys.enter } }
local chosen = Ui.choose(inputScreen, "NEW JOB", { { id = "3", label = "3x3" }, { id = "5", label = "5x5" }, { id = "9", label = "9x9" } }, { "Tunnel Size" })
assert(chosen == "5", "Pocket New Job tunnel picker must support arrow selection")
assert(has(inputScreen.lines(), "Tunnel Size"), "tunnel picker must identify the selected job parameter")
events = { { "key", keys.b } }
assert(Ui.choose(inputScreen, "NEW JOB", { { id = "3", label = "3x3" } }) == nil, "Pocket New Job tunnel picker must provide Back")
assert(Ui.isBackKey(keys.b) and Ui.isBackKey(keys.backspace) and not Ui.isBackKey(keys.escape))
_G.os, _G.keys = savedOs, savedKeys

local running = { id = 17, label = "Steve", online = true, status = { state = "CHASING_ORE", job_id = "job-secret-42", job_tunnel_size = 5, job_distance = 100, fuel_level = 8421, inventory_used = 6, inventory_slots = 16 } }
assert(Ui.userState(running) == "MINING")
assert(Ui.commandForKey(running, "p") == "PAUSE")
assert(Ui.commandForKey(running, "c") == nil)
local screen = terminal(26, 20)
Ui.command(screen, running)
assert(has(screen.lines(), "MINING"))
assert(has(screen.lines(), "Tunnel    5x5"))
assert(has(screen.lines(), "Distance  100"))
assert(has(screen.lines(), "Pause"))
assert(has(screen.lines(), "Recall"))
assert(not has(screen.lines(), "job-secret-42"))
assert(not has(screen.lines(), "Resume"))

local paused = { id = 17, online = true, status = { state = "PAUSED", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
assert(Ui.commandForKey(paused, "c") == "RESUME")
assert(Ui.commandForKey(paused, "p") == nil)
assert(Ui.deviceActions(paused)[1].label == "Continue")
assert(Ui.deviceActions(paused)[2].label == "Recall")

local ready = { id = 17, online = true, status = { state = "READY", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
assert(Ui.commandForKey(ready, "j") == nil)
screen = terminal(20, 12)
Ui.command(screen, ready)
assert(has(screen.lines(), "New Job"))
assert(has(screen.lines(), "Settings"))
assert(has(screen.lines(), "Back"), "narrow Pocket details must keep Back visible")

local failed = { id = 17, online = true, status = { state = "ERROR", reason = "Return path blocked", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
screen = terminal(26, 12)
Ui.command(screen, failed)
assert(has(screen.lines(), "Return path blocked"))
assert(has(screen.lines(), "Details"))

screen = terminal(40, 20)
running.device_info = { role = "MINING_WORKER", fleet_name = "Main", software_version = "0.3.1" }
Ui.details(screen, running)
assert(has(screen.lines(), "job-secret-42"))
assert(has(screen.lines(), "Internal    CHASING_ORE"), "raw state belongs in Details only")

screen = terminal(26, 12)
Ui.settings(screen, running, 2)
assert(has(screen.lines(), "Device Name"))
assert(has(screen.lines(), "Fleet"))
assert(has(screen.lines(), "Back"))

local fleet = {
  onlineCount = function() return 1 end,
  list = function() return { ready } end,
}
screen = terminal(40, 12)
Ui.update(screen, fleet, { pending = {}, results = { [17] = { status = "BUSY" } } }, 1)
assert(has(screen.lines(), "FLEET UPDATE"))
assert(has(screen.lines(), "BUSY"))
assert(has(screen.lines(), "Back"))

screen = terminal(40, 12)
Ui.update(screen, fleet, { target_version = "0.3.6", targets = { [17] = true }, pending = { [17] = { stage = "DOWNLOADING", completed_files = 14, total_files = 20 } }, results = {}, remote_total = 1, remote_complete = 0 }, 1)
assert(has(screen.lines(), "Target: v0.3.6"))
assert(has(screen.lines(), "Downloading") and has(screen.lines(), "14/20"), "update progress must show completed manifest files")
assert(has(screen.lines(), "Remote: 0/1 complete"))
screen = terminal(40, 12)
Ui.update(screen, fleet, { target_version = "0.3.6", targets = { [17] = true }, pending = {}, results = { [17] = { status = "VERIFIED", version = "0.3.6" } }, remote_total = 1, remote_complete = 1, resolved = true }, 1)
assert(has(screen.lines(), "Verified v0.3.6") and has(screen.lines(), "Update Pocket"))

screen = terminal(26, 12)
Ui.render(screen, fleet, 17)
assert(has(screen.lines(), "MAIN FLEET"))
assert(has(screen.lines(), "1 Turtles"))
assert(has(screen.lines(), "[M] Menu"))

screen = terminal(40, 12)
ready.status.software_version = "0.3.6"
Ui.render(screen, fleet, 17)
assert(has(screen.lines(), "v0.3.6"), "wide fleet rows must expose the installed worker version")
screen = terminal(40, 12)
Ui.controllerMenu(screen, 1)
assert(has(screen.lines(), "v0.3.8") and has(screen.lines(), "Back"))

print("pocket UI tests passed")

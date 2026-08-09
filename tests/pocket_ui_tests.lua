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

local running = { id = 17, label = "Steve", online = true, status = { state = "CHASING_ORE", job_id = "job-secret-42", job_distance = 100, fuel_level = 8421, inventory_used = 6, inventory_slots = 16 } }
assert(Ui.userState(running) == "MINING")
assert(Ui.commandForKey(running, "p") == "PAUSE")
assert(Ui.commandForKey(running, "c") == nil)
local screen = terminal(26, 20)
Ui.command(screen, running)
assert(has(screen.lines(), "MINING"))
assert(has(screen.lines(), "Distance: 100"))
assert(has(screen.lines(), "[P] Pause"))
assert(has(screen.lines(), "[R] Recall"))
assert(not has(screen.lines(), "job-secret-42"))
assert(not has(screen.lines(), "Resume"))

local paused = { id = 17, online = true, status = { state = "PAUSED", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
assert(Ui.commandForKey(paused, "c") == "RESUME")
assert(Ui.commandForKey(paused, "p") == nil)

local ready = { id = 17, online = true, status = { state = "READY", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
assert(Ui.commandForKey(ready, "j") == nil)
screen = terminal(20, 12)
Ui.command(screen, ready)
assert(has(screen.lines(), "[J] New Job"))
assert(has(screen.lines(), "[S] Setup"))

local failed = { id = 17, online = true, status = { state = "ERROR", reason = "Return path blocked", fuel_level = 1, inventory_used = 0, inventory_slots = 16 } }
screen = terminal(20, 12)
Ui.command(screen, failed)
assert(has(screen.lines(), "Return path blocked"))
assert(has(screen.lines(), "Details"))

screen = terminal(26, 20)
running.device_info = { role = "MINING_WORKER", fleet_name = "Main", software_version = "0.3.1" }
Ui.info(screen, running)
assert(has(screen.lines(), "job-secret-42"))

print("pocket UI tests passed")

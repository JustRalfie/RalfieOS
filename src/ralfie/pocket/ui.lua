local Ui = {}
Ui.VERSION = "0.3.10"

function Ui.isBackKey(key) return key == keys.b or key == keys.backspace end

function Ui.fuelText(value)
  if value == "unlimited" then return "Unlimited" end
  if type(value) == "number" then return tostring(value) end
  return "?"
end

local function writeLine(terminal, line, text, selected)
  local width, height = terminal.getSize()
  if line > height then return end
  terminal.setCursorPos(1, line)
  local value = tostring(text)
  if selected then value = "> " .. value else value = "  " .. value end
  terminal.write(value:sub(1, width))
end

local function normalized(state) return tostring(state or "UNKNOWN"):upper():gsub("[%s%-]", "_") end

function Ui.userState(miner)
  if not miner or not miner.online then return "OFFLINE" end
  local state = normalized((miner.status or {}).state)
  if state == "CHASING_ORE" or state == "ORE" or state == "MINE" or state == "RUNNING" then return "MINING" end
  if state == "RETURNING_HOME" or state == "RETURN" then return "RETURNING" end
  if state == "DUMP" then return "UNLOADING" end
  if state == "RESUME" then return "MINING" end
  if state == "COMPLETE" then return "READY" end
  if state == "FAILED" then return "ERROR" end
  return state
end

function Ui.deviceActions(miner)
  local state = Ui.userState(miner)
  local actions = {}
  if state == "READY" then actions = { { id = "job", label = "New Job" }, { id = "settings", label = "Settings" } }
  elseif state == "PAUSED" then actions = { { id = "RESUME", label = "Continue" }, { id = "RETURN_HOME", label = "Recall" }, { id = "details", label = "Details" } }
  elseif state == "MINING" then actions = { { id = "PAUSE", label = "Pause" }, { id = "UNLOAD", label = "Unload" }, { id = "RETURN_HOME", label = "Recall" }, { id = "details", label = "Details" } }
  elseif state == "UNLOADING" then actions = { { id = "PAUSE", label = "Pause" }, { id = "RETURN_HOME", label = "Recall" }, { id = "details", label = "Details" } }
  elseif state == "RETURNING" then actions = { { id = "details", label = "Details" } }
  elseif state == "ERROR" or state == "OFFLINE" then actions = { { id = "details", label = "Details" } }
  else actions = { { id = "details", label = "Details" } } end
  table.insert(actions, { id = "back", label = "Back" })
  return actions
end

function Ui.commandForKey(miner, key)
  local map = { p = "PAUSE", u = "UNLOAD", r = "RETURN_HOME", c = "RESUME" }
  local wanted = map[key]
  for _, action in ipairs(Ui.deviceActions(miner)) do if action.id == wanted then return wanted end end
  return nil
end

local function summary(fleet)
  local total, mining, ready, paused, offline = 0, 0, 0, 0, 0
  for _, miner in ipairs(fleet:list()) do
    total = total + 1
    local state = Ui.userState(miner)
    if state == "MINING" then mining = mining + 1 elseif state == "READY" then ready = ready + 1 elseif state == "PAUSED" then paused = paused + 1 elseif state == "OFFLINE" then offline = offline + 1 end
  end
  return total .. " Turtles", mining .. " Mining " .. ready .. " Ready " .. paused .. " Paused " .. offline .. " Offline"
end

function Ui.render(terminal, fleet, selected)
  terminal.clear()
  local total, states = summary(fleet)
  local width = select(1, terminal.getSize())
  writeLine(terminal, 1, "RALFIE OS v" .. Ui.VERSION)
  writeLine(terminal, 2, "MAIN FLEET  " .. fleet:onlineCount() .. " ONLINE")
  writeLine(terminal, 3, total)
  writeLine(terminal, 4, states)
  local line = 6
  for _, miner in ipairs(fleet:list()) do
    if line >= select(2, terminal.getSize()) - 2 then break end
    local row = (miner.label or ("#" .. miner.id)) .. "  " .. Ui.userState(miner)
    local version = (miner.status or {}).software_version or (miner.device_info or {}).software_version
    if version and width >= 30 then row = row .. "  v" .. tostring(version) end
    writeLine(terminal, line, row, selected == miner.id)
    line = line + 1
  end
  writeLine(terminal, select(2, terminal.getSize()) - 1, width < 28 and "[M] Menu  [A] Update" or "[A] Update Fleet  [M] Menu")
  writeLine(terminal, select(2, terminal.getSize()), "Enter Open")
end

function Ui.command(terminal, miner, selected, commandState)
  terminal.clear()
  local status, state = miner.status or {}, Ui.userState(miner)
  writeLine(terminal, 1, miner.label or ("Miner #" .. miner.id))
  writeLine(terminal, 2, state)
  local line = 4
  if status.job_tunnel_size then writeLine(terminal, line, "Tunnel    " .. tostring(status.job_tunnel_size) .. "x" .. tostring(status.job_tunnel_size)); line = line + 1 end
  if status.job_distance then writeLine(terminal, line, "Distance  " .. tostring(status.job_distance)); line = line + 1 end
  writeLine(terminal, line, "Fuel      " .. Ui.fuelText(status.fuel_level)); line = line + 1
  writeLine(terminal, line, "Inventory " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16)); line = line + 2
  if state == "ERROR" then writeLine(terminal, line, status.reason or status.error or "Needs attention."); line = line + 1 end
  for index, action in ipairs(Ui.deviceActions(miner)) do writeLine(terminal, line, action.label, index == selected); line = line + 1 end
  if commandState then writeLine(terminal, select(2, terminal.getSize()), commandState) end
end

function Ui.details(terminal, miner)
  terminal.clear()
  local info, status = miner.device_info or {}, miner.status or {}
  writeLine(terminal, 1, (miner.label or ("Miner #" .. miner.id)) .. " - DETAILS")
  writeLine(terminal, 3, "Computer ID " .. tostring(miner.id))
  writeLine(terminal, 4, "Role        " .. tostring(info.role or "Unknown"):gsub("_", " "))
  writeLine(terminal, 5, "Fleet       " .. tostring(info.fleet_name or "Unknown"))
  writeLine(terminal, 6, "Version     " .. tostring(info.software_version or status.software_version or "Unknown"))
  writeLine(terminal, 7, "GPS         " .. (info.gps and "Available" or "Unavailable"))
  writeLine(terminal, 8, "Modem       " .. (info.wireless_modem and "Connected" or "Unavailable"))
  if status.job_id then writeLine(terminal, 9, "Job         " .. status.job_id) end
  if status.state then writeLine(terminal, 10, "Internal    " .. status.state) end
  writeLine(terminal, select(2, terminal.getSize()), "[B] Back")
end

function Ui.settings(terminal, miner, selected)
  terminal.clear()
  local info = miner.device_info or {}
  writeLine(terminal, 1, (miner.label or ("Miner #" .. miner.id)) .. " - SETTINGS")
  local entries = { "Device Name  " .. tostring(info.device_name or miner.label or ""), "Fleet        " .. tostring(info.fleet_name or ""), "Auto-start   " .. ((info.auto_start and "On") or "Off"), "Back" }
  for index, entry in ipairs(entries) do writeLine(terminal, index + 2, entry, index == selected) end
  writeLine(terminal, select(2, terminal.getSize()), "Enter Edit  [B] Back")
end

function Ui.update(terminal, fleet, updateBatch, selected)
  terminal.clear(); writeLine(terminal, 1, "FLEET UPDATE")
  writeLine(terminal, 2, "Target: v" .. tostring(updateBatch and updateBatch.target_version or "?"))
  local line = 3
  for _, miner in ipairs(fleet:list()) do
    local result = updateBatch and updateBatch.results[miner.id]
    local pending = updateBatch and updateBatch.pending[miner.id]
    local targeted = not updateBatch or not updateBatch.targets or updateBatch.targets[miner.id]
    local text
    if pending then
      if pending.stage == "DOWNLOADING" then
        writeLine(terminal, line, miner.label or ("#" .. miner.id)); line = line + 1
        writeLine(terminal, line, "Downloading"); line = line + 1
        local total, completed = pending.total_files or 0, pending.completed_files or 0
        local width = math.max(1, math.min(10, select(1, terminal.getSize()) - 12))
        local filled = total > 0 and math.floor(width * completed / total) or 0
        writeLine(terminal, line, "[" .. string.rep("#", filled) .. string.rep("-", width - filled) .. "] " .. completed .. "/" .. (total > 0 and total or "?")); line = line + 1
        text = nil
      elseif pending.stage == "WAITING" or pending.stage == "SENT" then text = "Waiting for worker..."
      else text = pending.stage or "Waiting for worker..." end
    elseif result then
      text = result.status
      if result.status == "VERIFIED" then text = "Verified v" .. tostring(result.version or updateBatch.target_version) end
    else text = targeted and "Waiting for worker..." or (miner.online and "Not targeted" or "Offline") end
    if text then writeLine(terminal, line, (miner.label or ("#" .. miner.id)) .. "  " .. text); line = line + 1 end
  end
  local totals = { verified = 0, busy = 0, offline = 0, failed = 0 }
  for _, result in pairs((updateBatch and updateBatch.results) or {}) do
    if result.status == "VERIFIED" then totals.verified = totals.verified + 1
    elseif result.status == "BUSY" then totals.busy = totals.busy + 1
    elseif result.status == "OFFLINE" then totals.offline = totals.offline + 1
    elseif result.status == "FAILED" or result.status == "RESULT UNKNOWN" then totals.failed = totals.failed + 1 end
  end
  local height = select(2, terminal.getSize())
  local complete, total = updateBatch and updateBatch.remote_complete or 0, updateBatch and updateBatch.remote_total or 0
  writeLine(terminal, height - 3, "Remote: " .. tostring(complete) .. "/" .. tostring(total) .. " complete")
  if updateBatch and updateBatch.resolved then writeLine(terminal, height - 2, totals.verified .. " verified  " .. totals.busy .. " busy  " .. totals.offline .. " offline") end
  writeLine(terminal, height - 1, updateBatch and updateBatch.resolved and "Enter Update Pocket  [B] Back" or "[B] Back")
  writeLine(terminal, height, updateBatch and updateBatch.resolved and "Remote results resolved" or "Requests continue in background")
end

function Ui.choose(terminal, title, entries, header)
  local selected = 1
  while true do
    terminal.clear(); writeLine(terminal, 1, title)
    for index, value in ipairs(header or {}) do writeLine(terminal, index + 1, value) end
    local start = #(header or {}) + 3
    for index, entry in ipairs(entries) do writeLine(terminal, start + index - 1, entry.label, index == selected) end
    writeLine(terminal, select(2, terminal.getSize()), "Enter Select  [B] Back")
    local event, key = os.pullEvent("key")
    if event == "key" then
      if key == keys.up then selected = math.max(1, selected - 1)
      elseif key == keys.down then selected = math.min(#entries, selected + 1)
      elseif key == keys.enter then return entries[selected].id
      elseif Ui.isBackKey(key) then return nil, "BACK" end
    end
  end
end

function Ui.input(terminal, title, label, initial)
  local value = initial or ""
  while true do
    terminal.clear(); writeLine(terminal, 1, title); writeLine(terminal, 3, label); writeLine(terminal, 5, "> " .. value .. "_")
    writeLine(terminal, select(2, terminal.getSize()), "Enter Save  Backspace empty Cancel")
    local event, key = os.pullEvent()
    if event == "char" then value = value .. key
    elseif event == "key" then
      if key == keys.enter then return value elseif key == keys.escape then return nil, "BACK"
      elseif key == keys.backspace then if #value == 0 then return nil, "BACK" end; value = value:sub(1, -2) end
    end
  end
end

function Ui.confirm(terminal, title, lines)
  while true do
    terminal.clear(); writeLine(terminal, 1, title)
    for index, line in ipairs(lines or {}) do writeLine(terminal, index + 2, line) end
    writeLine(terminal, select(2, terminal.getSize()), "[Y] Confirm  [B] Back")
    local event, key = os.pullEvent("key")
    if event == "key" then if key == keys.y then return true elseif key == keys.n or Ui.isBackKey(key) or key == keys.escape then return false, "BACK" end end
  end
end

local function wrapped(text, width)
  local lines, line = {}, ""
  width = math.max(1, width)
  for word in tostring(text):gmatch("%S+") do
    if #word > width then
      if #line > 0 then table.insert(lines, line); line = "" end
      while #word > width do table.insert(lines, word:sub(1, width)); word = word:sub(width + 1) end
    end
    if #line == 0 then line = word
    elseif #line + 1 + #word <= width then line = line .. " " .. word
    else table.insert(lines, line); line = word end
  end
  if #line > 0 then table.insert(lines, line) end
  return lines
end

function Ui.error(terminal, source, message)
  local detail = false
  while true do
    terminal.clear()
    local width, height = terminal.getSize()
    writeLine(terminal, 1, detail and "RALFIEOS ERROR DETAILS" or "RALFIEOS ERROR")
    writeLine(terminal, 2, source)
    local lines = wrapped(message, math.max(1, width - 2))
    local limit = detail and height - 1 or math.min(height - 4, 5)
    for index = 1, math.min(#lines, limit) do writeLine(terminal, index + 3, lines[index]) end
    if detail then
      writeLine(terminal, height, "[B] Back")
    else
      writeLine(terminal, height - 1, "> Back")
      writeLine(terminal, height, "[Enter/B] Back  [D] Details")
    end
    local event, key = os.pullEvent("key")
    if event == "key" then
      if detail and Ui.isBackKey(key) then detail = false
      elseif not detail and (Ui.isBackKey(key) or key == keys.enter) then return false
      elseif not detail and key == keys.d then detail = true end
    end
  end
end

function Ui.controllerMenu(terminal, selected)
  terminal.clear()
  writeLine(terminal, 1, "RALFIE OS v" .. Ui.VERSION)
  writeLine(terminal, 2, "CONTROLLER MENU")
  local entries = { "Fleet", "Update Fleet", "Back" }
  for index, entry in ipairs(entries) do writeLine(terminal, index + 4, entry, index == selected) end
  writeLine(terminal, select(2, terminal.getSize()), "Enter Select  [B] Back")
end

return Ui

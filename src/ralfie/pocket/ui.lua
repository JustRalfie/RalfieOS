local Ui = {}

local function writeLine(terminal, line, text)
  local width = select(1, terminal.getSize())
  if line > select(2, terminal.getSize()) then return end
  terminal.setCursorPos(1, line)
  terminal.write(tostring(text):sub(1, width))
end

local function normalized(state)
  return tostring(state or "UNKNOWN"):upper():gsub("[%s%-]", "_")
end

function Ui.userState(miner)
  if not miner or not miner.online then return "OFFLINE" end
  local state = normalized((miner.status or {}).state)
  if state == "CHASING_ORE" or state == "ORE" or state == "MINE" then return "MINING" end
  if state == "RETURNING_HOME" or state == "RETURN" then return "RETURNING" end
  if state == "DUMP" then return "UNLOADING" end
  if state == "RESUME" then return "RESUMING" end
  if state == "COMPLETE" then return "READY" end
  if state == "FAILED" then return "ERROR" end
  return state
end

function Ui.actions(miner)
  local state = Ui.userState(miner)
  if state == "READY" then return { { key = "j", label = "New Job" }, { key = "s", label = "Setup" } } end
  if state == "PAUSED" then return { { key = "c", label = "Continue", command = "RESUME" }, { key = "r", label = "Recall", command = "RETURN_HOME" }, { key = "i", label = "Info" } } end
  if state == "MINING" then return { { key = "p", label = "Pause", command = "PAUSE" }, { key = "u", label = "Unload", command = "UNLOAD" }, { key = "r", label = "Recall", command = "RETURN_HOME" }, { key = "i", label = "Info" } } end
  if state == "UNLOADING" or state == "RESUMING" then return { { key = "p", label = "Pause", command = "PAUSE" }, { key = "r", label = "Recall", command = "RETURN_HOME" }, { key = "i", label = "Info" } } end
  if state == "STARTING" then return { { key = "r", label = "Recall", command = "RETURN_HOME" }, { key = "i", label = "Info" } } end
  if state == "RETURNING" then return { { key = "i", label = "Info" } } end
  if state == "ERROR" then return { { key = "i", label = "Details" } } end
  return { { key = "i", label = "Info" } }
end

function Ui.commandForKey(miner, key)
  for _, action in ipairs(Ui.actions(miner)) do
    if action.key == key then return action.command end
  end
  return nil
end

local function actionHintLines(actions, width)
  local lines, current = {}, ""
  for _, action in ipairs(actions) do
    local hint = "[" .. action.key:upper() .. "] " .. action.label
    local candidate = current == "" and hint or current .. "  " .. hint
    if current ~= "" and #candidate > width then table.insert(lines, current); current = hint else current = candidate end
  end
  if current ~= "" then table.insert(lines, current) end
  return lines
end

function Ui.render(terminal, fleet, selected, updateBatch)
  terminal.clear()
  writeLine(terminal, 1, "RALFIE MINING COMMAND")
  writeLine(terminal, 3, "Miners: " .. fleet:onlineCount() .. " online")
  local line = 5
  for _, miner in ipairs(fleet:list()) do
    if line > select(2, terminal.getSize()) - 3 then break end
    writeLine(terminal, line, (selected == miner.id and "> " or "  ") .. "#" .. miner.id .. " " .. (miner.label or "Unnamed miner")); line = line + 1
    writeLine(terminal, line, Ui.userState(miner)); line = line + 2
  end
  if updateBatch then
    local pending, complete, busy = 0, 0, 0
    for _ in pairs(updateBatch.pending) do pending = pending + 1 end
    for _, result in pairs(updateBatch.results) do
      complete = complete + 1
      if result.status == "BUSY" then busy = busy + 1 end
    end
    writeLine(terminal, select(2, terminal.getSize()), updateBatch.local_result or ("Update: " .. pending .. " pending, " .. complete .. " done" .. (busy > 0 and ", " .. busy .. " busy" or "")))
  else
    writeLine(terminal, select(2, terminal.getSize()), "[A] Update All")
  end
end

function Ui.command(terminal, miner, commandState)
  terminal.clear()
  local status = miner.status or {}
  local state = Ui.userState(miner)
  writeLine(terminal, 1, miner.label or ("Miner #" .. miner.id))
  writeLine(terminal, 3, state)
  if state == "ERROR" then writeLine(terminal, 4, status.reason or status.error or "Needs attention.") end
  local line = state == "ERROR" and 6 or 5
  if status.job_id then writeLine(terminal, line, "Job: Mining"); line = line + 1 end
  if status.job_distance then writeLine(terminal, line, "Distance: " .. tostring(status.job_distance)); line = line + 1 end
  writeLine(terminal, line, "Fuel: " .. tostring(status.fuel_level or "?")); line = line + 1
  writeLine(terminal, line, "Inventory: " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16)); line = line + 2
  for _, hints in ipairs(actionHintLines(Ui.actions(miner), select(1, terminal.getSize()))) do
    writeLine(terminal, line, hints); line = line + 1
  end
  writeLine(terminal, line, "[B] Back")
  if commandState then writeLine(terminal, line + 2, "Command: " .. commandState) end
end

function Ui.info(terminal, miner)
  terminal.clear()
  local info, status = miner.device_info or {}, miner.status or {}
  writeLine(terminal, 1, (miner.label or ("Miner #" .. miner.id)) .. " — INFO")
  writeLine(terminal, 3, "State: " .. Ui.userState(miner))
  writeLine(terminal, 4, "Role: " .. tostring(info.role or "Unknown"):gsub("_", " "))
  if info.fleet_name then writeLine(terminal, 5, "Fleet: " .. info.fleet_name) end
  if status.job_id then writeLine(terminal, 7, "Job: " .. status.job_id) end
  if status.state then writeLine(terminal, 8, "Internal: " .. status.state) end
  if info.software_version then writeLine(terminal, 9, "Version: " .. info.software_version) end
  if info.wireless_modem ~= nil then writeLine(terminal, 10, "Modem: " .. (info.wireless_modem and "Yes" or "No")) end
  if info.gps ~= nil then writeLine(terminal, 11, "GPS: " .. (info.gps and "Yes" or "No")) end
  if info.config_revision ~= nil then writeLine(terminal, 12, "Config rev: " .. tostring(info.config_revision)) end
  writeLine(terminal, 14, "[E] Edit  [B] Back")
end

return Ui

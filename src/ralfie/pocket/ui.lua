local Ui = {}

local function writeLine(terminal, line, text)
  local width = select(1, terminal.getSize())
  terminal.setCursorPos(1, line)
  terminal.write(tostring(text):sub(1, width))
end

function Ui.render(terminal, fleet, selected)
  terminal.clear()
  writeLine(terminal, 1, "RALFIE MINING COMMAND")
  writeLine(terminal, 3, "Miners: " .. fleet:onlineCount() .. " online")
  local line = 5
  for _, miner in ipairs(fleet:list()) do
    if line > select(2, terminal.getSize()) - 3 then break end
    writeLine(terminal, line, (selected == miner.id and "> " or "  ") .. "#" .. miner.id .. " " .. (miner.label or "Unnamed miner")); line = line + 1
    local status = miner.status or {}
    writeLine(terminal, line, "STATE: " .. (miner.online and (status.state or "UNKNOWN") or "OFFLINE")); line = line + 1
    if miner.online then
      writeLine(terminal, line, "FUEL: " .. tostring(status.fuel_level or "?")); line = line + 1
      writeLine(terminal, line, "INVENTORY: " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16)); line = line + 2
    else line = line + 1 end
  end
end

function Ui.command(terminal, miner, state)
  terminal.clear()
  local status = miner.status or {}
  local info = miner.device_info or {}
  writeLine(terminal, 1, miner.label or ("Miner #" .. miner.id))
  writeLine(terminal, 3, "State: " .. tostring(status.state or "UNKNOWN"))
  if info.role then writeLine(terminal, 2, tostring(info.role):gsub("_", " ")) end
  writeLine(terminal, 4, "Fuel: " .. tostring(status.fuel_level or "?"))
  writeLine(terminal, 5, "Inventory: " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16))
  if status.job_id then
    writeLine(terminal, 6, "Job: " .. status.job_id)
    writeLine(terminal, 7, "Distance: " .. tostring(status.job_distance or "?"))
  end
  local controls = status.job_id and 9 or 7
  if status.state == "READY" then writeLine(terminal, controls, "[J] Assign  [S] Info"); writeLine(terminal, controls + 1, "[E] Edit  [B] Back")
  else
    writeLine(terminal, controls, "[R] Return  [U] Unload")
    writeLine(terminal, controls + 1, "[P] Pause  [C] Resume")
    writeLine(terminal, controls + 2, "[S] Info [E] Edit [B] Back")
  end
  if state then writeLine(terminal, controls + 4, "Command: " .. state) end
end

return Ui

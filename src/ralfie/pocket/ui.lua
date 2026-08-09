local Ui = {}

function Ui.render(terminal, fleet, selected)
  terminal.clear(); terminal.setCursorPos(1, 1)
  terminal.write("RALFIE MINING COMMAND")
  terminal.setCursorPos(1, 3)
  terminal.write("Miners: " .. fleet:onlineCount() .. " online")
  local line = 5
  for _, miner in ipairs(fleet:list()) do
    if line > select(2, terminal.getSize()) - 3 then break end
    terminal.setCursorPos(1, line); terminal.write((selected == miner.id and "> " or "  ") .. "#" .. miner.id .. " " .. (miner.label or "Unnamed miner")); line = line + 1
    local status = miner.status or {}
    terminal.setCursorPos(1, line); terminal.write("STATE: " .. (miner.online and (status.state or "UNKNOWN") or "OFFLINE")); line = line + 1
    if miner.online then
      terminal.setCursorPos(1, line); terminal.write("FUEL: " .. tostring(status.fuel_level or "?")); line = line + 1
      terminal.setCursorPos(1, line); terminal.write("INVENTORY: " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16)); line = line + 2
    else line = line + 1 end
  end
end

function Ui.command(terminal, miner, state)
  terminal.clear(); terminal.setCursorPos(1, 1); terminal.write(miner.label or ("Miner #" .. miner.id))
  local status = miner.status or {}
  terminal.setCursorPos(1, 3); terminal.write("State: " .. tostring(status.state or "UNKNOWN"))
  terminal.setCursorPos(1, 4); terminal.write("Fuel: " .. tostring(status.fuel_level or "?"))
  terminal.setCursorPos(1, 5); terminal.write("Inventory: " .. tostring(status.inventory_used or "?") .. "/" .. tostring(status.inventory_slots or 16))
  terminal.setCursorPos(1, 7); terminal.write("[R] Return Home  [U] Unload  [P] Pause  [C] Resume  [B] Back")
  if state then terminal.setCursorPos(1, 9); terminal.write("Command: " .. state) end
end

return Ui

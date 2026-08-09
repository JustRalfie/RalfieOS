local Menu = {}

function Menu.choose(ui, title, entries, options)
  if os and os.pullEvent and keys and ui.terminal then
    local HubUi = dofile((ui.runtime_root or "/ralfie") .. "/interfaces/terminal/hub_ui.lua")
    return HubUi.new(ui.terminal, ui.colors):choose(title, entries, options)
  end
  ui:clear()
  ui:heading(title)
  for index, entry in ipairs(entries) do
    ui:line(index .. ". " .. entry.label)
    if entry.description then
      for _, line in ipairs(entry.description) do ui:line("   " .. line) end
    end
  end
  local raw = ui:prompt("Select ([B] Back):")
  if tostring(raw):lower() == "b" then
    for _, entry in ipairs(entries) do if entry.id == "back" then return "back" end end
    return nil
  end
  local selected = tonumber(raw)
  if not selected or selected % 1 ~= 0 or not entries[selected] then
    ui:status("INVALID", "Choose a listed number.", true)
    return nil
  end
  return entries[selected].id
end

return Menu

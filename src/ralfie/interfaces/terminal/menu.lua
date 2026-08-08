local Menu = {}

function Menu.choose(ui, title, entries)
  ui:clear()
  ui:heading(title)
  for index, entry in ipairs(entries) do
    ui:line(index .. ". " .. entry.label)
    if entry.description then
      for _, line in ipairs(entry.description) do ui:line("   " .. line) end
    end
  end
  local selected = tonumber(ui:prompt("Select:"))
  if not selected or selected % 1 ~= 0 or not entries[selected] then
    ui:status("INVALID", "Choose a listed number.", true)
    return nil
  end
  return entries[selected].id
end

return Menu

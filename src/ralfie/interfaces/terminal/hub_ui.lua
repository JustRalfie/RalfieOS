local HubUi = {}

function HubUi.new(terminal, colors)
  local ui = { terminal = terminal, colors = colors }
  function ui:line(y, text, selected)
    local width = select(1, self.terminal.getSize()); local value = tostring(text)
    if #value > width then value = value:sub(1, math.max(1, width - 3)) .. "..." end
    self.terminal.setCursorPos(1, y)
    if selected and self.terminal.setBackgroundColor and self.terminal.isColor and self.terminal.isColor() then self.terminal.setBackgroundColor(self.colors and self.colors.cyan or 1) end
    self.terminal.write((selected and "> " or "  ") .. value:sub(1, math.max(1, width - 2)))
    if selected and self.terminal.setBackgroundColor then self.terminal.setBackgroundColor(self.colors and self.colors.black or 32768) end
  end
  function ui:choose(title, entries)
    local selected, offset = 1, 1
    while true do
      local width, height = self.terminal.getSize(); self.terminal.clear(); self:line(1, title)
      local visible = math.max(1, height - 3)
      if selected < offset then offset = selected elseif selected >= offset + visible then offset = selected - visible + 1 end
      for row = 1, visible do local entry = entries[offset + row - 1]; if entry then self:line(row + 1, entry.label, offset + row - 1 == selected) end end
      self:line(height, "Up/Down Enter  Back")
      local event, key = os.pullEvent("key")
      if event == "key" then
        if key == keys.up then selected = math.max(1, selected - 1)
        elseif key == keys.down then selected = math.min(#entries, selected + 1)
        elseif key == keys.enter then return entries[selected].id
        elseif key == keys.backspace or key == keys.escape then return nil end
      end
    end
  end
  return ui
end

return HubUi

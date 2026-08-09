local Ui = {}

function Ui.new(options)
  local ui = {
    terminal = assert(options.terminal, "UI requires a terminal"),
    colors = options.colors,
    reader = assert(options.reader, "UI requires a line reader"),
  }

  function ui:clear()
    self.terminal.clear()
    self.terminal.setCursorPos(1, 1)
  end

  function ui:line(text)
    local width, height = self.terminal.getSize()
    local _, y = self.terminal.getCursorPos()
    local rendered = tostring(text)
    if #rendered > width then rendered = rendered:sub(1, math.max(0, width - 3)) .. "..." end
    self.terminal.setCursorPos(1, y)
    self.terminal.write(rendered)
    if y < height then self.terminal.setCursorPos(1, y + 1) end
  end

  function ui:heading(text)
    if self.colors and self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(self.colors.cyan) end
    self:line(text)
    if self.colors and self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(self.colors.white) end
  end

  function ui:status(label, message, isError)
    if self.colors and self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(isError and self.colors.red or self.colors.lime) end
    self:line("[" .. label .. "] " .. message)
    if self.colors and self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(self.colors.white) end
  end

  function ui:prompt(label, reader)
    self.terminal.write(label .. " ")
    return (reader or self.reader)()
  end

  function ui:input(title, label, initial)
    if not (os and os.pullEvent and keys) then return self:prompt(label) end
    local value = initial or ""
    while true do
      self:clear(); self:heading(title); self:line(label); self:line("> " .. value .. "_")
      self:line("Enter Continue  Esc Back")
      local event, key = os.pullEvent()
      if event == "char" then value = value .. key
      elseif event == "key" then
        if key == keys.enter then return value end
        if key == keys.escape then return nil, "BACK" end
        if key == keys.backspace then
          if #value == 0 then return nil, "BACK" end
          value = value:sub(1, -2)
        end
      end
    end
  end

  function ui:waitBack()
    self:line("[Enter/B] Back")
    if not (os and os.pullEvent and keys) then return self:prompt("") end
    while true do
      local event, key = os.pullEvent("key")
      if event == "key" and (key == keys.enter or key == keys.b or key == keys.backspace or key == keys.escape) then return true end
    end
  end

  function ui:progress(label, current, total)
    local width = math.max(1, math.min(30, select(1, self.terminal.getSize()) - #label - 12))
    local ratio = total > 0 and math.max(0, math.min(1, current / total)) or 0
    local filled = math.floor(width * ratio)
    self:line(label .. " [" .. string.rep("#", filled) .. string.rep("-", width - filled) .. "] " .. math.floor(ratio * 100) .. "%")
  end

  return ui
end

return Ui

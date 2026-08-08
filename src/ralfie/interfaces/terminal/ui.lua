local Ui = {}

function Ui.new(options)
  local terminal = options.terminal or term
  local ui = { terminal = assert(terminal, "UI requires a terminal") }

  function ui:clear()
    self.terminal.clear()
    self.terminal.setCursorPos(1, 1)
  end

  function ui:line(text)
    self.terminal.write(tostring(text))
    local _, y = self.terminal.getCursorPos()
    local _, height = self.terminal.getSize()
    if y < height then self.terminal.setCursorPos(1, y + 1) end
  end

  function ui:heading(text)
    if self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(colors.cyan) end
    self:line(text)
    if self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(colors.white) end
  end

  function ui:status(label, message, isError)
    if self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(isError and colors.red or colors.lime) end
    self:line("[" .. label .. "] " .. message)
    if self.terminal.isColor and self.terminal.isColor() then self.terminal.setTextColor(colors.white) end
  end

  function ui:prompt(label, reader)
    self.terminal.write(label .. " ")
    return (reader or read)()
  end

  function ui:progress(label, current, total)
    local width = math.max(10, math.min(30, select(1, self.terminal.getSize()) - #label - 12))
    local ratio = total > 0 and math.max(0, math.min(1, current / total)) or 0
    local filled = math.floor(width * ratio)
    self:line(label .. " [" .. string.rep("#", filled) .. string.rep("-", width - filled) .. "] " .. math.floor(ratio * 100) .. "%")
  end

  return ui
end

return Ui

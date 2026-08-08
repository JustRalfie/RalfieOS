local Dashboard = {}

local function clamp(value, low, high) return math.max(low, math.min(high, value)) end

function Dashboard.new(options)
  local terminal = assert(options.terminal, "dashboard requires terminal")
  local colors = options.colors
  local previous = {}
  local dashboard = {}

  local function lines(state)
    local width, height = terminal.getSize()
    local slice, distance = state.slice or 0, math.max(1, state.distance or 1)
    local percent = math.floor(clamp(slice / distance, 0, 1) * 100)
    local bar = math.max(4, math.min(18, width - 18))
    local filled = math.floor(bar * percent / 100)
    local output = {
      "RalfieOS Miner", "Status: " .. (state.status or "MINING"),
      "Progress: [" .. string.rep("#", filled) .. string.rep("-", bar - filled) .. "] " .. percent .. "%",
      "Slice: " .. slice .. " / " .. distance,
      "Fuel: " .. tostring(state.fuel or 0) .. "  Loot: " .. (state.loot or 0) .. " / " .. (state.capacity or 0),
      "Torches: " .. (state.torches or 0) .. "  Filler: " .. (state.filler or 0),
      "Ores: " .. (state.ores or 0) .. "  Veins: " .. (state.veins or 0) .. "  Unloads: " .. (state.unloads or 0),
    }
    if state.ore then table.insert(output, "Ore: " .. state.ore) end
    if state.status == "COMPLETE" then table.insert(output, "Tunnel Complete") end
    if state.status == "ERROR" and state.error then table.insert(output, "Error: " .. state.error) end
    while #output < height do table.insert(output, "") end
    return output, width, height
  end

  function dashboard:render(state)
    local output, width, height = lines(state)
    for row = 1, height do
      local text = output[row]:sub(1, width)
      if previous[row] ~= text then
        terminal.setCursorPos(1, row)
        terminal.write(text .. string.rep(" ", math.max(0, width - #text)))
        previous[row] = text
      end
    end
    if colors and terminal.isColor and terminal.isColor() then terminal.setTextColor(colors.white) end
  end

  function dashboard:reset()
    previous = {}
    terminal.clear()
    terminal.setCursorPos(1, 1)
  end

  return dashboard
end

return Dashboard

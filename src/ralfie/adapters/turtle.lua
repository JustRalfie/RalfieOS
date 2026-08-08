local TurtleAdapter = {}

local actions = {
  forward = { move = "forward", inspect = "inspect", dig = "dig", place = "place" },
  up = { move = "up", inspect = "inspectUp", dig = "digUp", place = "placeUp" },
  down = { move = "down", inspect = "inspectDown", dig = "digDown", place = "placeDown" },
}

function TurtleAdapter.new(options)
  local api = assert(options.turtle, "turtle adapter requires turtle API")
  local result = assert(options.result, "turtle adapter requires result")
  local adapter = {}

  local function invoke(method, ...)
    local called, success, message = pcall(api[method], ...)
    if not called then return result.fail("TURTLE.API_FAILED", "Turtle API call failed", { context = { method = method, detail = success } }) end
    if success ~= true then return result.fail("TURTLE.ACTION_FAILED", message or (method .. " failed"), { context = { method = method } }) end
    return result.ok(true)
  end

  function adapter:move(direction) return invoke(actions[direction].move) end
  function adapter:dig(direction) return invoke(actions[direction].dig) end
  function adapter:place(direction) return invoke(actions[direction].place) end
  function adapter:turnLeft() return invoke("turnLeft") end
  function adapter:turnRight() return invoke("turnRight") end

  function adapter:inspect(direction)
    local called, present, data = pcall(api[actions[direction].inspect])
    if not called then return result.fail("TURTLE.INSPECT_FAILED", "Turtle inspect call failed", { context = { detail = present } }) end
    return result.ok({ present = present == true, data = data })
  end

  function adapter:select(slot)
    local selected = invoke("select", slot)
    if not selected.ok then return selected end
    return result.ok(true)
  end
  function adapter:itemCount(slot) return api.getItemCount(slot) end
  function adapter:itemSpace(slot)
    local called, value = pcall(api.getItemSpace, slot)
    if not called then return nil end
    return value
  end
  function adapter:selectedSlot() return api.getSelectedSlot() end
  function adapter:fuelLevel() return api.getFuelLevel() end
  function adapter:fuelLimit() return api.getFuelLimit() end
  function adapter:canRefuel() return api.refuel(0) == true end
  function adapter:refuel(count) return invoke("refuel", count) end
  function adapter:drop(direction, count)
    local method = direction == "down" and "dropDown" or direction == "up" and "dropUp" or "drop"
    return invoke(method, count)
  end

  return adapter
end

return TurtleAdapter

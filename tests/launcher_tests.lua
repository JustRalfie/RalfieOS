local Result = dofile("src/ralfie/core/result.lua")

local function runScenario(options)
  local events, choices = {}, options.choices
  local ui = {
    clear = function() table.insert(events, "clear") end,
    heading = function(_, text) table.insert(events, "heading:" .. text) end,
    line = function(_, text) table.insert(events, "line:" .. text) end,
    status = function(_, label, message) table.insert(events, "status:" .. label .. ":" .. message) end,
    prompt = function(_, label)
      table.insert(events, "prompt:" .. label)
      if label == "Tunnel distance:" then return "3" end
      if options.noProfile and label == "Device Name:" then return "Steve" end
      if options.noProfile and label == "Enable Fleet Worker? [Y/N]:" then return options.workerEnabled and "y" or "n" end
      if options.noProfile and label == "Auto-start Worker next boot? [Y/N]:" then return options.autoStart and "y" or "n" end
      if options.noProfile and label == "Fleet Name [Main]:" then return "" end
      return ""
    end,
  }
  local menu = {
    choose = function(_, title)
      table.insert(events, "menu:" .. title)
      local choice = table.remove(choices, 1)
      return choice
    end,
  }
  local moduleLoader = {
    load = function(_, name)
      if name == "ralfie.interfaces.terminal.menu" then return Result.ok(menu) end
      if name == "ralfie.apps.miner.miner" or name == "ralfie.apps.miner.miner_5x5" or name == "ralfie.apps.miner.miner_9x9" then
        if options.loadFailure then return Result.fail("MODULE.LOAD_FAILED", "Miner module is unavailable") end
        return Result.ok({ start = (options.starts and options.starts[name]) or options.start })
      end
      if name == "ralfie.apps.miner.fleet_worker" then
        return Result.ok({ start = function() table.insert(events, "worker:start"); return Result.ok(true) end })
      end
      return Result.fail("MODULE.UNKNOWN", name)
    end,
  }
  local bootstrap = {
    start = function()
      local device = {
        detect = function() return { type = "TURTLE", capabilities = { wireless_modem = false } } end,
        roles = function() return { "MINING_WORKER", "STANDALONE_MINER", "UNCONFIGURED" } end,
      }
      return Result.ok({ ui = ui, module_loader = moduleLoader, turtle = {}, device = device, peripheral = {}, gps = {},
        device_profile = {
          load = function()
            if options.noProfile then return Result.ok(nil) end
            return Result.ok({ device_name = "Test", role = "STANDALONE_MINER", auto_start = false, fleet_name = "Main" })
          end,
          save = function(_, profile) table.insert(events, "profile:" .. profile.role .. ":" .. tostring(profile.auto_start)); return Result.ok(profile) end,
        } })
    end,
  }
  local environment = setmetatable({
    dofile = function(path)
      assert(path == "/ralfie/bootstrap/init.lua")
      return bootstrap
    end,
    turtle = {},
  }, { __index = _G })
  local chunk = assert(loadfile("src/ralfie/ralfie.lua", "t", environment))
  chunk()
  return events
end

local function contains(events, expected)
  for _, event in ipairs(events) do if event == expected then return true end end
  return false
end

local function count(events, expected)
  local matches = 0
  for _, event in ipairs(events) do if event == expected then matches = matches + 1 end end
  return matches
end

local function containsText(events, expected)
  for _, event in ipairs(events) do
    if event:find(expected, 1, true) then return true end
  end
  return false
end

local function appearsBefore(events, first, second)
  local firstIndex, secondIndex
  for index, event in ipairs(events) do
    if event == first and not firstIndex then firstIndex = index end
    if event == second and not secondIndex then secondIndex = index end
  end
  return firstIndex ~= nil and secondIndex ~= nil and firstIndex < secondIndex
end

local function prefixAppearsBefore(events, first, second)
  local firstIndex, secondIndex
  for index, event in ipairs(events) do
    if event:sub(1, #first) == first and not firstIndex then firstIndex = index end
    if event == second and not secondIndex then secondIndex = index end
  end
  return firstIndex ~= nil and secondIndex ~= nil and firstIndex < secondIndex
end

local success = runScenario({
  choices = { "mining", "tunnel_miner", "3", "back", "exit" },
  start = function(context)
    assert(context.turtle ~= nil)
    assert(context.ui:prompt("Tunnel distance:") == "3")
    return Result.ok(true)
  end,
})
assert(contains(success, "menu:Mining"))
assert(contains(success, "clear"))
assert(contains(success, "prompt:Tunnel distance:"))
assert(contains(success, "status:DONE:3x3 Tunnel Miner finished."))
assert(contains(success, "prompt:Press Enter to return:"))
assert(appearsBefore(success, "status:DONE:3x3 Tunnel Miner finished.", "prompt:Press Enter to return:"))
assert(count(success, "menu:Mining") == 2)
assert(count(success, "menu:Tunnel Miner") == 1)

local loadFailure = runScenario({ choices = { "mining", "tunnel_miner", "3", "back", "exit" }, loadFailure = true })
assert(contains(loadFailure, "status:ERROR:Tunnel Miner failed to load: Miner module is unavailable"))
assert(contains(loadFailure, "prompt:Press Enter to return:"))
assert(appearsBefore(loadFailure, "status:ERROR:Tunnel Miner failed to load: Miner module is unavailable", "prompt:Press Enter to return:"))

local exception = runScenario({
  choices = { "mining", "tunnel_miner", "3", "back", "exit" },
  start = function() error("simulated Miner crash") end,
})
assert(containsText(exception, "simulated Miner crash"))
assert(contains(exception, "prompt:Press Enter to return:"))
assert(prefixAppearsBefore(exception, "status:ERROR:Tunnel Miner crashed:", "prompt:Press Enter to return:"))

local failure = runScenario({
  choices = { "mining", "tunnel_miner", "3", "back", "exit" },
  start = function() return Result.fail("MINER.STOPPED", "simulated Miner failure") end,
})
assert(contains(failure, "status:STOPPED:simulated Miner failure"))
assert(contains(failure, "prompt:Press Enter to return:"))
assert(appearsBefore(failure, "status:STOPPED:simulated Miner failure", "prompt:Press Enter to return:"))

for _, size in ipairs({ 5, 9 }) do
  local moduleName = "ralfie.apps.miner.miner_" .. size .. "x" .. size
  local invoked = false
  local sized = runScenario({
    choices = { "mining", "tunnel_miner", tostring(size), "back", "exit" },
    starts = { [moduleName] = function(context) invoked = context.ui:prompt("Tunnel distance:") == "3"; return Result.ok(true) end },
  })
  assert(invoked, size .. "x" .. size .. " tunnel must dispatch to its existing miner module")
  assert(contains(sized, "status:DONE:" .. size .. "x" .. size .. " Tunnel Miner finished."))
end

local firstRun = runScenario({ choices = { "exit" }, noProfile = true, workerEnabled = true, autoStart = true, start = function() return Result.ok(true) end })
assert(contains(firstRun, "profile:MINING_WORKER:true"))
assert(contains(firstRun, "menu:RALFIE OS 0.3 - Steve"))
assert(not contains(firstRun, "worker:start"))

print("launcher tests passed")

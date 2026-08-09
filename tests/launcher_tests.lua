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
  if options.wizardInputs or options.tunnelInputs then
    ui.input = function(_, title, label)
      table.insert(events, "input:" .. label)
      if title == "NEW TUNNEL" then return table.remove(options.tunnelInputs, 1) end
      return table.remove(options.wizardInputs, 1)
    end
  end
  local menu = {
    choose = function(_, title, _, options)
      table.insert(events, "menu:" .. title)
      if options and options.header then for _, line in ipairs(options.header) do table.insert(events, "header:" .. line) end end
      local choice = table.remove(choices, 1)
      return choice
    end,
  }
  local moduleLoader
  moduleLoader = {
    load = function(_, name)
      if name == "ralfie.interfaces.terminal.menu" then return Result.ok(menu) end
      if name == "ralfie.core.result" then return Result.ok(Result) end
      if name == "ralfie.apps.miner.tunnel_dispatch" then
        return Result.ok({ new = function()
          return {
            start = function(_, context, size, minerOptions)
              local moduleName = size == 3 and "ralfie.apps.miner.miner" or (size == 5 and "ralfie.apps.miner.miner_5x5" or "ralfie.apps.miner.miner_9x9")
              local loaded = moduleLoader:load(moduleName)
              if not loaded.ok then return loaded end
              return loaded.value.start(context, minerOptions)
            end,
          }
        end })
      end
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
  choices = { "mining", "tunnel_miner", "3", "start", "back", "exit" },
  start = function(context, options)
    assert(context.turtle ~= nil and options.distance == 3)
    return Result.ok(true)
  end,
})
assert(contains(success, "menu:MINING"))
assert(contains(success, "clear"))
assert(contains(success, "prompt:Tunnel distance:"))
assert(contains(success, "status:DONE:3x3 Tunnel Miner finished."))
assert(contains(success, "prompt:[Enter/B] Back:"))
assert(appearsBefore(success, "status:DONE:3x3 Tunnel Miner finished.", "prompt:[Enter/B] Back:"))
assert(count(success, "menu:MINING") == 2)
assert(count(success, "menu:NEW TUNNEL") == 1)
assert(contains(success, "menu:START TUNNEL?"))
assert(contains(success, "header:Size: 3x3") and contains(success, "header:Distance: 3"))

local loadFailure = runScenario({ choices = { "mining", "tunnel_miner", "3", "start", "back", "exit" }, loadFailure = true })
assert(contains(loadFailure, "status:STOPPED:Miner module is unavailable"))
assert(contains(loadFailure, "prompt:[Enter/B] Back:"))
assert(appearsBefore(loadFailure, "status:STOPPED:Miner module is unavailable", "prompt:[Enter/B] Back:"))

local exception = runScenario({
  choices = { "mining", "tunnel_miner", "3", "start", "back", "exit" },
  start = function() error("simulated Miner crash") end,
})
assert(containsText(exception, "simulated Miner crash"))
assert(contains(exception, "prompt:[Enter/B] Back:"))
assert(prefixAppearsBefore(exception, "status:ERROR:Tunnel Miner crashed:", "prompt:[Enter/B] Back:"))

local failure = runScenario({
  choices = { "mining", "tunnel_miner", "3", "start", "back", "exit" },
  start = function() return Result.fail("MINER.STOPPED", "simulated Miner failure") end,
})
assert(contains(failure, "status:STOPPED:simulated Miner failure"))
assert(contains(failure, "prompt:[Enter/B] Back:"))
assert(appearsBefore(failure, "status:STOPPED:simulated Miner failure", "prompt:[Enter/B] Back:"))

for _, size in ipairs({ 5, 9 }) do
  local moduleName = "ralfie.apps.miner.miner_" .. size .. "x" .. size
  local invoked = false
  local sized = runScenario({
    choices = { "mining", "tunnel_miner", tostring(size), "start", "back", "exit" },
    starts = { [moduleName] = function(_, options) invoked = options.distance == 3; return Result.ok(true) end },
  })
  assert(invoked, size .. "x" .. size .. " tunnel must dispatch to its existing miner module")
  assert(contains(sized, "status:DONE:" .. size .. "x" .. size .. " Tunnel Miner finished."))
end

local cancelledStarts = 0
local cancelled = runScenario({ choices = { "mining", "tunnel_miner", "5", "back", "back", "back", "exit" }, start = function() cancelledStarts = cancelledStarts + 1; return Result.ok(true) end })
assert(cancelledStarts == 0, "cancelling the tunnel confirmation must not start a miner")
assert(count(cancelled, "menu:NEW TUNNEL") == 2, "Back from confirmation must return to size selection")

local distanceBack = runScenario({ choices = { "mining", "tunnel_miner", "5", "back", "back", "exit" }, tunnelInputs = { nil }, start = function() error("must not start") end })
assert(contains(distanceBack, "input:Size: 5x5  Distance:"))
assert(count(distanceBack, "menu:NEW TUNNEL") == 2, "Back from distance input must return to size selection")

local firstRun = runScenario({ choices = { "exit" }, noProfile = true, workerEnabled = true, autoStart = true, start = function() return Result.ok(true) end })
assert(contains(firstRun, "profile:MINING_WORKER:true"))
assert(contains(firstRun, "menu:RALFIE OS 0.3 - Steve"))
assert(not contains(firstRun, "worker:start"))

local setupBack = runScenario({ choices = { "exit" }, noProfile = true, wizardInputs = { "Steve", "y", nil, "n", "Main" }, start = function() return Result.ok(true) end })
assert(contains(setupBack, "profile:UNCONFIGURED:false"), "wizard Back must return to the previous safe setup step")
assert(count(setupBack, "input:Enable Fleet Worker? [Y/N]:") == 2)

local hierarchy = runScenario({ choices = { "settings", "back", "system", "back", "exit" }, start = function() return Result.ok(true) end })
assert(contains(hierarchy, "menu:SETTINGS"), "Turtle configuration must live under Settings")
assert(contains(hierarchy, "menu:SYSTEM"), "Update and diagnostics must live under System")
assert(not contains(hierarchy, "menu:Dashboard"), "implementation-oriented Dashboard must not be a root route")

print("launcher tests passed")

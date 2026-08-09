local Result = dofile("src/ralfie/core/result.lua")
local Miner = dofile("src/ralfie/apps/miner/miner.lua")

local function messagesFor(messages, commandId, kind, status)
  local matches = {}
  for _, message in ipairs(messages) do
    if message.type == kind and message.payload.command_id == commandId and (not status or message.payload.status == status) then
      table.insert(matches, message)
    end
  end
  return matches
end

local function run(commands, overrides, behavior)
  local sent, index, ticks = {}, 1, 0
  behavior = behavior or {}
  local networkModule = { new = function(options)
    local network = {}
    local function deliver(waiting)
      local entry = commands[index]
      if entry and ticks >= (entry.at or 1) and (not entry.wait or waiting) then
        index = index + 1
        local ack, result = options.command_handler(entry.sender or 42, entry)
        table.insert(sent, { type = "COMMAND_ACK", payload = ack })
        if result then table.insert(sent, { type = "COMMAND_RESULT", payload = result }) end
      end
    end
    function network:tick() ticks = ticks + 1; deliver(false); return true end
    function network:wait() ticks = ticks + 1; deliver(true); return true end
    function network:send(recipient, kind, payload)
      table.insert(sent, { type = kind, recipient = recipient, payload = payload })
      return true
    end
    return network
  end }
  local loader = { load = function(_, name)
    if name == "ralfie.services.platform.mining_network" then return Result.ok(networkModule) end
    if overrides and overrides[name] then return Result.ok(overrides[name]) end
    return Result.ok(dofile("src/" .. name:gsub("%.", "/") .. ".lua"))
  end }
  local selected, fuel, moves = 1, 10000, 0
  local function move()
    moves = moves + 1
    if behavior.fail_after and moves > behavior.fail_after then return false, "simulated movement failure" end
    fuel = fuel - 1
    return true
  end
  local turtle = {
    forward=move, up=move, down=move, turnLeft=function() return true end, turnRight=function() return true end,
    inspect=function() return false end, inspectUp=function() return false end, inspectDown=function() return false end,
    dig=function() return true end, digUp=function() return true end, digDown=function() return true end,
    place=function() return true end, placeUp=function() return true end, placeDown=function() return true end,
    select=function(slot) selected=slot; return true end, getSelectedSlot=function() return selected end,
    getItemCount=function(slot) return slot == 15 and 16 or (slot == 16 and 8 or 0) end, getItemSpace=function() return 64 end,
    getFuelLevel=function() return fuel end, getFuelLimit=function() return 10000 end, refuel=function() return true end,
    transferTo=function() return true end, drop=function() return true end, dropUp=function() return true end, dropDown=function() return true end,
  }
  local context = { turtle=turtle, module_loader=loader, configuration={get=function(_,_,fallback) return fallback end},
    ui={status=function() end,prompt=function() return "1" end,line=function() end}, logger={info=function() end,warn=function() end,debug=function() end},
    os={getComputerID=function() return 17 end,getComputerLabel=function() return "Miner" end,clock=function() return 0 end}, rednet={}, peripheral={} }
  local outcome = Miner.start(context, { distance=behavior.distance or 1, torch_slot=16, fuel_slot=15, filler_slot=14, torch_interval=10 })
  return outcome, sent, { ticks = ticks, moves = moves }
end

local returned, returnMessages = run({ { command_id="return", command="RETURN_HOME", target_id=17, issued_by=42 } })
assert(returned.ok and #messagesFor(returnMessages, "return", "COMMAND_ACK", "ACCEPTED") == 1)
assert(#messagesFor(returnMessages, "return", "COMMAND_RESULT", "SUCCESS") == 1)
assert(messagesFor(returnMessages, "return", "COMMAND_RESULT", "SUCCESS")[1].recipient == 42)

local resumed, pauseMessages, pauseStats = run({
  { command_id="pause", command="PAUSE", target_id=17, issued_by=42 },
  { at=20, wait=true, command_id="resume", command="RESUME", target_id=17, issued_by=42 },
  { at=21, command_id="resume", command="RESUME", target_id=17, issued_by=42 },
})
assert(resumed.ok and pauseStats.ticks >= 20)
assert(#messagesFor(pauseMessages, "pause", "COMMAND_RESULT", "SUCCESS") == 1)
assert(#messagesFor(pauseMessages, "resume", "COMMAND_ACK", "ACCEPTED") == 2)
assert(#messagesFor(pauseMessages, "resume", "COMMAND_RESULT", "SUCCESS") == 2)

local unloadRuns = 0
local unloadModule = { new = function()
  return {
    isNearlyFull = function() return false end,
    run = function(_, state) unloadRuns = unloadRuns + 1; return Result.ok({ state = state }) end,
  }
end }
local unloaded, unloadMessages = run({ { command_id="unload", command="UNLOAD", target_id=17, issued_by=42 } }, { ["ralfie.services.operations.unloading"] = unloadModule })
assert(unloaded.ok and unloadRuns == 1)
assert(#messagesFor(unloadMessages, "unload", "COMMAND_ACK", "ACCEPTED") == 1)
assert(#messagesFor(unloadMessages, "unload", "COMMAND_RESULT", "SUCCESS") == 1)

local emptyUnload, emptyUnloadMessages = run({ { command_id="empty-unload", command="UNLOAD", target_id=17, issued_by=42 } })
assert(emptyUnload.ok)
assert(#messagesFor(emptyUnloadMessages, "empty-unload", "COMMAND_RESULT", "SUCCESS") == 1)

local unloadFailures = 0
local failingUnloadModule = { new = function()
  return {
    isNearlyFull = function() return false end,
    run = function() unloadFailures = unloadFailures + 1; return Result.fail("UNLOAD.TEST", "simulated unload failure") end,
  }
end }
local unloadFailure, unloadFailureMessages = run({ { command_id="unload-failure", command="UNLOAD", target_id=17, issued_by=42 } }, { ["ralfie.services.operations.unloading"] = failingUnloadModule })
assert(not unloadFailure.ok and unloadFailures == 1)
assert(#messagesFor(unloadFailureMessages, "unload-failure", "COMMAND_RESULT", "FAILED") == 1)

local cancelledUnloadRuns = 0
local cancellationUnloadModule = { new = function()
  return { isNearlyFull = function() return false end, run = function() cancelledUnloadRuns = cancelledUnloadRuns + 1; return Result.ok() end }
end }
local unloadThenReturn, unloadThenReturnMessages = run({
  { command_id="queued-unload", command="UNLOAD", target_id=17, issued_by=42 },
  { at=2, command_id="return-wins", command="RETURN_HOME", target_id=17, issued_by=42 },
}, { ["ralfie.services.operations.unloading"] = cancellationUnloadModule })
assert(unloadThenReturn.ok and cancelledUnloadRuns == 0)
assert(#messagesFor(unloadThenReturnMessages, "queued-unload", "COMMAND_RESULT", "CANCELLED") == 1)
assert(#messagesFor(unloadThenReturnMessages, "return-wins", "COMMAND_RESULT", "SUCCESS") == 1)

local pauseThenReturn, pauseThenReturnMessages = run({
  { command_id="queued-pause", command="PAUSE", target_id=17, issued_by=42 },
  { at=2, command_id="return-after-pause", command="RETURN_HOME", target_id=17, issued_by=42 },
})
assert(pauseThenReturn.ok)
assert(#messagesFor(pauseThenReturnMessages, "queued-pause", "COMMAND_RESULT", "CANCELLED") == 1)
assert(#messagesFor(pauseThenReturnMessages, "return-after-pause", "COMMAND_RESULT", "SUCCESS") == 1)

local duplicateReturn, duplicateReturnMessages = run({
  { command_id="duplicate-return", command="RETURN_HOME", target_id=17, issued_by=42 },
  { at=2, command_id="duplicate-return", command="RETURN_HOME", target_id=17, issued_by=42 },
})
assert(duplicateReturn.ok)
assert(#messagesFor(duplicateReturnMessages, "duplicate-return", "COMMAND_ACK", "ACCEPTED") == 2)
assert(#messagesFor(duplicateReturnMessages, "duplicate-return", "COMMAND_RESULT", "SUCCESS") == 1)

local duplicateUnloadRuns = 0
local duplicateUnloadModule = { new = function()
  return { isNearlyFull = function() return false end, run = function() duplicateUnloadRuns = duplicateUnloadRuns + 1; return Result.ok() end }
end }
local duplicateUnload, duplicateUnloadMessages = run({
  { command_id="duplicate-unload", command="UNLOAD", target_id=17, issued_by=42 },
  { at=2, command_id="duplicate-unload", command="UNLOAD", target_id=17, issued_by=42 },
}, { ["ralfie.services.operations.unloading"] = duplicateUnloadModule })
assert(duplicateUnload.ok and duplicateUnloadRuns == 1)
assert(#messagesFor(duplicateUnloadMessages, "duplicate-unload", "COMMAND_ACK", "ACCEPTED") == 2)
assert(#messagesFor(duplicateUnloadMessages, "duplicate-unload", "COMMAND_RESULT", "SUCCESS") == 1)

local duplicatePause, duplicatePauseMessages = run({
  { command_id="duplicate-pause", command="PAUSE", target_id=17, issued_by=42 },
  { at=2, command_id="duplicate-pause", command="PAUSE", target_id=17, issued_by=42 },
  { at=20, wait=true, command_id="resume-after-duplicate-pause", command="RESUME", target_id=17, issued_by=42 },
})
assert(duplicatePause.ok)
assert(#messagesFor(duplicatePauseMessages, "duplicate-pause", "COMMAND_ACK", "ACCEPTED") == 2)
assert(#messagesFor(duplicatePauseMessages, "duplicate-pause", "COMMAND_RESULT", "SUCCESS") == 1)

local returnThenUnloadRuns = 0
local returnThenUnloadModule = { new = function()
  return { isNearlyFull = function() return false end, run = function() returnThenUnloadRuns = returnThenUnloadRuns + 1; return Result.ok() end }
end }
local returnThenUnload, returnThenUnloadMessages = run({
  { command_id="return-first", command="RETURN_HOME", target_id=17, issued_by=42 },
  { at=2, command_id="unload-after-return", command="UNLOAD", target_id=17, issued_by=42 },
}, { ["ralfie.services.operations.unloading"] = returnThenUnloadModule })
assert(returnThenUnload.ok and returnThenUnloadRuns == 0)
assert(#messagesFor(returnThenUnloadMessages, "unload-after-return", "COMMAND_ACK", "BUSY") == 1)

local returnThenPause, returnThenPauseMessages = run({
  { command_id="return-before-pause", command="RETURN_HOME", target_id=17, issued_by=42 },
  { at=2, command_id="pause-after-return", command="PAUSE", target_id=17, issued_by=42 },
})
assert(returnThenPause.ok)
assert(#messagesFor(returnThenPauseMessages, "pause-after-return", "COMMAND_ACK", "BUSY") == 1)

local pausedUnloadRuns = 0
local pausedUnloadModule = { new = function()
  return { isNearlyFull = function() return false end, run = function() pausedUnloadRuns = pausedUnloadRuns + 1; return Result.ok() end }
end }
local pausedThenReturn, pausedThenReturnMessages = run({
  { command_id="pause-before-return", command="PAUSE", target_id=17, issued_by=42 },
  { at=20, wait=true, command_id="return-while-paused", command="RETURN_HOME", target_id=17, issued_by=42 },
}, { ["ralfie.services.operations.unloading"] = pausedUnloadModule })
assert(pausedThenReturn.ok and pausedUnloadRuns == 0)
assert(#messagesFor(pausedThenReturnMessages, "return-while-paused", "COMMAND_ACK", "ACCEPTED") == 1)
assert(#messagesFor(pausedThenReturnMessages, "return-while-paused", "COMMAND_RESULT", "SUCCESS") == 1)

local pausedUnload, pausedUnloadMessages = run({
  { command_id="pause-for-unload", command="PAUSE", target_id=17, issued_by=42 },
  { at=20, wait=true, command_id="unload-while-paused", command="UNLOAD", target_id=17, issued_by=42 },
  { at=21, wait=true, command_id="resume-after-unload-rejection", command="RESUME", target_id=17, issued_by=42 },
}, { ["ralfie.services.operations.unloading"] = pausedUnloadModule })
assert(pausedUnload.ok)
assert(#messagesFor(pausedUnloadMessages, "unload-while-paused", "COMMAND_ACK", "BUSY") == 1)

local returnFailure, returnFailureMessages = run({ { command_id="return-failure", command="RETURN_HOME", target_id=17, issued_by=42 } }, nil, { fail_after = 0 })
assert(not returnFailure.ok)
assert(#messagesFor(returnFailureMessages, "return-failure", "COMMAND_RESULT", "FAILED") == 1)

local pendingUnloadFailure, pendingUnloadFailureMessages = run({ { command_id="pending-unload-failure", command="UNLOAD", target_id=17, issued_by=42 } }, nil, { fail_after = 0 })
assert(not pendingUnloadFailure.ok)
assert(#messagesFor(pendingUnloadFailureMessages, "pending-unload-failure", "COMMAND_RESULT", "FAILED") == 1)

local pauseFailure, pauseFailureMessages = run({ { command_id="pause-failure", command="PAUSE", target_id=17, issued_by=42 } }, nil, { fail_after = 0 })
assert(not pauseFailure.ok)
assert(#messagesFor(pauseFailureMessages, "pause-failure", "COMMAND_RESULT", "FAILED") == 1)

print("mining command integration tests passed")

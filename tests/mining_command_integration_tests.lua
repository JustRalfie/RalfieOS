local Result = dofile("src/ralfie/core/result.lua")
local Miner = dofile("src/ralfie/apps/miner/miner.lua")

local function run(commands)
  local sent, index, ticks = {}, 1, 0
  local networkModule = { new = function(options)
    local network = {}
    local function deliver(waiting)
      local entry = commands[index]
      if entry and ticks >= (entry.at or 1) and (not entry.wait or waiting) then
        index = index + 1
        local ack, result = options.command_handler(42, entry)
        table.insert(sent, { type = "COMMAND_ACK", payload = ack })
        if result then table.insert(sent, { type = "COMMAND_RESULT", payload = result }) end
      end
    end
    function network:tick() ticks = ticks + 1; deliver(false); return true end
    function network:wait() ticks = ticks + 1; deliver(true); return true end
    function network:send(_, kind, payload) table.insert(sent, { type = kind, payload = payload }); return true end
    return network
  end }
  local loader = { load = function(_, name)
    if name == "ralfie.services.platform.mining_network" then return Result.ok(networkModule) end
    return Result.ok(dofile("src/" .. name:gsub("%.", "/") .. ".lua"))
  end }
  local selected, fuel, moves = 1, 10000, 0
  local function move() moves = moves + 1; fuel = fuel - 1; return true end
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
  return Miner.start(context, { distance=1, torch_slot=16, fuel_slot=15, filler_slot=14, torch_interval=10 }), sent, ticks, moves
end

local returned, returnMessages = run({ { command_id="return", command="RETURN_HOME", target_id=17, issued_by=42 } })
assert(returned.ok and returnMessages[#returnMessages].type == "COMMAND_RESULT" and returnMessages[#returnMessages].payload.status == "SUCCESS")
local resumed, pauseMessages, ticks = run({
  { command_id="pause", command="PAUSE", target_id=17, issued_by=42 },
  { at=20, wait=true, command_id="resume", command="RESUME", target_id=17, issued_by=42 },
})
assert(resumed.ok and ticks >= 20)
local pause, resume = false, false
for _, message in ipairs(pauseMessages) do
  pause = pause or (message.payload.command_id == "pause" and message.payload.status == "SUCCESS")
  resume = resume or (message.payload.command_id == "resume" and message.payload.status == "SUCCESS")
end
assert(pause and resume)
print("mining command integration tests passed")

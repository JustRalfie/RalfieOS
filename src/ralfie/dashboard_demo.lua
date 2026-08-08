local Dashboard = dofile("/ralfie/interfaces/terminal/miner_dashboard.lua")
local dashboard = Dashboard.new({ terminal = term, colors = colors })
local states = { "MINING", "CHASING ORE", "SECURING FLUID", "RETURNING HOME", "UNLOADING", "RESUMING", "COMPLETE", "ERROR" }
local sample = { distance = 100, capacity = 13, fuel = 2000, loot = 2, torches = 48, filler = 64, ores = 0, veins = 0, unloads = 0 }
local index, timer = 1, os.startTimer(0.1)
dashboard:reset()
while true do
  local event, value = os.pullEvent()
  if event == "key" and value == keys.q then break end
  if event == "timer" and value == timer then
    sample.status = states[index]
    sample.slice = (index - 1) * 14
    sample.loot, sample.ores, sample.veins, sample.unloads = index % 13, index * 3, index - 1, math.floor(index / 3)
    sample.ore = index % 2 == 0 and "Allthemodium Ore" or nil
    sample.error = sample.status == "ERROR" and "Simulated safe-stop error" or nil
    dashboard:render(sample)
    index = index % #states + 1
    timer = os.startTimer(1)
  end
end
term.clear(); term.setCursorPos(1, 1)
return true

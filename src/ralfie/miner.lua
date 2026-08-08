local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({ turtle = turtle })
if not started.ok then
  print("RalfieOS Miner could not start: " .. started.error.message)
  return started
end
local minerModule = started.value.module_loader:load("ralfie.apps.miner.miner")
if not minerModule.ok then
  print("RalfieOS Miner failed to load: " .. minerModule.error.message)
  return minerModule
end
local mined = minerModule.value.start(started.value)
if not mined.ok then
  print("Miner stopped: " .. mined.error.message)
end
return mined

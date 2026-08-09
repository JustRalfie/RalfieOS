local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({ turtle = turtle })
if not started.ok then print("RalfieOS 5x5 Miner could not start: " .. started.error.message); return started end
local loaded = started.value.module_loader:load("ralfie.apps.miner.miner_5x5")
if not loaded.ok then print("RalfieOS 5x5 Miner failed to load: " .. loaded.error.message); return loaded end
return loaded.value.start(started.value)

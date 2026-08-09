local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({ turtle = turtle })
if not started.ok then print("RalfieOS 9x9 Miner could not start: " .. started.error.message); return started end
local loaded = started.value.module_loader:load("ralfie.apps.miner.miner_9x9")
if not loaded.ok then print("RalfieOS 9x9 Miner failed to load: " .. loaded.error.message); return loaded end
return loaded.value.start(started.value)

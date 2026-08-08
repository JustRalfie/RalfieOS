local Manifest = dofile("/ralfie/manifest.lua")
local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start()
if not started.ok then
  print("RalfieOS failed to start: " .. started.error.message)
  return started
end
started.value.ui:heading("RalfieOS " .. Manifest.version)
started.value.ui:status("READY", "Framework started; no turtle applications are installed.", false)
return started

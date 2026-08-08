local BASE_URL = "https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/"
local Bootstrap = dofile("/ralfie/bootstrap/init.lua")
local started = Bootstrap.start()
if not started.ok then
  print("RalfieOS update could not start: " .. started.error.message)
  return started
end
local context = started.value
local remoteModule = context.module_loader:load("ralfie.services.platform.remote_update")
if not remoteModule.ok then
  print("RalfieOS update failed: " .. remoteModule.error.message)
  return remoteModule
end
local fsxModule = context.module_loader:load("ralfie.lib.fsx")
local resultModule = context.module_loader:load("ralfie.core.result")
if not fsxModule.ok or not resultModule.ok then
  print("RalfieOS update failed to load its support modules.")
  return fsxModule.ok and resultModule or fsxModule
end
local remote = remoteModule.value.new({
  filesystem = fs, fsx = fsxModule.value, result = resultModule.value,
  updater = context.updater, http = http, load = load, output = print,
})
print("Checking RalfieOS updates...")
local updated = remote:install(BASE_URL, "/ralfie")
if updated.ok then
  print("RalfieOS " .. updated.value.version .. " installed. Restart with: dofile(\"/ralfie/start.lua\")")
else
  print("RalfieOS update failed: " .. updated.error.message)
end
return updated

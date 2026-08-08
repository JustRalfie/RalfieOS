local requestedSource = ... or "src/ralfie"
local sourceRoot = shell.resolve(requestedSource)
local moduleRoot = fs.getDir(sourceRoot)
local loaded, installerOrError = pcall(dofile, fs.combine(sourceRoot, "bootstrap/installer.lua"))
if not loaded then
  print("RalfieOS installer could not be loaded: " .. tostring(installerOrError))
  return false
end
local installed = installerOrError.install({ source_root = sourceRoot, module_root = moduleRoot, target_root = "/ralfie" })
if installed.ok then
  print("RalfieOS " .. installed.value.version .. " installed at " .. installed.value.target)
  print("Start it with: dofile(\"/ralfie/start.lua\")")
else
  print("RalfieOS installation failed: " .. installed.error.message)
end
return installed

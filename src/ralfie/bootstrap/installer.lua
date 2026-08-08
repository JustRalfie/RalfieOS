local Installer = {}

local function parentOfRalfie(path)
  local parent = path:match("^(.*)/ralfie$")
  return parent or "/"
end

function Installer.install(options)
  options = options or {}
  local sourceRoot = assert(options.source_root, "installer requires source_root")
  local targetRoot = options.target_root or "/ralfie"
  local moduleRoot = options.module_root or parentOfRalfie(sourceRoot)
  local filesystem = options.filesystem or fs
  local loadFile = options.loadfile or loadfile
  local function loadModule(name)
    local path = moduleRoot:gsub("/$", "") .. "/" .. name:gsub("%.", "/") .. ".lua"
    local chunk, err = loadFile(path)
    assert(chunk, err)
    return chunk()
  end
  local Result = loadModule("ralfie.core.result")
  local ModuleLoader = loadModule("ralfie.core.module_loader")
  local Fsx = loadModule("ralfie.lib.fsx")
  local loader = ModuleLoader.new({ root = moduleRoot, result = Result, loadfile = loadFile })
  local Updating = loadModule("ralfie.services.platform.updating")
  local updater = Updating.new({ filesystem = filesystem, fsx = Fsx, module_loader = loader, result = Result, api_version = 1 })
  return updater:apply(sourceRoot, targetRoot)
end

return Installer

local Bootstrap = {}

local function modulePath(root, name)
  return root:gsub("/$", "") .. "/" .. name:gsub("%.", "/") .. ".lua"
end

local function loadDirect(root, name, loadFile)
  local chunk, err = loadFile(modulePath(root, name))
  assert(chunk, err)
  return chunk()
end

function Bootstrap.start(options)
  options = options or {}
  local runtimeRoot = options.runtime_root or "/ralfie"
  local dataRoot = options.data_root or "/ralfie-data"
  local moduleRoot = options.module_root or "/"
  local filesystem = options.filesystem or fs
  local loadFile = options.loadfile or loadfile
  local serializationApi = options.serialization_api or textutils
  local terminal = options.terminal or term
  local colorApi = options.colors or colors
  local lineReader = options.reader or read
  local clock = options.clock or function()
    return os.epoch and os.epoch("utc") or os.time()
  end
  local function installedVersion()
    local loaded, chunk = pcall(loadFile, runtimeRoot .. "/manifest.lua")
    if not loaded or type(chunk) ~= "function" then return "unknown" end
    local ran, manifest = pcall(chunk)
    return ran and type(manifest) == "table" and type(manifest.version) == "string" and manifest.version or "unknown"
  end
  local Result = loadDirect(moduleRoot, "ralfie.core.result", loadFile)
  local ModuleLoader = loadDirect(moduleRoot, "ralfie.core.module_loader", loadFile)
  local loader = ModuleLoader.new({ root = moduleRoot, result = Result, loadfile = loadFile })

  local function requireModule(name)
    local loaded = loader:load(name)
    if not loaded.ok then return nil, loaded end
    return loaded.value
  end

  local Tablex, failure = requireModule("ralfie.lib.tablex")
  if not Tablex then return failure end
  local Fsx; Fsx, failure = requireModule("ralfie.lib.fsx")
  if not Fsx then return failure end
  local Serialization; Serialization, failure = requireModule("ralfie.lib.serialization")
  if not Serialization then return failure end
  local serializer = Serialization.new(serializationApi)
  local Configuration; Configuration, failure = requireModule("ralfie.services.platform.configuration")
  if not Configuration then return failure end
  local Logging; Logging, failure = requireModule("ralfie.services.platform.logging")
  if not Logging then return failure end
  local Updating; Updating, failure = requireModule("ralfie.services.platform.updating")
  if not Updating then return failure end
  local ApplicationLoader; ApplicationLoader, failure = requireModule("ralfie.bootstrap.application_loader")
  if not ApplicationLoader then return failure end
  local Ui; Ui, failure = requireModule("ralfie.interfaces.terminal.ui")
  if not Ui then return failure end
  local Device; Device, failure = requireModule("ralfie.services.platform.device")
  if not Device then return failure end
  local DeviceProfile; DeviceProfile, failure = requireModule("ralfie.services.platform.device_profile")
  if not DeviceProfile then return failure end

  local defaults = {
    system = {
      log_path = dataRoot .. "/logs/ralfie.log",
      log_level = "info",
      data_path = dataRoot .. "/data",
      applications_path = dataRoot .. "/apps",
    },
    miner = {
      inventory_free_slot_margin = 1,
      filler_slot = 14,
    },
  }
  local configuration = Configuration.new({
    filesystem = filesystem, fsx = Fsx, serialization = serializer, tablex = Tablex, result = Result,
    path = dataRoot .. "/config/config.lua", defaults = defaults,
  })
  configuration:registerSchema("system", function(value)
    if type(value) ~= "table" then return false, "system configuration must be a table" end
    if type(value.log_path) ~= "string" or type(value.data_path) ~= "string" or type(value.applications_path) ~= "string" then
      return false, "system paths must be strings"
    end
    if value.log_path:sub(1, 1) ~= "/" or value.data_path:sub(1, 1) ~= "/" or value.applications_path:sub(1, 1) ~= "/" then
      return false, "system paths must be absolute"
    end
    if value.log_level ~= "debug" and value.log_level ~= "info" and value.log_level ~= "warn" and value.log_level ~= "error" then
      return false, "system.log_level must be debug, info, warn, or error"
    end
    return true
  end)
  local loadedConfig = configuration:load(options.overrides)
  if not loadedConfig.ok then return loadedConfig end

  local logger = Logging.new({
    filesystem = filesystem, fsx = Fsx, serialization = serializer, result = Result, clock = clock,
    path = configuration:get("system.log_path"), minimum_level = configuration:get("system.log_level"),
    context = { component = "bootstrap" },
  })
  local updater = Updating.new({
    filesystem = filesystem, fsx = Fsx, module_loader = loader, result = Result, logger = logger, api_version = 1,
  })
  local applications = ApplicationLoader.new({
    filesystem = filesystem, fsx = Fsx, module_loader = loader, result = Result,
    root = configuration:get("system.applications_path"),
  })
  local context = {
    runtime_root = runtimeRoot, data_root = dataRoot, module_root = moduleRoot, configuration = configuration, logger = logger,
    updater = updater, applications = applications, ui = Ui.new({ terminal = terminal, colors = colorApi, reader = lineReader }),
    module_loader = loader, turtle = options.turtle, filesystem = filesystem, fsx = Fsx, serialization = serializer, clock = clock,
    rednet = options.rednet or rednet, peripheral = options.peripheral or peripheral, gps = options.gps or gps, os = options.os or os,
    pocket = options.pocket or pocket, device = Device, software_version = installedVersion,
  }
  context.ui.runtime_root = runtimeRoot
  context.device_profile = DeviceProfile.new({ filesystem = filesystem, fsx = Fsx, serialization = serializer, result = Result, device = Device, path = dataRoot .. "/device_profile.lua" })
  local loadedApps = applications:loadAll(context)
  if not loadedApps.ok then
    logger:error("bootstrap.application_load_failed", loadedApps.error.context)
    return loadedApps
  end
  logger:info("bootstrap.ready", { application_count = #Fsx.list(filesystem, configuration:get("system.applications_path")) })
  return Result.ok(context)
end

return Bootstrap

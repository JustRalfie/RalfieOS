local ApplicationLoader = {}

local function join(left, right)
  return left:gsub("/$", "") .. "/" .. right
end

function ApplicationLoader.new(options)
  local loader = {
    filesystem = assert(options.filesystem, "application loader requires filesystem"),
    fsx = assert(options.fsx, "application loader requires fsx"),
    moduleLoader = assert(options.module_loader, "application loader requires module loader"),
    result = assert(options.result, "application loader requires result"),
    root = assert(options.root, "application loader requires an application root"),
    applications = {},
  }

  function loader:discoverDirectories(path, directories)
    for _, name in ipairs(self.fsx.list(self.filesystem, path)) do
      local candidate = join(path, name)
      if self.filesystem.isDir(candidate) then
        if self.filesystem.exists(join(candidate, "manifest.lua")) then
          table.insert(directories, candidate)
        else
          self:discoverDirectories(candidate, directories)
        end
      end
    end
  end

  function loader:discover()
    local directories = {}
    if self.filesystem.exists(self.root) then
      self:discoverDirectories(self.root, directories)
    end
    return self.result.ok(directories)
  end

  function loader:loadManifest(directory)
    local manifestResult = self.moduleLoader:loadPath(join(directory, "manifest.lua"), "app-manifest:" .. directory)
    if not manifestResult.ok then return manifestResult end
    local manifest = manifestResult.value
    if type(manifest) ~= "table" or type(manifest.id) ~= "string" or type(manifest.entry) ~= "string" then
      return self.result.fail("APP.INVALID_MANIFEST", "Application manifest requires id and entry", { context = { directory = directory } })
    end
    return self.result.ok(manifest)
  end

  function loader:loadAll(context)
    local discovered = self:discover()
    if not discovered.ok then return discovered end
    for _, directory in ipairs(discovered.value) do
      local manifestResult = self:loadManifest(directory)
      if not manifestResult.ok then return manifestResult end
      local manifest = manifestResult.value
      if self.applications[manifest.id] then
        return self.result.fail("APP.DUPLICATE_ID", "Duplicate application id: " .. manifest.id)
      end
      local appResult = self.moduleLoader:loadPath(join(directory, manifest.entry), "app:" .. manifest.id)
      if not appResult.ok then return appResult end
      local application = appResult.value
      if type(application) ~= "table" or type(application.start) ~= "function" then
        return self.result.fail("APP.INVALID_EXPORT", "Application must export a start function", { context = { id = manifest.id } })
      end
      self.applications[manifest.id] = { manifest = manifest, application = application, context = context }
    end
    return self.result.ok(self.applications)
  end

  function loader:get(id)
    return self.applications[id]
  end

  return loader
end

return ApplicationLoader

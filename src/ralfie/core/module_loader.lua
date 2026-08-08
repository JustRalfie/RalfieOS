local ModuleLoader = {}

local function modulePath(root, name)
  return root:gsub("/$", "") .. "/" .. name:gsub("%.", "/") .. ".lua"
end

function ModuleLoader.new(options)
  assert(options and options.result, "module loader requires a result contract")
  local loader = {
    root = options.root or "/",
    result = options.result,
    cache = {},
  }

  function loader:loadPath(path, cacheKey)
    if cacheKey and self.cache[cacheKey] ~= nil then
      return self.result.ok(self.cache[cacheKey])
    end
    local chunk, loadErr = loadfile(path)
    if not chunk then
      return self.result.fail("MODULE.LOAD_FAILED", "Unable to load " .. path, {
        context = { detail = loadErr, path = path },
      })
    end
    local ran, value = pcall(chunk)
    if not ran then
      return self.result.fail("MODULE.INIT_FAILED", "Unable to initialize " .. path, {
        context = { detail = value, path = path },
      })
    end
    if value == nil then
      return self.result.fail("MODULE.NO_EXPORT", "Module did not return an export", {
        context = { path = path },
      })
    end
    if cacheKey then
      self.cache[cacheKey] = value
    end
    return self.result.ok(value)
  end

  function loader:load(name)
    return self:loadPath(modulePath(self.root, name), name)
  end

  return loader
end

return ModuleLoader

local Configuration = {}

function Configuration.new(options)
  local service = {
    filesystem = assert(options.filesystem, "configuration requires filesystem"),
    fsx = assert(options.fsx, "configuration requires fsx"),
    serialization = assert(options.serialization, "configuration requires serialization"),
    tablex = assert(options.tablex, "configuration requires tablex"),
    result = assert(options.result, "configuration requires result"),
    path = assert(options.path, "configuration requires a path"),
    defaults = options.tablex.copy(options.defaults or {}),
    schemas = {},
    values = nil,
  }

  function service:registerSchema(name, validator)
    if type(name) ~= "string" or type(validator) ~= "function" then
      return self.result.fail("CONFIG.INVALID_SCHEMA", "Schema name and validator are required")
    end
    self.schemas[name] = validator
    return self.result.ok(true)
  end

  function service:validate(values)
    if type(values) ~= "table" then
      return self.result.fail("CONFIG.INVALID", "Configuration root must be a table")
    end
    for name, validator in pairs(self.schemas) do
      local valid, message = validator(values[name], values)
      if valid ~= true then
        return self.result.fail("CONFIG.INVALID", message or ("Invalid configuration for " .. name), {
          context = { namespace = name },
        })
      end
    end
    return self.result.ok(true)
  end

  function service:load(overrides)
    local recovered, recoveryErr = self.fsx.recoverAtomic(self.filesystem, self.path)
    if not recovered then
      return self.result.fail("CONFIG.RECOVERY_FAILED", "Unable to recover a previous configuration write", { context = { detail = recoveryErr } })
    end
    local loaded = self.tablex.copy(self.defaults)
    if self.filesystem.exists(self.path) then
      local content, readErr = self.fsx.read(self.filesystem, self.path)
      if not content then
        return self.result.fail("CONFIG.READ_FAILED", "Unable to read configuration", { context = { detail = readErr } })
      end
      local decoded, decodeErr = self.serialization.decode(content)
      if type(decoded) ~= "table" then
        return self.result.fail("CONFIG.PARSE_FAILED", "Unable to parse configuration", { context = { detail = decodeErr } })
      end
      loaded = self.tablex.merge(loaded, decoded)
    end
    loaded = self.tablex.merge(loaded, overrides or {})
    local validation = self:validate(loaded)
    if not validation.ok then
      return validation
    end
    self.values = loaded
    if not self.filesystem.exists(self.path) then
      local saved = self:save()
      if not saved.ok then
        return saved
      end
    end
    return self.result.ok(self.values)
  end

  function service:get(path, fallback)
    local value = self.tablex.getPath(self.values or {}, path)
    if value == nil then
      return fallback
    end
    return value
  end

  function service:set(path, value)
    if not self.values then
      return self.result.fail("CONFIG.NOT_LOADED", "Configuration must be loaded before it can be changed")
    end
    local proposed = self.tablex.copy(self.values)
    local changed, changeErr = self.tablex.setPath(proposed, path, value)
    if not changed then
      return self.result.fail("CONFIG.INVALID_PATH", "Unable to set configuration value", { context = { path = path, detail = changeErr } })
    end
    local validation = self:validate(proposed)
    if not validation.ok then return validation end
    self.values = proposed
    return self.result.ok(true)
  end

  function service:save()
    if not self.values then
      return self.result.fail("CONFIG.NOT_LOADED", "Configuration must be loaded before it can be saved")
    end
    local encoded, encodeErr = self.serialization.encode(self.values)
    if not encoded then
      return self.result.fail("CONFIG.SERIALIZE_FAILED", "Unable to serialize configuration", { context = { detail = encodeErr } })
    end
    local saved, saveErr = self.fsx.atomicWrite(self.filesystem, self.path, encoded)
    if not saved then
      return self.result.fail("CONFIG.WRITE_FAILED", "Unable to save configuration", { context = { detail = saveErr } })
    end
    return self.result.ok(true)
  end

  return service
end

return Configuration

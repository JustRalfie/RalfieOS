local Logging = {}

local levels = { debug = 10, info = 20, warn = 30, error = 40 }

function Logging.new(options)
  local logger = {
    filesystem = assert(options.filesystem, "logger requires filesystem"),
    fsx = assert(options.fsx, "logger requires fsx"),
    serialization = assert(options.serialization, "logger requires serialization"),
    result = assert(options.result, "logger requires result"),
    path = assert(options.path, "logger requires a path"),
    minimumLevel = options.minimum_level or "info",
    context = options.context or {},
  }

  function logger:withContext(context)
    local merged = {}
    for key, value in pairs(self.context) do merged[key] = value end
    for key, value in pairs(context or {}) do merged[key] = value end
    return Logging.new({
      filesystem = self.filesystem, fsx = self.fsx, serialization = self.serialization,
      result = self.result, path = self.path, minimum_level = self.minimumLevel, context = merged,
    })
  end

  function logger:write(level, event, context)
    if not levels[level] then
      return self.result.fail("LOG.INVALID_LEVEL", "Unknown log level: " .. tostring(level))
    end
    if levels[level] < (levels[self.minimumLevel] or levels.info) then
      return self.result.ok(false)
    end
    local merged = {}
    for key, value in pairs(self.context) do merged[key] = value end
    for key, value in pairs(context or {}) do merged[key] = value end
    local timestamp = os.epoch and os.epoch("utc") or os.time()
    local encoded, encodeErr = self.serialization.encode({
      timestamp = timestamp, level = level, event = event, context = merged,
    })
    if not encoded then
      return self.result.fail("LOG.SERIALIZE_FAILED", "Unable to serialize log event", { context = { detail = encodeErr } })
    end
    local appended, appendErr = self.fsx.append(self.filesystem, self.path, encoded .. "\n")
    if not appended then
      return self.result.fail("LOG.WRITE_FAILED", "Unable to write log event", { context = { detail = appendErr } })
    end
    return self.result.ok(true)
  end

  for level in pairs(levels) do
    logger[level] = function(self, event, context)
      return self:write(level, event, context)
    end
  end

  return logger
end

return Logging

local Profile = {}

function Profile.new(options)
  local service = { filesystem = assert(options.filesystem), fsx = assert(options.fsx), serialization = assert(options.serialization), result = assert(options.result), device = assert(options.device), path = assert(options.path) }
  function service:valid(profile)
    return type(profile) == "table" and type(profile.device_name) == "string" and #profile.device_name > 0 and
      type(profile.role) == "string" and self.device.supportsRole(self.deviceInfo, profile.role) and type(profile.auto_start) == "boolean" and
      (profile.fleet_name == nil or type(profile.fleet_name) == "string") and (profile.config_revision == nil or type(profile.config_revision) == "number") and
      (profile.settings == nil or type(profile.settings) == "table")
  end
  function service:load(deviceInfo)
    self.deviceInfo = deviceInfo
    if not self.filesystem.exists(self.path) then return self.result.ok(nil) end
    local content = self.fsx.read(self.filesystem, self.path)
    if not content then return self.result.ok(nil) end
    local decoded = self.serialization.decode(content)
    if not self:valid(decoded) then return self.result.ok(nil) end
    return self.result.ok(decoded)
  end
  function service:save(profile, deviceInfo)
    self.deviceInfo = deviceInfo or self.deviceInfo
    if not self:valid(profile) then return self.result.fail("PROFILE.INVALID", "Device profile is invalid or incompatible") end
    local encoded, err = self.serialization.encode(profile)
    if not encoded then return self.result.fail("PROFILE.SERIALIZE", "Unable to save device profile", { context = { detail = err } }) end
    local saved, saveErr = self.fsx.atomicWrite(self.filesystem, self.path, encoded)
    if not saved then return self.result.fail("PROFILE.WRITE", "Unable to save device profile", { context = { detail = saveErr } }) end
    return self.result.ok(profile)
  end
  return service
end

return Profile

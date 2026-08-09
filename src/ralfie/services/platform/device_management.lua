local Management = {}

function Management.new(options)
  local manager = { profile_service = assert(options.profile_service), profile = assert(options.profile), device = assert(options.device), device_info = assert(options.device_info), os = assert(options.os),
    get_state = options.get_state or function() return "READY" end, get_job = options.get_job or function() return nil end,
    get_software_version = options.get_software_version or function() return options.software_version or "unknown" end, history = {}, order = {}, limit = 20 }
  local function remember(id, value)
    manager.history[id] = value; table.insert(manager.order, id)
    if #manager.order > manager.limit then manager.history[table.remove(manager.order, 1)] = nil end
  end
  local function unsafe()
    local state = manager.get_state()
    return manager.get_job() ~= nil or state == "RUNNING" or state == "MINING" or state == "PAUSED" or state == "UNLOADING" or state == "RETURNING" or state == "RETURNING HOME"
  end
  function manager:info()
    local readVersion, version = pcall(self.get_software_version)
    return { computer_id = self.os.getComputerID(), device_name = self.profile.device_name, device_type = self.device_info.type, role = self.profile.role,
      fleet_name = self.profile.fleet_name, auto_start = self.profile.auto_start, software_version = readVersion and version or "unknown", protocol_version = 1,
      wireless_modem = self.device_info.capabilities.wireless_modem, gps = self.device_info.capabilities.gps, worker_state = self.get_state(), active_job_id = self.get_job(), config_revision = self.profile.config_revision or 0 }
  end
  function manager:deviceName() return self.profile.device_name end
  function manager:handle(kind, sender, payload)
    if payload.target_id ~= self.os.getComputerID() then return kind == "INFO" and nil or { request_id = payload.request_id, target_id = payload.target_id, status = "REJECTED", reason = "request is for a different device" } end
    if kind == "INFO" then return self:info() end
    local previous = self.history[payload.request_id]
    if previous then return previous end
    local ack = { request_id = payload.request_id, target_id = payload.target_id }
    if payload.expected_revision ~= nil and payload.expected_revision ~= (self.profile.config_revision or 0) then ack.status, ack.reason = "FAILED", "configuration revision changed"
    elseif type(payload.changes) ~= "table" then ack.status, ack.reason = "INVALID", "changes are required"
    else
      local nextProfile, count = {}, 0
      for key, value in pairs(self.profile) do nextProfile[key] = value end
      for key, value in pairs(payload.changes) do
        count = count + 1
        if key == "device_name" then
          if type(value) ~= "string" or value == "" or #value > 32 then ack.status, ack.reason = "INVALID", "device name must be 1-32 characters"; break end
          nextProfile.device_name = value
        elseif key == "fleet_name" then
          if type(value) ~= "string" or #value > 32 then ack.status, ack.reason = "INVALID", "fleet name must be at most 32 characters"; break end
          nextProfile.fleet_name = value
        elseif key == "auto_start" then
          if type(value) ~= "boolean" then ack.status, ack.reason = "INVALID", "auto-start must be true or false"; break end
          nextProfile.auto_start = value
        elseif key == "role" then
          if unsafe() then ack.status, ack.reason = "BUSY", "role cannot change while worker is active"; break end
          if not self.device.supportsRole(self.device_info, value) then ack.status, ack.reason = "INVALID", "role is not compatible with this device"; break end
          nextProfile.role = value
        else ack.status, ack.reason = "INVALID", "field is not remotely editable"; break end
      end
      if count == 0 and not ack.status then ack.status, ack.reason = "INVALID", "no changes supplied" end
      if not ack.status then
        nextProfile.config_revision = (self.profile.config_revision or 0) + 1
        local saved = self.profile_service:save(nextProfile, self.device_info)
        if saved.ok then self.profile, ack.status, ack.config_revision = saved.value, "SUCCESS", nextProfile.config_revision else ack.status, ack.reason = "FAILED", saved.error.message end
      end
    end
    remember(payload.request_id, ack)
    return ack
  end
  return manager
end

return Management

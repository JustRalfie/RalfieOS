local MiningStatus = {}

function MiningStatus.new(options)
  local status = {
    turtle = assert(options.turtle, "mining status requires turtle API"),
    inventory = assert(options.inventory, "mining status requires inventory"),
    getState = assert(options.get_state, "mining status requires state reader"),
    getJob = options.get_job or function() return nil end,
    getJobDetails = options.get_job_details or function() return nil end,
    getPendingCommand = options.get_pending_command or function() return nil end,
    getSoftwareVersion = options.get_software_version or function() return options.software_version or "unknown" end,
    gps = options.gps,
  }

  function status:read()
    local occupied = 0
    for slot = 1, 16 do if self.inventory:count(slot) > 0 then occupied = occupied + 1 end end
    local position
    if self.gps and type(self.gps.locate) == "function" then
      local located, x, y, z = pcall(self.gps.locate, 0.1)
      if located and type(x) == "number" and type(y) == "number" and type(z) == "number" then position = { x = x, y = y, z = z } end
    end
    local details = self.getJobDetails()
    local readVersion, softwareVersion = pcall(self.getSoftwareVersion)
    local payload = {
      state = self.getState(), fuel_level = self.turtle.getFuelLevel(), inventory_used = occupied,
      inventory_slots = 16, position = position, job_id = self.getJob(), pending_command = self.getPendingCommand(), software_version = readVersion and softwareVersion or "unknown",
    }
    if details then payload.job_type, payload.job_lifecycle, payload.job_distance, payload.job_tunnel_size = details.type, details.lifecycle, details.distance, details.tunnel_size end
    return payload
  end

  return status
end

return MiningStatus

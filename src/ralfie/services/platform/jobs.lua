local Jobs = {}

function Jobs.new(options)
  local fs = assert(options.filesystem, "jobs requires filesystem")
  local fsx = assert(options.fsx, "jobs requires fsx")
  local serialization = assert(options.serialization, "jobs requires serialization")
  local result = assert(options.result, "jobs requires result")
  local root = options.root or "/ralfie-data/jobs"
  local clock = options.clock or function() return os.time() end
  local jobs = { active_path = root .. "/active.lua" }
  local function valid(state)
    return type(state) == "table" and (state.job_type == "tunnel_miner" or state.job_type == "tunnel_miner_5x5" or state.job_type == "tunnel_miner_9x9") and type(state.id) == "string" and type(state.position) == "table" and type(state.slice) == "number" and type(state.distance) == "number"
  end
  function jobs:load()
    local recovered, err = fsx.recoverAtomic(fs, self.active_path)
    if not recovered then return result.fail("JOB.RECOVERY_FAILED", err) end
    if not fs.exists(self.active_path) then return result.ok(nil) end
    local content, readErr = fsx.read(fs, self.active_path)
    if not content then return result.fail("JOB.READ_FAILED", readErr) end
    local state, decodeErr = serialization.decode(content)
    if not valid(state) then return result.fail("JOB.INVALID", "Saved job data is invalid.", { context = { detail = decodeErr } }) end
    return result.ok(state)
  end
  function jobs:save(state)
    state.sequence = (state.sequence or 0) + 1
    state.timestamp = clock()
    local encoded, err = serialization.encode(state)
    if not encoded then return result.fail("JOB.SERIALIZE_FAILED", err) end
    local saved, saveErr = fsx.atomicWrite(fs, self.active_path, encoded)
    if not saved then return result.fail("JOB.WRITE_FAILED", saveErr) end
    return result.ok(state)
  end
  function jobs:clear(completed)
    if not fs.exists(self.active_path) then return result.ok(true) end
    if completed then
      local content = fsx.read(fs, self.active_path)
      if content then fsx.atomicWrite(fs, root .. "/completed-" .. tostring(clock()) .. ".lua", content) end
    end
    local removed, err = pcall(fs.delete, self.active_path)
    if not removed then return result.fail("JOB.DELETE_FAILED", err) end
    return result.ok(true)
  end
  return jobs
end

return Jobs

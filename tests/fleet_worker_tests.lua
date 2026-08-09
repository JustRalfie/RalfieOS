local Result = dofile("src/ralfie/core/result.lua")
local Protocol = dofile("src/ralfie/services/platform/mining_protocol.lua")
local FleetWorker = dofile("src/ralfie/apps/miner/fleet_worker.lua")

local function environment(job, outcome, updateOutcome)
  local sent, delivered, starts, sizes = {}, false, 0, {}
  local Network = { new = function(options)
    local network = { opened = true }
    function network:start() return true end
    function network:send(recipient, kind, payload) table.insert(sent, { recipient = recipient, kind = kind, payload = payload }); return true end
    function network:wait()
      if not delivered then delivered = true; options.job_handler(42, job) end
      return true
    end
    return network
  end }
  local Miner = { start = function(_, options)
    starts = starts + 1
    assert(options.distance == job.job.distance and options.job_id == job.job_id)
    options.on_state_change("MINING")
    return outcome or Result.ok()
  end }
  local context = { turtle = { getItemCount = function() return 0 end, getFuelLevel = function() return 1000 end },
    os = { getComputerID = function() return 17 end, getComputerLabel = function() return "Worker" end }, rednet = {}, peripheral = {}, logger = {}, software_version = function() return "0.3.6" end }
  local dispatch = {
    moduleName = function(_, size) return (size == 3 or size == 5 or size == 9) and ("miner-" .. size) or nil end,
    start = function(_, workerContext, size, options) table.insert(sizes, size); return Miner.start(workerContext, options) end,
  }
  local worker = FleetWorker.new(context, { result = Result, protocol = Protocol, network = Network, tunnel_dispatch = dispatch,
    perform_update = function() return updateOutcome or Result.ok({ version = "test" }) end })
  return worker, sent, function() return starts end, sizes
end

local job = { job_id = "job-1", target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = 3, distance = 10 } }
local worker, sent, starts, sizes = environment(job)
assert(worker:status().state == "READY")
assert(worker:status().software_version == "0.3.6", "worker status must report its installed RalfieOS version")
assert(worker:run(function(current) return current.state == "READY" and starts() == 1 end).ok)
assert(starts() == 1 and worker.state == "READY")
assert(sizes[1] == 3)
local statusSize
for _, message in ipairs(sent) do if message.kind == Protocol.types.JOB_STATUS then statusSize = message.payload.tunnel_size end end
assert(statusSize == 3, "active JOB_STATUS must expose tunnel size")
local resultCount = 0
for _, message in ipairs(sent) do if message.kind == Protocol.types.JOB_RESULT and message.payload.status == "SUCCESS" then resultCount = resultCount + 1 end end
assert(resultCount == 1)
local replayAck, replayResult = worker:handleJob(42, job)
assert(replayAck.status == "ACCEPTED" and replayResult.status == "SUCCESS" and starts() == 1)
assert(worker:handleJob(42, { job_id = "bad-distance", target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = 3, distance = 0 } }).status == "INVALID")
assert(worker:handleJob(42, { job_id = "bad-size", target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = 7, distance = 1 } }).status == "INVALID")
assert(worker:handleJob(42, { job_id = "missing-size", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 1 } }).status == "INVALID")
assert(worker:handleJob(42, { job_id = "wrong", target_id = 99, issued_by = 42, job = { type = "MINING", tunnel_size = 3, distance = 1 } }).status == "REJECTED")

for _, tunnelSize in ipairs({ 5, 9 }) do
  local sizedJob = { job_id = "job-size-" .. tunnelSize, target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = tunnelSize, distance = 10 } }
  local sizedWorker, _, sizedStarts, dispatched = environment(sizedJob)
  assert(sizedWorker:run(function(current) return current.state == "READY" and sizedStarts() == 1 end).ok)
  assert(dispatched[1] == tunnelSize and sizedStarts() == 1, tunnelSize .. "x" .. tunnelSize .. " must dispatch exactly once")
end

local failedWorker, failedSent = environment({ job_id = "job-failed", target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = 5, distance = 3 } }, Result.fail("MINER.TEST", "simulated failure"))
assert(failedWorker:run(function(current) return current.state == "ERROR" end).ok)
assert(failedWorker.state == "ERROR")
local failed = 0
for _, message in ipairs(failedSent) do if message.kind == Protocol.types.JOB_RESULT and message.payload.status == "FAILED" then failed = failed + 1 end end
assert(failed == 1)
assert(failedWorker:handleJob(42, { job_id = "new-job", target_id = 17, issued_by = 42, job = { type = "MINING", tunnel_size = 3, distance = 1 } }).status == "BUSY")

local updateWorker, updateSent = environment(job, nil, Result.ok({ version = "0.3.6" }))
local updateRequest = { request_id = "update-1", target_id = 17, issued_by = 42 }
local updated = updateWorker:handleUpdate(42, updateRequest)
assert(updated.status == "SUCCESS" and updated.restart_required == true and updated.version == "0.3.6")
assert(updateSent[#updateSent].kind == Protocol.types.DEVICE_UPDATE_PROGRESS and updateSent[#updateSent].payload.stage == "ACCEPTED", "accepted updates must report a visible lifecycle state")
assert(updateWorker:handleUpdate(42, updateRequest) == updated, "duplicate update requests must replay the saved result")
updateWorker.state = "RUNNING"
assert(updateWorker:handleUpdate(42, { request_id = "update-busy", target_id = 17, issued_by = 42 }).status == "BUSY")
assert(updateWorker:handleUpdate(42, { request_id = "update-wrong", target_id = 99, issued_by = 42 }).status == "REJECTED")
print("fleet worker tests passed")

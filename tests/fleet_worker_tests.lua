local Result = dofile("src/ralfie/core/result.lua")
local Protocol = dofile("src/ralfie/services/platform/mining_protocol.lua")
local FleetWorker = dofile("src/ralfie/apps/miner/fleet_worker.lua")

local function environment(job, outcome)
  local sent, delivered, starts = {}, false, 0
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
    os = { getComputerID = function() return 17 end, getComputerLabel = function() return "Worker" end }, rednet = {}, peripheral = {}, logger = {} }
  local worker = FleetWorker.new(context, { result = Result, protocol = Protocol, network = Network, miner = Miner })
  return worker, sent, function() return starts end
end

local job = { job_id = "job-1", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 10 } }
local worker, sent, starts = environment(job)
assert(worker:status().state == "READY")
assert(worker:run(function(current) return current.state == "READY" and starts() == 1 end).ok)
assert(starts() == 1 and worker.state == "READY")
local resultCount = 0
for _, message in ipairs(sent) do if message.kind == Protocol.types.JOB_RESULT and message.payload.status == "SUCCESS" then resultCount = resultCount + 1 end end
assert(resultCount == 1)
local replayAck, replayResult = worker:handleJob(42, job)
assert(replayAck.status == "ACCEPTED" and replayResult.status == "SUCCESS" and starts() == 1)
assert(worker:handleJob(42, { job_id = "bad-distance", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 0 } }).status == "INVALID")
assert(worker:handleJob(42, { job_id = "wrong", target_id = 99, issued_by = 42, job = { type = "MINING", distance = 1 } }).status == "REJECTED")

local failedWorker, failedSent = environment({ job_id = "job-failed", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 3 } }, Result.fail("MINER.TEST", "simulated failure"))
assert(failedWorker:run(function(current) return current.state == "ERROR" end).ok)
assert(failedWorker.state == "ERROR")
local failed = 0
for _, message in ipairs(failedSent) do if message.kind == Protocol.types.JOB_RESULT and message.payload.status == "FAILED" then failed = failed + 1 end end
assert(failed == 1)
assert(failedWorker:handleJob(42, { job_id = "new-job", target_id = 17, issued_by = 42, job = { type = "MINING", distance = 1 } }).status == "BUSY")
print("fleet worker tests passed")

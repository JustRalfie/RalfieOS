local Batch = dofile("src/ralfie/pocket/update_batch.lua")

local requested = Batch.new("0.3.7")
assert(requested.resolved and requested.remote_total == 0 and requested.remote_complete == 0)

local sent = {}
Batch.request(requested, { { id = 17, online = true } }, function() return "READY" end, function(id, requestId)
  sent[#sent + 1] = { id = id, request_id = requestId }
  return true
end, 5, 100, function(miner) return "update-" .. miner.id end)
assert(#sent == 1 and sent[1].id == 17 and sent[1].request_id == "update-17", "a READY worker must receive a DEVICE_UPDATE_REQUEST")
assert(requested.pending[17] and requested.pending[17].stage == "WAITING" and not requested.resolved)

local batch = Batch.new("0.3.7")
Batch.target(batch, 17, { id = "update-17", stage = "WAITING", last_seen = 0 })
assert(batch.remote_total == 1 and batch.remote_complete == 0 and not batch.resolved, "one waiting worker must remain unresolved")

Batch.progress(batch, 17, { id = "update-17", stage = "SENT", last_seen = 1 })
assert(not batch.resolved, "SENT must remain unresolved")
Batch.progress(batch, 17, { id = "update-17", stage = "ACCEPTED", last_seen = 2 })
assert(not batch.resolved, "ACCEPTED must remain unresolved")
Batch.progress(batch, 17, { id = "update-17", stage = "DOWNLOADING", completed_files = 14, total_files = 81, last_seen = 3 })
assert(not batch.resolved and batch.pending[17].completed_files == 14, "real download progress must remain unresolved")

Batch.result(batch, 17, { status = "UPDATED", version = "0.3.7", verification_required = true })
assert(not batch.resolved, "UPDATED awaiting status verification must remain unresolved")
Batch.observeVersion(batch, 17, "0.3.7")
assert(batch.results[17].status == "VERIFIED" and batch.remote_complete == 1 and batch.resolved)

for _, status in ipairs({ "BUSY", "OFFLINE", "FAILED", "RESULT UNKNOWN" }) do
  local terminal = Batch.new("0.3.7")
  Batch.target(terminal, 17, { id = "update-17", stage = "WAITING" })
  Batch.result(terminal, 17, { status = status })
  assert(terminal.resolved and terminal.remote_complete == 1, status .. " must be terminal")
end

print("pocket update batch tests passed")

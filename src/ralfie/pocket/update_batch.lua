local UpdateBatch = {}

local terminal = {
  VERIFIED = true, BUSY = true, OFFLINE = true, FAILED = true, REJECTED = true, ["RESULT UNKNOWN"] = true,
}

function UpdateBatch.refresh(batch)
  local total, complete = 0, 0
  for id in pairs(batch.targets or {}) do
    total = total + 1
    local result = batch.results[id]
    local resolved = result and (terminal[result.status] or (result.status == "UPDATED" and result.verification_required == false))
    if resolved then complete = complete + 1 end
  end
  batch.remote_total, batch.remote_complete = total, complete
  batch.resolved = complete == total
  return batch.resolved
end

function UpdateBatch.new(targetVersion)
  local batch = { target_version = targetVersion, targets = {}, pending = {}, results = {}, remote_total = 0, remote_complete = 0, resolved = false }
  UpdateBatch.refresh(batch)
  return batch
end

function UpdateBatch.target(batch, id, pending)
  batch.targets[id] = true
  batch.pending[id] = pending
  UpdateBatch.refresh(batch)
end

function UpdateBatch.request(batch, miners, userState, send, issuedBy, now, requestId)
  for _, miner in ipairs(miners) do
    if miner.online then
      local state = userState(miner)
      if state == "READY" or state == "PAUSED" then
        local id = requestId(miner)
        UpdateBatch.target(batch, miner.id, { id = id, sent_at = now, last_seen = now, stage = "WAITING" })
        if not send(miner.id, id) then UpdateBatch.result(batch, miner.id, { status = "FAILED", reason = "could not send request" }) end
      else
        batch.results[miner.id] = { status = "BUSY", reason = "worker is " .. state:lower() }
      end
    else batch.results[miner.id] = { status = "OFFLINE" } end
  end
  UpdateBatch.refresh(batch)
end

function UpdateBatch.result(batch, id, result)
  batch.pending[id] = nil
  batch.results[id] = result
  UpdateBatch.refresh(batch)
end

function UpdateBatch.progress(batch, id, pending)
  if batch.targets[id] and batch.pending[id] then
    batch.pending[id] = pending
  end
  UpdateBatch.refresh(batch)
end

function UpdateBatch.observeVersion(batch, id, version)
  local result = batch.results[id]
  if result and result.status == "UPDATED" and version == (result.version or batch.target_version) then
    result.status, result.version = "VERIFIED", version
  end
  UpdateBatch.refresh(batch)
end

return UpdateBatch

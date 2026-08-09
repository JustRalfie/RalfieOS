local Miner5x5 = {}

function Miner5x5.start(context, options)
  options = options or {}
  local loaded = context.module_loader:load("ralfie.apps.miner.miner")
  if not loaded.ok then return loaded end
  options.width, options.height = 5, 5
  options.job_type = "tunnel_miner_5x5"
  options.job_name = "5x5 Tunnel Miner"
  return loaded.value.start(context, options)
end

return Miner5x5

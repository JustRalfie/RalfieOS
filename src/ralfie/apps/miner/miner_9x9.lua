local Miner9x9 = {}

function Miner9x9.start(context, options)
  options = options or {}
  local loaded = context.module_loader:load("ralfie.apps.miner.miner")
  if not loaded.ok then return loaded end
  options.width, options.height = 9, 9
  options.job_type = "tunnel_miner_9x9"
  options.job_name = "9x9 Tunnel Miner"
  return loaded.value.start(context, options)
end

return Miner9x9

local Result = dofile("src/ralfie/core/result.lua")
local TunnelDispatch = dofile("src/ralfie/apps/miner/tunnel_dispatch.lua")

local expected = {
  [3] = "ralfie.apps.miner.miner",
  [5] = "ralfie.apps.miner.miner_5x5",
  [9] = "ralfie.apps.miner.miner_9x9",
}
local loaded, starts = {}, {}
local loader = {
  load = function(_, name)
    table.insert(loaded, name)
    return Result.ok({ start = function(context, options)
      table.insert(starts, { name = name, context = context, options = options })
      return Result.ok(true)
    end })
  end,
}
local dispatch = TunnelDispatch.new({ module_loader = loader, result = Result })
for _, size in ipairs({ 3, 5, 9 }) do
  local moduleName = expected[size]
  assert(TunnelDispatch.validSize(size))
  assert(dispatch:moduleName(size) == moduleName)
  assert(dispatch:start({ marker = size }, size, { distance = 10 }).ok)
end
assert(#starts == 3)
for index, size in ipairs({ 3, 5, 9 }) do
  assert(starts[index].name == expected[size], size .. "x" .. size .. " must use its existing miner module")
  assert(starts[index].options.distance == 10)
end
assert(not TunnelDispatch.validSize(7))
assert(not dispatch:start({}, 7, {}).ok, "unsupported tunnel sizes must never dispatch a miner")

print("tunnel dispatch tests passed")

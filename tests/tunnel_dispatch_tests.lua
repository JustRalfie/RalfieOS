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

local geometry = {}
local wrapperLoader = {
  load = function(_, name)
    if name == "ralfie.apps.miner.miner" then
      return Result.ok({ start = function(_, options)
        table.insert(geometry, { width = options.width, height = options.height, job_type = options.job_type })
        return Result.ok(true)
      end })
    end
    if name == "ralfie.apps.miner.miner_5x5" then return Result.ok(dofile("src/ralfie/apps/miner/miner_5x5.lua")) end
    if name == "ralfie.apps.miner.miner_9x9" then return Result.ok(dofile("src/ralfie/apps/miner/miner_9x9.lua")) end
    return Result.fail("TEST.UNKNOWN_MODULE", name)
  end,
}
local geometryDispatch = TunnelDispatch.new({ module_loader = wrapperLoader, result = Result })
for _, size in ipairs({ 3, 5, 9 }) do
  assert(geometryDispatch:start({ module_loader = wrapperLoader }, size, { distance = 1 }).ok)
end
assert(geometry[1].width == nil and geometry[1].height == nil, "3x3 keeps the shared miner's explicit default")
assert(geometry[2].width == 5 and geometry[2].height == 5 and geometry[2].job_type == "tunnel_miner_5x5", "5x5 wrapper must propagate geometry")
assert(geometry[3].width == 9 and geometry[3].height == 9 and geometry[3].job_type == "tunnel_miner_9x9", "9x9 wrapper must propagate geometry")

print("tunnel dispatch tests passed")

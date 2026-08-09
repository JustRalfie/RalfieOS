local function normalize(path)
  if path == "" then return "" end
  local cleaned = path:gsub("//+", "/"):gsub("/$", "")
  return cleaned == "" and "/" or cleaned
end

local function parent(path)
  return normalize(path):match("^(.*)/[^/]+$") or ""
end

local function memoryFilesystem()
  local filesystem = { files = {}, directories = { ["/"] = true } }
  function filesystem.exists(path)
    path = normalize(path)
    return filesystem.files[path] ~= nil or filesystem.directories[path] == true
  end
  function filesystem.isDir(path)
    return filesystem.directories[normalize(path)] == true
  end
  function filesystem.getDir(path)
    return parent(path)
  end
  function filesystem.makeDir(path)
    path = normalize(path)
    if path == "" then return end
    local parts, current = {}, ""
    for part in path:gmatch("[^/]+") do table.insert(parts, part) end
    for _, part in ipairs(parts) do
      current = current .. "/" .. part
      filesystem.directories[current] = true
    end
  end
  function filesystem.open(path, mode)
    path = normalize(path)
    local buffer = mode == "a" and (filesystem.files[path] or "") or ""
    if mode == "r" then
      if filesystem.files[path] == nil then return nil, "not found" end
      return { readAll = function() return filesystem.files[path] end, close = function() end }
    end
    return {
      write = function(value) buffer = buffer .. value end,
      close = function() filesystem.makeDir(parent(path)); filesystem.files[path] = buffer end,
    }
  end
  function filesystem.list(path)
    path = normalize(path)
    local prefix = path == "/" and "/" or path .. "/"
    local found = {}
    for candidate in pairs(filesystem.files) do
      local name = candidate:match("^" .. prefix:gsub("%p", "%%%0") .. "([^/]+)$")
      if name then found[name] = true end
    end
    for candidate in pairs(filesystem.directories) do
      local name = candidate:match("^" .. prefix:gsub("%p", "%%%0") .. "([^/]+)$")
      if name then found[name] = true end
    end
    local items = {}
    for name in pairs(found) do table.insert(items, name) end
    return items
  end
  function filesystem.delete(path)
    path = normalize(path)
    local prefix = path .. "/"
    for candidate in pairs(filesystem.files) do
      if candidate == path or candidate:sub(1, #prefix) == prefix then filesystem.files[candidate] = nil end
    end
    for candidate in pairs(filesystem.directories) do
      if candidate ~= "/" and (candidate == path or candidate:sub(1, #prefix) == prefix) then filesystem.directories[candidate] = nil end
    end
  end
  function filesystem.move(source, destination)
    source, destination = normalize(source), normalize(destination)
    if filesystem.exists(destination) then error("destination exists") end
    local prefix = source .. "/"
    local movedFiles, movedDirectories = {}, {}
    for candidate, content in pairs(filesystem.files) do
      if candidate == source or candidate:sub(1, #prefix) == prefix then
        movedFiles[destination .. candidate:sub(#source + 1)] = content
      end
    end
    for candidate in pairs(filesystem.directories) do
      if candidate == source or candidate:sub(1, #prefix) == prefix then
        movedDirectories[destination .. candidate:sub(#source + 1)] = true
      end
    end
    filesystem.delete(source)
    for candidate, content in pairs(movedFiles) do filesystem.files[candidate] = content end
    for candidate in pairs(movedDirectories) do filesystem.directories[candidate] = true end
  end
  return filesystem
end

local function serialize(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) == "number" or type(value) == "boolean" then return tostring(value) end
  local pieces = {}
  for key, item in pairs(value) do table.insert(pieces, "[" .. serialize(key) .. "]=" .. serialize(item)) end
  return "{" .. table.concat(pieces, ",") .. "}"
end

_G.fs = memoryFilesystem()
_G.textutils = {
  serialize = serialize,
  unserialize = function(content)
    local chunk = assert(load("return " .. content))
    return chunk()
  end,
}
_G.colors = { cyan = 1, white = 2, red = 4, lime = 8 }
_G.term = {
  clear = function() end, setCursorPos = function() end, write = function() end,
  getCursorPos = function() return 1, 1 end, getSize = function() return 51, 19 end,
  isColor = function() return false end, setTextColor = function() end,
}

local Bootstrap = dofile("src/ralfie/bootstrap/init.lua")
local started = Bootstrap.start({
  module_root = "src", runtime_root = "/ralfie", filesystem = fs, terminal = term,
  colors = colors, reader = function() return "" end, serialization_api = textutils, clock = function() return 123 end,
})
assert(started.ok, started.error and started.error.message)
assert(fs.exists("/ralfie-data/config/config.lua"))
assert(fs.exists("/ralfie-data/logs/ralfie.log"))

local Result = dofile("src/ralfie/core/result.lua")
local Fsx = dofile("src/ralfie/lib/fsx.lua")
local Updating = dofile("src/ralfie/services/platform/updating.lua")
local RemoteUpdate = dofile("src/ralfie/services/platform/remote_update.lua")
local manifest = { version = "test", api_version = 1, files = { "main.lua" } }
local updater = Updating.new({
  filesystem = fs, fsx = Fsx, result = Result,
  module_loader = { loadPath = function() return Result.ok(manifest) end },
})
Fsx.write(fs, "/source/main.lua", "return 'updated'")
Fsx.write(fs, "/installed/main.lua", "return 'old'")
local updated = updater:apply("/source", "/installed")
assert(updated.ok, updated.error and updated.error.message)
assert(Fsx.read(fs, "/installed/main.lua") == "return 'updated'")

local deploymentManifest = dofile("src/ralfie/manifest.lua")
local requiredDeploymentFiles = {
  "apps/miner/fleet_worker.lua", "ralfie.lua", "services/platform/mining_protocol.lua",
  "services/platform/mining_network.lua", "pocket/main.lua", "launchers/mining_command.lua",
}
local declared = {}
for _, path in ipairs(deploymentManifest.files) do declared[path] = true; Fsx.write(fs, "/fleet-source/" .. path, "new:" .. path) end
for _, path in ipairs(requiredDeploymentFiles) do assert(declared[path], "deployment manifest is missing " .. path) end
local launchers = {}
for _, launcher in ipairs(deploymentManifest.launchers) do launchers[launcher.target] = launcher.source end
assert(launchers["/RalfieOS.lua"] == "launchers/RalfieOS.lua")
assert(launchers["/ralfie-mining-command.lua"] == "launchers/mining_command.lua")
local deploymentUpdater = Updating.new({
  filesystem = fs, fsx = Fsx, result = Result,
  module_loader = { loadPath = function() return Result.ok(deploymentManifest) end },
})
Fsx.write(fs, "/fleet-installed/ralfie.lua", "old mining menu: Tunnel Miner, Back")
local fleetUpdated = deploymentUpdater:apply("/fleet-source", "/fleet-installed")
assert(fleetUpdated.ok, fleetUpdated.error and fleetUpdated.error.message)
assert(Fsx.read(fs, "/fleet-installed/ralfie.lua") == "new:ralfie.lua", "update must replace a stale managed menu")
assert(Fsx.read(fs, "/fleet-installed/apps/miner/fleet_worker.lua") == "new:apps/miner/fleet_worker.lua", "update must install Fleet Worker")
assert(Fsx.read(fs, "/fleet-installed/services/platform/mining_protocol.lua") == "new:services/platform/mining_protocol.lua")
assert(Fsx.read(fs, "/fleet-installed/pocket/main.lua") == "new:pocket/main.lua")
local fleetFresh = deploymentUpdater:apply("/fleet-source", "/fleet-fresh")
assert(fleetFresh.ok, fleetFresh.error and fleetFresh.error.message)
assert(Fsx.read(fs, "/fleet-fresh/apps/miner/fleet_worker.lua") == "new:apps/miner/fleet_worker.lua")

local remoteManifest = "return { version = 'remote-test', api_version = 1, files = { 'payload.lua', 'launchers/ralf.lua' }, launchers = { { source = 'launchers/ralf.lua', target = '/ralf.lua' } } }"
local remoteFiles = {
  ["https://example.invalid/src/ralfie/manifest.lua"] = remoteManifest,
  ["https://example.invalid/src/ralfie/payload.lua"] = "return 'remote'",
  ["https://example.invalid/src/ralfie/launchers/ralf.lua"] = "return 'launcher'",
  ["https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/src/ralfie/manifest.lua"] = remoteManifest,
  ["https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/src/ralfie/payload.lua"] = "return 'remote'",
  ["https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/src/ralfie/launchers/ralf.lua"] = "return 'launcher'",
}
local fakeHttp = {
  get = function(url)
    local content = remoteFiles[url]
    if not content then return nil, "not found" end
    return { readAll = function() return content end, close = function() end }
  end,
}
local remote = RemoteUpdate.new({ filesystem = fs, fsx = Fsx, result = Result, updater = updater, http = fakeHttp, load = load })
local remotelyInstalled = remote:install("https://example.invalid/", "/remote-installed")
assert(remotelyInstalled.ok, remotelyInstalled.error and remotelyInstalled.error.message)
assert(Fsx.read(fs, "/remote-installed/payload.lua") == "return 'remote'")
assert(Fsx.read(fs, "/ralf.lua") == "return 'launcher'")
Fsx.write(fs, "/remote-failure/keep.lua", "return 'keep'")
local failedRemote = remote:install("https://missing.invalid/", "/remote-failure")
assert(not failedRemote.ok)
assert(Fsx.read(fs, "/remote-failure/keep.lua") == "return 'keep'")
_G.http = fakeHttp
local bootstrapInstalled = dofile("install.lua")
assert(bootstrapInstalled == true)
assert(Fsx.read(fs, "/ralfie/payload.lua") == "return 'remote'")
assert(Fsx.read(fs, "/ralf.lua") == "return 'launcher'")
fs.move("/installed", "/installed.previous")
local recoveredUpdate = updater:recover("/installed")
assert(recoveredUpdate.ok, recoveredUpdate.error and recoveredUpdate.error.message)
assert(Fsx.read(fs, "/installed/main.lua") == "return 'updated'")

local Installer = dofile("src/ralfie/bootstrap/installer.lua")
Fsx.write(fs, "/tests/fixtures/update_package/payload.lua", "return 'fixture'")
local installed = Installer.install({
  source_root = "/tests/fixtures/update_package", module_root = "src", target_root = "/installed-framework",
  loadfile = function(path)
    return loadfile(path:sub(1, 1) == "/" and path:sub(2) or path)
  end,
})
assert(installed.ok, installed.error and installed.error.message)
assert(Fsx.read(fs, "/installed-framework/payload.lua") == "return 'fixture'")

print("framework smoke test passed")

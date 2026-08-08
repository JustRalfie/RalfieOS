local BASE_URL = "https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/"
local TARGET_ROOT = "/ralfie"

local function join(left, right)
  return left:gsub("/$", "") .. "/" .. right
end

local function fail(message)
  print("RalfieOS installation failed: " .. message)
  return false
end

local function request(url)
  if not http or not http.get then return nil, "HTTP is unavailable; enable the HTTP API in CC:Tweaked" end
  local requested, responseOrError, requestErr = pcall(http.get, url)
  if not requested then return nil, tostring(responseOrError) end
  if not responseOrError then return nil, tostring(requestErr or "request failed") end
  local response = responseOrError
  local read, contentOrError = pcall(response.readAll)
  pcall(response.close)
  if not read then return nil, tostring(contentOrError) end
  return contentOrError
end

local function remove(path)
  if fs.exists(path) then
    local removed, removeErr = pcall(fs.delete, path)
    if not removed then return false, removeErr end
  end
  return true
end

local function ensureDirectory(path)
  if fs.exists(path) then return true end
  local made, makeErr = pcall(fs.makeDir, path)
  if not made then return false, makeErr end
  return true
end

local function writeFile(path, content)
  local parent = fs.getDir(path)
  local made, makeErr = ensureDirectory(parent)
  if not made then return false, makeErr end
  local opened, handleOrError = pcall(fs.open, path, "w")
  if not opened then return false, handleOrError end
  local handle = handleOrError
  local wrote, writeErr = pcall(handle.write, content)
  local closed, closeErr = pcall(handle.close)
  if not wrote then return false, writeErr end
  if not closed then return false, closeErr end
  return true
end

local function recover()
  local staging = TARGET_ROOT .. ".staging"
  local backup = TARGET_ROOT .. ".previous"
  if not fs.exists(TARGET_ROOT) and fs.exists(backup) then
    local restored, restoreErr = pcall(fs.move, backup, TARGET_ROOT)
    if not restored then return false, restoreErr end
  end
  if fs.exists(TARGET_ROOT) then
    local cleared, clearErr = remove(staging)
    if not cleared then return false, clearErr end
    cleared, clearErr = remove(backup)
    if not cleared then return false, clearErr end
  end
  return true
end

local function safeRuntimePath(path)
  return type(path) == "string" and path:sub(1, 1) ~= "/" and not path:find("..", 1, true)
end

local function hasSpace(bytes)
  if not fs.getFreeSpace then return true end
  local measured, free = pcall(fs.getFreeSpace, "/")
  if not measured then return false, free end
  if free ~= "unlimited" and free < bytes + 512 then
    return false, "not enough free space (need at least " .. (bytes + 512) .. " bytes; have " .. free .. ")"
  end
  return true
end

local recovered, recoveryErr = recover()
if not recovered then return fail("unable to recover a previous install: " .. tostring(recoveryErr)) end

print("Downloading RalfieOS manifest...")
local manifestContent, manifestErr = request(join(BASE_URL, "src/ralfie/manifest.lua"))
if not manifestContent then return fail(manifestErr) end
local manifestChunk, loadErr = load(manifestContent, "@ralfie-manifest", "t", {})
if not manifestChunk then return fail("downloaded manifest is invalid: " .. tostring(loadErr)) end
local ran, manifest = pcall(manifestChunk)
if not ran or type(manifest) ~= "table" or type(manifest.version) ~= "string" or type(manifest.api_version) ~= "number" or type(manifest.files) ~= "table" then
  return fail("downloaded manifest is incomplete")
end
for _, relativePath in ipairs(manifest.files) do
  if not safeRuntimePath(relativePath) then return fail("downloaded manifest contains an unsafe path") end
end

local stagingRoot = TARGET_ROOT .. ".staging"
local cleared, clearErr = remove(stagingRoot)
if not cleared then return fail("unable to clear old staging directory: " .. tostring(clearErr)) end
local made, makeErr = ensureDirectory(stagingRoot)
if not made then return fail("unable to create staging directory: " .. tostring(makeErr)) end

for index, relativePath in ipairs(manifest.files) do
  print("Downloading " .. index .. "/" .. #manifest.files .. ": " .. relativePath)
  local content, downloadErr = request(join(BASE_URL, "src/ralfie/" .. relativePath))
  if not content then
    remove(stagingRoot)
    return fail(downloadErr)
  end
  local enough, spaceErr = hasSpace(#content)
  if not enough then
    remove(stagingRoot)
    return fail(tostring(spaceErr))
  end
  local wrote, writeErr = writeFile(join(stagingRoot, relativePath), content)
  if not wrote then
    remove(stagingRoot)
    return fail("unable to stage " .. relativePath .. ": " .. tostring(writeErr))
  end
end

for _, relativePath in ipairs(manifest.files) do
  if not fs.exists(join(stagingRoot, relativePath)) then
    remove(stagingRoot)
    return fail("staged file is missing: " .. relativePath)
  end
end

local backupRoot = TARGET_ROOT .. ".previous"
if fs.exists(TARGET_ROOT) then
  local backedUp, backupErr = pcall(fs.move, TARGET_ROOT, backupRoot)
  if not backedUp then
    remove(stagingRoot)
    return fail("unable to preserve the current installation: " .. tostring(backupErr))
  end
end
local activated, activateErr = pcall(fs.move, stagingRoot, TARGET_ROOT)
if not activated then
  if fs.exists(backupRoot) then pcall(fs.move, backupRoot, TARGET_ROOT) end
  return fail("unable to activate staged installation: " .. tostring(activateErr))
end
remove(backupRoot)
print("RalfieOS " .. manifest.version .. " installed at /ralfie")
print("Start it with: dofile(\"/ralfie/start.lua\")")
return true

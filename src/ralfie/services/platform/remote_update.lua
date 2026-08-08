local RemoteUpdate = {}

local function join(left, right)
  return left:gsub("/$", "") .. "/" .. right
end

local function safePath(path)
  return type(path) == "string" and path:sub(1, 1) ~= "/" and not path:find("..", 1, true)
end

local function safeLauncher(entry)
  return type(entry) == "table" and safePath(entry.source) and type(entry.target) == "string" and entry.target:sub(1, 1) == "/" and not entry.target:find("..", 1, true)
end

function RemoteUpdate.new(options)
  local service = {
    filesystem = assert(options.filesystem, "remote updater requires filesystem"),
    fsx = assert(options.fsx, "remote updater requires fsx"),
    result = assert(options.result, "remote updater requires result"),
    updater = assert(options.updater, "remote updater requires updater"),
    http = assert(options.http, "remote updater requires HTTP"),
    load = assert(options.load, "remote updater requires load"),
    output = options.output or function() end,
  }

  function service:download(url)
    local requested, responseOrError, requestErr = pcall(self.http.get, url)
    if not requested then return self.result.fail("REMOTE.HTTP_FAILED", "Unable to download " .. url, { context = { detail = responseOrError } }) end
    if not responseOrError then return self.result.fail("REMOTE.HTTP_FAILED", "Unable to download " .. url, { context = { detail = requestErr or "request failed" } }) end
    local response = responseOrError
    local read, contentOrError = pcall(response.readAll)
    pcall(response.close)
    if not read then
      return self.result.fail("REMOTE.HTTP_READ_FAILED", "Unable to read downloaded content", { context = { url = url, detail = contentOrError } })
    end
    return self.result.ok(contentOrError)
  end

  function service:manifest(baseUrl)
    local downloaded = self:download(join(baseUrl, "src/ralfie/manifest.lua"))
    if not downloaded.ok then return downloaded end
    local chunk, loadErr = self.load(downloaded.value, "@ralfie-manifest", "t", {})
    if not chunk then
      return self.result.fail("REMOTE.INVALID_MANIFEST", "Downloaded manifest could not be compiled", { context = { detail = loadErr } })
    end
    local ran, manifest = pcall(chunk)
    if not ran or type(manifest) ~= "table" or type(manifest.version) ~= "string" or type(manifest.api_version) ~= "number" or type(manifest.files) ~= "table" then
      return self.result.fail("REMOTE.INVALID_MANIFEST", "Downloaded manifest is invalid")
    end
    for _, path in ipairs(manifest.files) do
      if not safePath(path) then
        return self.result.fail("REMOTE.INVALID_MANIFEST", "Downloaded manifest contains an unsafe path", { context = { path = path } })
      end
    end
    for _, launcher in ipairs(manifest.launchers or {}) do
      if not safeLauncher(launcher) then return self.result.fail("REMOTE.INVALID_MANIFEST", "Downloaded manifest contains an unsafe launcher") end
    end
    return self.result.ok(manifest)
  end

  function service:checkSpace(path, bytes)
    if not self.filesystem.getFreeSpace then return self.result.ok(true) end
    local probe = self.filesystem.exists(path) and path or self.filesystem.getDir(path)
    if probe == "" then probe = "/" end
    local measured, free = pcall(self.filesystem.getFreeSpace, probe)
    if not measured then return self.result.fail("REMOTE.SPACE_CHECK_FAILED", "Unable to measure free space", { context = { detail = free } }) end
    if free ~= "unlimited" and free < bytes + 512 then
      return self.result.fail("REMOTE.INSUFFICIENT_SPACE", "Not enough free space to stage downloaded file", { context = { required = bytes + 512, available = free } })
    end
    return self.result.ok(true)
  end

  function service:install(baseUrl, targetRoot)
    local recovered = self.updater:recover(targetRoot)
    if not recovered.ok then return recovered end
    local manifestResult = self:manifest(baseUrl)
    if not manifestResult.ok then return manifestResult end
    local manifest = manifestResult.value
    local stagingRoot = targetRoot .. ".staging"
    if self.filesystem.exists(stagingRoot) then self.filesystem.delete(stagingRoot) end
    local made, makeErr = self.fsx.ensureDir(self.filesystem, stagingRoot)
    if not made then return self.result.fail("REMOTE.STAGING_FAILED", "Unable to create staging directory", { context = { detail = makeErr } }) end
    for index, relativePath in ipairs(manifest.files) do
      self.output("Downloading " .. index .. "/" .. #manifest.files .. ": " .. relativePath)
      local downloaded = self:download(join(baseUrl, "src/ralfie/" .. relativePath))
      if not downloaded.ok then
        self.filesystem.delete(stagingRoot)
        return downloaded
      end
      local space = self:checkSpace(targetRoot, #downloaded.value)
      if not space.ok then
        self.filesystem.delete(stagingRoot)
        return space
      end
      local wrote, writeErr = self.fsx.atomicWrite(self.filesystem, join(stagingRoot, relativePath), downloaded.value)
      if not wrote then
        self.filesystem.delete(stagingRoot)
        return self.result.fail("REMOTE.WRITE_FAILED", "Unable to stage downloaded file", { context = { path = relativePath, detail = writeErr } })
      end
    end
    for _, relativePath in ipairs(manifest.files) do
      if not self.filesystem.exists(join(stagingRoot, relativePath)) then
        self.filesystem.delete(stagingRoot)
        return self.result.fail("REMOTE.VERIFY_FAILED", "A staged file is missing", { context = { path = relativePath } })
      end
    end
    local activated = self.updater:activateStaged(targetRoot, stagingRoot, manifest.version)
    if not activated.ok then return activated end
    for _, launcher in ipairs(manifest.launchers or {}) do
      local copied, copyErr = self.fsx.copyFile(self.filesystem, join(targetRoot, launcher.source), launcher.target)
      if not copied then
        return self.result.fail("REMOTE.LAUNCHER_FAILED", "Runtime installed but shell launcher could not be updated", { context = { target = launcher.target, detail = copyErr } })
      end
    end
    return activated
  end

  return service
end

return RemoteUpdate

local Updating = {}

local function join(left, right)
  return left:gsub("/$", "") .. "/" .. right
end

function Updating.new(options)
  local service = {
    filesystem = assert(options.filesystem, "updating requires filesystem"),
    fsx = assert(options.fsx, "updating requires fsx"),
    moduleLoader = assert(options.module_loader, "updating requires module loader"),
    result = assert(options.result, "updating requires result"),
    logger = options.logger,
    apiVersion = options.api_version or 1,
  }

  function service:loadManifest(root)
    local loaded = self.moduleLoader:loadPath(join(root, "manifest.lua"), "package-manifest:" .. root)
    if not loaded.ok then return loaded end
    local manifest = loaded.value
    if type(manifest) ~= "table" or type(manifest.version) ~= "string" or type(manifest.api_version) ~= "number" or type(manifest.files) ~= "table" then
      return self.result.fail("UPDATE.INVALID_MANIFEST", "Package manifest is incomplete", { context = { root = root } })
    end
    if manifest.api_version ~= self.apiVersion then
      return self.result.fail("UPDATE.INCOMPATIBLE", "Package API version is not supported", { context = { expected = self.apiVersion, received = manifest.api_version } })
    end
    for _, relativePath in ipairs(manifest.files) do
      if type(relativePath) ~= "string" or relativePath:find("%.%.", 1, true) or relativePath:sub(1, 1) == "/" then
        return self.result.fail("UPDATE.INVALID_PATH", "Manifest contains an unsafe path", { context = { path = relativePath } })
      end
    end
    return self.result.ok(manifest)
  end

  function service:preflight(sourceRoot)
    local manifestResult = self:loadManifest(sourceRoot)
    if not manifestResult.ok then return manifestResult end
    for _, relativePath in ipairs(manifestResult.value.files) do
      if not self.filesystem.exists(join(sourceRoot, relativePath)) then
        return self.result.fail("UPDATE.MISSING_FILE", "Manifest file is missing from source", { context = { path = relativePath } })
      end
    end
    return manifestResult
  end

  function service:apply(sourceRoot, targetRoot)
    local preflight = self:preflight(sourceRoot)
    if not preflight.ok then return preflight end
    local manifest = preflight.value
    local stagingRoot = targetRoot .. ".staging"
    local backupRoot = targetRoot .. ".previous"
    if self.filesystem.exists(stagingRoot) then self.filesystem.delete(stagingRoot) end
    if self.filesystem.exists(backupRoot) then self.filesystem.delete(backupRoot) end
    local created, createErr = self.fsx.ensureDir(self.filesystem, stagingRoot)
    if not created then
      return self.result.fail("UPDATE.STAGING_FAILED", "Unable to create update staging area", { context = { detail = createErr } })
    end
    for _, relativePath in ipairs(manifest.files) do
      local sourcePath = join(sourceRoot, relativePath)
      local stagedPath = join(stagingRoot, relativePath)
      local copied, copyErr = self.fsx.copyFile(self.filesystem, sourcePath, stagedPath)
      if not copied then
        self.filesystem.delete(stagingRoot)
        return self.result.fail("UPDATE.COPY_FAILED", "Unable to stage update file", { context = { path = relativePath, detail = copyErr } })
      end
      local sourceContent = self.fsx.read(self.filesystem, sourcePath)
      local stagedContent = self.fsx.read(self.filesystem, stagedPath)
      if sourceContent ~= stagedContent then
        self.filesystem.delete(stagingRoot)
        return self.result.fail("UPDATE.VERIFY_FAILED", "Staged file did not match source", { context = { path = relativePath } })
      end
    end
    if self.filesystem.exists(targetRoot) then
      local moved, moveErr = pcall(self.filesystem.move, targetRoot, backupRoot)
      if not moved then
        self.filesystem.delete(stagingRoot)
        return self.result.fail("UPDATE.BACKUP_FAILED", "Unable to preserve installed version", { context = { detail = moveErr } })
      end
    end
    local activated, activateErr = pcall(self.filesystem.move, stagingRoot, targetRoot)
    if not activated then
      if self.filesystem.exists(backupRoot) then self.filesystem.move(backupRoot, targetRoot) end
      return self.result.fail("UPDATE.ACTIVATION_FAILED", "Unable to activate update", { context = { detail = activateErr } })
    end
    if self.filesystem.exists(backupRoot) then self.filesystem.delete(backupRoot) end
    if self.logger then self.logger:info("update.applied", { version = manifest.version, target = targetRoot }) end
    return self.result.ok({ version = manifest.version, target = targetRoot })
  end

  return service
end

return Updating

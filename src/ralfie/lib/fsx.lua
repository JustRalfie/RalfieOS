local Fsx = {}

local function failure(message)
  return false, message
end

local function call(fn, ...)
  local ok, first, second = pcall(fn, ...)
  if not ok then return false, first end
  return true, first, second
end

function Fsx.exists(filesystem, path)
  return filesystem.exists(path)
end

function Fsx.ensureDir(filesystem, path)
  if path == "" or path == nil or filesystem.exists(path) then
    return true
  end
  local made, err = call(filesystem.makeDir, path)
  if not made then
    return failure(err)
  end
  return true
end

function Fsx.read(filesystem, path)
  local opened, handleOrErr = call(filesystem.open, path, "r")
  if not opened then
    return nil, handleOrErr or ("unable to open " .. path)
  end
  local handle = handleOrErr
  local read, content = call(handle.readAll)
  local closed, closeErr = call(handle.close)
  if not read then return nil, content end
  if not closed then return nil, closeErr end
  return content
end

function Fsx.write(filesystem, path, content)
  local parent = filesystem.getDir(path)
  local made, makeErr = Fsx.ensureDir(filesystem, parent)
  if not made then
    return failure(makeErr)
  end
  local opened, handleOrErr = call(filesystem.open, path, "w")
  if not opened then
    return failure(handleOrErr or ("unable to open " .. path))
  end
  local handle = handleOrErr
  local wrote, writeErr = call(handle.write, content)
  if not wrote then
    call(handle.close)
    return failure(writeErr)
  end
  local closed, closeErr = call(handle.close)
  if not closed then return failure(closeErr) end
  return true
end

function Fsx.append(filesystem, path, content)
  local parent = filesystem.getDir(path)
  local made, makeErr = Fsx.ensureDir(filesystem, parent)
  if not made then
    return failure(makeErr)
  end
  local opened, handleOrErr = call(filesystem.open, path, "a")
  if not opened then
    return failure(handleOrErr or ("unable to open " .. path))
  end
  local handle = handleOrErr
  local wrote, writeErr = call(handle.write, content)
  if not wrote then
    call(handle.close)
    return failure(writeErr)
  end
  local closed, closeErr = call(handle.close)
  if not closed then return failure(closeErr) end
  return true
end

function Fsx.recoverAtomic(filesystem, path)
  local temporary = path .. ".tmp"
  local backup = path .. ".bak"
  if not filesystem.exists(path) and filesystem.exists(backup) then
    local restored, restoreErr = call(filesystem.move, backup, path)
    if not restored then return failure(restoreErr) end
  end
  if filesystem.exists(path) and filesystem.exists(temporary) then
    local removed, removeErr = call(filesystem.delete, temporary)
    if not removed then return failure(removeErr) end
  end
  if filesystem.exists(path) and filesystem.exists(backup) then
    local removed, removeErr = call(filesystem.delete, backup)
    if not removed then return failure(removeErr) end
  end
  return true
end

function Fsx.atomicWrite(filesystem, path, content)
  local temporary = path .. ".tmp"
  local backup = path .. ".bak"
  local recovered, recoveryErr = Fsx.recoverAtomic(filesystem, path)
  if not recovered then return failure(recoveryErr) end
  if filesystem.exists(temporary) then
    local removed, removeErr = call(filesystem.delete, temporary)
    if not removed then return failure(removeErr) end
  end
  local wrote, writeErr = Fsx.write(filesystem, temporary, content)
  if not wrote then
    return failure(writeErr)
  end
  if filesystem.exists(backup) then
    local removed, removeErr = call(filesystem.delete, backup)
    if not removed then return failure(removeErr) end
  end
  if filesystem.exists(path) then
    local moved, moveErr = call(filesystem.move, path, backup)
    if not moved then
      call(filesystem.delete, temporary)
      return failure(moveErr)
    end
  end
  local moved, moveErr = call(filesystem.move, temporary, path)
  if not moved then
    if filesystem.exists(backup) then
      call(filesystem.move, backup, path)
    end
    return failure(moveErr)
  end
  if filesystem.exists(backup) then
    local removed, removeErr = call(filesystem.delete, backup)
    if not removed then return failure(removeErr) end
  end
  return true
end

function Fsx.copyFile(filesystem, source, destination)
  local content, readErr = Fsx.read(filesystem, source)
  if not content then
    return failure(readErr)
  end
  return Fsx.atomicWrite(filesystem, destination, content)
end

function Fsx.list(filesystem, path)
  if not filesystem.exists(path) then
    return {}
  end
  return filesystem.list(path)
end

return Fsx

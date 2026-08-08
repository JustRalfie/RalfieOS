local Fsx = {}

local function failure(message)
  return false, message
end

function Fsx.exists(filesystem, path)
  return filesystem.exists(path)
end

function Fsx.ensureDir(filesystem, path)
  if path == "" or path == nil or filesystem.exists(path) then
    return true
  end
  local ok, err = pcall(filesystem.makeDir, path)
  if not ok then
    return failure(err)
  end
  return true
end

function Fsx.read(filesystem, path)
  local handle, openErr = filesystem.open(path, "r")
  if not handle then
    return nil, openErr or ("unable to open " .. path)
  end
  local content = handle.readAll()
  handle.close()
  return content
end

function Fsx.write(filesystem, path, content)
  local parent = filesystem.getDir(path)
  local made, makeErr = Fsx.ensureDir(filesystem, parent)
  if not made then
    return failure(makeErr)
  end
  local handle, openErr = filesystem.open(path, "w")
  if not handle then
    return failure(openErr or ("unable to open " .. path))
  end
  handle.write(content)
  handle.close()
  return true
end

function Fsx.append(filesystem, path, content)
  local parent = filesystem.getDir(path)
  local made, makeErr = Fsx.ensureDir(filesystem, parent)
  if not made then
    return failure(makeErr)
  end
  local handle, openErr = filesystem.open(path, "a")
  if not handle then
    return failure(openErr or ("unable to open " .. path))
  end
  handle.write(content)
  handle.close()
  return true
end

function Fsx.atomicWrite(filesystem, path, content)
  local temporary = path .. ".tmp"
  local backup = path .. ".bak"
  if filesystem.exists(temporary) then
    filesystem.delete(temporary)
  end
  local wrote, writeErr = Fsx.write(filesystem, temporary, content)
  if not wrote then
    return failure(writeErr)
  end
  if filesystem.exists(backup) then
    filesystem.delete(backup)
  end
  if filesystem.exists(path) then
    local moved, moveErr = pcall(filesystem.move, path, backup)
    if not moved then
      filesystem.delete(temporary)
      return failure(moveErr)
    end
  end
  local moved, moveErr = pcall(filesystem.move, temporary, path)
  if not moved then
    if filesystem.exists(backup) then
      filesystem.move(backup, path)
    end
    return failure(moveErr)
  end
  if filesystem.exists(backup) then
    filesystem.delete(backup)
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

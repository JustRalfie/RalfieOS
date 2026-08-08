local Tablex = {}

function Tablex.copy(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for key, item in pairs(value) do
    result[key] = Tablex.copy(item)
  end
  return result
end

function Tablex.merge(base, override)
  local result = Tablex.copy(base or {})
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = Tablex.merge(result[key], value)
    else
      result[key] = Tablex.copy(value)
    end
  end
  return result
end

function Tablex.getPath(source, path)
  local current = source
  for key in string.gmatch(path, "[^%.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[key]
  end
  return current
end

function Tablex.setPath(target, path, value)
  local current = target
  local previous
  for key in string.gmatch(path, "[^%.]+") do
    if previous then
      current = current[previous]
    end
    previous = key
    if previous and current[previous] == nil then
      current[previous] = {}
    end
  end
  current[previous] = value
end

return Tablex

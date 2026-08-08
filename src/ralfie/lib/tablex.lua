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
  local keys = {}
  for key in string.gmatch(path, "[^%.]+") do
    table.insert(keys, key)
  end
  if #keys == 0 then
    return false, "path is empty"
  end
  for index = 1, #keys - 1 do
    local key = keys[index]
    if current[key] == nil then
      current[key] = {}
    elseif type(current[key]) ~= "table" then
      return false, "path crosses a non-table value"
    end
    current = current[key]
  end
  current[keys[#keys]] = value
  return true
end

return Tablex

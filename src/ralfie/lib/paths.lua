local Paths = {}

function Paths.combine(left, right)
  if left == "" or left == nil then
    return right
  end
  if right == "" or right == nil then
    return left
  end
  if fs and fs.combine then
    return fs.combine(left, right)
  end
  return (left:gsub("/$", "")) .. "/" .. right:gsub("^/", "")
end

function Paths.dirname(path)
  local normalized = path:gsub("/$", "")
  local parent = normalized:match("^(.*)/[^/]+$")
  return parent or ""
end

function Paths.basename(path)
  local normalized = path:gsub("/$", "")
  return normalized:match("([^/]+)$") or normalized
end

return Paths

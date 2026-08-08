local Serialization = {}

function Serialization.encode(value)
  if not textutils or not textutils.serialize then
    return nil, "CC:Tweaked textutils.serialize is unavailable"
  end
  return textutils.serialize(value)
end

function Serialization.decode(content)
  if not textutils or not textutils.unserialize then
    return nil, "CC:Tweaked textutils.unserialize is unavailable"
  end
  local value = textutils.unserialize(content)
  if value == nil then
    return nil, "content is not a valid serialized value"
  end
  return value
end

return Serialization

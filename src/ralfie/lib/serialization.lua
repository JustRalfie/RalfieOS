local Serialization = {}

function Serialization.new(api)
  assert(api and api.serialize and api.unserialize, "serialization requires a textutils-compatible API")
  return {
    encode = function(value)
      return api.serialize(value)
    end,
    decode = function(content)
      local value = api.unserialize(content)
      if value == nil then return nil, "content is not a valid serialized value" end
      return value
    end,
  }
end

return Serialization

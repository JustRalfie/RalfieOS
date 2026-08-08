local Result = {}

function Result.ok(value)
  return { ok = true, value = value }
end

function Result.fail(code, message, options)
  options = options or {}
  return {
    ok = false,
    error = {
      code = code,
      message = message,
      retryable = options.retryable == true,
      context = options.context or {},
    },
  }
end

function Result.isOk(value)
  return type(value) == "table" and value.ok == true
end

return Result

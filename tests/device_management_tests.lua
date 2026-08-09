local Result = dofile("src/ralfie/core/result.lua")
local Device = dofile("src/ralfie/services/platform/device.lua")
local Management = dofile("src/ralfie/services/platform/device_management.lua")

local saved, calls, state, job = nil, 0, "READY", nil
local profileService = { save = function(_, profile) calls = calls + 1; if profile.device_name == "fail" then return Result.fail("PROFILE.WRITE", "disk full") end; saved = profile; return Result.ok(profile) end }
local deviceInfo = { type = "TURTLE", capabilities = { wireless_modem = true, gps = false } }
local manager = Management.new({ profile_service = profileService, profile = { device_name = "Steve", role = "MINING_WORKER", auto_start = true, fleet_name = "Main", config_revision = 2 }, device = Device, device_info = deviceInfo,
  os = { getComputerID = function() return 17 end }, get_state = function() return state end, get_job = function() return job end })
local info = manager:handle("INFO", 42, { target_id = 17 })
assert(info.device_name == "Steve" and info.role == "MINING_WORKER" and info.config_revision == 2 and info.wireless_modem)
local renamed = manager:handle("CONFIG", 42, { request_id = "name", target_id = 17, changes = { device_name = "Digger" }, expected_revision = 2 })
assert(renamed.status == "SUCCESS" and saved.device_name == "Digger" and renamed.config_revision == 3)
local replay = manager:handle("CONFIG", 42, { request_id = "name", target_id = 17, changes = { device_name = "Again" } })
assert(replay.status == "SUCCESS" and calls == 1)
assert(manager:handle("CONFIG", 42, { request_id = "bad", target_id = 17, changes = { unknown = true } }).status == "INVALID")
assert(manager:handle("CONFIG", 42, { request_id = "role", target_id = 17, changes = { role = "FLEET_CONTROLLER" } }).status == "INVALID")
state, job = "RUNNING", "job-1"
assert(manager:handle("CONFIG", 42, { request_id = "busy", target_id = 17, changes = { role = "STANDALONE_MINER" } }).status == "BUSY")
state, job = "READY", nil
assert(manager:handle("CONFIG", 42, { request_id = "fail", target_id = 17, changes = { device_name = "fail" } }).status == "FAILED")
assert(manager.profile.device_name == "Digger", "failed save must preserve active profile")
print("device management tests passed")

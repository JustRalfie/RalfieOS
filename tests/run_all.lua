local tests = {
  "framework_smoke.lua", "fluid_tests.lua", "fuel_tests.lua", "launcher_tests.lua", "menu_tests.lua", "miner_dashboard_tests.lua", "miner_tests.lua",
  "hub_ui_tests.lua",
  "terminal_ui_tests.lua",
  "device_profile_tests.lua",
  "device_management_tests.lua",
  "fleet_worker_tests.lua",
  "mining_command_integration_tests.lua", "mining_network_tests.lua", "ore_discovery_api_tests.lua", "ore_observer_tests.lua", "ore_tests.lua", "unloading_tests.lua", "world_tests.lua",
  "pocket_ui_tests.lua", "tunnel_pattern_tests.lua", "tunnel_pattern_observation_tests.lua",
}

local passed = 0
for _, name in ipairs(tests) do
  local ok, err = xpcall(function() dofile("tests/" .. name) end, debug.traceback)
  if ok then
    print("PASS " .. name)
    passed = passed + 1
  else
    io.stderr:write("FAIL " .. name .. "\n" .. tostring(err) .. "\n")
    os.exit(1)
  end
end
print("PASS " .. passed .. " test files")

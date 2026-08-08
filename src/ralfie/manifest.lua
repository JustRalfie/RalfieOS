return {
  version = "0.1.0",
  api_version = 1,
  launchers = {
    { source = "launchers/ralf.lua", target = "/ralf.lua" },
    { source = "launchers/RalfieOS.lua", target = "/RalfieOS.lua" },
  },
  files = {
    "core/result.lua",
    "core/module_loader.lua",
    "lib/tablex.lua",
    "lib/paths.lua",
    "lib/serialization.lua",
    "lib/fsx.lua",
    "bootstrap/installer.lua",
    "bootstrap/application_loader.lua",
    "bootstrap/init.lua",
    "services/platform/configuration.lua",
    "services/platform/logging.lua",
    "services/platform/updating.lua",
    "services/platform/remote_update.lua",
    "interfaces/terminal/ui.lua",
<<<<<<< Updated upstream
    "start.lua",
    "update.lua",
=======
    "interfaces/terminal/menu.lua",
    "apps/miner/manifest.lua",
    "apps/miner/miner.lua",
    "start.lua",
    "update.lua",
    "miner.lua",
    "ralfie.lua",
    "launchers/ralf.lua",
    "launchers/RalfieOS.lua",
>>>>>>> Stashed changes
    "manifest.lua",
  },
}

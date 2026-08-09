# Framework Guide

RalfieOS 0.1 targets the CC:Tweaked CraftOS Lua API. It contains platform infrastructure only; no turtle workflow applications are installed or started.

## Install and start

On a new ComputerCraft computer, download the bootstrap installer and run it:

```lua
wget https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/install.lua install
install
```

The bootstrap fetches the package manifest and every manifest-listed runtime file from `https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/`. It stages the files in `/ralfie.staging`, verifies every expected file, and activates only the complete staged package. A failed download leaves the current `/ralfie` installation untouched.

Start the installed framework with:

```lua
dofile("/ralfie/start.lua")
```

First startup creates `/ralfie-data/config/config.lua` from built-in defaults and writes structured logs to `/ralfie-data/logs/ralfie.log`. `/ralfie` is replaceable program code; `/ralfie-data` is persistent mutable data and is deliberately not touched by an update.

## Framework services

- `bootstrap/init.lua` composes configuration, logging, updating, application discovery, and terminal UI into a context.
- `core/module_loader.lua` loads Lua modules by dotted name and returns structured load failures.
- `bootstrap/application_loader.lua` discovers installed application manifests. With no applications installed, it succeeds with an empty registry.
- `services/platform/configuration.lua` merges defaults with persisted configuration, validates schemas, and saves atomically.
- `services/platform/logging.lua` writes newline-delimited serialized event records.
- `services/platform/updating.lua` validates a package manifest, stages an exact file set, verifies staged contents, and activates it with rollback protection.
- `bootstrap/installer.lua` invokes the update service for a first installation.
- `interfaces/terminal/ui.lua` provides terminal output, headings, status messages, prompts, and progress rendering.

## Application contract for later milestones

An application directory beneath `/ralfie/apps` must contain `manifest.lua` returning an `id` and an `entry` path. The entry module must return a table exposing `start(context)`. The loader rejects duplicate IDs and malformed exports. No such application is included in this release.

## Launcher

After a normal install or update, type `ralf` from the computer's root shell to open the RalfieOS menu. `RalfieOS` is also installed as a root-shell launch command. The menu exposes Mining, Update, and Exit; Mining includes standalone miners and Fleet Worker when the installed manifest is version `0.2.0` or later.

The updater downloads the package manifest from the configured GitHub `main` branch, then replaces the complete managed `/ralfie` runtime from that manifest. It preserves `/ralfie-data` only. Thus a source-tree change is not deployable until the same manifest and files have been published to `main`; compare the version printed by `RalfieOS → Update` with the intended release before diagnosing a local modem or menu issue.

## Update source contract

Run `dofile("/ralfie/update.lua")` to update an installed system from the same GitHub source. Both install paths retain `/ralfie-data`, check free space when available, and preserve rollback data until staged activation succeeds. If an interruption leaves `/ralfie.previous` while `/ralfie` is absent, restore it with `move /ralfie.previous /ralfie` before starting again. Downloads are verified for completeness and staged byte writes, but GitHub branch contents are not cryptographically authenticated.

## Device Hub and profiles

RalfieOS 0.3 detects Turtle/Advanced Turtle, Pocket, and normal Computer hardware, plus wireless-modem and GPS capability. Its first run creates `/ralfie-data/device_profile.lua`; updates preserve this profile. A profile contains `device_name`, compatible `role`, `auto_start`, `fleet_name`, and optional role settings. Corrupt or incompatible profiles are ignored and the setup wizard is shown again. First-run Worker auto-start is saved for the next normal boot; setup always returns to a usable hub first.

Turtles can be `MINING_WORKER`, `STANDALONE_MINER`, or `UNCONFIGURED`. Pockets can be `FLEET_CONTROLLER` or `GENERAL`; normal computers offer `FLEET_CONTROLLER` or `GENERAL`. The hub offers only compatible roles. Device Setup changes local profile values; no remote profile-sync protocol exists.

`MINING_WORKER` with `auto_start = true` launches the existing Fleet Worker after profile load. Fleet Controller routes to the existing Pocket Fleet Command; `/ralfie-mining-command.lua` remains a direct shortcut. `/RalfieOS.lua` and standalone miner workflows remain supported. To reconfigure, choose Device Setup from the hub; delete `/ralfie-data/device_profile.lua` to force first-run setup.

## Terminal navigation

RalfieOS 0.3 uses a shared terminal menu layer on CC:Tweaked: Up/Down selects, Enter opens, and Backspace/Escape returns. Menus clip long labels and scroll on narrow Pocket screens. Color terminals use highlighted selections; monochrome terminals retain the `>` selection marker and textual status labels. Plain typed menu input remains as a compatibility fallback outside CraftOS.

## Remote device management

Fleet Command can request safe device information and edit one connected RalfieOS turtle. `DEVICE_INFO_REQUEST` returns identity, profile metadata, capabilities, worker/job state, software version, and configuration revision. `DEVICE_CONFIG_SET` is a patch with a unique request ID; currently only `device_name`, `fleet_name`, `auto_start`, and a safe role change are editable. The turtle validates and atomically saves the profile before `DEVICE_CONFIG_ACK SUCCESS` is returned. Duplicate request IDs replay the saved ACK for the current process only.

Role changes are rejected while a job or unsafe worker state is active. Offline devices cannot be edited; ERROR devices remain inspectable but are not made READY by configuration. Local Device Setup and remote changes use the same profile service. No offline queue, remote shell, arbitrary profile writes, ownership, or authentication is provided.

# Framework Guide

RalfieOS 0.1 targets the CC:Tweaked CraftOS Lua API. It contains platform infrastructure only; no turtle workflow applications are installed or started.

## Install and start

Place this repository on a ComputerCraft computer, change into the repository root, then run `shell.run("install.lua", "src/ralfie")`. The installer resolves the source through `shell.resolve`, copies the manifest-listed framework files to `/ralfie` through a staging directory, and preserves the current installation until activation succeeds.

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

## Update source contract

The updater currently accepts an absolute local source directory containing `manifest.lua`. A manifest declares `version`, `api_version`, and every relative file path to copy. Paths may not be absolute or contain `..`. It checks the destination drive has enough staging space when the filesystem exposes capacity information. If an interruption leaves `/ralfie.previous` while `/ralfie` is absent, restore it with `move /ralfie.previous /ralfie` before starting again. Remote transport and remote trust verification are intentionally not implemented yet.

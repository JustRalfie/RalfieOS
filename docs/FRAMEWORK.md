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

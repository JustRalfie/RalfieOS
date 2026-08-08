# RalfieOS Live Test: One CC:Tweaked Computer

Use a normal or advanced CC:Tweaked computer. Do not use a turtle for this test. Put a writable disk containing this repository at the computer; its files must be available as `/disk/install.lua` and `/disk/src/ralfie`.

At the Minecraft computer prompt, type exactly:

```lua
cd /disk
shell.run("install.lua", "src/ralfie")
dofile("/ralfie/start.lua")
ls /ralfie
ls /ralfie-data
type /ralfie-data/config/config.lua
type /ralfie-data/logs/ralfie.log
```

Expected results:

- The installer reports RalfieOS 0.1.0 installed at `/ralfie`.
- Startup prints `RalfieOS 0.1.0` and a `READY` status.
- `/ralfie-data/config/config.lua` and `/ralfie-data/logs/ralfie.log` exist.

Then verify persistence:

```lua
reboot
dofile("/ralfie/start.lua")
type /ralfie-data/logs/ralfie.log
```

The second startup must succeed and the log must contain another `bootstrap.ready` event.

To test a reinstall without losing configuration, run:

```lua
cd /disk
shell.run("install.lua", "src/ralfie")
dofile("/ralfie/start.lua")
```

To cleanly remove this framework test installation, type:

```lua
delete /ralfie
delete /ralfie-data
```

Do not create `/startup.lua` yet. RalfieOS currently has no long-running application to auto-start. If an interrupted update leaves `/ralfie` absent and `/ralfie.previous` present, recover before starting:

```lua
move /ralfie.previous /ralfie
dofile("/ralfie/start.lua")
```

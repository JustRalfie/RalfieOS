# RalfieOS Live Test: Remote Install

Use one normal or advanced CC:Tweaked computer or turtle with Internet access enabled for CC:Tweaked. No disk or local repository copy is required.

At the Minecraft computer prompt, type exactly:

```lua
wget https://raw.githubusercontent.com/JustRalfie/RalfieOS/main/install.lua install
install
dofile("/ralfie/start.lua")
ls /ralfie
ls /ralfie-data
type /ralfie-data/config/config.lua
type /ralfie-data/logs/ralfie.log
```

Expected results:

- The bootstrap reports each downloaded runtime file, then reports RalfieOS installed at `/ralfie`.
- Startup prints a `READY` status.
- `/ralfie-data/config/config.lua` and `/ralfie-data/logs/ralfie.log` exist.

Verify persistence and the installed remote updater:

```lua
reboot
dofile("/ralfie/start.lua")
dofile("/ralfie/update.lua")
dofile("/ralfie/start.lua")
type /ralfie-data/logs/ralfie.log
```

The update must download and stage every runtime file before replacing `/ralfie`. The `/ralfie-data` directory must remain present.

If an interrupted activation leaves `/ralfie` absent and `/ralfie.previous` present, recover with:

```lua
move /ralfie.previous /ralfie
dofile("/ralfie/start.lua")
```

To remove the test installation and its data:

```lua
delete /ralfie
delete /ralfie-data
delete install
```

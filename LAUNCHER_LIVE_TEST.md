# RalfieOS Launcher Live Test

After the launcher release is present on GitHub `main`, update an installed computer or turtle:

```lua
dofile("/ralfie/update.lua")
cd /
ralf
```

Expected main menu:

```text
RalfieOS
1. Mining
2. Update
3. Exit
```

Select `1` to view Mining. The Tunnel Miner description explains its 3x3 tunnel, torch, return-home, and behind-chest dumping behavior. Select `2` to return to the main menu. Select `3` from the main menu to return to the ComputerCraft shell.

The alternate root-shell command is:

```lua
RalfieOS
```

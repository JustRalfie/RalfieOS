# Testing

Tests are plain Lua 5.2-compatible scripts. Run them with a Lua 5.2-compatible runtime from the repository root:

```text
lua tests/run_all.lua
```

Run only the fleet protocol/network suite with:

```text
lua tests/mining_network_tests.lua
```

The suite uses deterministic fakes for turtle operations, inventory, filesystem, terminal, Rednet, modem discovery, GPS absence, and time. It does not require Minecraft. Rednet event/timer behavior used by Pocket UI and paused-worker waiting remains covered by the real-turtle smoke checklist because the unit tests use direct deterministic `receive` fakes.

## CC:Tweaked smoke checklist

1. Run standalone mining without a modem or Pocket.
2. Start Pocket Command and confirm discovery.
3. Pause an active miner; wait over 45 seconds and confirm it stays online.
4. Resume and confirm the same mining run continues.
5. Request UNLOAD; verify home dump and return to the saved mining position.
6. Request RETURN_HOME; verify final recall/dump.
7. Repeat a command ID where practical and confirm no action repeats.
8. Power off a turtle after ACK and confirm the Pocket shows `RESULT UNKNOWN`.

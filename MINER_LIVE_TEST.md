# Miner v0.1 Live Test

## Prepare the turtle

1. Use a Mining Turtle with enough fuel for the planned tunnel. Place it at the centre of the intended 3x3 tunnel entrance, on the tunnel floor, facing the mining direction.
2. Place a chest directly behind the turtle. It receives mined items only after successful completion.
3. Put torches in slot 16 and fuel in slot 15. Miner reserves both slots and never deposits their remaining contents.
4. Keep the first test short: use a distance of `5`. The default torch interval is 10, so no torch is required for that test; use distance `10` or more to verify torch placement.

## Install/update and run

After the Miner release is merged into GitHub `main`, type on the turtle:

```lua
dofile("/ralfie/update.lua")
dofile("/ralfie/miner.lua")
```

When prompted, enter:

```text
5
```

Expected result: Miner creates a 3x3 tunnel, returns to its starting block, faces its original direction, and deposits non-reserved inventory into the chest behind it.

## Torch test

For torch placement, ensure slot 16 contains at least one torch and run again with distance `10`:

```lua
dofile("/ralfie/miner.lua")
```

Enter `10`. Miner places a torch on the floor of the centre line at the configured interval.

## Configuration

Defaults are merged automatically on boot:

```lua
miner = {
  torch_interval = 10,
  torch_slot = 16,
  fuel_slot = 15,
  safety_margin = 20,
  movement_retries = 3,
}
```

To customize them, edit `/ralfie-data/config/config.lua`, preserving the serialized Lua-table format, then restart Miner. Torch and fuel slots must be different slots from 1 to 16.

## Safety checks

- Miner refuses to start if fuel cannot cover planned excavation travel, return travel, and safety margin.
- If a move remains blocked after retries, Miner stops and reports the failure; do not move the turtle manually before recording or resolving the problem.
- Miner v0.1 does not handle lava, full-inventory return/resume, GPS recovery, or ore-following.

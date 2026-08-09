# Profile recovery

RalfieOS 0.3.1 never starts Fleet Worker in the same process that created its first profile. Auto-start applies only after a later normal boot.

If an old profile causes worker startup to fail, RalfieOS returns to the hub with the failure message. To reset only the device profile without touching jobs, logs, or configuration, run:

```lua
fs.delete("/ralfie-data/device_profile.lua")
```

Then restart `RalfieOS`, complete setup, confirm the hub is usable, and reboot once to test Worker auto-start. On a turtle without a wireless modem, Worker startup fails cleanly and the hub remains available.

# Mining Fleet Communication

The optional fleet layer uses Rednet protocol `ralfie:mining:v1` (version `1`). Every envelope contains `protocol`, `version`, `type`, and a `sender` identity with the ComputerCraft computer ID and optional computer label. The supported message types are `HELLO`, `HELLO_ACK`, `STATUS_REQUEST`, `STATUS`, `PING`, and `PONG`.

Run the Pocket Computer application with `dofile("/ralfie/pocket/main.lua")` (or `/ralfie-mining-command.lua` after installation). It opens a wireless modem, broadcasts `HELLO` at startup and every 30 seconds, and records compatible `HELLO_ACK`/`STATUS` responses by computer ID.

When a miner is running, its optional network client opens any available wireless modem. It responds to discovery with `HELLO_ACK` and `STATUS`, answers status and ping requests, and broadcasts a status heartbeat at most every 15 seconds. The client is polled both on miner status updates and at every navigation state change, so long ore returns, unload trips, and the final home return continue to refresh the heartbeat without altering movement logic. The Pocket considers a miner offline after 45 seconds without communication, but retains its last known entry.

`STATUS` reports the live miner UI state, turtle fuel, occupied inventory slots, job ID when present, and software version. GPS coordinates are included only when `gps.locate()` succeeds; the miner's internal relative navigation position is never presented as GPS data. No modem is required: mining continues locally if networking is unavailable or fails.

## Return Home command

`COMMAND` currently supports only `RETURN_HOME`. Its payload contains a unique `command_id`, `command`, `target_id`, and `issued_by`. The target validates the envelope, sender, target ID, and command before replying directly to the issuing Pocket with `COMMAND_ACK`.

An `ACCEPTED` acknowledgement means the request was recorded, not that the turtle is home. The miner waits for the existing slice-safe boundary, then uses its normal return, refill, and dump sequence. It sends `COMMAND_RESULT` with `SUCCESS` or `FAILED` when that sequence ends. Pocket ACK timeout is 10 seconds; a missing ACK is distinct from a long in-progress physical return, which remains visible through normal heartbeats/status.

Each miner keeps the latest 20 command IDs. Duplicate delivery resends the saved ACK and, once available, the saved result without starting another return. Multiple Pocket Computers can issue commands; there is currently no ownership, locking, or authentication, so controllers must coordinate externally.

Accepted commands move from pending to executing at the slice-safe boundary, then to one terminal result: `SUCCESS` or `FAILED` (with `CANCELLED` reserved for a future explicit cancellation path). The miner finalizes accepted commands through one guarded path, so a normal miner failure before the safe boundary also produces `FAILED`. History is in-memory only: idempotency and result replay last for the current miner process, not across a reboot.

If the Pocket loses contact after an ACK, it shows `RESULT UNKNOWN`, not a guessed failure. When the miner reappears, the Pocket replays the same command ID so the bounded history can return the stored ACK/result.

`UNLOAD` uses the same command lifecycle but is distinct from `RETURN_HOME`: at the next completed slice boundary it invokes the existing `Unloading:run` operation, which returns home, dumps, restores the saved mining position/heading, and resumes work. Success means that whole operation completed, even if the inventory was already empty. `RETURN_HOME` takes precedence: it cancels queued UNLOAD commands, and a later UNLOAD while return is pending/active receives `BUSY`.

`PAUSE` is accepted during active work and completes only at the completed slice boundary. The miner then reports `PAUSED`, preserves its current checkpointed position and slice state, and waits with timed Rednet receives so heartbeats, status requests, duplicate replay, RETURN_HOME, and RESUME remain responsive without busy polling. `RESUME` is accepted only from `PAUSED` and returns the miner to normal slice progression. RETURN_HOME cancels a queued PAUSE and can recall a paused turtle; UNLOAD while paused is `BUSY`. A PAUSE received during unload waits until that operation has resumed safely.

## Fleet Worker and mining jobs

Fleet Worker is an explicit alternative to the standalone Tunnel Miner. Start it from `RalfieOS` → `Mining` → `Fleet Worker`. It remains in `READY` without moving, using timed Rednet waits for discovery, status requests, pings, heartbeats, and job assignments. A wireless modem is required for this mode; the standalone miner remains unchanged and does not require a Pocket Computer.

The protocol adds `JOB_ASSIGN`, `JOB_ACK`, `JOB_STATUS`, and `JOB_RESULT`. The first and only supported job is `MINING` with a positive whole-number `distance`:

```lua
{ job_id = "job-123", target_id = 17, issued_by = 5, job = { type = "MINING", distance = 100 } }
```

`JOB_ACK ACCEPTED` assigns responsibility, not completion. A worker accepts only while `READY`; malformed distances receive `INVALID`, another job type receives `REJECTED`, and active or error workers receive `BUSY`. The worker calls the existing `Miner.start` implementation with that same `distance`; it does not implement movement, ore handling, unloading, or return logic itself.

An active job reports its ID, type, distance, and lifecycle through regular `STATUS` and direct `JOB_STATUS` transitions. Terminal `JOB_RESULT` is exactly one of `SUCCESS`, `FAILED`, or `CANCELLED`. Normal completion returns the worker to `READY`. A managed miner failure reports `FAILED` and leaves the worker in `ERROR`, rather than claiming it can safely accept another job. RETURN_HOME cancels the active job at the miner's existing safe boundary, then completes or fails independently as a command; a successful final return returns the worker to `READY`.

PAUSE, RESUME, and UNLOAD continue to operate on the same active job; they do not create or complete it. A job ID is idempotent for the current worker process: the newest 20 IDs retain their ACK and terminal result for replay, but rebooting the turtle clears that in-memory history. Multiple Pocket Computers remain unarbitrated; a second job assignment while one is active is `BUSY`.

## Fleet updates

The Pocket's Fleet overview provides `Update All`. It sends a targeted `DEVICE_UPDATE_REQUEST` with a bounded, in-memory `request_id` to each online worker in `READY` or `PAUSED`. The worker validates its target and state, then invokes its own existing GitHub updater; the Pocket never sends program files over Rednet. `DEVICE_UPDATE_RESULT` reports `SUCCESS`, `FAILED`, `BUSY`, or `REJECTED` directly to the issuing Pocket. Successful remote updates report `restart_required = true`, so workers can be restarted deliberately after any paused work is handled.

Workers in active states are not updated by this action and are listed as `BUSY`. Duplicate request IDs replay the stored result and do not run the updater twice. Once all remote results or timeouts have been collected, the Pocket updates and reboots itself last.

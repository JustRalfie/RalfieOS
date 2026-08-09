# Fleet Worker real-turtle smoke test

Use one Mining Turtle and one Pocket Computer. Both need a wireless modem, must be within Rednet range, and must run the same RalfieOS version. Put a chest directly behind the turtle's starting position. Stock the turtle exactly as the existing Tunnel Miner expects: fuel in its configured fuel slot, torches in its configured torch slot, fillers in its configured filler slot, and enough fuel for the selected test distance. Use a clear, disposable test tunnel; start with distance `5`.

## Worker discovery and first job

- [ ] Start RalfieOS on the turtle, choose `Mining`, then `Fleet Worker`.
- [ ] Confirm the turtle shows `READY`. Starting this mode without a wireless modem must show a clean modem-required failure and must not retry forever.
- [ ] On the Pocket, run `/ralfie-mining-command.lua` (or `dofile("/ralfie/pocket/main.lua")`).
- [ ] Confirm the worker is discovered automatically with its computer ID, label, `READY`, fuel, inventory usage, and no job.
- [ ] Select it, press `J`, enter `5`, and confirm with `Y`.
- [ ] Confirm `JOB_ACK ACCEPTED`, then worker `STARTING`/`RUNNING`, an active job ID, and distance `5` appear on the Pocket.
- [ ] Watch the turtle execute the normal Tunnel Miner behavior; the worker must not use a different movement pattern.

## Natural completion and reassignment

- [ ] Allow the distance-5 job to finish.
- [ ] Confirm `JOB_RESULT SUCCESS`, the normal final return/dump behavior, and that Fleet Worker stays running.
- [ ] Confirm its Pocket state returns to `READY`.
- [ ] Assign a second small job without restarting Fleet Worker.

## Pause and resume

- [ ] During a running job send `P` (Pause). Confirm the command ACK is accepted but movement stops only at a safe checkpoint.
- [ ] Confirm state becomes `PAUSED`; retain the displayed job ID.
- [ ] Leave the turtle paused for at least 60 seconds. It must remain ONLINE on the Pocket.
- [ ] Send `C` (Resume). Confirm the same job ID resumes from its prior progress rather than beginning distance zero.

## Remote unload

Use a job that has collected items and a known-working chest behind the original start position.

- [ ] Send `U` (Unload) while the job is running.
- [ ] Confirm accepted ACK, then observe the existing home/dump/return-to-work route.
- [ ] Confirm items were deposited, the turtle returns to the work position, and the same job ID continues.
- [ ] Confirm `UNLOAD` eventually reports `SUCCESS`.

## Return home cancels the job

- [ ] During a running job send `R` (Return Home).
- [ ] Confirm the active job becomes `CANCELLED` at its safe boundary.
- [ ] Separately confirm the RETURN_HOME command reaches `SUCCESS` only after normal final return/dump behavior.
- [ ] Confirm the worker returns to `READY` and can accept another job.

Expected distinction:

```text
Job: CANCELLED
RETURN_HOME: SUCCESS
```

## Error safety test

Use only a disposable setup. A safe managed failure is to assign distance `10` with the configured torch slot deliberately empty; the miner should fail its existing preflight validation before moving.

- [ ] Confirm `JOB_RESULT FAILED` includes a concise reason.
- [ ] Confirm the worker shows `ERROR`, not `READY`.
- [ ] Confirm another JOB_ASSIGN receives `BUSY`; do not attempt automatic recovery.

## Pocket restart and input safety

- [ ] While a job is running, exit and restart the Pocket app.
- [ ] Confirm discovery restores the active worker, job ID, state/lifecycle, and distance. The turtle must continue unaffected.
- [ ] In the job screen try blank input, `0`, a negative number, letters, and a decimal. Each must show `Invalid distance` and send no job.
- [ ] Try a valid small integer. The Pocket sends it, and the worker repeats validation before accepting it.

## Known limitations

- Worker/job/command history is in memory only. Rebooting the turtle loses active lifecycle and duplicate replay history; the Pocket must treat the outcome as unknown.
- Rebooting the Pocket does not affect the turtle; rediscovery shows its current worker/job status.
- Multiple Pocket controllers have no ownership or arbitration. A busy worker rejects another job assignment.
- No persistence, recovery movement, scheduling, queues, or multi-turtle allocation exists.

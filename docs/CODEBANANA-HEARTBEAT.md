# CodeBanana Heartbeat — Desktop Commander self-heal

The container uses a CodeBanana heartbeat/scheduled task as the practical self-healing layer.

## Heartbeat action

From the workspace root, run:

```sh
sh dc-remote.sh start
```

The command is intentionally idempotent.

## Recovery rules

- `WAITING FOR AUTH`: do not start another instance. Complete browser device authentication, then run `sh dc-remote.sh backup`.
- `FAILED` or `TIMEOUT`: inspect the last 30 lines of `logs/desktop-commander.log`, fix the root cause, and retry once.
- Network failure to `mcp.desktopcommander.app`: report the failure and allow the next heartbeat to retry.
- If stale duplicate instances exist: run `sh dc-remote.sh stop`, then `sh dc-remote.sh start`.
- Finish with `sh dc-remote.sh status`.

## Why heartbeat instead of systemd

The CodeBanana container runtime does not expose a user service registry/CLI for arbitrary persistent processes, and the verified container uses `tini` rather than systemd. The heartbeat therefore provides the runtime-level recovery trigger while `dc-remote.sh` handles process lifecycle inside the persistent workspace.

## Persistence

The session backup lives at:

```text
.desktop-commander-backup/device.json
```

It must remain outside Git tracking and must never be replaced with a committed credential.

## Expected recovery

```text
container/process reset
        -> CodeBanana heartbeat
        -> agent session executes dc-remote.sh start
        -> restore device.json
        -> launch remote --persist-session
        -> verify Device ready
        -> backup session
```

With a heartbeat around 10 minutes, recovery is near-realtime rather than an instant post-boot hook.

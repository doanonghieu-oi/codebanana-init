# Runbook: Desktop Commander Remote — CodeBanana Container

This runbook documents the verified deployment pattern for Desktop Commander Remote in a CodeBanana container.

## Architecture

```text
CodeBanana runtime heartbeat (~10 min)
        |
        v
agent session -> sh dc-remote.sh start
        |
        +-> restore .desktop-commander-backup/device.json
        |
        +-> npx -y @wonderwhy-er/desktop-commander@latest remote --persist-session
        |
        +-> persistent logs + backup
        |
        +-> outbound WebSocket to mcp.desktopcommander.app
```

## Important architecture facts

- Desktop Commander Remote is an outbound WebSocket client. It does **not** need an HTTP port, public domain, `start_web_service`, or an ngrok tunnel.
- CodeBanana's `start_web_service` is intended for HTTP development servers and is agent-invoked; it is not a shell service registry.
- The container does not provide a user-accessible systemd/supervisor/pm2/cron service manager for this purpose.
- The practical self-healing mechanism is a CodeBanana scheduled/heartbeat task which invokes the persistent `dc-remote.sh start` wrapper.
- `dc-remote.sh start` is idempotent, restores the session before launch, prevents duplicate instances, waits for a healthy `Device ready` marker, and backs up the session after successful startup.

## Authentication and persistence

Desktop Commander uses an OAuth Device Flow with PKCE. The first run prints a verification URL and user code. Authentication does not require an OAuth callback, local callback port, public domain, or ngrok.

Persistent state:

```text
~/.desktop-commander-device/device.json
```

The persistent workspace copy is:

```text
.desktop-commander-backup/device.json
```

Never commit the backup file, `.env`, access tokens, refresh tokens, or other credentials.

## First authentication

```sh
cd /data/coda/dr4awfq4/ws/57f5a4ee-6368-4733-a527-2cf00cacf775
sh dc-remote.sh start
```

If the output says `WAITING FOR AUTH`, open the displayed verification URL, enter the displayed code, and approve the device. Then:

```sh
sh dc-remote.sh backup
sh dc-remote.sh status
```

Later starts restore the persisted session automatically and should not require authentication again.

## Normal operation

```sh
sh dc-remote.sh start
sh dc-remote.sh status
sh dc-remote.sh logs 30
```

Useful commands:

```sh
sh dc-remote.sh stop
sh dc-remote.sh restart
sh dc-remote.sh backup
sh dc-remote.sh restore
sh dc-remote.sh doctor
```

## Self-healing

The CodeBanana heartbeat task should execute:

```sh
sh dc-remote.sh start
```

The wrapper is safe to run repeatedly. If the process is already healthy it exits without creating a duplicate. If the process has died or the container has restarted, it restores the persistent session and starts a new instance.

Recovery is heartbeat-based rather than an instant post-container-boot hook. With a ~10 minute heartbeat, recovery can take up to roughly one heartbeat interval.

## Verification

```sh
sh dc-remote.sh status
pgrep -af 'desktop-commander'
sh dc-remote.sh logs 30
```

A healthy state should show one Desktop Commander process tree and a log containing `Device ready`.

The Remote connection is outbound, so an HTTP listener on ports 8000/8001/9100/9101 is not required for Desktop Commander.

## CodeBanana domain/port allocation

CodeBanana may expose general web preview domains such as `app-preview-*.codebanana.com` and mobile development tunnels such as `m-*.ngrok.app`. These allocations are unrelated to Desktop Commander Remote.

The exact runtime mapping is obtained from CodeBanana's agent-side `get_all_domains_ports()` tool. It is not a shell executable and should not be hard-coded into this deployment.

## Container model

The verified container uses `tini` as PID 1 rather than systemd. Therefore do not rely on:

```text
systemctl
supervisorctl
pm2
cron
```

for this deployment unless the container image changes and those components are explicitly installed/configured.

## Removing the local deployment

```sh
sh dc-remote.sh stop
rm -f .desktop-commander-backup/device.json
```

Removing the backup intentionally forgets the persisted Desktop Commander session and requires authentication again.

## Security

- Keep `.desktop-commander-backup/` gitignored.
- Keep `.env` gitignored.
- Keep session files mode `0600`.
- Do not print access or refresh tokens into logs or documentation.
- The scripts should never require a GitHub token for normal Desktop Commander operation.

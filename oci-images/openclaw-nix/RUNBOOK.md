# OpenClaw Nix - Podman Smoke QA Runbook

Quick reference for local Podman testing of the openclaw-nix image.

## Build

```bash
nix build .#openclaw-nix-image
```

## Load into Podman

```bash
podman load < result
```

## Run (Rootless)

Create directories first:

```bash
mkdir -p ~/.local/share/openclaw-nix/{state,logs,config}
```

Run the container:

```bash
podman run -d \
  --name openclaw-nix \
  --userns=keep-id \
  --user $(id -u):$(id -g) \
  -v ~/.local/share/openclaw-nix/state:/state:Z \
  -v ~/.local/share/openclaw-nix/logs:/logs:Z \
  -v ~/.local/share/openclaw-nix/config:/config:Z \
  -p 18789:18789 \
  localhost/openclaw-nix:dev
```

## Environment Variables (Optional)

Pass additional env vars with `-e`:

```bash
podman run -d \
  --name openclaw-nix \
  --userns=keep-id \
  --user $(id -u):$(id -g) \
  -v ~/.local/share/openclaw-nix/state:/state:Z \
  -v ~/.local/share/openclaw-nix/logs:/logs:Z \
  -v ~/.local/share/openclaw-nix/config:/config:Z \
  -p 18789:18789 \
  -e TZ=America/New_York \
  -e OPENCLAW_STATE_DIR=/state/openclaw \
  -e HOME=/state/home \
  localhost/openclaw-nix:dev
```

## Verification

Check logs:

```bash
podman logs -f openclaw-nix
```

Check gateway is listening:

```bash
curl http://localhost:18789/health
```

Verify toolchain inside container:

```bash
podman exec -it openclaw-nix bash -c "which uv && uv --version"
podman exec -it openclaw-nix bash -c "which gemini-cli && gemini-cli --version"
podman exec -it openclaw-nix bash -c "which gh && gh --version"
podman exec -it openclaw-nix bash -c "which ffmpeg && ffmpeg -version | head -1"
```

Check state persistence:

```bash
ls -la ~/.local/share/openclaw-nix/state/
ls -la ~/.local/share/openclaw-nix/logs/
```

## Cleanup

```bash
podman stop openclaw-nix
podman rm openclaw-nix
podman rmi localhost/openclaw-nix:dev
```

## Volume Reference

| Container Path | Purpose | Persistence |
|----------------|---------|-------------|
| `/state` | Workspace, creds, tools, caches | Yes |
| `/logs` | Application logs | Yes |
| `/config` | Config file (seeded from template) | No (ephemeral) |

## Key Environment Variables

| Variable | Default Value | Purpose |
|----------|---------------|---------|
| `OPENCLAW_STATE_DIR` | `/state/openclaw` | State directory |
| `OPENCLAW_CONFIG_PATH` | `/config/openclaw.json` | Config file path |
| `HOME` | `/state/home` | Writable home directory |
| `PATH` | `/state/bin:/state/npm/bin:/bin:/usr/bin` | Runtime tools |
| `NPM_CONFIG_PREFIX` | `/state/npm` | Global npm installs |
| `XDG_CACHE_HOME` | `/state/cache` | All caches |
| `SSL_CERT_FILE` | `/etc/ssl/certs/ca-bundle.crt` | TLS certificates |

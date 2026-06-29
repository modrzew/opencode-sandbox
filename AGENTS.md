# OpenCode Sandbox

## What this is

A Docker-based sandbox that runs OpenCode (AI coding agent) inside an Apple Container, with worktree support and host config passthrough.

## Developer commands

- `./ocsbx.sh` — start a fresh sandbox session
- `./ocsbx.sh <hash>` — resume a previous session (hash printed at end of each run)
- `container exec -it oc-<repo>-<hash> opencode -c` — exec into a running container
- `container stop oc-<repo>-<hash>` — stop a container

## Architecture

- **`ocsbx.sh`** — orchestrator: resolves git toplevel/common dirs, detects linked worktrees, mounts volumes, runs `container run`
- **`entrypoint.sh`** — runs inside container: copies host OpenCode config/data/state from `/tmp/*`, replaces `localhost` with `host.container.internal`, sets `permission: {}` (yolo mode), injects SSH key if present
- **`Dockerfile`** — debian bookworm slim → installs gh CLI, Node 22, Bun, OpenCode

## Key details

- Uses Apple `container` CLI (not Docker CLI) — defined in `ocsbx.sh`
- Worktree-aware: if `.git` is shared outside the working tree (linked worktree), the script mounts it separately
- `sandbox.env` is gitignored; copy from `sandbox.env.example` to configure `SSH_KEY_PATH`, `GIT_NAME`, `GIT_EMAIL`
- Host OpenCode config lives at `~/.config/opencode`, data at `~/.local/share/opencode`, state at `~/.local/state/opencode` — all mounted into container at `/tmp/` paths
- `GH_TOKEN` is captured live from `gh auth token` on the host at runtime
- `git config --global gc.auto 0` in Dockerfile to prevent GC conflicts on shared .git folders

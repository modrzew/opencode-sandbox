# OpenCode Sandbox

## What this is

A Docker-based sandbox that runs a coding agent — **`opencode`** or **`pi`** — inside an Apple Container, with worktree support and host config passthrough.

## Developer commands

- `./ocsbx.sh` — start a fresh session with the default agent (`AGENT` in `sandbox.env`, else `opencode`)
- `./ocsbx.sh pi` / `./ocsbx.sh opencode` — start a fresh session with a named agent
- `./ocsbx.sh <hash>` — resume a previous session (hash printed at end of each run); the container's agent is remembered
- `container exec -it oc-<repo>-<hash> <agent> -c` — exec into a running container
- `container stop oc-<repo>-<hash>` — stop a container

## Architecture

- **`ocsbx.sh`** — orchestrator: resolves git toplevel/common dirs, detects linked worktrees, picks the agent (first arg = agent name → fresh; a known agent name is never a hash), builds per-agent volume mounts, runs `container run ... -e OCSBX_AGENT=<agent> <agent>`
- **`entrypoint.sh`** — runs inside container: switches on `OCSBX_AGENT` to copy that agent's host config from `/tmp/*` into `/root`, rewrites `localhost` → `host.container.internal`, applies headless settings (opencode: `permission: {}`; pi: launched with `-a`), writes `/root/.ocsbx-agent` so resume continues the right agent, then injects SSH key / git identity
- **`Dockerfile`** — debian bookworm slim → installs gh CLI, Node 22, Bun, OpenCode, and pi (`@earendil-works/pi-coding-agent`)

## Key details

- Uses Apple `container` CLI (not Docker CLI) — defined in `ocsbx.sh`
- Agents both resume with `-c`; resume reads the agent from `/root/.ocsbx-agent` in the container, so `./ocsbx.sh <hash>` needs no agent argument
- Worktree-aware: if `.git` is shared outside the working tree (linked worktree), the script mounts it separately
- `sandbox.env` is gitignored; copy from `sandbox.env.example` to configure `SSH_KEY_PATH`, `GIT_NAME`, `GIT_EMAIL`, and the default `AGENT`
- Host config per agent (mounted read-only into `/tmp/*`, copied to `/root` by the entrypoint):
  - opencode → `~/.config/opencode`, `~/.local/share/opencode`, `~/.local/state/opencode`
  - pi → `~/.pi/agent` (holds `auth.json`, `settings.json`, `sessions/`, …); run `pi` + `/login` once on the host first
- `GH_TOKEN` is captured live from `gh auth token` on the host at runtime
- `git config --global gc.auto 0` in Dockerfile to prevent GC conflicts on shared .git folders

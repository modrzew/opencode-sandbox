#!/bin/bash

AGENT="${OCSBX_AGENT:-opencode}"

# Populate an agent home at $dest from the read-only host copy mounted at $src.
# Heavy, immutable dirs named in $3.. (package trees, vendored binaries) are
# symlinked straight to the read-only mount — copying them is the single biggest
# startup cost (hundreds of MB / thousands of files over virtiofs). Everything
# else is copied so it stays writable and container-local (config we rewrite,
# sessions, databases).
sync_agent_home() {
    local src="$1" dest="$2"; shift 2
    local link=" $* " entry base
    mkdir -p "$dest"
    for entry in "$src"/* "$src"/.[!.]*; do
        [ -e "$entry" ] || continue
        base=$(basename "$entry")
        case "$link" in
            *" $base "*) ln -s "$entry" "$dest/$base" ;;
            *)           cp -r "$entry" "$dest/$base" ;;
        esac
    done
}

# --- Per-agent config setup ---
# Host config is mounted read-only under /tmp; copy it into the agent's real
# home location so the agent can write to it, then apply sandbox tweaks.
case "$AGENT" in
  opencode)
    mkdir -p /root/.config /root/.local/share /root/.local/state
    # node_modules (~tens of MB of plugins) is read-only at runtime → symlink it
    sync_agent_home /tmp/opencode-config /root/.config/opencode node_modules
    cp -r /tmp/opencode-data  /root/.local/share/opencode
    cp -r /tmp/opencode-state /root/.local/state/opencode

    # Replace LLM endpoints to host.container.internal
    sed -i 's/localhost/host.container.internal/g' /root/.config/opencode/opencode.json
    # Replace permissions object with {} (ie. yolo mode)
    python3 -c "
import re, json
path='/root/.config/opencode/opencode.json'
raw = open(path).read()
cfg = json.loads(re.sub(r',\s*([}\]])', r'\1', raw))
cfg['permission'] = {}
open(path, 'w').write(json.dumps(cfg, indent=2) + '\n')
"
    ;;
  pi)
    # ~/.pi/agent holds auth.json, settings.json, sessions/, skills/, …
    # npm/ (installed subagents & MCP adapters) and bin/ (fd, rg) are read-only
    # at runtime and account for ~almost all of the dir's size → symlink them.
    sync_agent_home /tmp/pi-agent /root/.pi/agent npm bin
    # Replace LLM endpoints to host.container.internal (if a local provider is configured)
    [ -f /root/.pi/agent/models.json ] && sed -i 's/localhost/host.container.internal/g' /root/.pi/agent/models.json
    ;;
esac

# Record which agent this container runs, so resume continues the right one.
echo "$AGENT" > /root/.ocsbx-agent

# --- Git & GitHub setup ---

# Inject SSH key
if [ -f /tmp/ocsbx-ssh-key ]; then
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  cp /tmp/ocsbx-ssh-key /root/.ssh/id_ed25519
  chmod 600 /root/.ssh/id_ed25519
  # github.com host keys are baked into the image (/etc/ssh/ssh_known_hosts) at
  # build time — no runtime ssh-keyscan, which otherwise stalls ~5s when offline.
fi

# Set git identity
[ -n "${GIT_NAME:-}" ] && git config --global user.name "$GIT_NAME"
[ -n "${GIT_EMAIL:-}" ] && git config --global user.email "$GIT_EMAIL"

# gh will use GH_TOKEN env var automatically for authentication

exec "$@"

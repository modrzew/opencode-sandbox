#!/bin/bash

AGENT="${OCSBX_AGENT:-opencode}"

# --- Per-agent config setup ---
# Host config is mounted read-only under /tmp; copy it into the agent's real
# home location so the agent can write to it, then apply sandbox tweaks.
case "$AGENT" in
  opencode)
    mkdir -p /root/.config /root/.local/share /root/.local/state
    cp -r /tmp/opencode-config /root/.config/opencode
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
    mkdir -p /root/.pi
    cp -r /tmp/pi-agent /root/.pi/agent
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
  ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null || true
fi

# Set git identity
[ -n "${GIT_NAME:-}" ] && git config --global user.name "$GIT_NAME"
[ -n "${GIT_EMAIL:-}" ] && git config --global user.email "$GIT_EMAIL"

# gh will use GH_TOKEN env var automatically for authentication

exec "$@"

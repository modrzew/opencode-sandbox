#!/usr/bin/env bash
# ocsbx — coding agents (opencode, pi) in an Apple Container sandbox, worktree-aware
set -euo pipefail

IMAGE="opencode-sandbox"
AGENTS="opencode pi"
DEFAULT_AGENT="opencode"

is_agent() {
    local candidate="$1" a
    for a in $AGENTS; do
        [ "$candidate" = "$a" ] && return 0
    done
    return 1
}

# Resume command for a given agent (both continue the most recent session with -c)
resume_command() {
    case "$1" in
      pi) echo "pi -c -a" ;;
      *)  echo "opencode -c" ;;
    esac
}

# absolute, symlink-resolved paths
toplevel=$(git rev-parse --show-toplevel); toplevel=$(cd "$toplevel" && pwd -P)
common=$(git rev-parse --path-format=absolute --git-common-dir); common=$(cd "$common" && pwd -P)

# Resolve the real path of this script (follows symlinks) to find sandbox.env
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/sandbox.env"
# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

hash=$(openssl rand -hex 4)

# Stop the container when this script exits — whether the agent quits normally,
# the terminal is closed (HUP), or the script is killed (INT/TERM). Without this,
# the container daemon keeps the container running after the client detaches.
name=""
cleanup() { [ -n "$name" ] && container stop "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM HUP

# compute container name from hash
compute_name() {
    local h="$1"
    case "$common/" in
      "$toplevel"/*)
        echo "oc-$(basename "$toplevel")-$h"
        ;;
      *)
        echo "oc-$(basename "$(dirname "$common")")-$(basename "$toplevel")-$h"
        ;;
    esac
}

# --- decide mode from the (optional) first argument ---
#   ./ocsbx.sh            fresh, default agent (AGENT from sandbox.env or opencode)
#   ./ocsbx.sh <agent>    fresh, named agent (opencode | pi)
#   ./ocsbx.sh <hash>     resume the container with that hash (agent remembered)
if [ $# -ge 1 ] && is_agent "$1"; then
    MODE="fresh"; AGENT="$1"
elif [ $# -ge 1 ]; then
    MODE="resume"; hash="$1"
else
    MODE="fresh"; AGENT="${AGENT:-$DEFAULT_AGENT}"
fi

if [ "$MODE" = "resume" ]; then
    name=$(compute_name "$hash")
    if ! container start "$name" >/dev/null 2>&1; then
        echo "Error: container $name not found"
        exit 1
    fi
    sleep 1
    # The container records which agent it runs; continue that one.
    AGENT=$(container exec "$name" cat /root/.ocsbx-agent 2>/dev/null | tr -d '[:space:]')
    AGENT="${AGENT:-$DEFAULT_AGENT}"
    read -ra resume_cmd <<< "$(resume_command "$AGENT")"
    set +e
    container exec -it "$name" "${resume_cmd[@]}"
    set -e
else
    if ! is_agent "$AGENT"; then
        echo "Error: unknown agent '$AGENT' (known: $AGENTS)"
        exit 1
    fi

    name=$(compute_name "$hash")

    # always mount the working tree at its own absolute path
    mounts=(-v "$toplevel:$toplevel")

    # the worktree check: if the shared .git lives OUTSIDE the tree, mount it too
    case "$common/" in
      "$toplevel"/*) ;;                     # main repo — .git already inside the mount
      *) mounts+=(-v "$common:$common") ;;  # linked worktree — add the shared .git
    esac

    # Mount SSH key if configured (only if outside the mounted directory)
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "$SSH_KEY_PATH" ]; then
        resolved_key=$(cd "$(dirname "$SSH_KEY_PATH")" && pwd -P)/$(basename "$SSH_KEY_PATH")
        case "$resolved_key/" in
          "$toplevel"/*) ;;
          *) mounts+=(-v "$SSH_KEY_PATH:/tmp/ocsbx-ssh-key:ro") ;;
        esac
    fi

    # Per-agent config mounts + launch command
    launch=()
    case "$AGENT" in
      opencode)
        [ -d "$HOME/.config/opencode" ] || echo "Warning: $HOME/.config/opencode not found — opencode may be unconfigured."
        mounts+=(
          -v "$HOME/.config/opencode:/tmp/opencode-config:ro"
          -v "$HOME/.local/share/opencode:/tmp/opencode-data:ro"
          -v "$HOME/.cache/opencode:/root/.cache/opencode"
          -v "$HOME/.local/state/opencode:/tmp/opencode-state:ro"
        )
        launch=(opencode)
        ;;
      pi)
        [ -d "$HOME/.pi/agent" ] || echo "Warning: $HOME/.pi/agent not found — run 'pi' then '/login' on the host first."
        mounts+=(-v "$HOME/.pi/agent:/tmp/pi-agent:ro")
        launch=(pi -a)
        ;;
    esac

    # Capture gh token live from host
    GH_TOKEN=$(gh auth token 2>/dev/null || true)

    container run -it --name "$name" \
      --cpus 4 --memory 6g \
      "${mounts[@]}" -w "$toplevel" \
      -e GH_TOKEN="$GH_TOKEN" \
      -e GIT_NAME="${GIT_NAME:-}" \
      -e GIT_EMAIL="${GIT_EMAIL:-}" \
      -e OCSBX_AGENT="$AGENT" \
      "$IMAGE" "${launch[@]}"
fi

echo ""
echo "Resume: ./ocsbx.sh $hash"
echo "Or: container exec -it $name $(resume_command "$AGENT")"

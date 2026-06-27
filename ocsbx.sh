#!/usr/bin/env bash
# ocsbx — OpenCode in an Apple Container sandbox, worktree-aware
set -euo pipefail

IMAGE="opencode-sandbox"

# absolute, symlink-resolved paths
toplevel=$(git rev-parse --show-toplevel); toplevel=$(cd "$toplevel" && pwd -P)
common=$(git rev-parse --path-format=absolute --git-common-dir); common=$(cd "$common" && pwd -P)

hash=$(openssl rand -hex 4)

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

# --- resume mode: ./ocsbx.sh <hash> ---
if [ $# -ge 1 ]; then
    hash="$1"
    name=$(compute_name "$hash")
    if ! container start "$name" >/dev/null 2>&1; then
        echo "Error: container $name not found"
        exit 1
    fi
    sleep 1
    set +e
    container exec -it "$name" opencode -c
    rc=$?
    container stop "$name" >/dev/null 2>&1
    set -e
else
    # --- fresh mode: ./ocsbx.sh ---
    name=$(compute_name "$hash")

    # always mount the working tree at its own absolute path
    mounts=(-v "$toplevel:$toplevel")

    # the worktree check: if the shared .git lives OUTSIDE the tree, mount it too
    case "$common/" in
      "$toplevel"/*) ;;                     # main repo — .git already inside the mount
      *) mounts+=(-v "$common:$common") ;;  # linked worktree — add the shared .git
    esac

    # Resolve the real path of this script (follows symlinks) to find sandbox.env
    SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
    CONFIG_FILE="$SCRIPT_DIR/sandbox.env"
    source "$CONFIG_FILE"

    # Mount SSH key if configured (only if outside the mounted directory)
    if [ -n "$SSH_KEY_PATH" ] && [ -f "$SSH_KEY_PATH" ]; then
        resolved_key=$(cd "$(dirname "$SSH_KEY_PATH")" && pwd -P)/$(basename "$SSH_KEY_PATH")
        case "$resolved_key/" in
          "$toplevel"/*) ;;
          *) mounts+=(-v "$SSH_KEY_PATH:/tmp/opencode-ssh-key:ro") ;;
        esac
    fi

    # Capture gh token live from host
    GH_TOKEN=$(gh auth token 2>/dev/null || true)

    # container start -ai "$name" 2>/dev/null || \
    container run -it --name "$name" \
      --cpus 4 --memory 8g \
      "${mounts[@]}" -w "$toplevel" \
      -v ~/.config/opencode:/tmp/opencode-config:ro \
      -v ~/.local/share/opencode:/tmp/opencode-data:ro \
      -v ~/.cache/opencode:/root/.cache/opencode \
      -v ~/.local/state/opencode:/tmp/opencode-state:ro \
      -e GH_TOKEN="$GH_TOKEN" \
      -e GIT_NAME="$GIT_NAME" \
      -e GIT_EMAIL="$GIT_EMAIL" \
      "$IMAGE" opencode
fi

echo ""
echo "Resume: ./ocsbx.sh $hash"
echo "Or: container exec -it $name opencode -c"

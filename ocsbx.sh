#!/usr/bin/env bash
# ocsbx — OpenCode in an Apple Container sandbox, worktree-aware
set -euo pipefail

IMAGE="opencode-sandbox"

# absolute, symlink-resolved paths
toplevel=$(git rev-parse --show-toplevel); toplevel=$(cd "$toplevel" && pwd -P)
common=$(git rev-parse --path-format=absolute --git-common-dir); common=$(cd "$common" && pwd -P)

name="oc-$(basename "$toplevel")"

# always mount the working tree at its own absolute path
mounts=(-v "$toplevel:$toplevel")

# the worktree check: if the shared .git lives OUTSIDE the tree, mount it too
case "$common/" in
  "$toplevel"/*) ;;                     # main repo — .git already inside the mount
  *) mounts+=(-v "$common:$common") ;;  # linked worktree — add the shared .git
esac

exec container run --rm -it --name "$name" \
  "${mounts[@]}" -w "$toplevel" \
  -v ~/.config/opencode:/tmp/opencode-config:ro \
  -v ~/.local/share/opencode:/tmp/opencode-data:ro \
  -v opencode-cache:/root/.cache/opencode \
  "$IMAGE" opencode

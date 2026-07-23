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

# Resolve the real path of this script (follows symlinks) to find sandbox.env
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)"
CONFIG_FILE="$SCRIPT_DIR/sandbox.env"
# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Domain containers use to reach the host, served by Apple container's local DNS.
HOST_DNS_DOMAIN="${HOST_DNS_DOMAIN:-host.container.internal}"

# Delete and recreate the host DNS domain. It occasionally goes stale (usually
# after the host network changes), leaving containers unable to resolve the host
# even though the host itself still can. Needs admin, so it prompts for sudo.
reset_host_dns() {
    echo "Resetting container DNS domain '$HOST_DNS_DOMAIN' (needs sudo)…"
    sudo container system dns delete "$HOST_DNS_DOMAIN" 2>/dev/null || true
    sudo container system dns create "$HOST_DNS_DOMAIN"
}

# True if a throwaway container can resolve the host domain (~0.5s). A stale
# domain still resolves on the host, so we must probe from inside a container.
host_dns_ok() {
    container run --rm --entrypoint /usr/bin/getent "$IMAGE" hosts "$HOST_DNS_DOMAIN" >/dev/null 2>&1
}

# `ocsbx.sh fix-dns` — reset the domain on demand.
if [ "${1:-}" = "fix-dns" ]; then
    reset_host_dns
    echo "Done. Registered domains:"
    container system dns ls
    exit 0
fi

# `ocsbx.sh build`  — build the image, reusing every cached layer.
# `ocsbx.sh update` — same, but pull the current opencode + pi. The agents never
# update themselves (see the *_DISABLE_* / PI_OFFLINE env in the Dockerfile), so
# this is the one place their versions move. A fresh AGENTS_VERSION invalidates
# the opencode layer and everything below it; apt, gh, node and bun stay cached,
# making an update two downloads rather than a full rebuild.
case "${1:-}" in
  build|update)
    # `update` passes a fresh cache key, so the agent layers are reinstalled;
    # `build` passes the Dockerfile's own default, so they stay cached.
    if [ "$1" = "update" ]; then
        cache_key=$(date +%s)
        echo "Rebuilding '$IMAGE' with the latest opencode + pi…"
    else
        cache_key=1
        echo "Building '$IMAGE'…"
    fi
    container build --build-arg "AGENTS_VERSION=$cache_key" -t "$IMAGE" "$SCRIPT_DIR"
    # Report what actually landed, so `update` is verifiable rather than hopeful.
    # Bypass the entrypoint: it expects the /tmp config mounts, which aren't here.
    echo ""
    echo "Installed:"
    container run --rm --entrypoint /bin/sh "$IMAGE" -c \
      'printf "  opencode  "; opencode --version 2>/dev/null || echo "?"
       printf "  pi        "; pi --version 2>/dev/null || echo "?"' || true
    exit 0
    ;;
esac

# absolute, symlink-resolved paths. Outside a git repo, fall back to the current
# directory as the tree to mount and leave $common empty — no git wiring at all.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    toplevel=$(git rev-parse --show-toplevel); toplevel=$(cd "$toplevel" && pwd -P)
    common=$(git rev-parse --path-format=absolute --git-common-dir); common=$(cd "$common" && pwd -P)
else
    toplevel=$(pwd -P)
    common=""
fi

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
    # No git (or .git inside the tree) — name after the working tree alone.
    if [ -z "$common" ]; then
        echo "oc-$(basename "$toplevel")-$h"
        return
    fi
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

# Preflight: confirm the sandbox can resolve host.container.internal before we
# hand over to the agent, so a stale DNS domain surfaces here — with an offer to
# fix it on the spot — instead of as a failed first LLM call. Set OCSBX_HOST_CHECK=0
# (env or sandbox.env) to skip the ~0.5s probe.
if [ "${OCSBX_HOST_CHECK:-1}" = 1 ] && ! host_dns_ok; then
    echo "⚠  '$HOST_DNS_DOMAIN' is not resolvable from inside the sandbox — Apple" >&2
    echo "   container's local DNS domain has likely gone stale." >&2
    if [ -t 0 ]; then
        printf "   Reset it now (fix-dns)? [Y/n] " >&2
        read -r reply
        case "$reply" in
            n|N) echo "   Skipping — the agent may fail to reach the host." >&2 ;;
            *)   reset_host_dns
                 if host_dns_ok; then
                     echo "   ✓ fixed." >&2
                 else
                     echo "   ✗ still failing — check 'container system dns ls' and whether a VPN is interfering." >&2
                 fi ;;
        esac
    else
        echo "   Run './ocsbx.sh fix-dns' (or set OCSBX_HOST_CHECK=0 to skip)." >&2
    fi
fi

# Apple's container synthesizes TERM=xterm and forwards nothing else, so the
# agent sees a generic terminal and disables its richer output. pi in particular
# decides on inline images, 24-bit color and OSC 8 hyperlinks purely from these
# vars — it never queries the terminal — so without them a ghostty/kitty/iTerm
# host silently degrades to the plain-xterm path.
#
# A bare `-e KEY` inherits the host's value (and is a no-op if unset). TERM is
# pinned rather than inherited: the image only carries the stock terminfo
# entries, so passing e.g. xterm-ghostty through would leave ncurses programs
# inside (less, vim) with no terminfo to load.
term_envs=(-e TERM=xterm-256color -e COLORTERM -e TERM_PROGRAM)

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
    container exec -it "${term_envs[@]}" "$name" "${resume_cmd[@]}"
    set -e
else
    if ! is_agent "$AGENT"; then
        echo "Error: unknown agent '$AGENT' (known: $AGENTS)"
        exit 1
    fi

    name=$(compute_name "$hash")

    # always mount the working tree at its own absolute path
    mounts=(-v "$toplevel:$toplevel")

    # the worktree check: if the shared .git lives OUTSIDE the tree, mount it too.
    # $common is empty when launched outside a git repo — nothing to mount.
    if [ -n "$common" ]; then
        case "$common/" in
          "$toplevel"/*) ;;                     # main repo — .git already inside the mount
          *) mounts+=(-v "$common:$common") ;;  # linked worktree — add the shared .git
        esac
    fi

    # Mount SSH key if configured (only if outside the mounted directory)
    if [ -n "${SSH_KEY_PATH:-}" ] && [ -f "$SSH_KEY_PATH" ]; then
        resolved_key=$(cd "$(dirname "$SSH_KEY_PATH")" && pwd -P)/$(basename "$SSH_KEY_PATH")
        case "$resolved_key/" in
          "$toplevel"/*) ;;
          *) mounts+=(-v "$SSH_KEY_PATH:/tmp/ocsbx-ssh-key:ro") ;;
        esac
    fi

    # Per-agent config mounts, launch command, and environment
    launch=()
    envs=()
    case "$AGENT" in
      opencode)
        [ -d "$HOME/.config/opencode" ] || echo "Warning: $HOME/.config/opencode not found — opencode may be unconfigured."
        mounts+=(
          -v "$HOME/.config/opencode:/tmp/opencode-config:ro"
          -v "$HOME/.local/share/opencode:/tmp/opencode-data:ro"
          -v "$HOME/.cache/opencode:/root/.cache/opencode"
          -v "$HOME/.local/state/opencode:/tmp/opencode-state:ro"
        )
        # Startup network calls (models.dev fetch, update check, LSP downloads,
        # share pings) are suppressed by ENV in the Dockerfile, so they apply on
        # resume as well as here.
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
    envs+=(
      "${term_envs[@]}"
      -e GH_TOKEN="$GH_TOKEN"
      -e GIT_NAME="${GIT_NAME:-}"
      -e GIT_EMAIL="${GIT_EMAIL:-}"
      -e OCSBX_AGENT="$AGENT"
    )

    container run -it --name "$name" \
      --cpus 4 --memory 6g \
      "${mounts[@]}" -w "$toplevel" \
      "${envs[@]}" \
      "$IMAGE" "${launch[@]}"
fi

echo ""
echo "Resume: ./ocsbx.sh $hash"
echo "Or: container exec -it $name $(resume_command "$AGENT")"

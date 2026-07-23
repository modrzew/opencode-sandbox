FROM debian:bookworm-slim

# fd-find (as `fdfind`) and ripgrep back pi's file picker and grep tool. pi looks
# for them on PATH — see systemBinaryNames in its tools-manager — and would
# otherwise try to download them, which PI_OFFLINE=1 below blocks.
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip openssh-client \
      build-essential python3 python3-venv python3-pip \
      wget apt-transport-https fd-find ripgrep \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh)
RUN wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Ensure multiple git commands can work together on the same .git folder
RUN git config --global gc.auto 0

# Bake github.com SSH host keys into the image so git-over-ssh needs no runtime
# ssh-keyscan (which stalls ~5s when the sandbox is offline).
RUN ssh-keyscan github.com >> /etc/ssh/ssh_known_hosts 2>/dev/null

# Node LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# --- Coding agents ------------------------------------------------------------
# Installed last so a rebuild reuses every layer above (apt, gh, node, bun).
# AGENTS_VERSION exists only to give the build cache something to invalidate: the
# opencode RUN references it, so changing it reinstalls opencode *and* every layer
# below it (pi included), while everything above stays cached. An ARG that no RUN
# references would bust nothing. `./ocsbx.sh update` passes a fresh timestamp.
ARG AGENTS_VERSION=1

# OpenCode (confirm against their current install docs)
RUN echo "opencode+pi cache key: ${AGENTS_VERSION}" \
    && curl -fsSL https://opencode.ai/install | bash
ENV PATH="/root/.opencode/bin:${PATH}"
ENV OPENCODE_ENABLE_EXA=1
# Suppress opencode's startup network calls — each otherwise hangs for seconds
# (until it times out) when the sandbox is offline. Baked into the image rather
# than passed as `container run -e` so they cover the `container exec` used on
# resume too, not just the initial run.
ENV OPENCODE_DISABLE_MODELS_FETCH=1
ENV OPENCODE_DISABLE_AUTOUPDATE=1
ENV OPENCODE_DISABLE_LSP_DOWNLOAD=1
ENV OPENCODE_DISABLE_SHARE=1

# pi coding agent (binary lands on PATH at /usr/bin/pi via npm global)
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent
# pi's equivalent: skips its startup version check, package-update check and
# install telemetry. The npm/ packages are read-only symlinks and the binary is
# pinned to this image, so none of those could achieve anything anyway.
# Startup only — runtime LLM/MCP calls are unaffected.
ENV PI_OFFLINE=1

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

WORKDIR /work
CMD ["opencode"]

FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip openssh-client \
      build-essential python3 python3-venv python3-pip \
      wget apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI (gh)
RUN wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /usr/share/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh && rm -rf /var/lib/apt/lists/*

# Ensure multiple git commands can work together on the same .git folder
RUN git config --global gc.auto 0

# Node LTS
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs && rm -rf /var/lib/apt/lists/*

# Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# OpenCode (confirm against their current install docs)
RUN curl -fsSL https://opencode.ai/install | bash
ENV PATH="/root/.opencode/bin:${PATH}"
ENV OPENCODE_ENABLE_EXA=1

# pi coding agent (binary lands on PATH at /usr/bin/pi via npm global)
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

WORKDIR /work
CMD ["opencode"]

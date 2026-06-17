FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip \
      build-essential python3 python3-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

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

WORKDIR /work
CMD ["opencode"]

FROM oven/bun:1-debian AS base

# Install git, ssh client, and kubectl (arch-aware)
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    curl \
    ca-certificates \
    && ARCH=$(dpkg --print-architecture) \
    && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${ARCH}/kubectl" \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production

COPY src/ ./src/

# Configure SSH to not reject unknown hosts (gitops repo is trusted)
RUN mkdir -p /root/.ssh && echo "StrictHostKeyChecking accept-new" > /root/.ssh/config

CMD ["bun", "run", "src/index.ts"]

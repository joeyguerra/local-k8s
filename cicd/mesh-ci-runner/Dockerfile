FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    curl \
    git \
    gnupg \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install docker CLI before switching users (requires root)
RUN ARCH=$(dpkg --print-architecture) \
    && curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker.gpg \
    && echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -u 1001 -s /bin/bash mesh

USER mesh
ENV HOME=/home/mesh \
    PATH="/home/mesh/.local/bin:/home/mesh/.bun/bin:$PATH"

# Install mesh (includes CI runner capability — entrypoint leaves it enabled)
RUN curl -fsSL https://raw.githubusercontent.com/kaizen-hq/mesh/main/install.sh | MESH_REF=v5.5.0 bash

# Install bun (CI jobs run bun install, bun test, etc.)
RUN curl -fsSL https://bun.sh/install | bash

COPY --chown=mesh:mesh entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/mesh

EXPOSE 7979

ENTRYPOINT ["/entrypoint.sh"]

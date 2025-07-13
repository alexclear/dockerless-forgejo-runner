FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y yq fuse-overlayfs podman curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m forgejo

WORKDIR /home/forgejo
RUN curl -L -o forgejo-runner https://code.forgejo.org/forgejo/runner/releases/download/v6.3.1/forgejo-runner-6.3.1-linux-amd64 && \
    chmod +x forgejo-runner

COPY --chown=forgejo:forgejo entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

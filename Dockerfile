FROM ubuntu:24.04

RUN apt-get update && \
    apt-get install -y podman curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN useradd -m forgejo

USER forgejo
WORKDIR /home/forgejo
RUN curl -L -o forgejo-runner.tar.gz https://codeberg.org/forgejo/runner/releases/latest/download/forgejo-runner-linux-amd64.tar.gz && \
    tar -xzf forgejo-runner.tar.gz && \
    rm forgejo-runner.tar.gz && \
    chmod +x forgejo-runner

COPY --chown=forgejo:forgejo entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]

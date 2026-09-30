# Approximates a fresh WSL Ubuntu 24.04 install: the base image plus the packages WSL's Ubuntu
# ships with that the bootstrap assumes (sudo, curl, git, CA bundle, tzdata).
FROM ubuntu:24.04

# Container-only accommodations: no TTY for debconf, and no login to set $USER.
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
    && apt-get update \
    && apt-get install -y --no-install-recommends sudo curl git ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash tester \
    && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester \
    && chmod 0440 /etc/sudoers.d/tester

USER tester
ENV USER=tester
WORKDIR /home/tester

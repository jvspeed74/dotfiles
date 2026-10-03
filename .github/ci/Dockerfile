# Approximates a fresh WSL Ubuntu install: the base image plus the packages WSL's Ubuntu ships with
# that the bootstrap assumes (sudo, curl, git, CA bundle, tzdata).
ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

# Container-only accommodations: no TTY for debconf, and no login to set $USER.
# 26.04+ WSL images also ship sudo-rs, which takes /usr/bin/sudo through update-alternatives.
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections \
    && . /etc/os-release \
    && extra=$([ "${VERSION_ID%%.*}" -ge 26 ] && echo sudo-rs || true) \
    && apt-get update \
    && apt-get install -y --no-install-recommends sudo $extra curl git ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

# In group sudo, like a WSL user, so the stock `%sudo ... ALL` rule also matches: `sudo -v` then
# needs a password despite NOPASSWD, which the run_* scripts must handle.
RUN useradd --create-home --shell /bin/bash --groups sudo tester \
    && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester \
    && chmod 0440 /etc/sudoers.d/tester

USER tester
ENV USER=tester
WORKDIR /home/tester

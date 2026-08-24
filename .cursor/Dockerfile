FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV FLUTTER_VERSION=3.47.1
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV CHROME_EXECUTABLE=/usr/bin/google-chrome-stable

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        unzip \
        xz-utils \
        zip \
        python3 \
        clang \
        cmake \
        ninja-build \
        pkg-config \
        libgtk-3-dev \
        libglu1-mesa \
        wget \
        gnupg \
    && wget -q -O - https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        | tar -xJ -C /opt \
    && git config --global --add safe.directory /opt/flutter

RUN id ubuntu >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash ubuntu \
    && chown -R ubuntu:ubuntu /opt/flutter

USER ubuntu
WORKDIR /home/ubuntu

RUN flutter config --no-analytics --no-cli-animations \
    && flutter precache --web

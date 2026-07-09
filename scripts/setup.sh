#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NODE_VERSION="v16.13.1"

echo "[setup] installing npm dependencies..."
npm install --no-audit --no-fund

OS_NAME="$(uname -s)"
ARCH_NAME="$(uname -m)"

case "$OS_NAME" in
    Linux)
        PLATFORM="linux"
        ;;
    Darwin)
        PLATFORM="darwin"
        ;;
    *)
        echo "unsupported OS $OS_NAME"
        exit 1
        ;;
esac

case "$ARCH_NAME" in
    x86_64)
        NODE_ARCH="x64"
        ;;
    arm64|aarch64)
        NODE_ARCH="arm64"
        ;;
    *)
        echo "unsupported arch $ARCH_NAME"
        exit 1
        ;;
esac

NODE_DIR="node-${NODE_VERSION}-${PLATFORM}-${NODE_ARCH}"
ARCHIVE_NAME="${NODE_DIR}.tar.gz"
DESTINATION="vendor"
NODE_BIN="${DESTINATION}/${NODE_DIR}/bin/node"
DOWNLOAD_URL="https://nodejs.org/dist/${NODE_VERSION}/${ARCHIVE_NAME}"

if [[ -x "$NODE_BIN" ]]; then
    echo "[setup] Node ${NODE_VERSION} already present in vendor/"
else
    echo "[setup] downloading Node ${NODE_VERSION} (${PLATFORM}-${NODE_ARCH})..."
    mkdir -p "$DESTINATION"
    curl -sL "$DOWNLOAD_URL" -o "${DESTINATION}/${ARCHIVE_NAME}"
    tar -xzf "${DESTINATION}/${ARCHIVE_NAME}" -C "$DESTINATION"
    rm -f "${DESTINATION}/${ARCHIVE_NAME}"
    echo "[setup] Node installed: $("$NODE_BIN" --version)"
fi

echo "[setup] done. Run the demo with:  npm run demo"

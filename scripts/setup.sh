#!/usr/bin/env bash
#
# setup.sh — Docker-free one-time setup.
#   1. installs npm dependencies (express + vulnerable lodash 4.17.11)
#   2. fetches a local copy of Node 16.13.1 (the paper's runtime) into vendor/
#      so the real universal gadget can be reproduced without touching the
#      system Node install.
#
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[setup] installing npm dependencies..."
npm install --no-audit --no-fund

# Pick the right Node 16 build for this machine.
ARCH="$(uname -m)"; OS="$(uname -s)"
case "$OS" in
  Darwin) PLAT=darwin ;;
  Linux) PLAT=linux ;;
  *) echo "unsupported OS $OS"; exit 1 ;;
esac

case "$ARCH" in
  arm64|aarch64) NARCH=arm64 ;;
  x86_64) NARCH=x64 ;;
  *) echo "unsupported arch $ARCH"; exit 1 ;;
esac

# control version
VER="v16.13.1"
DIR="node-${VER}-${PLAT}-${NARCH}"
TARBALL="${DIR}.tar.gz"
URL="https://nodejs.org/dist/${VER}/${TARBALL}"

if [ -x "vendor/${DIR}/bin/node" ]; then
  echo "[setup] Node ${VER} already present in vendor/"
else
  echo "[setup] downloading Node ${VER} (${PLAT}-${NARCH})..."
  mkdir -p vendor
  curl -sL "$URL" -o "vendor/${TARBALL}"
  tar -xzf "vendor/${TARBALL}" -C vendor
  rm -f "vendor/${TARBALL}"
  echo "[setup] Node installed: $(vendor/${DIR}/bin/node --version)"
fi

echo "[setup] done. Run the demo with:  npm run demo"

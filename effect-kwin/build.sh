#!/usr/bin/env bash
# Compiles the KWin effect and checks that the paint chain is still intact.
#
# Does NOT install or activate. For that:  ./install.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

if ! command -v cmake >/dev/null 2>&1; then
  cat <<'MSG'
CMAKE IS MISSING

  sudo pacman -S --needed cmake ninja

The KWin and KF6 headers are already installed: nothing else is needed.
MSG
  exit 1
fi

# The Vulkan headers are only used to compile (we do not link against Vulkan), so
# a stub of our own is enough: it avoids installing the 42 MiB of vulkan-headers.
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
      -DVulkan_INCLUDE_DIR="$HERE/_stub"
cmake --build build

# If the chain is not there, it does NOT continue: installing that .so leaves the desktop black.
if ! "$HERE/verify-chain.sh"; then
  echo
  echo "NOT installing: the effect does not continue KWin's paint chain."
  exit 1
fi

echo
echo "Compiled: build/plugins/kwin/effects/macosglass2.so"
echo "  Install:       ./install.sh"
echo "  Test (without closing the session):  ./test-installed.sh"
echo
echo "The effect still does NOT draw: the material shader is the next step."

#!/usr/bin/env bash
# Builds the M6 QStyle skeleton. Does NOT install and does NOT select it: installing is
# `../install.sh aplicar --si` (with its rollback) and selecting is the user's own step, both of
# them documented in README.md and in docs/M6-QSTYLE-PLAN.md.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

if ! command -v cmake >/dev/null 2>&1; then
  cat <<'MSG'
CMAKE IS MISSING

  sudo pacman -S --needed cmake ninja

Qt 6 Widgets development files are already present: nothing else is needed.
MSG
  exit 1
fi

# Ninja when it is there, so the build matches effect-kwin's and is fast. The generator is fixed on
# the FIRST configure: running a build directory configured by another one is an error, so a stale
# directory built with a different generator is removed instead of failing with a cmake message
# nobody reads.
GEN=()
if command -v ninja >/dev/null 2>&1; then
  GEN=(-G Ninja)
  if [ -f build/CMakeCache.txt ] && ! grep -q 'CMAKE_GENERATOR:INTERNAL=Ninja' build/CMakeCache.txt 2>/dev/null; then
    echo "The build directory was configured with another generator: removing it."
    rm -rf build
  fi
fi

cmake -B build "${GEN[@]}" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build build

echo
echo "Compiled:"
echo "  plugin (what Qt loads):  build/styles/kdemacosstyle.so"
echo "  probe  (what tests run): build/bin/style-probe"
echo
echo "  Install it for the session:   ../install.sh aplicar --si    (then log out and back in)"
echo "  Try it on ONE application, without touching anything:"
echo "      QT_PLUGIN_PATH=\"$HERE/build\" QT_STYLE_OVERRIDE=KdeMacOS dolphin"
echo
echo "The style still draws NOTHING by itself: it chains to the base style, on purpose."

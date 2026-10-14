#!/usr/bin/env bash
# Installs and activates the project's KWin effect. Needs sudo. WITHOUT sudo in front.
#
# Self-contained: it does not depend on binaries in build/ (which is regenerable).
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SO="$AQUI/build/plugins/kwin/effects/macosglass2.so"
ID=macosglass2
DEST=/usr/lib/qt6/plugins/kwin/effects/plugins

[ -f "$SO" ] || { echo "The .so is missing. Compile first:  ./build.sh"; exit 1; }

# 1. The paint chain: without it KWin draws NO window (black screen).
if ! "$AQUI/verify-chain.sh" >/dev/null 2>&1; then
  echo "ABORTED: the .so does not continue the paint chain -> black screen."
  echo "Detail:  ./verify-chain.sh"
  exit 1
fi
echo "1. Paint chain: OK"

# 2. Install in the path KWin READS. PluginEffectLoader looks in
#    "kwin/effects/plugins"; one level up KWin does not see it, and silently.
echo "2. Installing $ID in $DEST"
sudo install -Dm755 "$SO" "$DEST/$ID.so"

# 3. Leftovers from previous attempts. The id 'macosglass' broke rendering, and the
#    bisection test plugins are no longer needed.
echo "3. Removing leftovers (old ids and test plugins)"
for viejo in macosglass libmacosglass bisect testglass2; do
  sudo rm -f "$DEST/$viejo.so" 2>/dev/null || true
  kwriteconfig6 --file kwinrc --group Plugins --key "${viejo}Enabled" --delete 2>/dev/null || true
done
sudo rm -f /usr/share/kwin/effects/macosglass/metadata.json 2>/dev/null || true
sudo rmdir /usr/share/kwin/effects/macosglass 2>/dev/null || true

echo "4. Activating in kwinrc"
kwriteconfig6 --file kwinrc --group Plugins --key "${ID}Enabled" true

echo
echo "Installed and activated."
echo
echo "  Check without closing the session (loads, measures and unloads by itself):"
echo "      ./test-installed.sh"
echo
echo "  For it to stay loaded permanently, LOG OUT."
echo "  NEVER use 'kwin_wayland --replace': on Wayland it starts a second"
echo "  compositor that competes for the DRM/GL and leaves the screen BLACK."
echo "  See INCIDENT.md."

#!/usr/bin/env bash
# Mide M1.2 sin cargar nada: descarga, captura, carga, captura, mide.
set -uo pipefail
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
ID=macosglass2
OUT="$HOME/diffusion-test"; mkdir -p "$OUT"
unload() { timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$ID" >/dev/null 2>&1; }
trap 'unload' EXIT INT TERM

echo "1. Efecto OFF (descargo y espero)..."
unload; sleep 4
spectacle -b -n -o "$OUT/off.png" >/dev/null 2>&1
echo "2. Efecto ON (cargo y espero)..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "$ID" >/dev/null 2>&1
sleep 6
spectacle -b -n -o "$OUT/on.png" >/dev/null 2>&1
echo "3. Descargo..."
unload; sleep 2
echo
python3 measure-diffusion.py "$OUT/off.png" "$OUT/on.png"

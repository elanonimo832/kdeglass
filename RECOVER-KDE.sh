#!/usr/bin/env bash
# ============================================================================
# RECOVER-KDE.sh — black screen recovery (2026-10-13 incident)
#
# Full context in:  ~/INCIDENT.md   (read it first)
#
# Typical case: the macosglass effect was loaded (or `kwin_wayland --replace` was used)
# and KWin stops rendering: black screen with a visible cursor, but KWin and
# plasmashell are still alive and respond over D-Bus.
#
# Usage:
#   bash ~/RECOVER-KDE.sh estado                 # see what is configured
#   bash ~/RECOVER-KDE.sh reanimar               # FIXES IT ON THE FLY, without closing the session
#   bash ~/RECOVER-KDE.sh recuperar              # disables effects/decoration on disk
#   bash ~/RECOVER-KDE.sh recuperar --reset-output   # + regenerates the output config
#   bash ~/RECOVER-KDE.sh revertir               # re-enables the macOS look (be careful!)
#
# It is idempotent and reversible: it backs up everything it touches.
#
# RECOMMENDED ORDER WHEN IT IS BLACK:
#   1) reanimar            (reconfigure -> unloadEffect -> reinitialize)
#   2) if that is not enough:  sudo systemctl restart plasmalogin   (or sudo reboot)
# ============================================================================
set -uo pipefail

HOME_DIR="${HOME:-/home/jracosta}"
CONF="$HOME_DIR/.config"
ESTADO="$HOME_DIR/.local/state/kde-macos/incidente-recuperacion"
FECHA="$(date +%Y%m%d-%H%M%S)"
PROY="$HOME_DIR/Projects/Deepseek Harness/analisis-kde-macos"
KWINRC="$CONF/kwinrc"
KDEGLOBALS="$CONF/kdeglobals"
OUTCFG="$CONF/kwinoutputconfig.json"
EFECTOS_DE_RIESGO=(macosglass blur)

azul()  { printf '\033[1;34m%s\033[0m\n' "$1"; }
ok()    { printf '  \033[1;32mOK\033[0m   %s\n' "$1"; }
aviso() { printf '  \033[1;33mAVISO\033[0m %s\n' "$1"; }

tengo() { command -v "$1" >/dev/null 2>&1; }
kwrite() { # kwrite <file> <group> <key> <value>
  if tengo kwriteconfig6; then
    kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4" 2>/dev/null && return 0
  fi
  aviso "could not write $3 in $1 (kwriteconfig6?)"
  return 1
}
kbaja() { # kbaja <file> <group> <key>
  if tengo kwriteconfig6; then
    kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete 2>/dev/null
  fi
}

# Prepares the environment to talk to the KWin of the graphical session.
entorno_kwin() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
}

# Returns the TTY of the *wayland* session (e.g. "tty3"), or nothing if there is none.
tty_wayland() {
  local s t
  for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
    t=$(loginctl show-session "$s" -p Type --value 2>/dev/null || true)
    if [ "$t" = "wayland" ]; then
      loginctl show-session "$s" -p TTY --value 2>/dev/null
      return 0
    fi
  done
  return 1
}

dime_como_volver() {
  local tty
  tty="$(tty_wayland || true)"
  if [ -n "${tty:-}" ]; then
    echo "  1) Return to the graphical session with Ctrl+Alt+F${tty#tty}  (it is on $tty; it is not always tty2)."
  else
    echo "  1) Switch to the TTY of the graphical session (find it with: loginctl list-sessions)."
  fi
}

backup() {
  mkdir -p "$ESTADO/$FECHA"
  for f in "$KWINRC" "$KDEGLOBALS" "$OUTCFG"; do
    [ -f "$f" ] && cp -a "$f" "$ESTADO/$FECHA/" 2>/dev/null
  done
  ok "backup in $ESTADO/$FECHA"
}

cmd_estado() {
  entorno_kwin
  azul "CURRENT STATUS"
  echo "--- $KWINRC [Plugins] / [org.kde.kdecoration2] ---"
  [ -f "$KWINRC" ] && grep -E 'Enabled|ButtonsOn|library|theme' "$KWINRC"
  echo "--- $KDEGLOBALS ---"
  [ -f "$KDEGLOBALS" ] && grep -iE '^ColorScheme=|^LookAndFeelPackage=|^widgetStyle=' "$KDEGLOBALS"
  echo "--- sessions ---"
  loginctl list-sessions 2>/dev/null | sed 's/^/  /'
  echo "--- effects loaded in the live KWin ---"
  if timeout 6 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1; then
    timeout 8 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null \
      | sed -n '/Currently Active Effects/,/Effect Settings/p' | head -8 | sed 's/^/  /'
  else
    aviso "KWin does not respond over D-Bus (graphical session down?)"
  fi
  echo "--- recent render errors ---"
  printf '  KWin render errors in 10 min: '
  journalctl --user -b --no-pager -o short-iso --since '10 min ago' 2>/dev/null \
    | grep -cE 'kwin_wayland\[[0-9]+\]: (Could not delete render time query|No QSGTexture)'
}

# ---------------------------------------------------------------------------
# REANIMAR: the hot recovery that worked on 2026-10-13 at 23:12
# ---------------------------------------------------------------------------
cmd_reanimar() {
  entorno_kwin
  azul "REANIMAR — recover the screen ON THE FLY (without closing the session)"
  if ! tengo qdbus6; then
    aviso "qdbus6 is missing (qt6-tools package); cannot revive on the fly"
    return 1
  fi
  if ! timeout 6 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1; then
    aviso "KWin does not respond over D-Bus; this has to be fixed by restarting the session"
    dime_como_volver
    echo "  2) sudo systemctl restart plasmalogin   (or sudo reboot)"
    return 1
  fi

  # 1) Have KWin re-read kwinrc. ESSENTIAL: otherwise reinitialize() reloads
  #    macosglass from the config KWin has IN MEMORY (it happened at 23:10:07).
  if timeout 10 qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
    ok "KWin re-read the configuration (reconfigure)"
  else
    aviso "reconfigure failed; continuing anyway"
  fi

  # 2) Unload the risky effects that are loaded.
  descargar_riesgo

  # 3) Recreate the OpenGL context / compositing backend.
  if timeout 15 qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize >/dev/null 2>&1; then
    ok "compositing backend reinitialized (reinitialize)"
  else
    aviso "reinitialize failed"
  fi
  sleep 2

  # 4) reinitialize() can reload effects: unload them again.
  descargar_riesgo

  echo
  azul "CHECK"
  printf '  isEffectLoaded macosglass = '
  timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass 2>&1
  printf '  isEffectLoaded blur      = '
  timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur 2>&1
  printf '  KWin render errors in the last 2 min = '
  journalctl --user -b --no-pager -o short-iso --since '2 min ago' 2>/dev/null \
    | grep -cE 'kwin_wayland\[[0-9]+\]: (Could not delete render time query|No QSGTexture)'
  echo
  echo "  If the screen is still black, restart the session:"
  echo "      sudo systemctl restart plasmalogin    (or sudo reboot)"
}

descargar_riesgo() {
  local e estado
  for e in "${EFECTOS_DE_RIESGO[@]}"; do
    estado="$(timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$e" 2>/dev/null || true)"
    if [ "$estado" = "true" ]; then
      if timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$e" >/dev/null 2>&1; then
        ok "effect unloaded on the fly: $e"
      else
        aviso "could not unload $e"
      fi
    fi
  done
}

cmd_recuperar() {
  local reset_output="${1:-}"
  azul "RECUPERAR — leaving KWin almost factory-fresh"
  backup

  kwrite "$KWINRC" Plugins macosglassEnabled false && ok "macosglass disabled"
  kwrite "$KWINRC" Plugins blurEnabled       false && ok "blur disabled"
  kbaja  "$KWINRC" org.kde.kdecoration2 theme   && ok "decoration: theme deleted (the factory one remains)"
  kbaja  "$KWINRC" org.kde.kdecoration2 library && ok "decoration: library deleted (the factory one remains)"

  if tengo plasma-apply-colorscheme && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    plasma-apply-colorscheme BreezeDark 2>/dev/null && ok "BreezeDark color scheme"
  fi
  kwrite "$KDEGLOBALS" General ColorScheme BreezeDark && ok "kdeglobals -> BreezeDark"

  if [ "$reset_output" = "--reset-output" ] && [ -f "$OUTCFG" ]; then
    mv -f "$OUTCFG" "$ESTADO/$FECHA/kwinoutputconfig.json.movido" 2>/dev/null \
      && ok "kwinoutputconfig.json moved aside (KWin will regenerate it)"
  fi

  echo
  azul "NEXT STEP"
  echo "  0) To recover the screen NOW, without closing the session:  bash $0 reanimar"
  dime_como_volver
  echo "  2) If it is still black:   sudo systemctl restart plasmalogin   (or sudo reboot)"
  echo "  3) macosglass/blur will no longer be loaded in the next KWin."
}

cmd_revertir() {
  azul "REVERTIR — re-enabling the macOS look (do it only if the desktop already works)"
  aviso "WATCH OUT: the macosglass effect BREAKS rendering (2026-10-13 incident, 2 times)."
  aviso "Recommended: do NOT activate it. If you still do, reboot the machine, not just the session."
  backup
  kwrite "$KWINRC" Plugins macosglassEnabled true && ok "macosglass activated (requires a reboot)"
  kwrite "$KWINRC" Plugins blurEnabled       true && ok "blur activated"
  kwrite "$KDEGLOBALS" General ColorScheme KdeMacosDark && ok "KdeMacosDark scheme"

  if [ -x "$PROY/install-decoration.sh" ]; then
    aviso "run this for the decoration (traffic lights) if you want it:"
    echo "    cd \"$PROY\" && ./install-decoration.sh aplicar --si --activar"
  fi
  echo
  aviso "Reboot the machine (sudo reboot) so KWin loads the effect."
}

ayuda() {
  cat <<EOF
Usage: bash $0 {estado|reanimar|recuperar [--reset-output]|revertir}

  estado                     Shows the current KWin/Plasma configuration.
  reanimar                   Recovers the screen ON THE FLY, without closing the session:
                             reconfigure -> unloadEffect macosglass/blur -> reinitialize.
  recuperar                  Disables macosglass and blur, resets the decoration
                             and sets the BreezeDark scheme. Makes a backup.
  recuperar --reset-output   Also moves kwinoutputconfig.json aside so that KWin
                             regenerates the screen configuration.
  revertir                   Re-activates the effect and the macOS scheme (it breaks!).

Full notes: ~/INCIDENT.md
EOF
}

case "${1:-}" in
  estado)    cmd_estado ;;
  reanimar)  cmd_reanimar ;;
  recuperar) cmd_recuperar "${2:-}" ;;
  revertir)  cmd_revertir ;;
  *)         ayuda ;;
esac

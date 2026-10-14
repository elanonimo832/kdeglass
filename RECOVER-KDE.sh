#!/usr/bin/env bash
# ============================================================================
# RECOVER-KDE.sh — recuperación de la pantalla negra (incidente 2026-10-13)
#
# Contexto completo en:  ~/INCIDENT.md   (léelo primero)
#
# Caso típico: se cargó el efecto macosglass (o se usó `kwin_wayland --replace`)
# y KWin deja de renderizar: pantalla negra con el cursor visible, pero KWin y
# plasmashell siguen vivos y responden por D-Bus.
#
# Uso:
#   bash ~/RECOVER-KDE.sh estado                 # ver qué hay configurado
#   bash ~/RECOVER-KDE.sh reanimar               # ARREGLA EN CALIENTE, sin cerrar sesión
#   bash ~/RECOVER-KDE.sh recuperar              # desactiva efectos/decoración en disco
#   bash ~/RECOVER-KDE.sh recuperar --reset-output   # + regenera config de salida
#   bash ~/RECOVER-KDE.sh revertir               # rehabilita el aspecto macOS (¡cuidado!)
#
# Es idempotente y reversible: hace backup de todo lo que toca.
#
# ORDEN RECOMENDADO CUANDO ESTÁ NEGRA:
#   1) reanimar            (reconfigure -> unloadEffect -> reinitialize)
#   2) si no basta:  sudo systemctl restart plasmalogin   (o sudo reboot)
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
kwrite() { # kwrite <fichero> <grupo> <clave> <valor>
  if tengo kwriteconfig6; then
    kwriteconfig6 --file "$1" --group "$2" --key "$3" "$4" 2>/dev/null && return 0
  fi
  aviso "no se pudo escribir $3 en $1 (¿kwriteconfig6?)"
  return 1
}
kbaja() { # kbaja <fichero> <grupo> <clave>
  if tengo kwriteconfig6; then
    kwriteconfig6 --file "$1" --group "$2" --key "$3" --delete 2>/dev/null
  fi
}

# Prepara el entorno para hablar con el KWin de la sesión gráfica.
entorno_kwin() {
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
}

# Devuelve la TTY de la sesión *wayland* (p. ej. "tty3"), o nada si no hay.
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
    echo "  1) Vuelve a la sesión gráfica con Ctrl+Alt+F${tty#tty}  (está en $tty; no siempre es tty2)."
  else
    echo "  1) Cambia a la TTY de la sesión gráfica (mírala con: loginctl list-sessions)."
  fi
}

backup() {
  mkdir -p "$ESTADO/$FECHA"
  for f in "$KWINRC" "$KDEGLOBALS" "$OUTCFG"; do
    [ -f "$f" ] && cp -a "$f" "$ESTADO/$FECHA/" 2>/dev/null
  done
  ok "backup en $ESTADO/$FECHA"
}

cmd_estado() {
  entorno_kwin
  azul "ESTADO ACTUAL"
  echo "--- $KWINRC [Plugins] / [org.kde.kdecoration2] ---"
  [ -f "$KWINRC" ] && grep -E 'Enabled|ButtonsOn|library|theme' "$KWINRC"
  echo "--- $KDEGLOBALS ---"
  [ -f "$KDEGLOBALS" ] && grep -iE '^ColorScheme=|^LookAndFeelPackage=|^widgetStyle=' "$KDEGLOBALS"
  echo "--- sesiones ---"
  loginctl list-sessions 2>/dev/null | sed 's/^/  /'
  echo "--- efectos cargados en KWin vivo ---"
  if timeout 6 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1; then
    timeout 8 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation 2>/dev/null \
      | sed -n '/Currently Active Effects/,/Effect Settings/p' | head -8 | sed 's/^/  /'
  else
    aviso "KWin no responde por D-Bus (¿sesión gráfica caída?)"
  fi
  echo "--- errores de render recientes ---"
  printf '  errores de render de KWin en 10 min: '
  journalctl --user -b --no-pager -o short-iso --since '10 min ago' 2>/dev/null \
    | grep -cE 'kwin_wayland\[[0-9]+\]: (Could not delete render time query|No QSGTexture)'
}

# ---------------------------------------------------------------------------
# REANIMAR: la recuperación en caliente que funcionó el 2026-10-13 a las 23:12
# ---------------------------------------------------------------------------
cmd_reanimar() {
  entorno_kwin
  azul "REANIMAR — recuperar la pantalla EN CALIENTE (sin cerrar sesión)"
  if ! tengo qdbus6; then
    aviso "falta qdbus6 (paquete qt6-tools); no puedo reanimar en caliente"
    return 1
  fi
  if ! timeout 6 qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation >/dev/null 2>&1; then
    aviso "KWin no responde por D-Bus; esto hay que arreglarlo reiniciando la sesión"
    dime_como_volver
    echo "  2) sudo systemctl restart plasmalogin   (o sudo reboot)"
    return 1
  fi

  # 1) Que KWin relea kwinrc. IMPRESCINDIBLE: si no, reinitialize() recarga
  #    macosglass desde la config que KWin tiene EN MEMORIA (pasó a las 23:10:07).
  if timeout 10 qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure >/dev/null 2>&1; then
    ok "KWin releyó la configuración (reconfigure)"
  else
    aviso "reconfigure falló; sigo igualmente"
  fi

  # 2) Descargar los efectos de riesgo que estén cargados.
  descargar_riesgo

  # 3) Recrear el contexto OpenGL / backend de composición.
  if timeout 15 qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize >/dev/null 2>&1; then
    ok "backend de composición reinicializado (reinitialize)"
  else
    aviso "reinitialize falló"
  fi
  sleep 2

  # 4) reinitialize() puede recargar efectos: volver a descargarlos.
  descargar_riesgo

  echo
  azul "COMPROBACIÓN"
  printf '  isEffectLoaded macosglass = '
  timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass 2>&1
  printf '  isEffectLoaded blur      = '
  timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded blur 2>&1
  printf '  errores de render de KWin en los últimos 2 min = '
  journalctl --user -b --no-pager -o short-iso --since '2 min ago' 2>/dev/null \
    | grep -cE 'kwin_wayland\[[0-9]+\]: (Could not delete render time query|No QSGTexture)'
  echo
  echo "  Si la pantalla sigue negra, reinicia la sesión:"
  echo "      sudo systemctl restart plasmalogin    (o sudo reboot)"
}

descargar_riesgo() {
  local e estado
  for e in "${EFECTOS_DE_RIESGO[@]}"; do
    estado="$(timeout 6 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded "$e" 2>/dev/null || true)"
    if [ "$estado" = "true" ]; then
      if timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect "$e" >/dev/null 2>&1; then
        ok "efecto descargado en caliente: $e"
      else
        aviso "no se pudo descargar $e"
      fi
    fi
  done
}

cmd_recuperar() {
  local reset_output="${1:-}"
  azul "RECUPERAR — dejando KWin casi de fábrica"
  backup

  kwrite "$KWINRC" Plugins macosglassEnabled false && ok "macosglass desactivado"
  kwrite "$KWINRC" Plugins blurEnabled       false && ok "blur desactivado"
  kbaja  "$KWINRC" org.kde.kdecoration2 theme   && ok "decoración: theme borrado (queda la de fábrica)"
  kbaja  "$KWINRC" org.kde.kdecoration2 library && ok "decoración: library borrada (queda la de fábrica)"

  if tengo plasma-apply-colorscheme && [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
    plasma-apply-colorscheme BreezeDark 2>/dev/null && ok "esquema de color BreezeDark"
  fi
  kwrite "$KDEGLOBALS" General ColorScheme BreezeDark && ok "kdeglobals -> BreezeDark"

  if [ "$reset_output" = "--reset-output" ] && [ -f "$OUTCFG" ]; then
    mv -f "$OUTCFG" "$ESTADO/$FECHA/kwinoutputconfig.json.movido" 2>/dev/null \
      && ok "kwinoutputconfig.json apartado (KWin lo regenerará)"
  fi

  echo
  azul "SIGUIENTE PASO"
  echo "  0) Para recuperar la pantalla AHORA, sin cerrar sesión:  bash $0 reanimar"
  dime_como_volver
  echo "  2) Si sigue negra:   sudo systemctl restart plasmalogin   (o sudo reboot)"
  echo "  3) macosglass/blur ya no se cargarán en el próximo KWin."
}

cmd_revertir() {
  azul "REVERTIR — rehabilitando el aspecto macOS (hazlo solo si el escritorio ya va)"
  aviso "OJO: el efecto macosglass ROMPE el render (incidente 2026-10-13, 2 veces)."
  aviso "Recomendado: NO activarlo. Si aun así lo haces, reinicia el equipo, no solo la sesión."
  backup
  kwrite "$KWINRC" Plugins macosglassEnabled true && ok "macosglass activado (requiere reiniciar)"
  kwrite "$KWINRC" Plugins blurEnabled       true && ok "blur activado"
  kwrite "$KDEGLOBALS" General ColorScheme KdeMacosDark && ok "esquema KdeMacosDark"

  if [ -x "$PROY/install-decoration.sh" ]; then
    aviso "ejecuta esto para la decoración (semáforos) si la quieres:"
    echo "    cd \"$PROY\" && ./install-decoration.sh aplicar --si --activar"
  fi
  echo
  aviso "Reinicia el equipo (sudo reboot) para que KWin cargue el efecto."
}

ayuda() {
  cat <<EOF
Uso: bash $0 {estado|reanimar|recuperar [--reset-output]|revertir}

  estado                     Muestra la configuración actual de KWin/Plasma.
  reanimar                   Recupera la pantalla EN CALIENTE, sin cerrar sesión:
                             reconfigure -> unloadEffect macosglass/blur -> reinitialize.
  recuperar                  Desactiva macosglass y blur, resetea la decoración
                             y pone el esquema BreezeDark. Hace backup.
  recuperar --reset-output   Además aparta kwinoutputconfig.json para que KWin
                             regenere la configuración de la pantalla.
  revertir                   Vuelve a activar el efecto y el esquema macOS (¡rompe!).

Notas completas: ~/INCIDENT.md
EOF
}

case "${1:-}" in
  estado)    cmd_estado ;;
  reanimar)  cmd_reanimar ;;
  recuperar) cmd_recuperar "${2:-}" ;;
  revertir)  cmd_revertir ;;
  *)         ayuda ;;
esac

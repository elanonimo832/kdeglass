#!/usr/bin/env bash
#
# install-decoration.sh — Installs the tuned window decoration
#
# WHY THIS SCRIPT EXISTS
#   The titlebar buttons (the menu, minimize and close) are NOT drawn by the
#   GTK theme: KWin draws them, with the Aurorae decoration active. On this machine the
#   decoration is "Ant-Dark", and its configuration had ButtonSpacing=8, which leaves the
#   buttons practically stuck to each other.
#
#   This script installs a VARIANT called KdeMacOS, a copy of Ant-Dark with the
#   buttons more separated. It does not modify the original theme: if you do not like it, go back to
#   Ant-Dark from Settings and nothing has happened here.
#
# USAGE
#   ./install-decoration.sh plan              # what it would do. Touches nothing.
#   ./install-decoration.sh aplicar --si      # copies the theme (does not activate it)
#   ./install-decoration.sh aplicar --si --activar   # also sets it as active
#   ./install-decoration.sh rollback          # removes it
#
# GUARANTEES
#   - Never sudo, never writes outside $HOME.
#   - Does not touch the original Ant-Dark theme.
#   - Reversible with one command.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGEN="$AQUI/output/aurorae/KdeMacOS"

: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

DESTINO="$XDG_DATA_HOME/aurorae/themes/KdeMacOS"
ORIGINAL="$XDG_DATA_HOME/aurorae/themes/Ant-Dark"
ESTADO="$XDG_STATE_HOME/kde-macos"
MANIFIESTO="$ESTADO/manifest-decoracion.tsv"

VERDE=$'\033[32m'; ROJO=$'\033[31m'; AMBAR=$'\033[33m'; AZUL=$'\033[34m'; GRIS=$'\033[90m'; FIN=$'\033[0m'
ok()    { printf '  %sOK%s   %s\n' "$VERDE" "$FIN" "$1"; }
fallo() { printf '  %sFAIL%s  %s\n' "$ROJO" "$FIN" "$1"; }
aviso() { printf '  %sWARN%s  %s\n' "$AMBAR" "$FIN" "$1"; }
info()  { printf '%s%s%s\n' "$AZUL" "$1" "$FIN"; }
gris()  { printf '%s%s%s\n' "$GRIS" "$1" "$FIN"; }

cmd_plan() {
  info "PLAN for the macOS-style decoration (nothing is touched)"
  echo
  printf '  %-46s %s\n' "Source" "${ORIGEN/#$HOME/~}"
  printf '  %-46s %s\n' "Destination" "${DESTINO/#$HOME/~}"
  echo
  if [ ! -d "$ORIGEN" ]; then
    fallo "source does not exist: $ORIGEN"
    return 1
  fi
  ok "$(find "$ORIGEN" -type f | wc -l) files ready to copy"
  echo
  # NO third-party theme is modified: this decoration is installed separately and chosen
  # in Settings. That is why there is nothing to "put back the way it was".
  ok "no existing theme is modified: it is installed separately"
  if [ -d "$DESTINO" ]; then
    aviso "KdeMacOS is already installed (it will be overwritten)"
  else
    gris "  KdeMacOS is not installed yet"
  fi
  echo
  info "Button layout (what defines the look)"
  grep -E '^(LeftButtons|RightButtons|ButtonSpacing|ButtonWidth|ButtonHeight)' \
       "$ORIGEN/KdeMacOSrc" 2>/dev/null | sed 's/^/    /' || true
  echo
  gris "  X = close, I = minimize, A = maximize (KWin notation)."
  gris "  On the left and in that order is what macOS does."
  echo
  info "Layout KWin has RIGHT NOW (this is what rules)"
  local izq der
  izq="$(timeout 3 kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft 2>/dev/null)"
  der="$(timeout 3 kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight 2>/dev/null)"
  printf '    ButtonsOnLeft  = %s\n' "${izq:-(not set -> KWin uses its default)}"
  printf '    ButtonsOnRight = %s\n' "${der:-(not set -> KWin uses its default)}"
  gris "    If they are not set, KWin puts the buttons on the RIGHT even if the theme"
  gris "    asks for the left. That is what happened."
  echo
  gris "To install it:  ./install-decoration.sh aplicar --si"
}

cmd_aplicar() {
  local activar="no"
  for a in "$@"; do [ "$a" = "--activar" ] && activar="si"; done
  case " $* " in *" --si "*) ;; *) fallo "it must be confirmed:  ./install-decoration.sh aplicar --si"; return 1;; esac

  [ -d "$ORIGEN" ] || { fallo "$ORIGEN does not exist"; return 1; }

  info "Installing the KdeMacOS decoration"
  mkdir -p "$DESTINO" "$ESTADO" || { fallo "could not create the destination"; return 1; }
  : > "$MANIFIESTO"

  if [ -d "$DESTINO" ] && [ "$(find "$DESTINO" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
    local BK="$ESTADO/backups/decoracion-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK" && cp -a "$DESTINO/." "$BK/" 2>/dev/null \
      && printf '%s\t%s\t%s\n' "$DESTINO" "modificado" "$BK" >> "$MANIFIESTO"
    aviso "there was a previous version: backed up in ${BK/#$HOME/~}"
  fi

  cp -a "$ORIGEN/." "$DESTINO/" || { fallo "the copy failed"; return 1; }
  ok "$(find "$DESTINO" -type f | wc -l) files in ${DESTINO/#$HOME/~}"
  printf '%s\t%s\t%s\n' "$DESTINO" "creado" "-" >> "$MANIFIESTO"

  echo
  if [ "$activar" = "si" ]; then
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      # The group is org.kde.kdecoration2 and the keys are KWin's, not the theme's.
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae.v2
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__KdeMacOS
      # THIS is what puts the traffic lights on the left. The theme's .rc declares it,
      # but KWin 6 reads the layout from kwinrc; if the key does not exist, it applies ITS
      # default, which is on the right. Verified in the user's kwinrc.
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
      ok "kwinrc: decoration = KdeMacOS, traffic lights on the LEFT (XIA)"
      echo
      if command -v qdbus6 >/dev/null 2>&1; then
        timeout 5 qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
          && ok "KWin reloaded on the fly" \
          || gris "  manual reload:  qdbus6 org.kde.KWin /KWin reconfigure"
      fi
    else
      aviso "could not write kwinrc (no kwriteconfig6): activate it by hand"
    fi
  else
    gris "It has NOT been activated. To activate it:"
    gris "  System Settings > Appearance > Window Decorations > KdeMacOS"
    gris "  or run it again with  --activar"
  fi
  echo
  gris "Your current decoration is still intact: this is installed separately."
  gris "Revert:  ./install-decoration.sh rollback"
}

cmd_rollback() {
  if [ ! -f "$MANIFIESTO" ]; then fallo "no manifest: nothing to revert"; return 1; fi
  info "Removing the KdeMacOS decoration"
  echo
  local n=0
  while IFS=$'\t' read -r destino estado backup; do
    case "$estado" in
      creado)     [ -d "$destino" ] && rm -rf "$destino" && ok "removed ${destino/#$HOME/~}" && n=$((n+1)) ;;
      modificado) [ -d "$backup" ] && rm -rf "$destino" && cp -a "$backup" "$destino" && ok "restored ${destino/#$HOME/~}" && n=$((n+1)) ;;
    esac
  done < "$MANIFIESTO"
  echo
  printf '  %s elements reverted\n' "$n"
  gris "If you had it active in KWin, choose another decoration in Settings."
}

cmd_limpiar() {
  # The first version of the installer created "Ant-MacOS", a copy of Ant-Dark.
  # It was replaced by KdeMacOS, which is generated from the tokens. This removes the leftover.
  local OBSOLETO="$XDG_DATA_HOME/aurorae/themes/Ant-MacOS"
  info "Cleaning up obsolete decorations"
  echo
  if [ -d "$OBSOLETO" ]; then
    rm -rf "$OBSOLETO" && ok "removed Ant-MacOS (it was the copy of Ant-Dark, no longer used)"
  else
    gris "  Ant-MacOS was not installed"
  fi
  echo
  gris "KdeMacOS is kept: it is the good decoration."
}

case "${1:-}" in
  plan)     cmd_plan ;;
  limpiar)  cmd_limpiar ;;
  aplicar)  shift; cmd_aplicar "$@" ;;
  rollback) cmd_rollback ;;
  *) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

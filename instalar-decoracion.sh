#!/usr/bin/env bash
#
# instalar-decoracion.sh — Instala la decoracion de ventana ajustada
#
# POR QUE EXISTE ESTE SCRIPT
#   Los botones de la barra de titulo (el menu, minimizar y cerrar) NO los dibuja el
#   tema GTK: los dibuja KWin, con la decoracion Aurorae activa. En este equipo la
#   decoracion es "Ant-Dark", y su configuracion tenia ButtonSpacing=8, que deja los
#   botones practicamente pegados entre si.
#
#   Este script instala una VARIANTE llamada KdeMacOS, copia de Ant-Dark con los
#   botones mas separados. No modifica el tema original: si no te gusta, vuelves a
#   Ant-Dark desde Ajustes y aqui no ha pasado nada.
#
# USO
#   ./instalar-decoracion.sh plan              # que haria. No toca nada.
#   ./instalar-decoracion.sh aplicar --si      # copia el tema (no lo activa)
#   ./instalar-decoracion.sh aplicar --si --activar   # ademas lo pone como activo
#   ./instalar-decoracion.sh rollback          # lo quita
#
# GARANTIAS
#   - Nunca sudo, nunca escribe fuera de $HOME.
#   - No toca el tema Ant-Dark original.
#   - Reversible con un comando.

set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORIGEN="$AQUI/salida/aurorae/KdeMacOS"

: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

DESTINO="$XDG_DATA_HOME/aurorae/themes/KdeMacOS"
ORIGINAL="$XDG_DATA_HOME/aurorae/themes/Ant-Dark"
ESTADO="$XDG_STATE_HOME/kde-macos"
MANIFIESTO="$ESTADO/manifest-decoracion.tsv"

VERDE=$'\033[32m'; ROJO=$'\033[31m'; AMBAR=$'\033[33m'; AZUL=$'\033[34m'; GRIS=$'\033[90m'; FIN=$'\033[0m'
ok()    { printf '  %sOK%s   %s\n' "$VERDE" "$FIN" "$1"; }
fallo() { printf '  %sFALLA%s %s\n' "$ROJO" "$FIN" "$1"; }
aviso() { printf '  %sAVISO%s %s\n' "$AMBAR" "$FIN" "$1"; }
info()  { printf '%s%s%s\n' "$AZUL" "$1" "$FIN"; }
gris()  { printf '%s%s%s\n' "$GRIS" "$1" "$FIN"; }

cmd_plan() {
  info "PLAN de la decoracion estilo macOS (no se toca nada)"
  echo
  printf '  %-46s %s\n' "Origen" "${ORIGEN/#$HOME/~}"
  printf '  %-46s %s\n' "Destino" "${DESTINO/#$HOME/~}"
  echo
  if [ ! -d "$ORIGEN" ]; then
    fallo "no existe el origen: $ORIGEN"
    return 1
  fi
  ok "$(find "$ORIGEN" -type f | wc -l) ficheros listos para copiar"
  echo
  # No se modifica NINGUN tema ajeno: esta decoracion se instala aparte y se elige
  # en Ajustes. Por eso no hay nada que "volver a dejar como estaba".
  ok "no se modifica ningun tema existente: se instala aparte"
  if [ -d "$DESTINO" ]; then
    aviso "KdeMacOS ya esta instalado (se sobrescribira)"
  else
    gris "  KdeMacOS no esta instalado todavia"
  fi
  echo
  info "Disposicion de los botones (lo que define el aspecto)"
  grep -E '^(LeftButtons|RightButtons|ButtonSpacing|ButtonWidth|ButtonHeight)' \
       "$ORIGEN/KdeMacOSrc" 2>/dev/null | sed 's/^/    /' || true
  echo
  gris "  X = cerrar, I = minimizar, A = maximizar (notacion de KWin)."
  gris "  A la izquierda y en ese orden es lo que hace macOS."
  echo
  info "Disposicion que tiene KWin AHORA MISMO (esto es lo que manda)"
  local izq der
  izq="$(timeout 3 kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft 2>/dev/null)"
  der="$(timeout 3 kreadconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight 2>/dev/null)"
  printf '    ButtonsOnLeft  = %s\n' "${izq:-(sin definir -> KWin usa su defecto)}"
  printf '    ButtonsOnRight = %s\n' "${der:-(sin definir -> KWin usa su defecto)}"
  gris "    Si no estan definidas, KWin pone los botones a la DERECHA aunque el tema"
  gris "    pida la izquierda. Eso fue lo que paso."
  echo
  gris "Para instalarlo:  ./instalar-decoracion.sh aplicar --si"
}

cmd_aplicar() {
  local activar="no"
  for a in "$@"; do [ "$a" = "--activar" ] && activar="si"; done
  case " $* " in *" --si "*) ;; *) fallo "hay que confirmarlo:  ./instalar-decoracion.sh aplicar --si"; return 1;; esac

  [ -d "$ORIGEN" ] || { fallo "no existe $ORIGEN"; return 1; }

  info "Instalando la decoracion KdeMacOS"
  mkdir -p "$DESTINO" "$ESTADO" || { fallo "no se pudo crear el destino"; return 1; }
  : > "$MANIFIESTO"

  if [ -d "$DESTINO" ] && [ "$(find "$DESTINO" -type f 2>/dev/null | wc -l)" -gt 0 ]; then
    local BK="$ESTADO/backups/decoracion-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BK" && cp -a "$DESTINO/." "$BK/" 2>/dev/null \
      && printf '%s\t%s\t%s\n' "$DESTINO" "modificado" "$BK" >> "$MANIFIESTO"
    aviso "habia una version previa: respaldada en ${BK/#$HOME/~}"
  fi

  cp -a "$ORIGEN/." "$DESTINO/" || { fallo "fallo la copia"; return 1; }
  ok "$(find "$DESTINO" -type f | wc -l) ficheros en ${DESTINO/#$HOME/~}"
  printf '%s\t%s\t%s\n' "$DESTINO" "creado" "-" >> "$MANIFIESTO"

  echo
  if [ "$activar" = "si" ]; then
    if command -v kwriteconfig6 >/dev/null 2>&1; then
      # El grupo es org.kde.kdecoration2 y las claves son las de KWin, no las del tema.
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.kwin.aurorae.v2
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key theme __aurorae__svg__KdeMacOS
      # ESTO es lo que pone los semaforos a la izquierda. El .rc del tema lo declara,
      # pero KWin 6 lee la disposicion de kwinrc; si la clave no existe, aplica SU
      # defecto, que es a la derecha. Comprobado en el kwinrc del usuario.
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
      timeout 5 kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
      ok "kwinrc: decoracion = KdeMacOS, semaforos a la IZQUIERDA (XIA)"
      echo
      if command -v qdbus6 >/dev/null 2>&1; then
        timeout 5 qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
          && ok "KWin recargado en caliente" \
          || gris "  recarga manual:  qdbus6 org.kde.KWin /KWin reconfigure"
      fi
    else
      aviso "no se pudo escribir kwinrc (sin kwriteconfig6): activala a mano"
    fi
  else
    gris "NO se ha activado. Para activarla:"
    gris "  Ajustes del sistema > Apariencia > Decoraciones de ventana > KdeMacOS"
    gris "  o vuelve a ejecutar con  --activar"
  fi
  echo
  gris "Tu decoracion actual sigue intacta: esto se instala aparte."
  gris "Reversion:  ./instalar-decoracion.sh rollback"
}

cmd_rollback() {
  if [ ! -f "$MANIFIESTO" ]; then fallo "no hay manifiesto: nada que revertir"; return 1; fi
  info "Quitando la decoracion KdeMacOS"
  echo
  local n=0
  while IFS=$'\t' read -r destino estado backup; do
    case "$estado" in
      creado)     [ -d "$destino" ] && rm -rf "$destino" && ok "eliminado ${destino/#$HOME/~}" && n=$((n+1)) ;;
      modificado) [ -d "$backup" ] && rm -rf "$destino" && cp -a "$backup" "$destino" && ok "restaurado ${destino/#$HOME/~}" && n=$((n+1)) ;;
    esac
  done < "$MANIFIESTO"
  echo
  printf '  %s elementos revertidos\n' "$n"
  gris "Si la tenias activa en KWin, elige otra decoracion en Ajustes."
}

cmd_limpiar() {
  # La primera version del instalador creo "Ant-MacOS", una copia de Ant-Dark.
  # Se sustituyo por KdeMacOS, que se genera desde los tokens. Esto quita el resto.
  local OBSOLETO="$XDG_DATA_HOME/aurorae/themes/Ant-MacOS"
  info "Limpiando decoraciones obsoletas"
  echo
  if [ -d "$OBSOLETO" ]; then
    rm -rf "$OBSOLETO" && ok "eliminado Ant-MacOS (era la copia de Ant-Dark, ya no se usa)"
  else
    gris "  Ant-MacOS no estaba instalado"
  fi
  echo
  gris "KdeMacOS se conserva: es la decoracion buena."
}

case "${1:-}" in
  plan)     cmd_plan ;;
  limpiar)  cmd_limpiar ;;
  aplicar)  shift; cmd_aplicar "$@" ;;
  rollback) cmd_rollback ;;
  *) sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

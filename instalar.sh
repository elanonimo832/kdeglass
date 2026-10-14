#!/usr/bin/env bash
#
# instalar.sh — Instalador de la capa de escritorio estilo macOS
#
# REGLA DE ORO DE ESTE INSTALADOR
#   Por defecto NO ESCRIBE NADA. Todos los subcomandos son de lectura o de ensayo
#   salvo `aplicar`, que ademas exige --si. Asi no hay forma de romper el escritorio
#   por invocarlo sin querer, y se puede auditar todo antes de tocar nada.
#
# USO
#   ./instalar.sh preflight     # comprueba el entorno. NO toca nada.
#   ./instalar.sh plan          # muestra QUE haria, fichero por fichero. NO toca nada.
#   ./instalar.sh estado        # que hay instalado y en que se diferencia del repo.
#   ./instalar.sh aplicar --si  # aplica de verdad. Hace backup antes de cada cambio.
#   ./instalar.sh rollback      # restaura el ultimo backup completo.
#   ./instalar.sh verificar     # comprobaciones posteriores.
#
# GARANTIAS
#   - Nunca invoca sudo ni escribe fuera de $HOME.
#   - Backup con fecha de cada fichero antes de tocarlo, en $XDG_STATE_HOME.
#   - Idempotente: aplicar dos veces el mismo contenido no cambia nada.
#   - Reversible con un solo comando.

set -uo pipefail

# --------------------------------------------------------------------------
# Rutas y constantes
# --------------------------------------------------------------------------
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SALIDA="$AQUI/salida"
TOKENS="$AQUI/tokens"

: "${XDG_CONFIG_HOME:=$HOME/.config}"
: "${XDG_DATA_HOME:=$HOME/.local/share}"
: "${XDG_STATE_HOME:=$HOME/.local/state}"

ESTADO="$XDG_STATE_HOME/kde-macos"
BACKUPS="$ESTADO/backups/$(date +%Y%m%d-%H%M%S)"
MANIFIESTO="$ESTADO/manifest.tsv"

VERDE=$'\033[32m'; ROJO=$'\033[31m'; AMBAR=$'\033[33m'; AZUL=$'\033[34m'; GRIS=$'\033[90m'; FIN=$'\033[0m'

ok()    { printf '  %sOK%s   %s\n' "$VERDE" "$FIN" "$1"; }
fallo() { printf '  %sFALLA%s %s\n' "$ROJO" "$FIN" "$1"; }
aviso() { printf '  %sAVISO%s %s\n' "$AMBAR" "$FIN" "$1"; }
info()  { printf '%s%s%s\n' "$AZUL" "$1" "$FIN"; }
gris()  { printf '%s%s%s\n' "$GRIS" "$1" "$FIN"; }

# --------------------------------------------------------------------------
# Lectura de configuracion, a prueba de cuelgues
#
# `kreadconfig6` habla con el bus de sesion de D-Bus. Si no hay bus (contenedores,
# SSH, sesiones degradadas) no falla: SE QUEDA COLGADO. Un instalador no puede
# permitirse eso, asi que se sondea su disponibilidad UNA vez con timeout y, si no
# responde, se lee el fichero directamente con awk.
# --------------------------------------------------------------------------
KRECONFIG_UTIL="no-disponible"
if command -v kreadconfig6 >/dev/null 2>&1; then
  timeout 3 kreadconfig6 --file kdeglobals --group General --key _sondeo >/dev/null 2>&1
  case $? in
    124) KRECONFIG_UTIL="cuelga" ;;
    *)   KRECONFIG_UTIL="si" ;;
  esac
fi

leer_clave() {
  # leer_clave <fichero> <grupo> <clave>
  local fichero="$1" grupo="$2" clave="$3" ruta
  ruta="$XDG_CONFIG_HOME/$fichero"
  [ -f "$ruta" ] || { echo ""; return; }
  if [ "$KRECONFIG_UTIL" = "si" ]; then
    local v
    v="$(timeout 3 kreadconfig6 --file "$fichero" --group "$grupo" --key "$clave" 2>/dev/null)"
    echo "$v"
    return
  fi
  # Alternativa sin D-Bus: leer el INI a mano. Suficiente para informar del estado.
  # OJO: los kdeglobals de KDE pueden tener finales de linea CRLF, y el \r pegado
  # rompe cualquier comparacion. Se limpia en cada linea antes de mirarla.
  awk -v g="$grupo" -v k="$clave" '
    { linea = $0; sub(/\r$/, "", linea) }
    /^\[/ { sec = linea; sub(/^\[/, "", sec); sub(/\]$/, "", sec); dentro = (sec == g); next }
    dentro && index(linea, k"=") == 1 { sub("^"k"=", "", linea); print linea; exit }
  ' "$ruta"
}

# --------------------------------------------------------------------------
# Mapa de instalacion: origen en el repo -> destino en el sistema
# --------------------------------------------------------------------------
# Formato: "origen|destino|descripcion"
mapa() {
  cat <<MAPA
$SALIDA/color-schemes/KdeMacosLight.colors|$XDG_DATA_HOME/color-schemes/KdeMacosLight.colors|Esquema de color claro
$SALIDA/color-schemes/KdeMacosDark.colors|$XDG_DATA_HOME/color-schemes/KdeMacosDark.colors|Esquema de color oscuro
$SALIDA/gtk-3.0/kde-macos.css|$XDG_DATA_HOME/themes/kde-macos/gtk-3.0/gtk.css|Tema GTK3
$SALIDA/gtk-3.0/kde-macos-dark.css|$XDG_DATA_HOME/themes/kde-macos/gtk-3.0/gtk-dark.css|Tema GTK3 oscuro
$SALIDA/gtk-4.0/kde-macos.css|$XDG_DATA_HOME/themes/kde-macos/gtk-4.0/gtk.css|Tema GTK4
$SALIDA/gtk-4.0/kde-macos-dark.css|$XDG_DATA_HOME/themes/kde-macos/gtk-4.0/gtk-dark.css|Tema GTK4 oscuro
MAPA
}

# --------------------------------------------------------------------------
# preflight
# --------------------------------------------------------------------------
cmd_preflight() {
  info "PREFLIGHT — comprobacion del entorno (no se toca nada)"
  echo

  info "1. Sesion"
  if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then ok "Wayland"; else aviso "no es Wayland (${XDG_SESSION_TYPE:-sin definir})"; fi
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then ok "KDE"; else aviso "no es KDE (${XDG_CURRENT_DESKTOP:-sin definir})"; fi
  if [ "${KDE_SESSION_VERSION:-}" = "6" ]; then ok "Plasma 6"; else aviso "no es Plasma 6 (${KDE_SESSION_VERSION:-sin definir})"; fi
  echo

  info "2. Herramientas necesarias"
  for c in kwriteconfig6 kreadconfig6 fc-cache; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c"; else fallo "$c (falta)"; fi
  done
  case "$KRECONFIG_UTIL" in
    si)        ok "kreadconfig6 responde (hay bus de sesion)" ;;
    cuelga)    aviso "kreadconfig6 NO responde (sin bus de sesion): se leera kdeglobals con awk" ;;
    *)         aviso "kreadconfig6 no disponible: se leera kdeglobals con awk" ;;
  esac
  echo

  info "3. Estilo de widgets actual"
  local estilo
  # widgetStyle vive en la seccion [KDE], no en [General]. Verificado en el
  # kdeglobals real de este equipo (widgetStyle=kvantum esta en [KDE]).
  estilo="$(leer_clave kdeglobals KDE widgetStyle)"
  if [ -n "$estilo" ]; then
    ok "widgetStyle = $estilo  (se guardara en el backup antes de cambiarlo)"
  else
    aviso "widgetStyle no definido en kdeglobals"
  fi
  # Motivo por el que el paso 4 puede fallar EN SILENCIO si esto esta activo.
  if [ "${KDE_WIDGET_STYLE_OVERRIDE:-}" != "" ]; then
    fallo "KDE_WIDGET_STYLE_OVERRIDE esta definido: el cambio de estilo se ignoraria"
  else
    ok "sin KDE_WIDGET_STYLE_OVERRIDE en el entorno"
  fi
  echo

  info "4. Rutas de plugins de Qt6 (lib vs lib64)"
  local encontradas=0
  for d in "$HOME/.local/lib/qt6/plugins/styles" "$HOME/.local/lib64/qt6/plugins/styles" \
           /usr/lib/qt6/plugins/styles /usr/lib64/qt6/plugins/styles; do
    if [ -d "$d" ]; then ok "$d"; encontradas=$((encontradas+1)); else gris "  (no existe) $d"; fi
  done
  [ "$encontradas" -gt 0 ] || fallo "no se encontro ningun directorio de plugins de estilos"
  echo

  info "5. Ficheros de configuracion que se tocarian"
  for f in "$XDG_CONFIG_HOME/kdeglobals" "$XDG_CONFIG_HOME/kwinrc"; do
    if [ -f "$f" ]; then ok "$f ($(stat -c%s "$f") bytes)"; else aviso "$f (no existe todavia)"; fi
  done
  echo

  info "6. Ficheros de kde-gtk-config (NO se tocan, se respetan)"
  for f in "$XDG_CONFIG_HOME/gtk-3.0/gtk.css" "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"; do
    if [ -f "$f" ]; then
      ok "$f existe — el instalador NO lo sobrescribe (es de kde-gtk-config)"
    else
      gris "  (no existe) $f"
    fi
  done
  echo

  info "7. Salida generada disponible"
  local n=0
  for f in "$SALIDA"/color-schemes/*.colors "$SALIDA"/gtk-3.0/*.css "$SALIDA"/gtk-4.0/*.css; do
    [ -f "$f" ] && n=$((n+1))
  done
  if [ "$n" -gt 0 ]; then ok "$n ficheros generados en salida/"; else fallo "no hay nada en salida/: ejecuta los generadores"; fi
  echo
  gris "Preflight terminado. No se ha modificado nada."
}

# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------
cmd_plan() {
  info "PLAN — esto es lo que haria 'aplicar' (no se toca nada)"
  echo
  printf '%-9s %-58s %s\n' "ACCION" "DESTINO" "DETALLE"
  printf '%s\n' "---------------------------------------------------------------------------------------------------"

  while IFS='|' read -r origen destino desc; do
    local accion detalle
    if [ ! -f "$origen" ]; then
      accion="FALTA"; detalle="no existe el origen"
    elif [ ! -e "$destino" ]; then
      accion="CREAR"; detalle="$desc"
    elif cmp -s "$origen" "$destino"; then
      accion="IGUAL"; detalle="sin cambios"
    else
      accion="CAMBIAR"; detalle="$desc ($(stat -c%s "$destino") -> $(stat -c%s "$origen") bytes)"
    fi
    printf '%-9s %-58s %s\n' "$accion" "${destino/#$HOME/~}" "$detalle"
  done < <(mapa)

  echo
  info "Cambios en la configuracion de KDE"
  local actual
  actual="$(leer_clave kdeglobals General ColorScheme)"; [ -n "$actual" ] || actual="(sin definir)"
  printf '  %-34s %s\n' "kdeglobals [General] ColorScheme" "$actual -> KdeMacosLight"
  echo
  gris "Nada de esto se ha aplicado. Para aplicarlo:  ./instalar.sh aplicar --si"
}

# --------------------------------------------------------------------------
# estado
# --------------------------------------------------------------------------
cmd_estado() {
  info "ESTADO — que hay instalado y en que se diferencia del repo"
  echo
  info "Esquema de color activo"
  local cs ws ft
  cs="$(leer_clave kdeglobals General ColorScheme)"; [ -n "$cs" ] || cs="(sin definir)"
  ws="$(leer_clave kdeglobals KDE widgetStyle)"; [ -n "$ws" ] || ws="(sin definir)"
  ft="$(leer_clave kdeglobals General font)"; [ -n "$ft" ] || ft="(sin definir)"
  printf '  %-34s %s\n' "kdeglobals [General] ColorScheme" "$cs"
  printf '  %-34s %s\n' "kdeglobals [KDE] widgetStyle" "$ws"
  printf '  %-34s %s\n' "kdeglobals [General] font" "$ft"
  echo
  info "Diferencia entre el repo y lo instalado"
  local iguales=0 distintos=0 ausentes=0
  while IFS='|' read -r origen destino desc; do
    if [ ! -e "$destino" ]; then ausentes=$((ausentes+1))
    elif cmp -s "$origen" "$destino"; then iguales=$((iguales+1))
    else distintos=$((distintos+1)); printf '  %sDISTINTO%s %s\n' "$AMBAR" "$FIN" "${destino/#$HOME/~}"; fi
  done < <(mapa)
  printf '  %s iguales · %s distintos · %s sin instalar\n' "$iguales" "$distintos" "$ausentes"
  echo
  if [ -f "$MANIFIESTO" ]; then
    info "Ultimo backup: $(tail -1 "$MANIFIESTO" | cut -f3 2>/dev/null || echo '?')"
  else
    gris "No hay manifiesto: nunca se ha aplicado nada."
  fi
}

# --------------------------------------------------------------------------
# aplicar
# --------------------------------------------------------------------------
cmd_aplicar() {
  if [ "${1:-}" != "--si" ]; then
    fallo "Para aplicar de verdad hay que confirmarlo:  ./instalar.sh aplicar --si"
    gris "Antes conviene revisar:            ./instalar.sh plan"
    return 1
  fi

  info "APLICAR — se hara backup de todo lo que se toque"
  echo
  mkdir -p "$BACKUPS" "$(dirname "$MANIFIESTO")" || { fallo "no se pudo crear $ESTADO"; return 1; }
  : > "$MANIFIESTO"

  local creados=0 cambiados=0 iguales=0
  while IFS='|' read -r origen destino desc; do
    if [ ! -f "$origen" ]; then fallo "falta el origen: $origen"; continue; fi
    mkdir -p "$(dirname "$destino")" || { fallo "no se pudo crear $(dirname "$destino")"; continue; }

    if [ -f "$destino" ]; then
      if cmp -s "$origen" "$destino"; then
        iguales=$((iguales+1))
        printf '%s\t%s\t%s\n' "$destino" "sin-cambios" "-" >> "$MANIFIESTO"
        continue
      fi
      cp -a "$destino" "$BACKUPS/$(basename "$destino").bak" 2>/dev/null \
        || aviso "no se pudo respaldar $destino"
      cambiados=$((cambiados+1))
      printf '%s\t%s\t%s\n' "$destino" "modificado" "$BACKUPS/$(basename "$destino").bak" >> "$MANIFIESTO"
    else
      creados=$((creados+1))
      printf '%s\t%s\t%s\n' "$destino" "creado" "-" >> "$MANIFIESTO"
    fi
    # Escritura atomica: a temporal y luego mv, para no dejar un fichero a medias.
    cp "$origen" "$destino.tmp.$$" && mv "$destino.tmp.$$" "$destino" \
      || fallo "no se pudo escribir $destino"
    ok "${destino/#$HOME/~}"
  done < <(mapa)

  echo
  # El esquema de color se activa con kwriteconfig6, nunca editando el fichero a mano.
  #
  # IMPORTANTE: kdeglobals NO esta en el mapa de instalacion, asi que su backup hay
  # que hacerlo AQUI. Sin el, el rollback borra los ficheros pero deja
  # `ColorScheme=KdeMacosLight` apuntando a un esquema que ya no existe.
  # Bug real, encontrado al probar el ciclo aplicar -> rollback con un HOME falso.
  local KDEFILE="$XDG_CONFIG_HOME/kdeglobals"
  if command -v kwriteconfig6 >/dev/null 2>&1 && [ "$KRECONFIG_UTIL" != "cuelga" ]; then
    if [ -f "$KDEFILE" ]; then
      if cp -a "$KDEFILE" "$BACKUPS/kdeglobals.bak"; then
        printf '%s\t%s\t%s\n' "$KDEFILE" "modificado" "$BACKUPS/kdeglobals.bak" >> "$MANIFIESTO"
      else
        fallo "no se pudo respaldar $KDEFILE: no se cambia, para no dejarlo irreversible"
        return 1
      fi
    else
      printf '%s\t%s\t%s\n' "$KDEFILE" "creado" "-" >> "$MANIFIESTO"
    fi
    if timeout 5 kwriteconfig6 --file kdeglobals --group General --key ColorScheme KdeMacosLight; then
      ok "kdeglobals [General] ColorScheme = KdeMacosLight (con backup previo)"
    else
      aviso "kwriteconfig6 no respondio: activa el esquema a mano en Ajustes del sistema"
    fi
  else
    aviso "kwriteconfig6 no utilizable aqui: activa el esquema a mano en Ajustes del sistema"
    gris "  (no se ha tocado kdeglobals: no hay nada que revertir ahi)"
  fi

  echo
  printf '  %s creados · %s modificados · %s sin cambios\n' "$creados" "$cambiados" "$iguales"
  echo
  gris "Los ficheros de kde-gtk-config NO se han tocado, a proposito."
  gris "Para el tema GTK, selecciona 'kde-macos' en: Ajustes del sistema > Apariencia > Estilo GNOME/GTK"
  gris "Reversion completa:  ./instalar.sh rollback"
}

# --------------------------------------------------------------------------
# rollback
# --------------------------------------------------------------------------
cmd_rollback() {
  if [ ! -f "$MANIFIESTO" ]; then fallo "no hay manifiesto: nada que revertir"; return 1; fi
  info "ROLLBACK — restaurando desde el ultimo manifiesto"
  echo
  local restaurados=0 borrados=0
  while IFS=$'\t' read -r destino estado backup; do
    case "$estado" in
      modificado)
        if [ -f "$backup" ]; then cp -a "$backup" "$destino" && ok "restaurado ${destino/#$HOME/~}" && restaurados=$((restaurados+1));
        else aviso "no se encuentra el backup de $destino"; fi ;;
      creado)
        [ -e "$destino" ] && rm -f "$destino" && ok "eliminado ${destino/#$HOME/~}" && borrados=$((borrados+1)) ;;
    esac
  done < "$MANIFIESTO"
  echo
  printf '  %s restaurados · %s eliminados\n' "$restaurados" "$borrados"
  gris "Puede hacer falta reiniciar la sesion para que Plasma vuelva a leer la configuracion."
}

# --------------------------------------------------------------------------
# verificar
# --------------------------------------------------------------------------
cmd_verificar() {
  info "VERIFICAR — comprobaciones posteriores"
  echo
  local fallos=0
  while IFS='|' read -r origen destino desc; do
    if [ -f "$destino" ] && cmp -s "$origen" "$destino"; then ok "${destino/#$HOME/~}"
    else fallo "${destino/#$HOME/~} no coincide con el repo"; fallos=$((fallos+1)); fi
  done < <(mapa)
  echo
  if [ "$fallos" -eq 0 ]; then ok "todo instalado coincide con el repositorio"; else fallo "$fallos discrepancias"; fi
  echo
  gris "Recuerda: el QStyle y el efecto KWin no son parte de este instalador todavia."
}

# --------------------------------------------------------------------------
case "${1:-}" in
  preflight) cmd_preflight ;;
  plan)      cmd_plan ;;
  estado)    cmd_estado ;;
  aplicar)   shift; cmd_aplicar "${1:-}" ;;
  rollback)  cmd_rollback ;;
  verificar) cmd_verificar ;;
  *)
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 2 ;;
esac

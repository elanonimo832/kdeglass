#!/usr/bin/env bash
#
# install.sh — macOS-style desktop layer installer
#
# GOLDEN RULE OF THIS INSTALLER
#   By default it WRITES NOTHING. All subcommands are read-only or dry-run
#   except `aplicar`, which also requires --si. That way there is no way to break the
#   desktop by running it by accident, and everything can be audited before touching anything.
#
# USAGE
#   ./install.sh preflight     # checks the environment. Touches NOTHING.
#   ./install.sh plan          # shows WHAT it would do, file by file. Touches NOTHING.
#   ./install.sh estado        # what is installed and how it differs from the repo.
#   ./install.sh aplicar --si  # actually applies. Backs up before every change.
#   ./install.sh rollback      # restores the last full backup.
#   ./install.sh verificar     # post-install checks.
#
# GUARANTEES
#   - Never invokes sudo or writes outside $HOME.
#   - Dated backup of every file before touching it, in $XDG_STATE_HOME.
#   - Idempotent: applying the same content twice changes nothing.
#   - Reversible with a single command.

set -uo pipefail

# --------------------------------------------------------------------------
# Paths and constants
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
fallo() { printf '  %sFAIL%s  %s\n' "$ROJO" "$FIN" "$1"; }
aviso() { printf '  %sWARN%s  %s\n' "$AMBAR" "$FIN" "$1"; }
info()  { printf '%s%s%s\n' "$AZUL" "$1" "$FIN"; }
gris()  { printf '%s%s%s\n' "$GRIS" "$1" "$FIN"; }

# --------------------------------------------------------------------------
# Configuration reading, hang-proof
#
# `kreadconfig6` talks to the D-Bus session bus. If there is no bus (containers,
# SSH, degraded sessions) it does not fail: IT HANGS. An installer cannot afford
# that, so its availability is probed ONCE with a timeout and, if it does not
# respond, the file is read directly with awk.
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
  # leer_clave <file> <group> <key>
  local fichero="$1" grupo="$2" clave="$3" ruta
  ruta="$XDG_CONFIG_HOME/$fichero"
  [ -f "$ruta" ] || { echo ""; return; }
  if [ "$KRECONFIG_UTIL" = "si" ]; then
    local v
    v="$(timeout 3 kreadconfig6 --file "$fichero" --group "$grupo" --key "$clave" 2>/dev/null)"
    echo "$v"
    return
  fi
  # Alternative without D-Bus: read the INI by hand. Enough to report the status.
  # WATCH OUT: KDE's kdeglobals files can have CRLF line endings, and a trailing \r
  # breaks any comparison. It is trimmed on every line before looking at it.
  awk -v g="$grupo" -v k="$clave" '
    { linea = $0; sub(/\r$/, "", linea) }
    /^\[/ { sec = linea; sub(/^\[/, "", sec); sub(/\]$/, "", sec); dentro = (sec == g); next }
    dentro && index(linea, k"=") == 1 { sub("^"k"=", "", linea); print linea; exit }
  ' "$ruta"
}

# --------------------------------------------------------------------------
# Install map: source in the repo -> destination on the system
# --------------------------------------------------------------------------
# Format: "source|destination|description"
mapa() {
  cat <<MAPA
$SALIDA/color-schemes/KdeMacosLight.colors|$XDG_DATA_HOME/color-schemes/KdeMacosLight.colors|Light color scheme
$SALIDA/color-schemes/KdeMacosDark.colors|$XDG_DATA_HOME/color-schemes/KdeMacosDark.colors|Dark color scheme
$SALIDA/gtk-3.0/kde-macos.css|$XDG_DATA_HOME/themes/kde-macos/gtk-3.0/gtk.css|GTK3 theme
$SALIDA/gtk-3.0/kde-macos-dark.css|$XDG_DATA_HOME/themes/kde-macos/gtk-3.0/gtk-dark.css|Dark GTK3 theme
$SALIDA/gtk-4.0/kde-macos.css|$XDG_DATA_HOME/themes/kde-macos/gtk-4.0/gtk.css|GTK4 theme
$SALIDA/gtk-4.0/kde-macos-dark.css|$XDG_DATA_HOME/themes/kde-macos/gtk-4.0/gtk-dark.css|Dark GTK4 theme
MAPA
}

# --------------------------------------------------------------------------
# preflight
# --------------------------------------------------------------------------
cmd_preflight() {
  info "PREFLIGHT — environment check (nothing is touched)"
  echo

  info "1. Session"
  if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then ok "Wayland"; else aviso "not Wayland (${XDG_SESSION_TYPE:-undefined})"; fi
  if [ "${XDG_CURRENT_DESKTOP:-}" = "KDE" ]; then ok "KDE"; else aviso "not KDE (${XDG_CURRENT_DESKTOP:-undefined})"; fi
  if [ "${KDE_SESSION_VERSION:-}" = "6" ]; then ok "Plasma 6"; else aviso "not Plasma 6 (${KDE_SESSION_VERSION:-undefined})"; fi
  echo

  info "2. Required tools"
  for c in kwriteconfig6 kreadconfig6 fc-cache; do
    if command -v "$c" >/dev/null 2>&1; then ok "$c"; else fallo "$c (missing)"; fi
  done
  case "$KRECONFIG_UTIL" in
    si)        ok "kreadconfig6 responds (session bus available)" ;;
    cuelga)    aviso "kreadconfig6 does NOT respond (no session bus): kdeglobals will be read with awk" ;;
    *)         aviso "kreadconfig6 not available: kdeglobals will be read with awk" ;;
  esac
  echo

  info "3. Current widget style"
  local estilo
  # widgetStyle lives in the [KDE] section, not in [General]. Verified on this
  # machine's real kdeglobals (widgetStyle=kvantum is in [KDE]).
  estilo="$(leer_clave kdeglobals KDE widgetStyle)"
  if [ -n "$estilo" ]; then
    ok "widgetStyle = $estilo  (will be saved to the backup before changing it)"
  else
    aviso "widgetStyle not set in kdeglobals"
  fi
  # Reason why step 4 can fail SILENTLY if this is active.
  if [ "${KDE_WIDGET_STYLE_OVERRIDE:-}" != "" ]; then
    fallo "KDE_WIDGET_STYLE_OVERRIDE is set: the style change would be ignored"
  else
    ok "no KDE_WIDGET_STYLE_OVERRIDE in the environment"
  fi
  echo

  info "4. Qt6 plugin paths (lib vs lib64)"
  local encontradas=0
  for d in "$HOME/.local/lib/qt6/plugins/styles" "$HOME/.local/lib64/qt6/plugins/styles" \
           /usr/lib/qt6/plugins/styles /usr/lib64/qt6/plugins/styles; do
    if [ -d "$d" ]; then ok "$d"; encontradas=$((encontradas+1)); else gris "  (does not exist) $d"; fi
  done
  [ "$encontradas" -gt 0 ] || fallo "no style plugin directory was found"
  echo

  info "5. Configuration files that would be touched"
  for f in "$XDG_CONFIG_HOME/kdeglobals" "$XDG_CONFIG_HOME/kwinrc"; do
    if [ -f "$f" ]; then ok "$f ($(stat -c%s "$f") bytes)"; else aviso "$f (does not exist yet)"; fi
  done
  echo

  info "6. kde-gtk-config files (NOT touched, respected)"
  for f in "$XDG_CONFIG_HOME/gtk-3.0/gtk.css" "$XDG_CONFIG_HOME/gtk-4.0/gtk.css"; do
    if [ -f "$f" ]; then
      ok "$f exists — the installer does NOT overwrite it (it belongs to kde-gtk-config)"
    else
      gris "  (does not exist) $f"
    fi
  done
  echo

  info "7. Generated output available"
  local n=0
  for f in "$SALIDA"/color-schemes/*.colors "$SALIDA"/gtk-3.0/*.css "$SALIDA"/gtk-4.0/*.css; do
    [ -f "$f" ] && n=$((n+1))
  done
  if [ "$n" -gt 0 ]; then ok "$n generated files in output/"; else fallo "nothing in output/: run the generators"; fi
  echo
  gris "Preflight finished. Nothing has been modified."
}

# --------------------------------------------------------------------------
# plan
# --------------------------------------------------------------------------
cmd_plan() {
  info "PLAN — this is what 'aplicar' would do (nothing is touched)"
  echo
  printf '%-9s %-58s %s\n' "ACTION" "DESTINATION" "DETAIL"
  printf '%s\n' "---------------------------------------------------------------------------------------------------"

  while IFS='|' read -r origen destino desc; do
    local accion detalle
    if [ ! -f "$origen" ]; then
      accion="MISSING"; detalle="source does not exist"
    elif [ ! -e "$destino" ]; then
      accion="CREATE"; detalle="$desc"
    elif cmp -s "$origen" "$destino"; then
      accion="SAME"; detalle="no changes"
    else
      accion="CHANGE"; detalle="$desc ($(stat -c%s "$destino") -> $(stat -c%s "$origen") bytes)"
    fi
    printf '%-9s %-58s %s\n' "$accion" "${destino/#$HOME/~}" "$detalle"
  done < <(mapa)

  echo
  info "Changes to the KDE configuration"
  local actual
  actual="$(leer_clave kdeglobals General ColorScheme)"; [ -n "$actual" ] || actual="(not set)"
  printf '  %-34s %s\n' "kdeglobals [General] ColorScheme" "$actual -> KdeMacosLight"
  echo
  gris "None of this has been applied. To apply it:  ./install.sh aplicar --si"
}

# --------------------------------------------------------------------------
# estado
# --------------------------------------------------------------------------
cmd_estado() {
  info "ESTADO — what is installed and how it differs from the repo"
  echo
  info "Active color scheme"
  local cs ws ft
  cs="$(leer_clave kdeglobals General ColorScheme)"; [ -n "$cs" ] || cs="(not set)"
  ws="$(leer_clave kdeglobals KDE widgetStyle)"; [ -n "$ws" ] || ws="(not set)"
  ft="$(leer_clave kdeglobals General font)"; [ -n "$ft" ] || ft="(not set)"
  printf '  %-34s %s\n' "kdeglobals [General] ColorScheme" "$cs"
  printf '  %-34s %s\n' "kdeglobals [KDE] widgetStyle" "$ws"
  printf '  %-34s %s\n' "kdeglobals [General] font" "$ft"
  echo
  info "Difference between the repo and what is installed"
  local iguales=0 distintos=0 ausentes=0
  while IFS='|' read -r origen destino desc; do
    if [ ! -e "$destino" ]; then ausentes=$((ausentes+1))
    elif cmp -s "$origen" "$destino"; then iguales=$((iguales+1))
    else distintos=$((distintos+1)); printf '  %sDIFFERENT%s %s\n' "$AMBAR" "$FIN" "${destino/#$HOME/~}"; fi
  done < <(mapa)
  printf '  %s equal · %s different · %s not installed\n' "$iguales" "$distintos" "$ausentes"
  echo
  if [ -f "$MANIFIESTO" ]; then
    info "Last backup: $(tail -1 "$MANIFIESTO" | cut -f3 2>/dev/null || echo '?')"
  else
    gris "No manifest: nothing has ever been applied."
  fi
}

# --------------------------------------------------------------------------
# aplicar
# --------------------------------------------------------------------------
cmd_aplicar() {
  if [ "${1:-}" != "--si" ]; then
    fallo "To actually apply it must be confirmed:  ./install.sh aplicar --si"
    gris "It is best to review first:       ./install.sh plan"
    return 1
  fi

  info "APLICAR — everything that is touched will be backed up"
  echo
  mkdir -p "$BACKUPS" "$(dirname "$MANIFIESTO")" || { fallo "could not create $ESTADO"; return 1; }
  : > "$MANIFIESTO"

  local creados=0 cambiados=0 iguales=0
  while IFS='|' read -r origen destino desc; do
    if [ ! -f "$origen" ]; then fallo "missing source: $origen"; continue; fi
    mkdir -p "$(dirname "$destino")" || { fallo "could not create $(dirname "$destino")"; continue; }

    if [ -f "$destino" ]; then
      if cmp -s "$origen" "$destino"; then
        iguales=$((iguales+1))
        printf '%s\t%s\t%s\n' "$destino" "sin-cambios" "-" >> "$MANIFIESTO"
        continue
      fi
      cp -a "$destino" "$BACKUPS/$(basename "$destino").bak" 2>/dev/null \
        || aviso "could not back up $destino"
      cambiados=$((cambiados+1))
      printf '%s\t%s\t%s\n' "$destino" "modificado" "$BACKUPS/$(basename "$destino").bak" >> "$MANIFIESTO"
    else
      creados=$((creados+1))
      printf '%s\t%s\t%s\n' "$destino" "creado" "-" >> "$MANIFIESTO"
    fi
    # Atomic write: to a temp file and then mv, so no half-written file is left.
    cp "$origen" "$destino.tmp.$$" && mv "$destino.tmp.$$" "$destino" \
      || fallo "could not write $destino"
    ok "${destino/#$HOME/~}"
  done < <(mapa)

  echo
  # The color scheme is activated with kwriteconfig6, never by editing the file by hand.
  #
  # IMPORTANT: kdeglobals is NOT in the install map, so its backup has to be
  # made HERE. Without it, rollback deletes the files but leaves
  # `ColorScheme=KdeMacosLight` pointing at a scheme that no longer exists.
  # Real bug, found while testing the aplicar -> rollback cycle with a fake HOME.
  local KDEFILE="$XDG_CONFIG_HOME/kdeglobals"
  if command -v kwriteconfig6 >/dev/null 2>&1 && [ "$KRECONFIG_UTIL" != "cuelga" ]; then
    if [ -f "$KDEFILE" ]; then
      if cp -a "$KDEFILE" "$BACKUPS/kdeglobals.bak"; then
        printf '%s\t%s\t%s\n' "$KDEFILE" "modificado" "$BACKUPS/kdeglobals.bak" >> "$MANIFIESTO"
      else
        fallo "could not back up $KDEFILE: it is not changed, to avoid leaving it irreversible"
        return 1
      fi
    else
      printf '%s\t%s\t%s\n' "$KDEFILE" "creado" "-" >> "$MANIFIESTO"
    fi
    if timeout 5 kwriteconfig6 --file kdeglobals --group General --key ColorScheme KdeMacosLight; then
      ok "kdeglobals [General] ColorScheme = KdeMacosLight (with prior backup)"
    else
      aviso "kwriteconfig6 did not respond: activate the scheme by hand in System Settings"
    fi
  else
    aviso "kwriteconfig6 not usable here: activate the scheme by hand in System Settings"
    gris "  (kdeglobals has not been touched: there is nothing to revert there)"
  fi

  echo
  printf '  %s created · %s modified · %s unchanged\n' "$creados" "$cambiados" "$iguales"
  echo
  gris "The kde-gtk-config files have NOT been touched, on purpose."
  gris "For the GTK theme, select 'kde-macos' in: System Settings > Appearance > GNOME/GTK Style"
  gris "Full revert:  ./install.sh rollback"
}

# --------------------------------------------------------------------------
# rollback
# --------------------------------------------------------------------------
cmd_rollback() {
  if [ ! -f "$MANIFIESTO" ]; then fallo "no manifest: nothing to revert"; return 1; fi
  info "ROLLBACK — restoring from the last manifest"
  echo
  local restaurados=0 borrados=0
  while IFS=$'\t' read -r destino estado backup; do
    case "$estado" in
      modificado)
        if [ -f "$backup" ]; then cp -a "$backup" "$destino" && ok "restored ${destino/#$HOME/~}" && restaurados=$((restaurados+1));
        else aviso "backup for $destino not found"; fi ;;
      creado)
        [ -e "$destino" ] && rm -f "$destino" && ok "removed ${destino/#$HOME/~}" && borrados=$((borrados+1)) ;;
    esac
  done < "$MANIFIESTO"
  echo
  printf '  %s restored · %s removed\n' "$restaurados" "$borrados"
  gris "A session restart may be needed for Plasma to re-read the configuration."
}

# --------------------------------------------------------------------------
# verificar
# --------------------------------------------------------------------------
cmd_verificar() {
  info "VERIFICAR — post-install checks"
  echo
  local fallos=0
  while IFS='|' read -r origen destino desc; do
    if [ -f "$destino" ] && cmp -s "$origen" "$destino"; then ok "${destino/#$HOME/~}"
    else fallo "${destino/#$HOME/~} does not match the repo"; fallos=$((fallos+1)); fi
  done < <(mapa)
  echo
  if [ "$fallos" -eq 0 ]; then ok "everything installed matches the repository"; else fallo "$fallos discrepancies"; fi
  echo
  gris "Remember: the QStyle and the KWin effect are not part of this installer yet."
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

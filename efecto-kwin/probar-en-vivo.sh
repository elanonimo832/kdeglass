#!/usr/bin/env bash
# Prueba EN VIVO, a prueba de fallos, del efecto arreglado.
#
# Carga macosglass en el KWin que corre, captura la pantalla, mide el porcentaje
# de negro y lo DESCARGA SIEMPRE (trap EXIT), aunque el render fallara. No cierra
# sesion. No reinicia el compositor.
#
# Requisitos:
#   - El .so instalado debe ser el ARREGLADO. El script lo comprueba y aborta si
#     es el antiguo. Para instalarlo:
#       sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
#            /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
#   - La sesion grafica activa (KWin 6 corriendo).
#
# Si algo fuera mal de todos modos:  bash ~/RECUPERAR-KDE.sh reanimar
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
SISTEMA=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
SAL="$AQUI/build/prueba-en-vivo"
mkdir -p "$SAL"

command -v qdbus6 >/dev/null 2>&1 || { echo "Falta qdbus6 (paquete qt6-tools)."; exit 1; }

# --- Seguridad 1: el .so instalado tiene que ser el arreglado -------------
if [ ! -f "$SISTEMA" ]; then
  echo "ABORTADO: no hay .so instalado en $SISTEMA"
  exit 1
fi
if ! objdump -d --demangle "$SISTEMA" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null; then
  echo "ABORTADO: el .so instalado es el ANTIGUO (sin llamada de cadena)."
  echo "Instala el nuevo primero:"
  echo "  sudo install -Dm755 \"$AQUI/build/plugins/kwin/effects/macosglass.so\" \"$SISTEMA\""
  exit 1
fi

# --- Seguridad 2: nunca dejarlo activado en disco -------------------------
kwriteconfig6 --file kwinrc --group Plugins --key macosglassEnabled false

descargar() {
  timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass >/dev/null 2>&1
}
trap descargar EXIT INT TERM

capturar() { # $1 = etiqueta -> imprime la ruta
  local f="$SAL/$1.png"
  rm -f "$f"
  timeout 25 spectacle -b -n -o "$f" >/dev/null 2>&1 || true
  printf '%s' "$f"
}

medir() { # $1 = png
  python3 - "$1" <<'PY'
import sys
from PIL import Image
try:
    im = Image.open(sys.argv[1]).convert("RGB")
except Exception as e:
    print(f"    (no se pudo leer la captura: {e})")
    raise SystemExit
px = im.getdata()
n = len(px)
negro = sum(1 for r, g, b in px if r < 8 and g < 8 and b < 8)
print(f"    {im.size[0]}x{im.size[1]}  negro={100*negro/n:.1f}%")
PY
}

echo "1. Captura de CONTROL (efecto descargado)"
A=$(capturar control); medir "$A"

echo "2. Cargando macosglass EN CALIENTE en el KWin vivo..."
timeout 10 qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect macosglass >/dev/null 2>&1 || true
sleep 5
B=$(capturar cargado); medir "$B"

echo "3. Descargando macosglass..."
descargar
sleep 2
C=$(capturar tras-descargar); medir "$C"

echo
echo "Capturas en: $SAL"
echo "Criterio: 'cargado' NO debe ser 100% negra (deben verse escritorio/panel)."
echo "Si sale negra, el arreglo no basta. Recupera con:  bash ~/RECUPERAR-KDE.sh reanimar"

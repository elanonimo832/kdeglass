#!/usr/bin/env bash
# Compila e instala el efecto KWin.
#
# Avisa si falta cmake, que es el unico requisito que no esta en el sistema.
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AQUI"

if ! command -v cmake >/dev/null 2>&1; then
  cat <<'MSG'
FALTA CMAKE

El codigo compila y enlaza sin el (esta verificado), pero la metadata del plugin
no queda bien embebida y KWin lo rechaza. cmake lo resuelve solo.

  sudo pacman -S --needed cmake ninja

Los headers de KWin y de KF6 YA estan instalados: no hace falta nada mas.
MSG
  exit 1
fi

cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build build

# Comprueba el arreglo de la pantalla negra ANTES de nada. Si la cadena no esta,
# no se instala ni se activa: seria volver a dejar el escritorio negro.
if ! "$AQUI/verificar-cadena.sh"; then
  echo
  echo "NO se instala: el efecto no continua la cadena de pintado de KWin."
  exit 1
fi

echo
echo "Instalando en ~/.local ..."
cmake --install build

# A PROPOSITO no se activa aqui. Motivo: KWin ya conoce un `macosglass` en la
# ruta del sistema (/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so), y
# si ese es el binario ANTIGUO, activarlo con reconfigure deja la pantalla negra.
# El ~/.local no lo ve KWin. Para activarlo de verdad, instala el binario nuevo
# en la ruta del sistema y prueba con red de seguridad:
#
#   sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
#        /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
#   ./probar-en-vivo.sh
echo
echo "Compilado. NO se ha activado (a proposito)."
echo "El efecto todavia NO dibuja: solo garantiza que no rompe el render."
echo "Para instalarlo y probarlo con descarga automatica, lee instalar-efecto.sh."

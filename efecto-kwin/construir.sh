#!/usr/bin/env bash
# Compila el efecto KWin y comprueba que la cadena de pintado sigue intacta.
#
# NO instala ni activa. Para eso:  ./instalar-efecto.sh
set -euo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AQUI"

if ! command -v cmake >/dev/null 2>&1; then
  cat <<'MSG'
FALTA CMAKE

  sudo pacman -S --needed cmake ninja

Los headers de KWin y de KF6 ya estan instalados: no hace falta nada mas.
MSG
  exit 1
fi

# Los headers de Vulkan solo se usan para compilar (no enlazamos con Vulkan), asi
# que basta un stub propio: evita instalar los 42 MiB de vulkan-headers.
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
      -DVulkan_INCLUDE_DIR="$AQUI/_stub"
cmake --build build

# Si la cadena no esta, NO se sigue: instalar ese .so deja el escritorio negro.
if ! "$AQUI/verificar-cadena.sh"; then
  echo
  echo "NO se instala: el efecto no continua la cadena de pintado de KWin."
  exit 1
fi

echo
echo "Compilado: build/plugins/kwin/effects/macosglass2.so"
echo "  Instalar:      ./instalar-efecto.sh"
echo "  Probar (sin cerrar sesion):  ./probar-ya-instalado.sh"
echo
echo "El efecto todavia NO dibuja: el shader del material es el paso siguiente."

#!/usr/bin/env bash
# Estado del efecto. Ejecutalo DESPUES de reiniciar KWin.
set -uo pipefail
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== 1. PRUEBA DIRECTA (lo que hace KWin al arrancar) ==="
"$AQUI/build/verificar-carga" 2>&1 | grep -vE 'explicitly states' | sed 's/^/  /'

echo
echo "=== 2. ESTADO EN EL KWIN QUE CORRE ==="
printf '  isEffectSupported : '; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectSupported macosglass 2>&1
printf '  isEffectLoaded    : '; qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass 2>&1
printf '  en listOfEffects  : '; qdbus6 org.kde.KWin /Effects listOfEffects 2>/dev/null | tr ',' '\n' | grep -c macosglass

echo
echo "=== 3. CRONOLOGIA (si KWin es anterior al .so, no lo habra visto) ==="
printf '  KWin arranco : '; ps -eo lstart,comm 2>/dev/null | grep -E 'kwin_wayland$' | awk '{print $2" "$3" "$4" "$5}'
printf '  .so instalado: '; stat -c '%y' /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so 2>/dev/null | cut -c1-19

echo
echo "=== 4. MENSAJES DE MI EFECTO EN EL JOURNAL ==="
journalctl --user --since '30 min ago' --no-pager 2>/dev/null \
  | grep -iE 'macos-glass|macosglass' | grep -viE 'systemd-run|sudo\[|diagnostico|verificar-carga|probar-fabrica' | tail -6 \
  || echo "  (ninguno todavia: el efecto aun no se ha cargado)"

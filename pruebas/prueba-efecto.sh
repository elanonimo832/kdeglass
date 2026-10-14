# El efecto KWin: invariantes que NO deben romperse.
# Estas pruebas son las que impiden volver a la pantalla negra.

EF="$PROY/efecto-kwin"
FUENTE="$EF/src/glass.cpp"
SO_BUILD="$EF/build/plugins/kwin/effects/macosglass2.so"
SO_SIS=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

echo "  -- la cadena de pintado (causa de la pantalla negra) --"
afirmar_existe "existe src/glass.cpp" "$FUENTE"
afirmar_codigo "paintWindow llama a effects->paintWindow()" "$FUENTE" "^[[:space:]]*effects->paintWindow\("
afirmar_contiene "incluye glass.moc (necesario para el plugin)" "$FUENTE" 'include "glass\.moc"'

echo "  -- el plugin compilado --"
if [ -f "$SO_BUILD" ]; then
  objdump -d --demangle "$SO_BUILD" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null \
    && ok "el .so compilado llama a la cadena" || fallo "el .so compilado NO llama a la cadena"
  nm -D "$SO_BUILD" 2>/dev/null | grep -q 'qt_plugin_instance' \
    && ok "el .so exporta qt_plugin_instance" || fallo "falta qt_plugin_instance"
  strings "$SO_BUILD" 2>/dev/null | grep -q 'KWin/Effect' \
    && ok "la metadata declara KWin/Effect" || fallo "falta KPackageStructure KWin/Effect"
else
  fallo "no esta compilado el .so (ejecuta: cmake --build build)"
fi

echo "  -- el plugin instalado --"
if [ -f "$SO_SIS" ]; then
  objdump -d --demangle "$SO_SIS" 2>/dev/null | grep -cE 'EffectsHandler::paintWindow' >/dev/null \
    && ok "el .so instalado llama a la cadena" || fallo "el .so INSTALADO no llama a la cadena"
else
  fallo "macosglass2.so no esta instalado"
fi

echo "  -- la ruta correcta (kwin/effects/plugins, NO kwin/effects) --"
# KWin::PluginEffectLoader busca en kwin/effects/plugins. Instalar un nivel mas
# arriba hace que KWin no lo vea, EN SILENCIO. Fue uno de los fallos del incidente.
afirmar_contiene "el instalador usa la ruta con /plugins" "$EF/instalar-efecto.sh" 'kwin/effects/plugins'
negar "no queda ningun .so en kwin/effects/ (ruta equivocada)" \
  test -f /usr/lib/qt6/plugins/kwin/effects/macosglass2.so

echo "  -- el identificador --"
# El id del plugin lo deriva KWin del NOMBRE DEL FICHERO. Si no coincide con la
# clave de kwinrc, KWin no lo encuentra. Y con el id 'macosglass' rompia el render.
afirmar_contiene "el instalador instala macosglass2" "$EF/instalar-efecto.sh" 'macosglass2'
negar "no queda el .so con el id que rompia" \
  test -f /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so

echo "  -- scripts de diagnostico --"
for s in "$EF/instalar-efecto.sh" "$EF/construir.sh" \
         "$PROY/instalar.sh" "$PROY/instalar-decoracion.sh" \
         "$PROY/RECUPERAR-KDE.sh"; do
  [ -f "$s" ] && { bash -n "$s" 2>/dev/null && ok "$(basename "$s"): sintaxis bash OK" || fallo "$(basename "$s"): sintaxis bash MALA"; }
done

echo "  -- ningun script EJECUTA kwin_wayland --replace --"
# Deja la pantalla negra: en Wayland arranca un segundo compositor que compite por
# el DRM/GL y mata el contexto OpenGL del KWin vivo. Solo miramos lineas de COMANDO:
# mencionarlo en un comentario para avisar de que no se use es correcto y deseable.
malos=0
for s in "$EF"/*.sh "$PROY"/*.sh; do
  [ -f "$s" ] || continue
  # Solo cuenta si el comando se EJECUTA: al principio de la linea o tras un
  # separador de shell. Dentro de un echo (para avisar de que no se use) no cuenta.
  if grep -vE '^\s*#' "$s" 2>/dev/null \
       | grep -qE '(^|[;&|]|\$\()[[:space:]]*kwin_wayland[[:space:]]+--replace'; then
    malos=$((malos+1)); printf '      -> %s\n' "$(basename "$s")"
    grep -nE '(^|[;&|]|\$\()[[:space:]]*kwin_wayland[[:space:]]+--replace' "$s" | sed 's/^/         /'
  fi
done
afirmar_igual "ningun script ejecuta --replace" "0" "$malos"

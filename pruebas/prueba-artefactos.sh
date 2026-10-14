# Artefactos generados: tokens, esquemas de color, CSS de GTK.
# Invariante: los ficheros existen, son validos y contienen lo que dicen.

echo "  -- tokens --"
afirmar_existe "existe tokens.toml" "$PROY/tokens.toml"
afirmar_existe "existe el directorio tokens/" "$PROY/tokens"

n_toml=$(ls "$PROY"/tokens/*.toml 2>/dev/null | wc -l)
afirmar "hay colecciones de tokens ($n_toml)" test "$n_toml" -ge 5

# todos los .toml tienen que ser TOML valido
malos=0
for f in "$PROY"/tokens/*.toml; do
  python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$f" 2>/dev/null || malos=$((malos+1))
done
afirmar_igual "todos los .toml de tokens/ son validos" "0" "$malos"

python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$PROY/tokens.toml" 2>/dev/null \
  && ok "tokens.toml es TOML valido" || fallo "tokens.toml no es TOML valido"

# cada token debe declarar su procedencia (lo prometimos en el README)
afirmar_contiene "tokens.toml declara procedencia" "$PROY/tokens.toml" '_procedencia|procedencia'

echo "  -- esquemas de color de KDE --"
for s in KdeMacosLight KdeMacosDark; do
  f="$PROY/salida/color-schemes/$s.colors"
  afirmar_existe "existe $s.colors" "$f"
  if [ -f "$f" ]; then
    grupos=$(grep -c '^\[' "$f" 2>/dev/null)
    afirmar "  $s tiene grupos de KDE ($grupos)" test "$grupos" -ge 10
    afirmar_contiene "  $s define [Colors:Window]" "$f" '^\[Colors:Window\]'
    afirmar_contiene "  $s define [Colors:Button]" "$f" '^\[Colors:Button\]'
  fi
done

echo "  -- CSS de GTK --"
for v in 3.0 4.0; do
  for t in kde-macos kde-macos-dark colors; do
    f="$PROY/salida/gtk-$v/$t.css"
    afirmar_existe "existe gtk-$v/$t.css" "$f"
  done
done

# el CSS no debe tener llaves descompensadas
for f in "$PROY"/salida/gtk-*/*.css; do
  [ -f "$f" ] || continue
  a=$(grep -o '{' "$f" 2>/dev/null | wc -l); b=$(grep -o '}' "$f" 2>/dev/null | wc -l)
  afirmar_igual "$(basename "$f"): llaves equilibradas" "$a" "$b"
done

echo "  -- reproducibilidad --"
# generar dos veces debe dar lo mismo (los tokens son la fuente unica)
f1=$(mktemp); f2=$(mktemp)
cp "$PROY/salida/color-schemes/KdeMacosDark.colors" "$f1"
python3 "$PROY/herramientas/generar-esquemas-kde.py" >/dev/null 2>&1 || true
if [ -f "$PROY/salida/color-schemes/KdeMacosDark.colors" ]; then
  cp "$PROY/salida/color-schemes/KdeMacosDark.colors" "$f2"
  if cmp -s "$f1" "$f2"; then ok "regenerar el esquema da un fichero identico"
  else fallo "regenerar el esquema CAMBIA el fichero (no es reproducible)"; fi
fi
rm -f "$f1" "$f2"

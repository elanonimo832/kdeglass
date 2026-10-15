# Generated artifacts: tokens, color schemes, GTK CSS.
# Invariant: the files exist, are valid, and contain what they claim.

echo "  -- tokens --"
afirmar_existe "tokens.toml exists" "$PROJECT/tokens.toml"
afirmar_existe "tokens/ directory exists" "$PROJECT/tokens"

n_toml=$(ls "$PROJECT"/tokens/*.toml 2>/dev/null | wc -l)
afirmar "there are token collections ($n_toml)" test "$n_toml" -ge 5

# every .toml must be valid TOML
bad=0
for f in "$PROJECT"/tokens/*.toml; do
  python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$f" 2>/dev/null || bad=$((bad+1))
done
afirmar_igual "all .toml files in tokens/ are valid" "0" "$bad"

python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$PROJECT/tokens.toml" 2>/dev/null \
  && ok "tokens.toml is valid TOML" || fallo "tokens.toml is not valid TOML"

# every token must declare its provenance (we promised that in the README)
afirmar_contiene "tokens.toml declares provenance" "$PROJECT/tokens.toml" '_procedencia|procedencia|provenance'

echo "  -- KDE color schemes --"
for s in KdeMacosLight KdeMacosDark; do
  f="$PROJECT/output/color-schemes/$s.colors"
  afirmar_existe "$s.colors exists" "$f"
  if [ -f "$f" ]; then
    grupos=$(grep -c '^\[' "$f" 2>/dev/null)
    afirmar "  $s has KDE groups ($grupos)" test "$grupos" -ge 10
    afirmar_contiene "  $s defines [Colors:Window]" "$f" '^\[Colors:Window\]'
    afirmar_contiene "  $s defines [Colors:Button]" "$f" '^\[Colors:Button\]'
  fi
done

echo "  -- GTK CSS --"
for v in 3.0 4.0; do
  for t in kde-macos kde-macos-dark colors; do
    afirmar_existe "gtk-$v/$t.css exists" "$PROJECT/output/gtk-$v/$t.css"
  done
done

# the CSS must not have unbalanced braces
for f in "$PROJECT"/output/gtk-*/*.css; do
  [ -f "$f" ] || continue
  a=$(grep -o '{' "$f" 2>/dev/null | wc -l); b=$(grep -o '}' "$f" 2>/dev/null | wc -l)
  afirmar_igual "$(basename "$f"): balanced braces" "$a" "$b"
done

echo "  -- reproducibility --"
# generating twice must produce the same bytes (the tokens are the single source)
f1=$(mktemp); f2=$(mktemp)
cp "$PROJECT/output/color-schemes/KdeMacosDark.colors" "$f1"
python3 "$PROJECT/tools/generate-kde-schemes.py" >/dev/null 2>&1 || true
if [ -f "$PROJECT/output/color-schemes/KdeMacosDark.colors" ]; then
  cp "$PROJECT/output/color-schemes/KdeMacosDark.colors" "$f2"
  if cmp -s "$f1" "$f2"; then ok "regenerating the scheme produces an identical file"
  else fallo "regenerating the scheme CHANGES the file (not reproducible)"; fi
fi
rm -f "$f1" "$f2"

echo "  -- the decoration regenerates WITHOUT undoing what was fixed on screen --"
# LA DECORACION NO ESTABA CUBIERTA POR LA COMPROBACION DE ARRIBA, y por eso el generador se quedo
# atras sin que nadie lo notara: producia los valores de ANTES de los arreglos del apartado 10a
# (botones de 12 en vez de 16, PaddingTop 7 -- el que empujaba los botones fuera de la barra --,
# ButtonMarginTop 8, colores de texto viejos y comentarios en español). Ejecutarlo habria revertido
# el aspecto que el usuario ya habia pedido y aprobado. Estas dos aserciones lo impiden.
d1=$(mktemp); d2=$(mktemp)
cp "$PROJECT/output/aurorae/KdeMacOS/KdeMacOSrc" "$d1"
cp "$PROJECT/output/aurorae/KdeMacOS/decoration.svg" "$d2"
python3 "$PROJECT/tools/generate-macos-decoration.py" >/dev/null 2>&1 || true
afirmar_codigo "the generator keeps the 16 px buttons the user asked for" \
  "$PROJECT/output/aurorae/KdeMacOS/KdeMacOSrc" '^ButtonWidth=16$'
afirmar_codigo "and the measured vertical centring (PaddingTop 2, margin 4)" \
  "$PROJECT/output/aurorae/KdeMacOS/KdeMacOSrc" '^ButtonMarginTop=4$'
# NO HAY ASERCION SOBRE EL `fill` DE LA PIEZA DEL CENTRO, y es deliberado. Se intento quitar su
# blanco porque en una captura parecia un "borde blanco muy grande y feo", y fue un error: ese
# rectangulo no es un borde, es lo que le da cuerpo a la ventana por detras del contenido. Al
# quitarlo el escritorio se vio a traves de los lados y las esquinas de abajo quedaron sin nada --
# el usuario: "mis ventanas estan extranas". Se revirtio. Lo que si queda es la reproducibilidad de
# abajo, que es lo que impide que el generador vuelva a divergir del arbol.
if cmp -s "$d1" "$PROJECT/output/aurorae/KdeMacOS/KdeMacOSrc" \
   && cmp -s "$d2" "$PROJECT/output/aurorae/KdeMacOS/decoration.svg"; then
  ok "regenerating the decoration produces identical files"
else
  fallo "regenerating the decoration CHANGES the files (the generator has drifted from the tree)"
  diff "$d1" "$PROJECT/output/aurorae/KdeMacOS/KdeMacOSrc" | head -6 | sed 's/^/      /'
fi
rm -f "$d1" "$d2"

echo "  -- rollback: restaurar, no borrar --"
# EL FALLO REAL, encontrado al usarlo: `rollback` BORRABA el tema en vez de restaurarlo. El
# manifiesto guardaba DOS lineas para el mismo destino -- `modificado <copia>` y luego `creado -` --
# porque el `creado` se escribia siempre, tambien cuando ya habia una version previa. El bucle las
# lee en orden, restaura de la copia y acto seguido borra el directorio: la segunda anula a la
# primera. Un rollback que borra lo que debia devolver es peor que no tener rollback, asi que esto
# se prueba en un HOME de mentira, sin tocar nada del usuario, y sin activar nada en KWin.
ISLA=$(mktemp -d)
mkdir -p "$ISLA/data/aurorae/themes/KdeMacOS" "$ISLA/state"
printf 'la decoracion que el usuario ya tenia\n' > "$ISLA/data/aurorae/themes/KdeMacOS/KdeMacOSrc"
printf 'un fichero que solo existe en la instalacion previa\n' > "$ISLA/data/aurorae/themes/KdeMacOS/solo-previo.txt"
cp -a "$ISLA/data/aurorae/themes/KdeMacOS" "$ISLA/lo-que-habia"
XDG_DATA_HOME="$ISLA/data" XDG_STATE_HOME="$ISLA/state" \
  timeout 60 "$PROJECT/install-decoration.sh" aplicar --si >/dev/null 2>&1
XDG_DATA_HOME="$ISLA/data" XDG_STATE_HOME="$ISLA/state" \
  timeout 60 "$PROJECT/install-decoration.sh" rollback >/dev/null 2>&1

afirmar_existe "rollback deja el tema donde estaba (NO lo borra)" \
  "$ISLA/data/aurorae/themes/KdeMacOS/KdeMacOSrc"
if [ -f "$ISLA/data/aurorae/themes/KdeMacOS/KdeMacOSrc" ]; then
  afirmar_igual "y devuelve el contenido que tenia, no el instalado" \
    "la decoracion que el usuario ya tenia" \
    "$(cat "$ISLA/data/aurorae/themes/KdeMacOS/KdeMacOSrc")"
  afirmar_existe "sin perder los ficheros que solo estaban en la version previa" \
    "$ISLA/data/aurorae/themes/KdeMacOS/solo-previo.txt"
fi
# El manifiesto no puede pedir dos cosas contradictorias para el mismo destino: es la raiz del fallo.
duplicados=$(cut -f1 "$ISLA/state/kde-macos/manifest-decoracion.tsv" 2>/dev/null | sort | uniq -d | wc -l)
afirmar_igual "el manifiesto tiene UNA entrada por destino, no dos" "0" "$duplicados"

# LA OTRA MITAD DEL CONTRATO, que no debe romperse al arreglar esto: si NO habia nada antes, el
# rollback SI tiene que borrar lo que creo. Un `creado` que nunca se escribe dejaria basura instalada
# y nadie se enteraria; por eso las dos ramas se prueban.
ISLA2=$(mktemp -d)
mkdir -p "$ISLA2/data" "$ISLA2/state"
XDG_DATA_HOME="$ISLA2/data" XDG_STATE_HOME="$ISLA2/state" \
  timeout 60 "$PROJECT/install-decoration.sh" aplicar --si >/dev/null 2>&1
afirmar_existe "una instalacion desde cero crea el tema" \
  "$ISLA2/data/aurorae/themes/KdeMacOS/KdeMacOSrc"
XDG_DATA_HOME="$ISLA2/data" XDG_STATE_HOME="$ISLA2/state" \
  timeout 60 "$PROJECT/install-decoration.sh" rollback >/dev/null 2>&1
negar "y su rollback SI lo borra (era una creacion, no una modificacion)" \
  test -d "$ISLA2/data/aurorae/themes/KdeMacOS"
rm -rf "$ISLA" "$ISLA2"

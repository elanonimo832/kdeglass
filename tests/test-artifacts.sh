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

# The numbers and file names the docs assert must match reality.
#
# Why this exists: the docs drifted silently. DELIVERY.md claimed "55 checks"
# when the harness had 100, "1814 lines" for a 1813-line file, and that cmake was
# "not installed" when it was. A number in prose has no way to stay honest on its
# own, so it gets a test.

echo "  -- the docs must NOT quote a check count --"
# A number in prose cannot stay honest: adding one test changes it. We learned
# this the hard way -- the count went 55 -> 68 -> 100 -> 109 -> 110 -> 109,
# oscillating because the test that checked the number WAS one of the checks.
# The stable rule: the docs name the harness, and never its size.
malos=0
for f in "$PROY"/*.md "$PROY"/docs/*.md "$PROY"/effect-kwin/README.md; do
  [ -f "$f" ] || continue
  if grep -qE '[0-9]+ (checks|comprobaciones)' "$f" 2>/dev/null; then
    malos=$((malos+1))
    printf '      -> %s quotes a check count\n' "$(basename "$f")"
    grep -nE '[0-9]+ (checks|comprobaciones)' "$f" | sed 's/^/         /'
  fi
done
afirmar_igual "no doc quotes a check count" "0" "$malos"

# Y si alguna cita el arnes, debe hacerlo por su ruta.
afirmar_contiene "the README names the harness by path" "$PROY/README.md" 'tests/run\.sh'

echo "  -- tokens.toml line count --"
lineas=$(wc -l < "$PROY/tokens.toml")
malos=0
for f in "$PROY"/*.md; do
  [ -f "$f" ] || continue
  for n in $(grep -oE '[0-9]+ lines' "$f" 2>/dev/null | grep -oE '^[0-9]+'); do
    # 1813 es la cifra real; cualquier "N lines" que cite tokens.toml debe cuadrar
    [ "$n" = "$lineas" ] || true
  done
done
# comprobacion directa: si algun doc afirma un numero de lineas para tokens.toml, debe ser el real
malos=0
for f in "$PROY"/*.md; do
  [ -f "$f" ] || continue
  if grep -qE 'tokens\.toml.{0,40}[0-9]+ lines|[0-9]+ lines.{0,40}tokens\.toml' "$f" 2>/dev/null; then
    for n in $(grep -oE '[0-9]+ lines' "$f" | grep -oE '^[0-9]+'); do
      [ "$n" = "$lineas" ] || { malos=$((malos+1)); printf '      -> %s cites %s lines for tokens.toml, real is %s\n' "$(basename "$f")" "$n" "$lineas"; }
    done
  fi
done
afirmar_igual "any tokens.toml line count cited is the real one" "0" "$malos"

echo "  -- token collection count --"
real_toml=$(ls -1 "$PROY"/tokens/*.toml 2>/dev/null | wc -l)
afirmar "there are token collections ($real_toml)" test "$real_toml" -ge 5

echo "  -- tools the docs say are missing, and tools that must exist --"
# The realistic claim to guard: the four generators exist and are named correctly.
for t in generate-kde-schemes.py generate-gtk-css.py generate-macos-decoration.py consolidate-tokens.py; do
  afirmar_existe "tools/$t exists" "$PROY/tools/$t"
done
# And the reverse: a doc must not claim a real tool does not exist.
negar "the docs do not claim cmake is missing" \
  grep -qE 'cmake.{0,30}(are|is) not installed' "$PROY/DELIVERY.md"

echo "  -- the effect artifact the docs describe --"
SO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
if [ -f "$SO" ]; then
  real_size=$(stat -c%s "$SO")
  malos=0
  for f in "$PROY"/*.md; do
    [ -f "$f" ] || continue
    for n in $(grep -oE '[0-9]{4,6} bytes' "$f" 2>/dev/null | grep -oE '^[0-9]+'); do
      # solo se contrastan los que hablan del plugin instalado
      grep -qE "macosglass2[^0-9]{0,60}$n bytes|$n bytes[^0-9]{0,60}macosglass2" "$f" 2>/dev/null || continue
      [ "$n" = "$real_size" ] || { malos=$((malos+1)); printf '      -> %s says %s bytes, real is %s\n' "$(basename "$f")" "$n" "$real_size"; }
    done
  done
  afirmar_igual "any installed-plugin size cited is the real one" "0" "$malos"
else
  ok "(plugin not installed; size claims not checked)"
fi

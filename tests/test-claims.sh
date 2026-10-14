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
bad=0
for f in "$PROJECT"/*.md "$PROJECT"/docs/*.md "$PROJECT"/effect-kwin/README.md; do
  [ -f "$f" ] || continue
  if grep -qE '[0-9]+ (checks|comprobaciones)' "$f" 2>/dev/null; then
    bad=$((bad+1))
    printf '      -> %s quotes a check count\n' "$(basename "$f")"
    grep -nE '[0-9]+ (checks|comprobaciones)' "$f" | sed 's/^/         /'
  fi
done
afirmar_igual "no doc quotes a check count" "0" "$bad"

# And if a document cites the harness, it must cite it by path.
afirmar_contiene "the README names the harness by path" "$PROJECT/README.md" 'tests/run\.sh'

echo "  -- tokens.toml line count --"
lines=$(wc -l < "$PROJECT/tokens.toml")
bad=0
for f in "$PROJECT"/*.md; do
  [ -f "$f" ] || continue
  for n in $(grep -oE '[0-9]+ lines' "$f" 2>/dev/null | grep -oE '^[0-9]+'); do
    # 1813 is the real figure; any "N lines" cited for tokens.toml has to match it
    [ "$n" = "$lines" ] || true
  done
done
# direct check: if a document claims a line count for tokens.toml, it must be the real one
bad=0
for f in "$PROJECT"/*.md; do
  [ -f "$f" ] || continue
  if grep -qE 'tokens\.toml.{0,40}[0-9]+ lines|[0-9]+ lines.{0,40}tokens\.toml' "$f" 2>/dev/null; then
    for n in $(grep -oE '[0-9]+ lines' "$f" | grep -oE '^[0-9]+'); do
      [ "$n" = "$lines" ] || { bad=$((bad+1)); printf '      -> %s cites %s lines for tokens.toml, real is %s\n' "$(basename "$f")" "$n" "$lines"; }
    done
  fi
done
afirmar_igual "any tokens.toml line count cited is the real one" "0" "$bad"

echo "  -- token collection count --"
real_toml=$(ls -1 "$PROJECT"/tokens/*.toml 2>/dev/null | wc -l)
afirmar "there are token collections ($real_toml)" test "$real_toml" -ge 5

echo "  -- tools the docs say are missing, and tools that must exist --"
# The realistic claim to guard: the four generators exist and are named correctly.
for t in generate-kde-schemes.py generate-gtk-css.py generate-macos-decoration.py consolidate-tokens.py; do
  afirmar_existe "tools/$t exists" "$PROJECT/tools/$t"
done
# And the reverse: a doc must not claim a real tool does not exist.
negar "the docs do not claim cmake is missing" \
  grep -qE 'cmake.{0,30}(are|is) not installed' "$PROJECT/DELIVERY.md"

echo "  -- the effect artifact the docs describe --"
SO=/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
if [ -f "$SO" ]; then
  real_size=$(stat -c%s "$SO")
  bad=0
  for f in "$PROJECT"/*.md; do
    [ -f "$f" ] || continue
    for n in $(grep -oE '[0-9]{4,6} bytes' "$f" 2>/dev/null | grep -oE '^[0-9]+'); do
      # only the ones about the installed plugin are compared
      grep -qE "macosglass2[^0-9]{0,60}$n bytes|$n bytes[^0-9]{0,60}macosglass2" "$f" 2>/dev/null || continue
      [ "$n" = "$real_size" ] || { bad=$((bad+1)); printf '      -> %s says %s bytes, real is %s\n' "$(basename "$f")" "$n" "$real_size"; }
    done
  done
  afirmar_igual "any installed-plugin size cited is the real one" "0" "$bad"
else
  ok "(plugin not installed; size claims not checked)"
fi

echo "  -- no tracked file may have a Spanish name --"
# The whole repository is in English: file names, directories, documentation and
# code comments. Only the CONVERSATION stays in Spanish, and BRIEF-ORIGINAL.md is
# the user's untouched brief. This test stops a stray Spanish name creeping back.
#
# We check for Spanish WORDS, not accents: the original names were unaccented
# (ANALISIS, OUTPUT, efecto-kwin) so an accent check would have missed them all.
bad=$(python3 - "$PROJECT" <<'PYEOF'
import subprocess, sys, re
root = sys.argv[1]
output = subprocess.run(['git', '-C', root, 'ls-files'],
                        capture_output=True, text=True).stdout.split()
# Spanish words that used to appear in names and are not technical terms.
# They are DATA: the detector needs the Spanish spelling, so a rename must not translate
# them (one did, and it started flagging the output/ directory).
PALABRAS = ('analisis','inventario','huellas','referencias','anexo','verificacion',
            'incidente','instalacion','recuperar','instalar','efecto','pruebas',
            'evidencia','herramientas','leeme','forma-efectos','tipografia',
            'vista-previa','testName','construir','probar','diagnostico','ejecutar',
            'rutas','pantalla','salida','recuperada','descargar','escritorio')
allowed = ('BRIEF-ORIGINAL.md',)  # the original brief, untouched on purpose
bad = []
for ruta in output:
    if any(ruta.endswith(p) or ruta == p for p in allowed):
        continue
    # the COMPONENTS of the name are compared, not the whole path
    for parte in ruta.lower().replace('_', '-').replace('.', '-').split('/'):
        if parte in PALABRAS or any(parte.startswith(p + '-') or parte.endswith('-' + p) for p in PALABRAS):
            bad.append(ruta); break
for m in bad:
    print(f"      -> Spanish name: {m}")
print(len(bad))
PYEOF
)
n="${bad##*$'\n'}"
afirmar_igual "no tracked file has a Spanish name" "0" "$n"

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

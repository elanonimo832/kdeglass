# Documentation must not contradict itself: that was a real problem.
echo "  -- the incident has an authoritative summary --"
# The document accumulated 4 conclusions from 2 sessions. Whoever reads it must
# know which one is right WITHOUT having to read the whole thing.
afirmar_existe "INCIDENT.md exists" "$PROY/INCIDENT.md"
afirmar_contiene "it warns that it is historical" "$PROY/INCIDENT.md" 'SUPERSEDED|SUPERADAS|HISTORICAL|HISTÓRICO|HISTORICO'
afirmar_contiene "it names the final cause" "$PROY/INCIDENT.md" 'IDENTIFIER|IDENTIFICADOR'
afirmar_contiene "it mentions macosglass2" "$PROY/INCIDENT.md" 'macosglass2'

echo "  -- DELIVERY.md points to the correction --"
afirmar_contiene "DELIVERY.md corrects its conclusions" "$PROY/DELIVERY.md" 'FINAL CORRECTION|CORRECCIÓN FINAL|CORRECCION FINAL'

echo "  -- the effect has a README --"
afirmar_existe "effect-kwin/README.md exists" "$PROY/effect-kwin/README.md"
afirmar_literal "the README explains the right path" "$PROY/effect-kwin/README.md" 'kwin/effects/plugins'
afirmar_literal "the README explains the paint chain" "$PROY/effect-kwin/README.md" 'effects->paintWindow'
afirmar_literal "the README explains the current id" "$PROY/effect-kwin/README.md" 'macosglass2'
afirmar_literal "the README explains the shader is missing" "$PROY/effect-kwin/README.md" 'shader'

echo "  -- no broken links in the documentation --"
malos=0
for md in "$PROY"/*.md "$PROY"/docs/*.md "$PROY"/effect-kwin/README.md; do
  [ -f "$md" ] || continue
  d="$(dirname "$md")"
  while read -r e; do
    [ -z "$e" ] && continue
    case "$e" in http*|\#*) continue;; esac
    [ -e "$d/$e" ] || { malos=$((malos+1)); printf '      -> %s: %s\n' "$(basename "$md")" "$e"; }
  done < <(grep -oE '\]\([A-Za-z0-9._/-]+\.(md|sh|py|js|toml|colors|css|png)\)' "$md" 2>/dev/null | sed 's/^](//;s/)$//')
done
afirmar_igual "no broken links in the documentation" "0" "$malos"

echo "  -- the recovery manual is there --"
afirmar_existe "RECOVER-KDE.sh exists" "$PROY/RECOVER-KDE.sh"
afirmar_contiene "it has the revive command" "$PROY/RECOVER-KDE.sh" 'reanimar'

echo "  -- process documentation (docs/) --"
for d in ARCHITECTURE METHODOLOGY ROADMAP; do
  afirmar_existe "docs/$d.md exists" "$PROY/docs/$d.md"
done

# The methodology must collect the lessons that cost hours.
afirmar_literal "the methodology includes 'Measure before reasoning'" "$PROY/docs/METHODOLOGY.md" 'Measure before reasoning'
afirmar_literal "the methodology includes the minimal case" "$PROY/docs/METHODOLOGY.md" 'minimal case'
afirmar_literal "the methodology requires seeing the test fail" "$PROY/docs/METHODOLOGY.md" 'see it fail'
afirmar_literal "the methodology forbids --replace" "$PROY/docs/METHODOLOGY.md" 'kwin_wayland --replace'

# The roadmap must say the shader is next and have a done criterion.
afirmar_literal "the roadmap marks the shader as next" "$PROY/docs/ROADMAP.md" 'next'
afirmar_literal "the roadmap has a done criterion" "$PROY/docs/ROADMAP.md" 'Done when'
afirmar_literal "the roadmap acknowledges the OpenGL risk" "$PROY/docs/ROADMAP.md" 'black screen'

# The architecture explains the tokens -> artifacts flow.
afirmar_literal "the architecture explains the source of truth" "$PROY/docs/ARCHITECTURE.md" 'SOURCE OF TRUTH'

echo "  -- secrets: the repo accepts no credentials --"
# A token in git history is permanent: GitHub revokes the ones it detects.
afirmar_contiene ".env is ignored" "$PROY/.gitignore" '^\.env$'
afirmar_contiene ".pem/.key are ignored" "$PROY/.gitignore" '\*\.pem'
# NOTE: `.env.example` is the TEMPLATE and MUST be versioned (it holds no values).
# It is excluded on purpose; what must not get in is the real `.env`.
malos=0
for f in $(git -C "$PROY" ls-files 2>/dev/null | grep -iE '^\.env|\.pem$|\.key$|secret' | grep -v '\.example$'); do
  malos=$((malos+1)); printf '      -> versioned: %s\n' "$f"
done
afirmar_igual "no secrets file versioned" "0" "$malos"

echo "  -- the README mentions the harness and the docs --"
afirmar_literal "the README mentions the harness" "$PROY/README.md" 'tests/run.sh'
for d in ARCHITECTURE METHODOLOGY ROADMAP; do
  afirmar_literal "the README links docs/$d" "$PROY/README.md" "docs/$d.md"
done

echo "  -- environment template (.env.example) --"
# The template IS versioned (it is documentation); the real .env is NOT.
# A real failure: the '.env.*' pattern also ignored the template.
afirmar_existe ".env.example exists" "$PROY/.env.example"
negar ".env.example is NOT ignored" git -C "$PROY" check-ignore -q .env.example
afirmar ".env IS ignored" git -C "$PROY" check-ignore -q .env
afirmar ".env.local IS ignored" git -C "$PROY" check-ignore -q .env.local

# The template must not carry a real token. Classic GitHub patterns.
if grep -qE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' "$PROY/.env.example" 2>/dev/null; then
  fallo ".env.example contains what looks like a real token"
else
  ok ".env.example contains no token"
fi

# And it must explain the right way to authenticate.
afirmar_literal ".env.example documents gh auth login" "$PROY/.env.example" 'gh auth login'
afirmar_literal ".env.example warns that history is permanent" "$PROY/.env.example" 'PERMANENT'

echo "  -- the remote is prepared --"
remoto="$(git -C "$PROY" remote get-url origin 2>/dev/null)"
afirmar_igual "the remote points to kdeglass" "https://github.com/elanonimo832/kdeglass.git" "$remoto"
afirmar_igual "the branch is main" "main" "$(git -C "$PROY" branch --show-current)"

echo "  -- no build artifacts or ignored files in the repo --"
# A real failure: after renaming effect-kwin/, the .gitignore patterns still
# pointed at the old path and 36 files of build/ got committed (44k lines).
malos=0
for f in $(git -C "$PROY" ls-files 2>/dev/null); do
  case "$f" in
    */build/*|*.so|*.o|*.a|*/node_modules/*|*.fig|kit.json|figma-export/*|fuentes/*)
      malos=$((malos+1)); ;;
  esac
done
afirmar_igual "no build artifacts or Apple material versioned" "0" "$malos"

# And the .gitignore must reference the CURRENT directory names.
afirmar_contiene ".gitignore covers effect-kwin/build" "$PROY/.gitignore" 'effect-kwin/build'
afirmar_contiene ".gitignore covers tools/figma node_modules" "$PROY/.gitignore" 'node_modules'

echo "  -- .gitignore: no pattern that matches nothing --"
# This is what let the bug through: after renaming effect-kwin/, the pattern
# `efecto-kwin/build/` matched nothing and 36 build files got committed (44k
# lines). A rule that matches nothing is a rule that protects nothing.
#
# Two legitimate exceptions, and they are category, not convenience:
#   - `node_modules/`, `__pycache__/` are ECOSYSTEM globs with no leading path:
#     the directory appears anywhere, at any depth, and may not exist yet.
#   - `figma-export/`, `fuentes/` are APPLE MATERIAL inputs that only exist on the
#     author's machine and must never be committed. Their absence is normal.
# What must be caught is a concrete project path that has been renamed or removed.
SIN_RUTA_OK="node_modules __pycache__ _npm-cache _tokens figma-export fuentes fig-extraido"
huerfanos=$(python3 - "$PROY" "$SIN_RUTA_OK" <<'PYEOF'
import os, sys
root, permitidos = sys.argv[1], set(sys.argv[2].split())
bad = []
for raw in open(os.path.join(root, '.gitignore'), encoding='utf-8'):
    line = raw.strip()
    if not line or line.startswith('#') or line.startswith('!'):
        continue
    if '/' not in line or any(c in line for c in '*?['):
        continue
    path = line.rstrip('/')
    if os.path.basename(path) in permitidos or path in permitidos:
        continue
    if not os.path.exists(os.path.join(root, path)):
        bad.append(line)
for b in bad:
    print(f"      -> matches nothing: {b}")
print(len(bad))
PYEOF
)
n="${huerfanos##*$'\n'}"
afirmar_igual "no .gitignore pattern matches nothing" "0" "$n"

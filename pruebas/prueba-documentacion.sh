# La documentación no puede contradecirse: eso fue un problema real.
echo "  -- el incidente tiene un resumen autoritativo --"
# El documento acumuló 4 conclusiones de 2 sesiones. Quien lo lea debe saber
# cual es la buena SIN tener que leerlo entero.
afirmar_existe "existe INCIDENTE.md" "$PROY/INCIDENTE.md"
afirmar_contiene "avisa de que es historico" "$PROY/INCIDENTE.md" 'SUPERADAS|HISTÓRICO|HISTORICO'
afirmar_contiene "nombra la causa final" "$PROY/INCIDENTE.md" 'IDENTIFICADOR'
afirmar_contiene "menciona macosglass2" "$PROY/INCIDENTE.md" 'macosglass2'

echo "  -- SALIDA.md apunta a la correccion --"
afirmar_contiene "SALIDA.md corrige sus conclusiones" "$PROY/SALIDA.md" 'CORRECCIÓN FINAL|CORRECCION FINAL'

echo "  -- el efecto tiene README --"
afirmar_existe "existe efecto-kwin/README.md" "$PROY/efecto-kwin/README.md"
afirmar_literal "el README explica la ruta correcta" "$PROY/efecto-kwin/README.md" 'kwin/effects/plugins'
afirmar_literal "el README explica la cadena de pintado" "$PROY/efecto-kwin/README.md" 'effects->paintWindow'
afirmar_literal "el README explica el id actual" "$PROY/efecto-kwin/README.md" 'macosglass2'
afirmar_literal "el README explica que falta el shader" "$PROY/efecto-kwin/README.md" 'shader'

echo "  -- los enlaces del README no estan rotos --"
malos=0
for md in "$PROY"/*.md "$PROY"/efecto-kwin/README.md; do
  [ -f "$md" ] || continue
  d="$(dirname "$md")"
  while read -r enlace; do
    [ -z "$enlace" ] && continue
    case "$enlace" in http*|\#*) continue;; esac
    [ -e "$d/$enlace" ] || { malos=$((malos+1)); printf '      -> %s: %s\n' "$(basename "$md")" "$enlace"; }
  done < <(grep -oE '\]\([A-Za-z0-9._/-]+\.(md|sh|py|js|toml|colors|css)\)' "$md" 2>/dev/null | sed 's/^](//;s/)$//')
done
afirmar_igual "ningun enlace roto en la documentacion" "0" "$malos"

echo "  -- el manual de recuperacion esta --"
afirmar_existe "existe RECUPERAR-KDE.sh" "$PROY/RECUPERAR-KDE.sh"
afirmar_contiene "tiene el comando reanimar" "$PROY/RECUPERAR-KDE.sh" 'reanimar'

echo "  -- documentacion de proceso (docs/) --"
for d in ARQUITECTURA METODOLOGIA ROADMAP; do
  afirmar_existe "existe docs/$d.md" "$PROY/docs/$d.md"
done

# La metodologia tiene que recoger las lecciones que costaron horas.
afirmar_literal "la metodologia incluye 'medir antes de razonar'" "$PROY/docs/METODOLOGIA.md" 'Medir antes de razonar'
afirmar_literal "la metodologia incluye el caso minimo" "$PROY/docs/METODOLOGIA.md" 'caso mínimo'
afirmar_literal "la metodologia exige ver fallar la prueba" "$PROY/docs/METODOLOGIA.md" 'verla fallar'
afirmar_literal "la metodologia prohibe --replace" "$PROY/docs/METODOLOGIA.md" 'kwin_wayland --replace'

# El roadmap tiene que decir que el shader es lo siguiente y con criterio de hecho.
afirmar_literal "el roadmap marca el shader como siguiente" "$PROY/docs/ROADMAP.md" 'el siguiente'
afirmar_literal "el roadmap tiene criterio de hecho" "$PROY/docs/ROADMAP.md" 'Hecho cuando'
afirmar_literal "el roadmap reconoce el riesgo de OpenGL" "$PROY/docs/ROADMAP.md" 'pantalla negra'

# La arquitectura explica el flujo tokens -> artefactos.
afirmar_literal "la arquitectura explica la fuente de verdad" "$PROY/docs/ARQUITECTURA.md" 'FUENTE DE VERDAD'

echo "  -- secretos: el repo no admite credenciales --"
# Un token en el historial de git es permanente: GitHub revoca los que detecta.
afirmar_contiene ".env esta ignorado" "$PROY/.gitignore" '^\.env$'
afirmar_contiene "los .pem/.key estan ignorados" "$PROY/.gitignore" '\*\.pem'
# OJO: `.env.example` es la PLANTILLA y SI debe versionarse (no lleva valores).
# Se excluye a proposito; lo que no puede entrar es el `.env` real.
malos=0
for f in $(git -C "$PROY" ls-files 2>/dev/null | grep -iE '^\.env|\.pem$|\.key$|secret' | grep -v '\.example$'); do
  malos=$((malos+1)); printf '      -> versionado: %s\n' "$f"
done
afirmar_igual "ningun fichero de secretos versionado" "0" "$malos"

echo "  -- el README menciona el arnes y los docs --"
afirmar_literal "el README menciona el arnes" "$PROY/README.md" 'pruebas/ejecutar.sh'
for d in ARQUITECTURA METODOLOGIA ROADMAP; do
  afirmar_literal "el README enlaza docs/$d" "$PROY/README.md" "docs/$d.md"
done

echo "  -- plantilla de entorno (.env.example) --"
# La plantilla SI se versiona (es documentacion); el .env real NO.
# Un fallo real: el patron '.env.*' ignoraba tambien la plantilla.
afirmar_existe "existe .env.example" "$PROY/.env.example"
negar ".env.example NO esta ignorado" git -C "$PROY" check-ignore -q .env.example
afirmar ".env SI esta ignorado" git -C "$PROY" check-ignore -q .env
afirmar ".env.local SI esta ignorado" git -C "$PROY" check-ignore -q .env.local

# La plantilla no puede llevar un token de verdad. Patrones de GitHub clasicos.
afirmar_existe ".env.example sin tokens reales" "$PROY/.env.example"
if grep -qE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}' "$PROY/.env.example" 2>/dev/null; then
  fallo ".env.example contiene algo que parece un token real"
else
  ok ".env.example no contiene ningun token"
fi

# Y tiene que explicar la forma correcta de autenticar.
afirmar_literal ".env.example documenta gh auth login" "$PROY/.env.example" 'gh auth login'
afirmar_literal ".env.example avisa de que el historial es permanente" "$PROY/.env.example" 'PERMANENTE'

echo "  -- el remoto esta preparado --"
remoto="$(git -C "$PROY" remote get-url origin 2>/dev/null)"
afirmar_igual "el remoto apunta a kdeglass" "https://github.com/elanonimo832/kdeglass.git" "$remoto"
afirmar_igual "la rama es main" "main" "$(git -C "$PROY" branch --show-current)"

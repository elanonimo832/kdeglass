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

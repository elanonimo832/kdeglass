# Tokens de referencia — NO aplicar al tema de macOS

Estas colecciones salieron en el mismo export de Figma, pero **no son de Apple**.
Se conservan para consulta; aplicarlas al escritorio daría un resultado incoherente.

| Fichero | Sistema | Por qué no |
|---|---|---|
| `tokens-m3.toml` | Material 3 (Google) | Es el sistema de Material. El `Primary` es `#6750A4` (violeta), no el azul de Apple |
| `tokens-typescale.toml` | Material 3 | Escala tipográfica M3 (Display/Headline/Title/Label/Body), no la de macOS |
| `tokens-typography_primitives.toml` | Material 3 | Pesos y familias (`Roboto`, `Roboto Mono`) de Material |
| `tokens-shape.toml` | Material 3 (probable) | `Corner/Extra-small 4 · Small 8 · Medium 12 · Large 28`, que es la escala de forma de M3 |
| `tokens-color.toml` | Salesforce (SDS) | Tokens `Utilities/Scrim`, `Blanket`, `Border` del sistema de Salesforce |
| `tokens-color_primitives.toml` | Escala genérica | Paleta 100-1000 sin relación con Apple |
| `tokens-dimensions.toml` | Apple iOS | Radios de hoja, barra de estado, indicador de inicio: es iPhone/iPad |
| `tokens-dynamic_type.toml` | Apple iOS | El `Body` de iOS es 17 pt; el de macOS es 13 pt |
| `tokens-text_leading.toml` | Apple iOS | Interlineados de iOS. Sirven como **proporción**, no como valor |
| `tokens-font_theme.toml` | genérico | Fuente `Roboto`: es de otro sistema |
| `tokens-typography.toml` | genérico | Referencias a la escala de Material 3 |
| `tokens-context.toml`, `tokens-icons.toml` | — | Solo contienen el nombre del contexto, sin valores |

**Cómo se ha decidido:** no por el nombre del ZIP, sino por **marcas encontradas en los
propios tokens** (ver `herramientas/figma/tokens-desde-figma.py`, clasificador). Cada
fichero lleva su verdicto en `[_meta] > sistema` y `aplicable_macos`.

Para regenerar solo lo aplicable:

```bash
python3 herramientas/figma/tokens-desde-figma.py tokens --solo-macos figma-export/*.zip
```

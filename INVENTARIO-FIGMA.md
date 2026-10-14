# Inventario de los exports de Figma

Qué se ha recibido, qué se ha extraído y **qué falta**. Con los avisos de procedencia,
que aquí resultaron ser lo más importante.

- Procedencia y método: [REFERENCIAS-DISENO.md](REFERENCIAS-DISENO.md)
- Herramienta: [herramientas/figma/](herramientas/figma/)
- Fecha del export: 13/10/2026

## Resultado

```
16 colecciones recibidas   ·   629 tokens convertidos   ·   16/16 TOML válidos

  APLICABLES A macOS ....  146 tokens en  3 colecciones  ->  tokens/
  DE OTROS SISTEMAS .....  483 tokens en 13 colecciones  ->  tokens/referencia/
```

---

## 1. AVISO PRINCIPAL: el fichero es multi-sistema de diseño

El fichero de Figma del que salieron estos exports **no contiene solo las variables de
macOS**. Contiene también colecciones de **Material 3 (Google)**, de **Salesforce (SDS)**
y una escala de color genérica. Extraer todo y aplicarlo habría metido en el tema de
macOS colores y métricas que no son de Apple — un error silencioso y difícil de detectar
después.

Pruebas concretas:

| Señal | Qué significa |
|---|---|
| `Schemes/Primary = #6750A4` | Ese violeta es el **Primary de Material 3** por defecto. Apple no usa eso |
| `Static/Display Large 57 / Line Height 64` | La escala tipográfica de Material 3 |
| `Corner/Extra-small 4 · Small 8 · Medium 12 · Large 28` | La escala de forma de Material 3 |
| `Family Sans = Inter`, `Family Mono = Roboto Mono` | Familias de otro sistema |
| `Background/Utilities/Scrim`, `Blanket` | Nomenclatura de **Salesforce Lightning Design System** |

Por eso el conversor **clasifica la procedencia a partir de los propios datos**, no del
nombre del fichero: cada TOML generado lleva en `[_meta]` su `sistema` y su
`aplicable_macos`. Las 13 colecciones ajenas están en
[`tokens/referencia/`](tokens/referencia/LEEME.md), con el motivo de cada una.

---

## 2. Colecciones aplicables a macOS (146 tokens)

| ZIP | Modos | Tokens | Contenido |
|---|---|---|---|
| `Colors.zip` | Light, Dark | 63 | Acentos, rellenos, etiquetas, grises, misceláneos |
| `Kit.zip` | Mode 1 | 18 | Rellenos/bordes de componente + **material Liquid Glass** |
| `Sizes.zip` | Mini→XL | 65 | **Métricas de todos los controles** |

Estas tres son el núcleo del tema, y entre las tres cubren **color completo en claro y
oscuro** y **métricas de control**. Es justo lo que faltaba en el brief.

---

## 3. El material Liquid Glass, como números

`Kit.zip` trae el material del brief parametrizado:

```
[kit.liquid_glass]
light_angle             = 0
opacity                 = 25
refraction              = 70
depth_regular           = 30
depth_medium_and_large  = 30
dispersion              = 20
frost_regular           = 6
frost_medium            = 16
frost_large             = 16
splay_regular           = 20
splay_medium_and_large  = 20
```

Esto **corrige el brief**. El brief describía el material con tres conceptos («difusión,
borde oscurecido, reflejos especulares»). El kit declara **siete parámetros**, y dos de
ellos no aparecen en el brief en absoluto:

- **`refraction` (70)** — el material *desvía* lo que hay detrás, no solo lo difumina. Es
  la diferencia entre cristal esmerilado y vidrio.
- **`dispersion` (20)** — separación cromática en los bordes. Es lo que da sensación de
  grosor físico y lo que impide que el Liquid Glass parezca un blur corriente.
- **`frost` con dos valores** (6 en Regular, 16 en Medium/Large) y `splay` aparte: el
  material **no es el mismo en todos los tamaños de control**. Son dos ejes de difusión
  distintos, no un único «deslizador de translucidez» como decía el brief.

**Consecuencia de arquitectura:** el efecto KWin necesitará el **tamaño del control** para
elegir parámetros. No es un valor único. El modelo del brief es más pobre que el real;
ahora hay números, y un shader con siete parámetros sigue siendo un shader.

---

## 4. Las métricas de control (Sizes)

Resuelve el agujero de forma del brief, y confirma la corrección que señalé: **no hay un
radio único, escala con el tamaño del control**.

```
[global]     font_size = 13 (Mini 11) · height = 24
             radius = Mini 4 · Small 5 · Medium 6 · Large 7 · XL 9
[button]     padding_horizontal = Mini 7 · Small 10 · Medium 16 · Large 16 · XL 16
             radius = Medium 6 · Large 1000 · XL 1000
[checkbox]   radius = Mini 3.5 · Small 4.5 · Medium 5.5 · Large 6.5
[radio]      width  = Mini 12 · Small 14 · Medium 16 · Large 18
[toggle]     track_width = Mini 36 · Small 44 · Medium 54 · Large 64 · XL 80
             knob_width  = 32 (Medium), 50 al pulsar
[segmented]  margins 10 · separator_height 14
[fields]     inset 8 · font_size 13
[menu]       height 24 · font_size 13
[slider]     knob 20×16 (25×20 al pulsar) · track_inset 1
[stepper]    width 20 · radius 6
```

**`Button/Radius = 1000` en Large y XL** es la forma que tiene Figma de decir «píldora»
(radio = altura/2). El botón de macOS **cambia de rectangular redondeado a píldora según
el tamaño**: un `tokens.toml` con un solo radio de botón sería incorrecto.

**Y verifican los valores provisionales** de [REFERENCIAS-DISENO.md](REFERENCIAS-DISENO.md) §4:
`Global/Radius` Medium = **6**, exactamente lo citado desde la especificación de la
comunidad. La cadena queda confirmada de punta a punta.

Los alias (`Button/Radius = {Global.Radius}`) están **resueltos** en el TOML, anotando el
destino original en la línea anterior para poder auditar la cadena.

---

## 5. Lo recibido que NO es aplicable, y por qué

| ZIP | Sistema | Motivo |
|---|---|---|
| `M3.zip` | Material 3 | El sistema de Google completo (196 tokens, 6 variantes de contraste) |
| `Typescale.zip` | Material 3 | Escala Display/Headline/Title/Label/Body |
| `Typography Primitives.zip` | Material 3 | Pesos 100-900, familias `Inter`/`Roboto Mono` |
| `Shape.zip` | Material 3 | `Corner/None 0 · XS 4 · S 8 · M 12 · L 16 · XL 28 · Full 1000` |
| `Color.zip` | Salesforce (SDS) | `Utilities/Scrim`, `Blanket`, `Border` |
| `Color Primitives.zip` | Escala genérica | Paleta 100-1000 |
| `Dimensions.zip` | **Apple iOS** | Radios de hoja, barra de estado, indicador de inicio |
| `Dynamic Type.zip` | **Apple iOS** | El `Body` de iOS es 17 pt; el de macOS es **13 pt** |
| `Text Leading.zip` | **Apple iOS** | Interlineados de iOS |
| `Font theme.zip` | genérico | Fuente `Roboto` |
| `Typography.zip` | genérico | Referencias a la escala de Material 3 |
| `Context.zip`, `Icons.zip` | — | Solo el nombre del contexto, sin valores |

**El error que esto evita:** `Dynamic Type` trae una escala tipográfica atractiva y
completa (12 tamaños, con variantes de accesibilidad). Aplicarla al escritorio sería el
fallo más fácil de cometer de todo el proyecto, porque *parece* exactamente lo que falta.
Pero es la escala de **iOS**: en macOS el texto de control es de **13 pt**, no de 17.

**Lo único aprovechable de `Text Leading`:** la *relación* interlineado/tamaño. En
`Large (Default)`: Body 17/22 = **1.29**, Footnote 13/18 = 1.38, Caption 1 12/16 = 1.33.
Eso permite parametrizar el token `interlineado_escala` que propuse en
[INSTALACION.md](INSTALACION.md) §9 — ahora con una proporción medida, no inventada.

---

## 6. Qué falta todavía

| Falta | Por qué | Cómo se obtiene |
|---|---|---|
| ~~**Escala tipográfica de macOS**~~ | **RESUELTO por otra vía**: las HIG oficiales la publican completa | [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml) |
| **Tamaño de fuente por control** | **RESUELTO** igual: los 11 estilos de macOS incluyen el tracking | Igual que el anterior |
| **Radios de ventana, hoja y popover de macOS** | `Dimensions` es iOS; `Shape` es Material 3 | El `.fig`, en las propiedades de los nodos |
| **Geometría del squircle de icono** | No es una variable, es un trazado | El `.fig`, o el App Icon Template oficial |
| **Efectos: sombras y bordes capilares** | Son propiedades de nodo | El `.fig` |
| **Espaciados de layout** | Principalmente en nodos | El `.fig` |

Ninguno de los exports resuelve la tipografía de macOS — pero **ya no hace falta que lo
haga**: las Human Interface Guidelines oficiales publican la tabla completa de «macOS
built-in text styles», con tamaños, interlineados, pesos y tracking. Está extraída en
[`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml), y confirma
el `Sizes/Global/Font Size = 13` del export. **Hace falta el `.fig` completo** (`File → Save local copy`, solo en la app de
escritorio). El decodificador ya está escrito y validado para eso:
[herramientas/figma/README.md](herramientas/figma/README.md).

---

## 7. Reproducir

```bash
cd herramientas/figma
npm install
# todo, clasificado por procedencia
python3 tokens-desde-figma.py ../../tokens ../../figma-export/*.zip
# solo lo aplicable a macOS
python3 tokens-desde-figma.py ../../tokens --solo-macos ../../figma-export/*.zip
```

# Extracción de valores desde un kit de Figma

Herramienta que convierte un kit de Figma (`.fig`) en JSON con los **valores reales**
del diseño: radios, colores, alfas, tamaños de texto. Es el paso que llena
`tokens.toml` con datos en lugar de impresiones.

- Contexto: [../../DESIGN-REFERENCES.md](../../DESIGN-REFERENCES.md)
- Estado: **el decodificador está escrito y validado con un `.fig` de prueba. Falta
  probarlo contra un kit real.**

## Resultado con el export real (Colors.zip)

`Colors.zip` (export de Variables de Figma) contiene `Light.tokens.json` y
`Dark.tokens.json`: **61 tokens de color en cada modo, con hex y alfa exactos**. Se han
convertido a `tokens-color.toml` (61/61, sin pérdidas) con `tokens-from-figma.py`.

Lo que cubre y lo que no:

| | |
|---|---|
| **Cubre** | Todos los colores, en claro y oscuro: acentos, rellenos, etiquetas, grises y misceláneos |
| **No cubre** | Radios, tamaños de texto, interlineado, espaciados. **No son variables en el kit**: viven en las propiedades de los nodos, así que una exportación de Variables no puede verlos |

De ahí que siga haciendo falta el `.fig` completo (`File → Save local copy`, solo en la
app de escritorio).

## Estado de verificación (honesto)

| Parte | Estado |
|---|---|
| Localizar el payload Kiwi dentro del ZIP | **Verificado** |
| Leer el contenedor (versión + longitudes de chunk) | **Verificado** |
| Descomprimir el esquema (deflate crudo y zlib envuelto) | **Verificado** |
| Decodificar el esquema Kiwi | **Verificado** |
| Descomprimir el chunk de datos zstd (bloques en crudo) | **Verificado** |
| Decodificar el documento Kiwi a JSON | **Verificado** |
| Conversión del export de Variables a TOML | **Verificado** con `Colors.zip`: 61/61 tokens |
| **Contra un `.fig` real** | **FUNCIONA**: `macOS 27 (Community).fig`, 80 MB, esquema v106, 19.011 nodos, 168 MB de JSON |

El round-trip se validó generando un `.fig` con un esquema Kiwi real y datos Kiwi
reales, y comprobando que los valores vuelven intactos:

```
radios 10/6            -> recuperados
alfa 0.85              -> 0.8500000238  (float32 exacto)
color azul (0, 0.568, 1) -> recuperado
```

> Nota de precisión: los `float` de Kiwi son de 32 bits, así que `0.85` se lee como
> `0.8500000238418579`. Es correcto, no un error. Al generar `tokens.toml` hay que
> redondear.

## Tres trampas que cuesta descubrir (todas resueltas)

Probar el decodificador con un `.fig` sintético **no vale**: el sintético lo construyes
tú y acaba confirmando tus propias suposiciones. Estas tres solo aparecieron con el
fichero real de 80 MB.

**1. El chunk de datos ya es un frame zstd completo.** Mi versión inicial asumía
`[uint32 tamaño][bloques]` y reinsertaba el número mágico. En un `.fig` real el chunk
**empieza** por el mágico (`28 B5 2F FD`) y trae su propia cabecera de trama, que varía:
en el kit real son **13 bytes** (descriptor `0x80`, con tamaño de contenido de 4 bytes y
ventana). Reinsertar el mágico corrompe todo.

**2. `fzstd` falla EN SILENCIO con ventanas grandes.** Con el descriptor `0x80` devolvía
14,7 MB de basura **sin lanzar error**, y el fallo aparecía mucho después, como
`Invalid type -8` del decodificador Kiwi. Eso despista por completo: parece un problema
de esquema cuando es de compresión. **El CLI de `zstd` va primero**; `fzstd` solo como
último recurso.

**3. El salto de versión de Kiwi.** `kiwi-schema@0.4.7` **no** entiende el esquema de
Figma v106 (`Invalid type -8`). **`kiwi-schema@0.5.0` sí**: 653 tipos definidos. Es el
paquete correcto y hay que fijarlo.

Y dos trampas menores: el esquema va en **deflate crudo** (y `pako.inflate()` devuelve el
buffer de entrada en vez de fallar, así que hay que comprobar el resultado, no confiar en
que no haya excepción), y el documento trae **BigInt**, que `JSON.stringify` no sabe
serializar.

## Cómo se usa

```bash
cd tools/figma
npm install                     # pako, kiwi-schema, fzstd
node decode-figma.js kit.fig kit.json
```

## Formato que entiende (y por qué el detalle importa)

Un `.fig` es un ZIP con un payload binario **Kiwi autodescriptivo**:

```
[8]  "fig-kiwi"
[4]  version (uint32 LE)
[4]  longitud del chunk de esquema (uint32 LE)
[N]  esquema   -> deflate CRUDO (sin cabecera)
[4]  longitud del chunk de datos (uint32 LE)
[M]  datos     -> zstd SIN cabecera de trama
```

**El detalle que rompe cualquier implementación ingenua:** el chunk de datos no empieza
por el número mágico de zstd (`28 B5 2F FD`). Son **bloques zstd en crudo** precedidos
por el tamaño sin comprimir en 4 bytes little-endian. Para descomprimirlo hay que
reinsertar el mágico delante de los bloques. Sin eso, zstd responde:

```
Decoding error (36): Unsupported frame parameter
```

**Segundo detalle:** el esquema va en deflate **crudo**, no en zlib envuelto. Se
descomprime con `inflateRaw`. La herramienta prueba ambos, porque algunas versiones
envuelven el chunk con cabecera zlib.

**Tercer detalle:** el nombre del decodificador depende del **tipo raíz del esquema**.
No siempre se llama `decodeMessage`. La herramienta lo autodetecta entre los
`decode*` que exponga el módulo compilado.

## Dependencias y por qué estas

- **`kiwi-schema`** — decodifica el esquema y compila el documento. Es el decodificador
  real; el resto es transporte.
- **`pako`** — inflate/deflate para los chunks.
- **`kiwi-schema@0.5.0`** — versión mínima. La 0.4.7 no entiende el esquema v106 de Figma.
- **`fzstd`** — zstd en JS puro, solo como último recurso (ver trampa 2).
- **`fig-kiwi` queda descartado**: en npm solo está publicada la versión **0.0.1**, que
  solo entiende el pegado de portapapeles (deflate) y **no** lee `.fig` de disco (zstd).
  Su README documenta `readFigFile`, pero esa función no existe en el paquete publicado.

## Aviso legal

El kit de Figma es **material de Apple**. Esta herramienta extrae **números** y no
redistribuye recursos. El `.fig`, el JSON resultante y las capturas van **fuera del
repositorio público**: ver el `.gitignore` de esta carpeta y el §6 de
[../../ANALYSIS.md](../../ANALYSIS.md).

## Resultado sobre el kit real

```bash
node decode-figma.js "../../macOS 27 (Community).fig" ../../kit.json
# -> 168 MB de JSON, 19.011 nodos, 2.262 blobs

python3 extract-fig.py ../../kit.json ../../fig-extraido
# -> radios, squircle, efectos, trazos, textos y espaciados
```

Convirtió los 5 huecos que quedaban en `tokens/tokens-forma-efectos.toml`.

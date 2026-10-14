# Referencias de diseño: de dónde salen los números

Documento que responde a una pregunta concreta: **¿podemos empezar a definir el sistema
visual sin ver macOS 27?** Respuesta corta: **sí, y no hace falta que nadie lo vea. Lo que
hace falta son los números, y los números están publicados.**

- Documentos relacionados: [ANALISIS.md](ANALISIS.md) · [INSTALACION.md](INSTALACION.md) · [ANEXO-VERIFICACION.md](ANEXO-VERIFICACION.md)
- Fecha: 13/10/2025

---

## 1. La respuesta honesta sobre «ver» macOS 27

Conviene separar dos cosas que se confunden:

| | ¿Lo tengo? |
|---|---|
| **El lenguaje visual** de macOS (retención, bezel de 1 px, acento azul, vasos de material, escala tipográfica, jerarquía) | **Sí**, con detalle |
| **Los valores numéricos exactos de macOS 27 Golden Gate** (radios, alfas, colores, opacidades) | **No** — y **nadie** los tiene por memoria |

Y aquí está el punto que importa: **para este proyecto, la segunda fila es la única que
cuenta, y no requiere que yo vea nada.** Un QStyle no se construye mirando una foto: se
construye escribiendo `6` en un `Tokens.h`. El diseño *es* el número.

> Conclusión: no necesito ver macOS 27. Necesito que el repositorio **cite la fuente de
> cada número**, igual que cualquier otro dato del proyecto.

---

## 2. La fuente autorizada existe

Apple publica los kits de diseño oficiales. Verificado en
[developer.apple.com/design/resources](https://developer.apple.com/design/resources/):

| Recurso | Enlace |
|---|---|
| **macOS 27 UI Kit — Figma (oficial)** | https://www.figma.com/community/file/1651309434229735362/macos-27 |
| **macOS 27 UI Kit — Sketch (oficial)** | https://sketch.com/s/57153a31-3379-4737-8ac6-dbfd6525f052 |
| iOS/iPadOS 27 UI Kit | https://www.figma.com/community/file/1651309003795292092/ios-and-ipados-27 |
| Plantilla de iconos 27 (Figma/Sketch/PS/AI) | En el mismo índice |

Esto es exactamente lo que el proyecto necesita: **la fuente de verdad de Apple, con los
valores reales, publicada y citables.** Además, al ser el kit oficial, resuelve el aviso
legal: se extraen **números**, no se redistribuyen recursos de Apple.

**Riesgo conocido:** los kits se actualizan entre betas. Todo token extraído debe llevar
fecha de captura y versión (ya previsto en [ANALISIS.md](ANALISIS.md) §4.4).

---

## 3. Hallazgo que mejora el brief: hay tres «radios», no uno

Buscando material medible encontré una especificación de un kit de la comunidad para
macOS 27 que **contradice una simplificación del brief**. El brief dice:

```
VENTANAS ..... un radio de esquina UNICO para todas
ICONOS ....... squircle obligatorio, mas capas de vidrio
```

Correcto en intención, pero **mezcla tres métricas que en macOS son distintas**:

| Métrica | Qué es | Orden de magnitud |
|---|---|---|
| **Radio de control** | Botones, campos de texto, checkbox, combo | **Pequeño**: ~4 a 10 pt según tamaño del control |
| **Radio de ventana** | La esquina de la ventana entera | Otro valor, distinto del de control |
| **Squircle de icono** | La superelipse de los iconos de app | No es un radio: es una curva continua |

Y la consecuencia práctica, que es dinero: **si el `tokens.toml` tiene una sola clave
`radio`, el QStyle aplicará la misma a controles y ventanas y quedará mal.** El sistema de
tokens necesita tres familias de forma desde el día uno:

```toml
[forma.control]
radio_mini     = 4      # provisional
radio_pequeno  = 5      # provisional
radio_regular  = 6      # provisional  <- el control estándar (13 pt de texto)
radio_grande   = 8      # provisional

[forma.ventana]
radio          = ?      # PENDIENTE DE MEDIR en el kit oficial

[forma.icono]
superelipse    = true   # "squircle": curva continua, no radio circular
exponente      = ?      # PENDIENTE DE MEDIR
```

Los valores marcados como *provisionales* provienen de una medición de un kit **de la
comunidad**, no del oficial: sirven para arrancar, **no como especificación**. Ver §5.

### 3.1 La incoherencia de esquinas en Tahoe

El brief dice que Golden Gate unifica el radio de las ventanas. Hay evidencia
independiente de que en Tahoe (macOS 26) **las ventanas tenían radios distintos entre sí**
— es literalmente una de las quejas recogidas en un hilo de Hacker News titulado
[*«macOS Tahoe windows have different corner radiuses»*](https://hn.nuxt.dev/item/47279761).

Esto **refuerza** la tesis del brief: Golden Gate es la corrección, y la lista de
«correcciones» que el brief usa como lista de tokens tiene sentido. El brief acierta aquí
y ahora hay una fuente que lo respalda.

---

## 4. Valores medidos (VERIFICADOS contra tu propio export)

> **Actualización:** los valores de este apartado, que eran provisionales procedentes de
> un kit de la comunidad, han quedado **verificados** al recibir el export de Variables
> del kit: coinciden exactamente (azul oscuro `#0091FF`, acentos, y las escalas de alfa
> de `Fills` y `Labels`). Los valores definitivos, con claro y oscuro, están en
> [`tokens/tokens-colors.toml`](tokens/tokens-colors.toml) y el detalle en
> [`INVENTARIO-FIGMA.md`](INVENTARIO-FIGMA.md). El `#007AFF` clásico **no** aparece: el
> acento de macOS 27 es `#0088FF` en claro y `#0091FF` en oscuro.

Extraídos de [`macos.md` de Fluent-Qt](https://raw.githubusercontent.com/calvinhxx/Fluent-Qt/6f0ef75996f0b2fcba92fdd276eff61dc2a6b0f0/docs/design-languages/macos.md),
que documenta su método y los `nodeId` de Figma en
[`figma-sources.md`](https://raw.githubusercontent.com/calvinhxx/Fluent-Qt/6f0ef75996f0b2fcba92fdd276eff61dc2a6b0f0/docs/design-languages/figma-sources.md).
**Método reproducible y auditable**, que es lo valioso.

### Colores de acento

| Tinte | Opaco | Vibrante |
|---|---|---|
| **Azul** (acento por defecto) | `#0091FF` | `#0A99FF` |
| Verde | `#30D158` | `#3BDB63` |
| Rojo | `#FF4245` | `#FF4747` |
| Naranja | `#FF9230` | `#FF9E33` |
| Amarillo | `#FFD600` | `#FFE014` |
| Rosa | `#FF375F` | `#FF4169` |
| Mentagua | `#00DAC3` | `#2DE0CD` |
| Índigo | `#6D7CFF` | `#7163FF` |
| Púrpura | `#DB34F2` | `#E647FC` |
| Marrón | `#B78A66` | `#C29672` |
| Gris | `#98989F` | — |

### Etiquetas y rellenos: el patrón de «velo»

Apple no define grises para texto: define **blanco con alfa decreciente** (y negro sobre
claro). Este patrón es la clave arquitectónica del material:

| | Etiqueta | Relleno |
|---|---|---|
| Primario | `#FFFFFF` @ 85 % | `#FFFFFF` @ 10 % |
| Secundario | @ 55 % | @ 8 % |
| Terciario | @ 25 % | @ 5 % |
| Cuaternario | @ 10 % | @ 3 % |

Esto se traduce **directamente** a un QStyle y a CSS de GTK sin ambigüedad, y es más
importante que cualquier radio: es lo que hace que un control se vea «de macOS» en
cualquier fondo.

### Tipografía

- Fuente de sistema: **SF Pro** (Text/Display). **No redistribuible** → se sustituye por
  Inter u otra con métricas calibradas (§9 de [INSTALACION.md](INSTALACION.md)).
- Texto de control estándar: **13 pt**. (Confirmado por las HIG oficiales: macOS, por
  defecto 13 pt, mínimo 10 pt.)
- Escala: large title 26, title-1 22, **headline 13 en Bold** (no semibold), title-3 15,
  body 13, callout 12, subheadline 11, footnote y captions 10.

> **RESUELTO.** Este apartado quedó cerrado con las Human Interface Guidelines oficiales:
> la tabla completa de «macOS built-in text styles» y los valores de tracking están en
> [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml), extraídos
> de la fuente autorizada con `herramientas/figma/hig-tipografia.py`. Ver §8.
- **Color de texto por alfa**, no por valor absoluto (ver tabla del velo).

### Controles (formas y medidas mencionadas)

| Control | Medida |
|---|---|
| Checkbox | cuadrado ~14, radio ~3.5 |
| Radio button | círculo ~16 |
| Switch (pista) | píldora completa; **ON = acento azul, no verde** (diferencia con iOS) |
| Slider: pista | ~3–4 px |
| Slider: pulgar | círculo blanco ~16–20 |
| Barra de progreso | ~6 pt, totalmente redondeada |
| Anillo de progreso | ~3 pt |
| Campo de texto | radio ~5–6 + borde de 1 px; **foco = anillo de acento**, no borde más grueso |
| Semáforos de ventana | ~12 px: cierre `#FF5F57`, minimizar `#FFBD2E`, zoom `#28C840`; los glifos **solo al pasar el ratón**; inactiva = gris |

### Las dos reglas de oro del idioma macOS

1. **Retención, no espectáculo.** Relleno sutil + **borde capilar de 1 px** + sombra muy
   suave (el *bezel*). Nunca contornos gruesos ni radios grandes.
2. **El acento es el único color con voz.** El resto es neutro con velo. El texto sobre
   acento es **blanco**.

---

## 5. Advertencias sobre estos valores (importante)

1. **La fuente no es Apple.** Son mediciones de un kit de la **comunidad** de Figma. La
   verificación de §2 reveló que el **kit oficial de macOS 27 tiene otro `fileKey`**
   (`1651309434229735362`) distinto del que midió ese proyecto. Por tanto estos valores
   pueden corresponder a una revisión distinta del kit. **Tratar como provisionales.**
2. **Se capturaron en apariencia oscura.** El método de extracción resuelve **una sola
   apariencia** por consulta; los alfas de las etiquetas y los rellenos de arriba son de
   **modo oscuro**. El claro debe extraerse por separado.
3. **La tipografía tiene un punto de duda útil**: en la misma página se dice que el texto
   de control es «13 pt» y, un poco antes, que en macOS el cuerpo es «13» en un contexto
   donde el 13 aparece junto a un interlineado. **El tamaño va a estar bien; el
   interlineado es lo que hay que confirmar** — y es justo el token que el brief no tenía.
4. **El azul `#0091FF` no coincide con el `systemBlue` clásico** (`#007AFF` claro /
   `#0A84FF` oscuro). Puede ser el refresco de la beta 27 o el efecto de la apariencia
   oscura. No fijar el acento sin comprobarlo en el kit oficial.

---

## 6. Dos caminos para obtener los números buenos

### Camino A · El kit oficial de Figma (recomendado)

El kit oficial es un fichero **público y gratuito** de la comunidad de Figma. Con una
cuenta gratuita se puede:

1. Abrir el kit: https://www.figma.com/community/file/1651309434229735362/macos-27
2. «Duplicate» a un borrador propio (gratis, sin equipo de pago).
3. Exportar los valores. El camino más productivo encontrado en la investigación es
   **extraer las variables del fichero** en lugar de leerlas a ojo — así el resultado es
   una tabla, no una impresión.

Salida esperada: un `tokens-captura-<fecha>.toml` con **valores y procedencia**, listo para
ser la fuente de `tokens.toml`. Y como se extrae del kit oficial, queda cubierto el aviso
legal del brief: números sí, recursos de Apple no.

### Camino B · Medir capturas de pantalla (complementario, y automatizable)

Sirve para **verificar** lo del camino A y para capturar cosas que un kit no muestra: el
material real compuesto sobre un fondo real, el HDR, las animaciones.

**En este equipo ya están las herramientas** (verificado):

```
magick / convert / identify        -> ImageMagick, presente
python3 + PIL 12.3.0 + numpy 2.5.4 -> presente
spectacle                          -> presente (capturas en Wayland/KDE)
```

Lo que se puede medir automáticamente con eso:

| Token | Cómo se mide |
|---|---|
| Radio de esquina | Por canal alfa: recuento de píxeles transparentes en la esquina, ajuste a un cuarto de círculo |
| Colores exactos | Muestreo puntual y cálculo de histograma dominante |
| Alfa / translucidez del material | **Matemática de composición inversa**: con el mismo material sobre dos fondos conocidos, se despeja el alfa |
| Grosor del borde capilar | Perfil de intensidad en un corte transversal |
| Contraste / legibilidad | Cálculo de ratio de contraste WCAG (útil contra la crítica de Tahoe) |
| Espaciado | Detección de bordes y medición de separaciones entre controles |

**Requisito para que sirva:** capturas de **un solo píxel lógico por píxel físico**
(escala 1×). Con escala 2× hay que dividir, y ahí se pierden los valores impares.

En este equipo hay un monitor a **escala 1**, que es lo correcto para medir, pero **no hay
macOS**: las capturas tienen que venir de fuera.

### Lo que NO se puede medir de una captura

- El **HDR** (necesita metadatos y monitor compatible) — otra razón para dejarlo a v3.
- El **comportamiento**: animaciones, gestos, curvas de tiempo. Eso solo se describe.

---

## 7. Qué necesito, en concreto

Si eliges el **camino A**: nada mío. Tú o yo con una cuenta de Figma, extracción de
variables, y yo convierto la salida en `tokens.toml` con los tres ejes de forma y el eje
tipográfico.

Si eliges el **camino B**, necesito capturas con estos nombres. El nombre importa porque
el script de medición automatiza el procesamiento por lote:

```
capturas/
├── 01-ventana-activa-claro.png      <- esquina de ventana sobre fondo liso
├── 02-ventana-activa-oscuro.png
├── 03-ventana-inactiva-oscuro.png
├── 04-botones-claro.png             <- botón normal, prominente, deshabilitado
├── 05-botones-oscuro.png
├── 06-campo-texto-foco-oscuro.png   <- el anillo de foco
├── 07-controles-claro.png           <- checkbox, radio, switch ON/OFF, slider
├── 08-segmentado-oscuro.png
├── 09-menu-abierto-oscuro.png       <- el resalte de acento
├── 10-barralateral-oscuro.png       <- a ras, no flotante (token del brief)
├── 11-material-sobre-fondo-1.png    <- MISMO material sobre fondo claro
├── 12-material-sobre-fondo-2.png    <- MISMO material sobre fondo oscuro
│                                       (el par 11+12 permite despejar el alfa)
└── 13-iconos.png                    <- para medir el squircle
```

Reglas de captura: escala **1×**, PNG sin comprimir con pérdida, **una ventana por
captura** con fondo liso detrás, y las dos capturas de material (11 y 12) con **el mismo
contenido** detrás para que el despeje del alfa sea válido.

**Nota legal:** estas capturas son material de Apple. Van **fuera del repositorio
público** (ya previsto en [ANALISIS.md](ANALISIS.md) §6). El repositorio guarda los
**números** y el **script de medición**, no las imágenes.

---

## 8. Plan de arranque propuesto

> **Actualización:** los pasos 1 y 3 ya no son necesarios para la tipografía. Las HIG
> oficiales de Apple publican la tabla completa de estilos de macOS (tamaños, interlineados,
> pesos y tracking), así que el eje tipográfico está **cerrado sin medir capturas**. Ver
> [`tokens/tokens-tipografia_macos.toml`](tokens/tokens-tipografia_macos.toml).

```
PASO 1 · Obtener el kit oficial (camino A)         <- desbloquea todo lo demás
         y/o capturas 1x (camino B)

PASO 2 · tokens.toml con los TRES ejes de forma    <- corrige la mezcla de §3
         + eje tipográfico (familia, tamanos, interlineado, espaciado)
         + el patron de velo (blanco @ alfa) como base del material

PASO 3 · Script de medicion                        <- convierte capturas en TOML
         (probado con las capturas reales, no con ejemplos)

PASO 4 · Generador de esquemas + CSS GTK           <- entregable visible sin QStyle
         (paso 2 del plan de ANALISIS.md)

PASO 5 · Ya con numeros verificados: empezar el QStyle
```

El paso 3 es opcional si el camino A da todo lo necesario — y probablemente lo dé para
controles y colores. Se mantiene para el material y para verificar, porque **una captura
mide el resultado real**, mientras que un kit mide la intención de Apple.

---

## 9. Resumen

- **No hace falta que yo vea macOS 27.** Un QStyle se define con números, y los números
  son el diseño.
- **Apple publica el kit oficial de macOS 27** (Figma y Sketch). Esa es la fuente de
  verdad, es pública y es lo que resuelve el problema. Verificado hoy en el índice oficial
  de Apple Design Resources.
- **Los valores provisionales de §4 son utilizables pero de un kit de la comunidad**, con
  `fileKey` distinto del oficial. Sirven para arrancar el `tokens.toml`; no como
  especificación final.
- **El brief tiene una simplificación a corregir:** hay **tres** familias de forma
  (control, ventana, icono), no un radio único. Un solo `radio` en los tokens producirá un
  QStyle incorrecto.
- **Lo que sí sé con solidez es el lenguaje, no las cifras**: retención, bezel capilar de
  1 px, acento único, velo por alfa, escala tipográfica de 13 pt. Eso basta para diseñar
  la arquitectura de tokens; las cifras se extraen.

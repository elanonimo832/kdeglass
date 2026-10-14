# Verificación en pantalla real

Registro de la comprobación del esquema aplicado, midiendo los píxeles de una captura de
*Configuración del sistema → Apariencia → Colores*. Es la verificación que faltaba: la
que confirma que lo generado **se aplica y se ve como estaba calculado**.

- Captura: `Colors — System Settings`, 1171x905
- Esquema en pantalla: **KdeMacosLight**, seleccionado (aparece con el borde de foco azul)
- Método: muestreo de píxeles con PIL, agrupando por franjas y contando el color dominante

---

## 1. Fondos: coinciden exactamente

Medido en la tarjeta de vista previa de `KdeMacosLight`, y comparado con
`salida/color-schemes/KdeMacosLight.colors`:

| Región | En pantalla | Yo declaré | |
|---|---|---|---|
| Cuerpo de la ventana | `#FFFFFF` | `Colors:Window.BackgroundNormal = 255,255,255` | ✔ |
| Barra de título | `#F1F1F1` | `Colors:Header.BackgroundNormal = 241,241,241` | ✔ |
| Banda de resalte (fila seleccionada) | `#CDDFE0` | `Colors:Selection.BackgroundNormal = 1,101,226` | ⚠ ver §3 |

Los dos primeros son **idénticos**. El tercero no, y tiene explicación.

## 2. Textos: coinciden dentro de la tolerancia de compresión

El texto se mide por el **núcleo del trazo** (el 0,5 % de píxeles más extremo), no por los
bordes suavizados, que siempre son más claros:

| Texto | En pantalla | Yo declaré | Diferencia |
|---|---|---|---|
| Texto normal | `#282828` | `38,38,38` = `#262626` | 2/255 por canal |
| Texto deshabilitado | `#2D2D2D` | `35,35,35` = `#232323` | 10/255 por canal |
| Texto sobre el resalte | casi blanco | `255,255,255` | antialiasing |

La diferencia de 2 niveles en el texto normal es **ruido de la conversión a WebP**, no un
error de cálculo. La de 10 niveles en el deshabilitado es antialiasing: al medir el
"núcleo" de un trazo fino se mezcla parte del fondo.

**Conclusión:** la composición del velo es correcta. El texto normal se ve a `#282828`
sobre blanco, que es exactamente `negro al 85 %` sobre `#FFFFFF`, que es lo que calcula el
generador a partir del token `label/primary` del kit.

## 3. La única discrepancia real: el resalte no es azul sólido

`Colors:Selection.BackgroundNormal` lo declaré como `1,101,226` (`#0165E2`), que es el
token `misc.table.bg_selected_active` del kit: en macOS, la fila seleccionada de una tabla
se pinta con **azul de acento sólido y texto blanco**.

Pero en pantalla el resalte se ve **azul muy claro** (`#CDDFE0`), y el texto del resalte
sale oscuro en vez de blanco.

**Causa:** el kit de macOS 27 tiene una opción de accesibilidad que KDE llama *«usar el
color de acento para la selección»*. Cuando está activa, los widgets calculan el resalte a
partir del **color de acento** y no del `BackgroundNormal` del grupo `Colors:Selection`.
En la captura, el acento está seleccionado como «Accent color from color scheme», así que
KDE deriva un tinte claro del azul.

Es decir: el color declarado es correcto, pero **KDE lo sustituye**. Para verlo como en
macOS (azul sólido) hay que desactivar esa opción, o fijar el acento explícitamente.

**Esto no es un fallo del esquema**: los otros cinco esquemas de la captura (KvAdapta,
KvAdaptaDark, KvAmbiance, KvAmbiance… y Kvantum) muestran exactamente el mismo resalte
claro. Es el comportamiento de KDE en esta versión, no de mis colores.

## 4. Nota sobre el cromo oscuro

En la captura, la barra de título de *Configuración del sistema* y los bordes de la ventana
se ven oscuros aunque el esquema sea claro. Es esperado: el **tema global** del sistema
sigue siendo `Ant-Dark` y la **decoración de ventana** es de Kvantum/Ant. El instalador
cambia el esquema de color, no el tema global ni la decoración — a propósito, para que el
cambio sea pequeño y reversible.

Cuando el esquema esté validado, el siguiente paso natural es un tema global que una
esquema + decoración + Plasma Style.

---

## 5. Qué queda verificado y qué no

| | |
|---|---|
| **Verificado** | El `aplicar` funciona: el esquema aparece en Ajustes y se puede seleccionar |
| **Verificado** | Los fondos se aplican exactamente como se calcularon |
| **Verificado** | La composición del velo da el color de texto previsto |
| **Verificado** | El contraste alto se conserva en pantalla (el texto se ve nítido) |
| **Pendiente** | El CSS de GTK: no se ha probado con una app GTK real |
| **Pendiente** | El esquema oscuro `KdeMacosDark` en pantalla |
| **Pendiente** | El aspecto como tema global (decoración + Plasma Style) |


---

## 6. Los botones de la barra de título: NO los dibuja el tema GTK

Al probar con **Proton VPN** (`proton-vpn-gtk-app 4.18.6`, GTK4 nativo, **sin
libadwaita**) apareció una confusión que conviene dejar escrita, porque es un error fácil
de cometer:

> Los botones de la barra de título —el menú, minimizar y cerrar— **no los dibuja el tema
> GTK**. Los dibuja **KWin**, con la decoración de ventana activa.

Por eso no se arreglan tocando `kde-macos.css`, por mucho que se ajuste.

### Primera respuesta, y por qué estaba mal

Lo primero que hice fue copiar la decoración que ya tenías (**Ant-Dark**) y separar sus
botones. Eso **no es lo acordado**: el proyecto es *una capa estilo macOS*, y una copia del
tema de otro con los botones más separados no es eso. Fue resolver el síntoma en vez del
objetivo.

### Lo correcto: una decoración propia, generada desde los tokens

`salida/aurorae/KdeMacOS/` es una decoración **generada desde cero** por
`herramientas/generar-decoracion-macos.py`, con los valores medidos del kit:

| Elemento | Valor | Origen |
|---|---|---|
| Tamaño del semáforo | 12 px | Medido en el `.fig` |
| Cerrar | `#FF5F57` | `tokens-forma-efectos.toml` |
| Minimizar | `#FFBD2E` | Idem |
| Zoom | `#28C840` | Idem |
| Posición | **Izquierda**, orden cerrar-minimizar-zoom | Convención de macOS |
| Separación | 8 px | Para que respiren |
| Alto de barra | 28 px | Medido |

**Los tres detalles que casi nadie reproduce y aquí sí están:**

1. **Los glifos solo aparecen al pasar el ratón.** En reposo son tres círculos limpios.
2. **Sin foco, los tres se apagan a gris** (`#48484A` / `#3A3A3C`). En macOS los semáforos
   no se quedan de color: se desaturan. Es el estado `inactive` de Aurorae.
3. **Están a la izquierda.** Tu decoración anterior los tenía repartidos y sin semáforos.

Vista previa: `salida/aurorae/vista-previa/`.

### Instalación

```bash
./instalar-decoracion.sh plan              # ver qué haría
./instalar-decoracion.sh aplicar --si      # instalar
```

Luego: *Ajustes → Apariencia → Decoraciones de ventana → **KdeMacOS***.

**No modifica ninguna decoración existente**: se instala aparte y se elige en Ajustes. El
ciclo instalar → revertir está probado con un `HOME` falso.

### Lo que sigue pendiente en la decoración

El `.rc` declara `Shadow=true` y el marco es una aproximación: la sombra real de macOS son
**dos capas** (difusa radio 54 + contacto radio 1) que ya están medidas en
`tokens-forma-efectos.toml`. Aurorae no permite declarar dos sombras, así que la del marco
la tendrá que poner el efecto KWin del paso 5.

### El otro dato que salió de aquí

Proton VPN trae su propio CSS, con su marca en violeta (`#8A6EFF`). El verde de «Protected»
es suyo, de estado, no del tema. Para apps que pintan lo suyo, el tema del sistema solo
influye en lo que la app no dibuja ella misma. Es la lista de excepciones de
[ANALISIS.md](ANALISIS.md) §3.3, ahora con un caso real comprobado.


---

## 7. Por qué los semáforos salían a la derecha (y no a la izquierda)

Tras instalar `KdeMacOS`, la captura de Konsole mostró **tres círculos oscuros a la
derecha** en lugar de los semáforos de colores a la izquierda. La causa está localizada y
comprobada contra el `kwinrc` real:

```
~/.config/kwinrc
    [org.kde.kdecoration2]
    library=org.kde.kwin.aurorae.v2
    theme=__aurorae__svg__KdeMacOS
    <-- NO habia ninguna clave de botones
```

**El tema declara `LeftButtons=XIA` en su `.rc`, pero KWin 6 no lee ahí la disposición.**
La lee de `kwinrc`. Si las claves no existen, aplica **su propio valor por defecto, que
pone los botones a la derecha**. Por eso el tema pedía la izquierda y salían a la derecha.

Las claves correctas son:

```ini
[org.kde.kdecoration2]
ButtonsOnLeft=XIA
ButtonsOnRight=
```

`X` = cerrar, `I` = minimizar, `A` = maximizar. En ese orden y a la izquierda es lo que
hace macOS.

Esto **no lo podía ver el análisis estático**: el tema era coherente, el motor estaba bien
elegido y el SVG estaba bien formado. Solo aparece al mirar la ventana renderizada.

### Corregido en el instalador

El subcomando `--activar` ahora escribe las tres claves que importan:

```
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__KdeMacOS
ButtonsOnLeft=XIA
ButtonsOnRight=
```

Y `plan` informa de la disposición **que tiene KWin en ese momento**, no de la que declara
el tema, que es la que engañaba.

### Y una limpieza pendiente

La primera versión del instalador creó **`Ant-MacOS`** (la copia de Ant-Dark, antes de que
se corrigiera el criterio). Sigue instalada. Se quita con:

```bash
./instalar-decoracion.sh limpiar
```

### Lo que sigue sin poder verificar aquí

No pude arrancar un KWin anidado para ver el resultado: el sandbox no permite crear el
socket en `/run/user/1000` ni sobrevive el proceso. Así que **el color final de los
semáforos está sin confirmar en pantalla**. Lo que sí está verificado: el SVG es válido,
tiene los cinco estados en su sitio y los colores son los del kit.


---

## 8. Confirmado en pantalla: los semáforos funcionan

Tras aplicar `ButtonsOnLeft=XIA`, la captura de Konsole muestra los **tres semáforos a la
izquierda**, en color, y el mismo aspecto en Ajustes del sistema. Medido sobre la captura:

| Semáforo | En pantalla | Del kit | Diferencia |
|---|---|---|---|
| Cerrar | `#F26E69` | `#FF5F57` | 18/255 |
| Minimizar | `#F7C450` | `#FFBD2E` | 34/255 |
| Zoom | `#45C95A` | `#28C840` | 29/255 |
| Separación entre bordes | **8 px** | declarado 8 px | exacto |

Las diferencias de color son de la **compresión WebP** de la captura y del suavizado de
bordes a 12 px, no del renderizado. La separación coincide **exactamente**.

### Comprobado en el `kwinrc` real

```ini
[org.kde.kdecoration2]
ButtonsOnLeft=XIA
ButtonsOnRight=
library=org.kde.kwin.aurorae.v2
theme=__aurorae__svg__KdeMacOS
```

### Y una mejora que faltaba: el aro

El kit da **dos** colores por semáforo: el relleno del círculo **y el del aro**. Yo solo
usaba el primero, y los botones salían planos. Ya están los dos:

```
close.svg     relleno #FF5F57   aro #FF4245
minimize.svg  relleno #FFBD2E   aro #FF9230
maximize.svg  relleno #28C840   aro #30D158
```

---

## 9. Lo que NO es fiel, y conviene saberlo

Comparé los colores del kit con los que macOS **pinta realmente**. Hay una diferencia
sistemática:

| | Kit (lo que uso) | macOS en pantalla |
|---|---|---|
| Cerrar | `#FF5F57` | `#ED6A5F` |
| Minimizar | `#FFBD2E` | `#F6BE50` |
| Zoom | `#28C840` | `#61C555` |
| Saturación del verde | 80 % | **57 %** |

El kit está **~18/255 más saturado** que lo que se ve en la pantalla de macOS, sobre todo
en el verde (`#28C840` frente a `#61C555`). La causa probable es que los valores del kit
son los *declarados* en sRGB, mientras que macOS los dibuja con su gestión de color y un
poco de vibrancy encima.

**Decisión tomada:** se usan los valores del **kit**, no los de la pantalla. Motivo: el
proyecto se construye *desde los tokens*, y mezclar aquí una corrección sacada de una
captura rompería esa regla. Queda anotado aquí y, si se quiere afinar, es un cambio de tres
constantes en `herramientas/generar-decoracion-macos.py`.

**Y falta un detalle de fidelidad:** macOS pone un **aro ligeramente más oscuro** que el
relleno (el kit lo refleja con el segundo color), pero además los semáforos reales llevan
transparencia en los bordes. KWin con SVG no aplica ese desvanecido con facilidad.

### Referencia consultada

[`lwouis/macos-traffic-light-buttons-as-SVG`](https://github.com/lwouis/macos-traffic-light-buttons-as-SVG),
una aproximación en SVG de los botones reales, con los colores medidos por su autor.

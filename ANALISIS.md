# Análisis del brief: capa de escritorio «estilo macOS» para Linux

> Análisis crítico de [PROYECTO-KDE-MACOS.md](PROYECTO-KDE-MACOS.md).
> Fecha del análisis: 13 de octubre de 2025.
> Método: lectura del brief + verificación de cada supuesto técnico contra el estado
> actual de KDE Plasma 6, Qt 6, GTK4 y macOS 27 (ver [ANEXO-VERIFICACION.md](ANEXO-VERIFICACION.md)).

---

## 1. Veredicto en una página

**El diagnóstico del brief es correcto y el plan es ejecutable.** Las tres tesis
centrales se sostienen:

1. **Un tema repinta, no re-arquitectura.** Cierto. Un tema Plasma es QSS + SVG +
   esquemas de color: no puede cambiar métricas, hit-testing ni animaciones de
   control. Un QStyle sí. El brief identifica bien *dónde* está la frontera.
2. **El QStyle es el multiplicador de esfuerzo.** Cierto, y es la parte con más
   volumen mecánico y menos acoplamiento del proyecto — exactamente el perfil donde
   la asistencia por IA rinde más.
3. **La capa declarativa portable vale por sí sola.** Cierto, y es el único entregable
   cuyo valor no depende de que el resto del proyecto se termine. Es el orden correcto.

**Los problemas no están en la estrategia, están en cuatro supuestos operativos** que,
si no se corrigen antes de escribir código, producen trabajo que nadie ve:

| # | Supuesto del brief | Realidad | Coste de no corregirlo |
|---|---|---|---|
| A1 | «De los tokens se **generan** los tres» (QStyle incluido) | De los tokens se genera la *capa de apariencia*; el QStyle se **escribe** | Esperar un generador que no puede existir |
| A2 | Un QStyle propio «convierte un tema en el sistema» | En Plasma 6 **no hay selector de estilo por aplicación**; hay que forzar `QT_STYLE_OVERRIDE` por proceso | Construir un QStyle que la mayoría de apps nunca carga |
| A3 | «libdecor: la app cede el dibujo al compositor» | `libdecor` es una biblioteca **del cliente**; no obliga al servidor a decorar, y GTK4 no la usa | Esperar que GTK4 obedezca por una vía que no existe |
| A4 | «KWin recorta la ventana: se hace una vez» | El recorte de esquinas es viable (hay precedentes), pero no es gratis en apps con contenido en las esquinas | Prometer un efecto que se ve sucio en apps reales |

**Además hay tres omisiones que pesan más que cualquier decisión técnica:**

- **La tipografía.** El look de macOS es ~50 % tipografía y espaciado, ~30 % forma,
  ~20 % material. El brief dedica 11 líneas al material y **cero a la fuente**. Sin
  una fuente con métricas equivalentes y licencia compatible, el resultado no
  parecerá macOS aunque todos los tokens sean correctos.
- **El criterio de éxito.** No hay definición de «terminado» ni forma de medir avance.
- **Las pruebas de regresión visual.** En un proyecto puramente estético, esto no es
  un lujo: es el único test que tiene sentido y es automatizable con script.

**Recomendación:** mantener el plan, reordenar dos pasos, añadir el eje tipográfico y
la verificación visual como infraestructura del **paso 0**, y bajar el HDR a v3.

---

## 2. Lo que el brief acierta (y conviene no tocar)

- **Tokens primero.** Es la decisión arquitectónica que hace posibles las demás. Sin
  fuente única de verdad, QStyle, CSS GTK y KWin divergen en tres semanas.
- **No hacer fork de Plasma.** Correcto: un fork de Plasma es deuda de mantenimiento
  permanente y rompe con cada release. Un QStyle + efecto KWin son puntos de extensión
  **públicos y documentados**.
- **KWin para las esquinas, una vez, no por app.** Es el único punto del sistema donde
  se puede imponer forma a ventanas ajenas. El instinto es correcto — la *garantía* es
  lo que hay que matizar (A4).
- **NO usar `LD_PRELOAD`.** Correcto y hay que defenderlo. Es la solución que parece
  gratis y se rompe en cada actualización de GTK.
- **Aceptar que GTK4 no cede al 100 %.** El brief estima ~10 % irreducible. Es la
  actitud correcta; la cifra es optimista (§3.3).
- **Aviso legal y no usar marcas ni iconos de Apple.** Correcto y necesario.

---

## 3. Correcciones técnicas

### A1 · Lo que se genera y lo que se escribe

El brief dice: *«Un `tokens.json` … De ahí se GENERAN los tres»* (QStyle + CSS GTK +
KWin). Eso describe bien dos de los tres y mal el tercero.

| Salida | ¿Generable desde tokens? | Por qué |
|---|---|---|
| Esquemas de color (`.colors`) | **Sí, 100 %** | Transformación pura datos→datos |
| CSS de GTK | **Sí, ~85 %** | Salvo overrides por versión de GTK y apps concretas |
| Scripts/efectos KWin | **Parcial** | La *config* del efecto se genera; el efecto en C++/QML se escribe |
| Assets (máscaras squircle, SVGs) | **Sí, con parámetros** | Geometría determinista |
| **El QStyle (C++)** | **No** | Es dibujo imperativo acoplado a la API `QStyle` |

El QStyle no es un formato declarativo: es C++ que implementa `drawControl`,
`subControlRect`, `pixelMetric`, `sizeFromContents`, `hitTestComplexControl`, etc.
Lo que se puede generar de verdad es lo periférico y valioso:

- Un **`Tokens.h` generado** con las constantes, para que ningún número se escriba a mano.
- Un **manifiesto de cobertura**: la lista de *todas* las enumeraciones de QStyle
  (`QStyle::ControlElement`, `PrimitiveElement`, `SubControl`, `PixelMetric`,
  `StyleHint`, `ComplexControl`) con estado por elemento. Eso es lo que convierte
  «1–3 meses» en un plan medible en vez de una sensación.

**Corolario:** separa el proyecto en **generador** (herramienta terminada y testeable)
y **QStyle** (implementación incremental). Son dos ciclos de vida distintos y mezclarlos
es lo que hace fracasar este tipo de proyecto.

### A2 · El QStyle no se activa solo (el riesgo más subestimado)

> **Corrección posterior a este análisis.** El requisito señalado aquí es real, pero la
> solución que propongo en este apartado (`QT_STYLE_OVERRIDE`) resultó **innecesariamente
> complicada**. Al verificar el sistema se comprobó que Plasma 6 selecciona el estilo con
> **una sola clave en `kdeglobals`** (`[KDE] widgetStyle`), y este equipo ya lo
> demuestra: tiene `widgetStyle=kvantum` y `/usr/lib/qt6/plugins/styles/libkvantum.so`.
> Kvantum es un QStyle de terceros funcionando en el sistema, sin overrides por proceso.
> **El diseño correcto está en [`INSTALACION.md`](INSTALACION.md) §1.** Se conserva este
> apartado porque el diagnóstico —Plasma 6 no tiene selector de estilo por aplicación— es
> correcto y sigue siendo el punto que el brief ignoraba por completo.

En Plasma 6, *Configuración del sistema → Apariencia* selecciona el **tema global**
(QSS + decoración + colores + iconos). **No existe el selector de «estilo de widgets
por aplicación» que existía en Plasma 5.** Consecuencias:

- El estilo se selecciona en `kdeglobals` (`[KDE] widgetStyle`), que es **global**: no
  se puede aplicar el QStyle propio a unas apps y no a otras desde la interfaz.
- Existe un KCM (`kcm_style.so`) que escribe esa misma clave, y una propiedad
  `isWidgetStyleImmutable` que puede hacer que la clave se ignore. Hay que comprobarlo.
- Consecuencia práctica para el desarrollo: durante el paso 4 conviene una **prueba
  aislada en un solo proceso** (`QT_STYLE_OVERRIDE=<nombre> kate`), no porque haga falta
  para instalar, sino porque permite validar el QStyle con **riesgo cero** antes de
  activarlo globalmente.

**Acción:** añadir al brief un apartado «Activación del estilo» y tratar la prueba en un
solo proceso como puerta obligatoria antes del despliegue global (etapa 1 de
[`INSTALACION.md`](INSTALACION.md) §6).

### A3 · GTK4: expectativa realista

- `kde-gtk-config` + CSS generado: **válido y suficiente** para GTK3. Mantenerlo.
- `libdecor`: es una biblioteca que el **cliente** enlaza para obtener decoración
  híbrida (dibuja el cliente, pero el compositor aporta sombras y gestión). No es un
  mecanismo para que KWin decore a la fuerza, y **GTK4 no la usa**. El brief lo presenta
  como «el mecanismo sancionado: la app cede el dibujo al compositor» — eso describe
  `xdg-decoration` en modo *server-side*, que en GTK4 simplemente no se activa.
- **El porcentaje irreducible es mayor del 10 %.** Casos que ignoran el tema con
  independencia de lo que hagas:
  - Apps **Electron/Chromium** con decoración propia y CSS embebido.
  - **Flatpak** que empaqueta su propio tema y no ve `~/.themes` ni `~/.config/gtk-4.0`.
  - Apps modernas que enlazan contra **libadwaita sin el opt-in** de respetar el tema
    del sistema.
  - Apps que dibujan su propia barra de título (VS Code, Spotify, navegadores).

**Acción:** reformular el objetivo de GTK como *«GTK3 totalmente, GTK4 en lo que
respete `gtk-4.0/gtk.css`, y una lista documentada de excepciones conocidas»*. Una lista
de excepciones honesta vale más que un porcentaje inventado.

### A4 · El recorte de esquinas: viable, pero no gratis

Existe precedente directo y activo: **LightlyShaders** (esquinas redondeadas + contorno
para KWin, con [puerto a Plasma 6](https://github.com/walterfang12/LightlyShaders-Plasma6))
y [kwin-effect-rounded-corners](https://github.com/ekaaty/kwin-effect-rounded-corners).
Por tanto el mecanismo es real: un efecto KWin que aplica una máscara por ventana al
componer. Pero conviene precisar tres cosas que el brief da por hechas:

1. **Redondear y recortar no es lo mismo.** Redondear pinta esquinas transparentes
   alrededor de una ventana cuadrada. Recortar **elimina píxeles**: si la app dibuja
   contenido en la esquina (un botón, un borde, texto pegado al vértice), ese contenido
   desaparece. En apps con barra de título propia el resultado se ve roto.
2. **El radio efectivo depende del cliente.** El brief pide «un radio único para todas».
   No se puede garantizar: la app puede tener su propia decoración con su propio radio, y
   el efecto solo añade el exterior. Hay que decidir la política para apps con CSD
   (¿no tocar? ¿recortar y aceptar el destrozo?).
3. **El orden correcto es paso 1, no paso 5.** El brief coloca el efecto KWin *«encima
   del 4»*. Error de priorización: el recorte de esquinas es **lo que más cambia la
   percepción por línea de código** y es lo único que unifica apps que jamás respetarán
   tu QStyle. Debe ir justo después de la capa declarativa.

### Observación menor · «escort»

La lista de tokens de Golden Gate incluye `ICONOS ....... escort obligatorio`. Es casi
con seguridad **«squircle»** (el superelipse de Apple). Corregir en el brief para no
arrastrar el error a los nombres de fichero y de tipos.

### Alcance · HDR

`EXTRA: la interfaz usa HDR para dar profundidad` es real en macOS, pero en Linux
implica KWin con HDR (soporte aún en maduración en Plasma 6), dependencia del monitor y
multiplicación de casos de prueba de color. **Sacarlo de la v1.** Es la clase de token
que se declara en `tokens.json` desde el día uno y se implementa en v3, cuando el motor
ya está estable.

---

## 4. Lo que falta y hay que añadir al brief

### 4.1 Tipografía (el hueco más grande)

Sin resolver esto, el proyecto no alcanzará el objetivo aunque todo lo demás funcione.

- **No distribuir SF Pro.** La licencia de Apple lo prohíbe para redistribución. Un
  repositorio público con SF Pro dentro es un problema legal real, y contradice el propio
  aviso legal del brief.
- **Necesitas una fuente con métricas calibradas**, no solo parecida: interlineado,
  ancho de avance y altura-x son lo que produce la sensación de «densidad» de macOS.
  Candidatas de licencia libre: **Inter** (la más cercana en proporciones y con eje
  óptico), **SF Pro sustitutas** como `Inter Display` para títulos, y para monoespaciada
  **JetBrains Mono** o **IBM Plex Mono**.
- **Escala tipográfica en tokens**: tamaño de UI, de títulos de barra, de cuerpo, y —lo
  más importante— **el espaciado interno por control**, que es lo que casi nadie ajusta y
  es lo que hace que el control «se sienta» de macOS o no.

### 4.2 Criterio de éxito y pruebas de regresión visual

Propuesta concreta, barata y automatizable desde el paso 0:

- **Definición de terminado por hito** (habrá que fijar el valor exacto de N):
  - Hito 1: la suite de apps representativas se ve coherente en capturas comparadas
    contra una referencia congelada.
  - Hito 2: ninguna app de la suite *falla al arrancar* ni pierde funcionalidad.
  - Hito 3: el instalador funciona **sin sudo** y la desinstalación deja el sistema como
    estaba (verificable con `git status` de los dotfiles + hashes previos).
- **Arnés de capturas**: lista fija de apps y diálogos, capturadas con `spectacle
  --background --fullscreen` o `grim`, comparadas píxel a píxel (o con tolerancia) contra
  una referencia guardada. Un script de 40 líneas. Detecta la mitad de las regresiones
  antes de que las veas a ojo.
- **Banco de apps representativas** (fijar y no ampliar sin motivo): Dolphin, Kate,
  Kwrite, Konsole, una app GTK3, una GTK4/libadwaita, una Electron y una Flatpak.

### 4.3 Portabilidad: concreción

El brief acierta en la intención, pero «todo declarativo en un repo» ya tiene solución
estándar y conviene no reinventarla:

- Usar **dotfiles + instalador idempotente** (o herramienta existente tipo `chezmoi`,
  `stow`) en vez de un formato propio. El valor está en que cambiar de distro sea un
  comando, y eso ya está resuelto.
- Añadir un **modo `--dry-run`** al instalador, y un **manifiesto de reversión** (lista
  de ficheros tocados + hash previo). Es lo que hace el script «auditable y reversible»
  de verdad, no solo declarativo.
- **Matiz sobre «nada de sudo, nada de AUR»**: correcto como restricción del
  *entregable* (el instalador no lo usa). Distinto de tu máquina de desarrollo, donde
  compilar Qt/KWin o instalar `gcc`, `cmake` y cabeceras sí requiere paquetes del
  sistema. Conviene redactarlo como «el instalador no usa sudo» y no como «el proyecto
  no usa sudo», para no bloquearse tontamente en la fase de desarrollo.

### 4.4 Riesgo de obsolescencia de los tokens

macOS 27 Golden Gate es una referencia **previa a su lanzamiento**. Apple ajusta
radios, opacidades y contrastes entre betas, y con el histórico de Liquid Glass es
especialmente probable que haya correcciones en los primeros meses. Por tanto:

- Los tokens deben llevar **versión** y **fecha de captura**, y el generador debe
  tolerar que un token cambie de valor sin romper nada.
- Conviene diseñar para «una capa de tokens por versión de referencia», no para un único
  conjunto congelado.

---

## 5. Orden de trabajo propuesto (corrige el del brief)

```
0. INFRAESTRUCTURA Y MEDICIÓN             <- nuevo, 2-3 días
   arnés de capturas + banco de apps + tokens.json versionado
   + fuente elegida y escala tipográfica
   -> sin esto, los pasos 3 y 4 son invisibles y no verificables

1. TOKENS DE GOLDEN GATE                  <- del brief, se mantiene
   + eje tipográfico y de espaciado (el brief no lo tenía)

2. CAPA DECLARATIVA PORTABLE + INSTALADOR <- del brief, se mantiene
   aquí vive también el generador de esquemas y CSS GTK

3. EFECTO KWIN: ESQUINAS + BORDE OSCURECIDO  <- MOVIDO desde el paso 5
   máximo impacto visual por línea de código; unifica apps que no cooperan
   -> incluye la prueba temprana de QT_STYLE_OVERRIDE (A2)

4. GENERADOR: TOKENS -> QSTYLE + CSS + KWIN  <- del brief, se mantiene
   entregable real: Tokens.h + manifiesto de cobertura + assets

5. QSTYLE COMPLETO                        <- del brief, se mantiene
   implementación por enumeraciones, guiada por el manifiesto del paso 4

6. (v3) HDR Y PROFUNDIDAD AVANZADA        <- sacado de la v1
```

Cambios respecto al brief: **paso 0 nuevo** (medición), **efecto KWin del 5 al 3**, y
**HDR explícitamente a v3**.

---

## 6. Sobre el aviso legal: un punto que falta

El brief cubre bien marcas, nombres e iconos. Falta el ítem que más gente pasa por alto:

- **Fuentes**: no redistribuir SF Pro (ver §4.1). Es el incumplimiento más fácil de
  cometer sin darse cuenta, porque la fuente suele acabar en el repositorio como
  «recurso de estilo».
- **Iconos**: además de no usar los de Apple, hay que verificar la licencia del set
  elegido si el repositorio es público.
- **Capturas de pantalla**: si se comparan contra capturas de macOS, publicar esas
  capturas como referencia también entra en juego. Guardarlas fuera del repo público, o
  usar métricas (radios, opacidades) en vez de imágenes.

---

## 7. Resumen de acciones sobre el brief

| # | Acción | Prioridad |
|---|---|---|
| 1 | Añadir eje **tipográfico** (fuente + escala + espaciado) al sistema de tokens | **Alta** |
| 2 | Resolver **cómo se activa el QStyle** en Plasma 6 (`widgetStyle` en `kdeglobals`) | **Resuelto** → [`INSTALACION.md`](INSTALACION.md) §1 |
| 3 | Añadir **paso 0 de medición**: arnés de capturas + banco de apps + criterio de terminado | **Alta** |
| 4 | Mover el **efecto KWin del paso 5 al 3** | **Alta** |
| 5 | Separar **generador** de **QStyle** (dos ciclos de vida, dos entregables) | Media |
| 6 | Reformular GTK: GTK3 completo, GTK4 parcial, **lista honesta de excepciones** | Media |
| 7 | Precisar el recorte de esquinas: redondear ≠ recortar, política para apps con CSD | Media |
| 8 | Sacar **HDR a v3** | Media |
| 9 | Reescribir «nada de sudo» como «**el instalador no usa sudo**» | Baja |
| 10 | Corregir `escort` → **`squircle`** | Baja |
| 11 | Versionar los tokens (Golden Gate aún no ha salido) | Baja |
| 12 | Añadir fuentes y licencia de iconos al **aviso legal** | Baja |

---

## 8. Conclusión

El brief vale como punto de partida: identifica el problema correcto, descarta las
soluciones equivocadas (temas, `LD_PRELOAD`, fork de Plasma) y ordena el trabajo con
sensatez. No es un plan ingenuo.

Lo que le falta no es estrategia, es **realismo operativo en cuatro puntos** —el QStyle
no se genera ni se activa solo, GTK4 no cede por `libdecor`, el recorte de esquinas tiene
coste— y **dos ejes que no aparecen**: la tipografía y la medición. De los dos, la
tipografía es el que decide si el resultado parece macOS; la medición es el que decide si
el proyecto llega al final.

Con esas correcciones, el proyecto es viable en el orden propuesto y tiene un entregable
de valor inmediato (paso 2) que justifica el esfuerzo aunque los pasos 5 y 6 nunca se
completen. Eso, en sí, ya es un buen plan.

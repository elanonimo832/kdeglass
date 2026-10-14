# Instalación y aplicación del proyecto

Diseño de **cómo se instala y cómo se aplica** la capa «estilo macOS». Escrito sobre
hechos verificados en este equipo (CachyOS, KDE Plasma 6, Wayland), no sobre supuestos.

- Fecha: 13/10/2025
- Análisis del que deriva: [ANALISIS.md](ANALISIS.md) · Evidencia: [ANEXO-VERIFICACION.md](ANEXO-VERIFICACION.md)
- Brief: [PROYECTO-KDE-MACOS.md](PROYECTO-KDE-MACOS.md)

---

## 1. Hallazgo principal: tu sistema ya resolvió el problema difícil

El punto A2 del análisis («el QStyle no se activa solo») **era correcto como advertencia,
pero tiene mejor solución de la que supuse**, y la prueba está en tu propia máquina:

```
~/.config/kdeglobals
    [KDE]
    Línea 144:  widgetStyle=kvantum

/usr/lib/qt6/plugins/styles/
    breeze6.so
    libkvantum.so
```

**Kvantum es un QStyle de terceros, instalado desde el sistema, y está activo en tu
sesión.** Eso demuestra el mecanismo completo, sin necesidad de `QT_STYLE_OVERRIDE`:

1. El `.so` del estilo vive en el directorio de plugins de estilos de Qt 6.
2. El estilo se selecciona con **una sola clave** en `kdeglobals`: `[KDE] widgetStyle=`.
3. Plasma 6 la respeta y la aplica a las apps que arrancan después.

Conclusión operativa: **no hace falta forzar el estilo por proceso.** El instalador
escribe una clave de configuración, igual que hizo Kvantum. Esto elimina de un golpe el
mecanismo de lanzadores y el `QT_STYLE_OVERRIDE` que temía en el análisis, y hace el
proyecto bastante más viable.

> Matiz verificado: Plasma 6 **sí** conserva el selector «Estilo de las aplicaciones».
> En este equipo existe `kcm_style.so` en
> `/usr/lib/qt6/plugins/plasma/kcms/systemsettings/`, y sus cadenas internas contienen
> `widgetStyle`, `WidgetStyle`, `widgetStyleChanged` y `defaultWidgetStyleValue`. Es
> decir: **el KCM escribe exactamente la misma clave `kdeglobals` que va a escribir el
> instalador.** Por tanto el instalador hace lo mismo que la interfaz gráfica, sin
> depender de ella. Esa correspondencia es lo que hace el diseño robusto.
>
> Dos avisos que salen de esas mismas cadenas:
> - Existe una propiedad `isWidgetStyleImmutable`. Si una distro o un entorno marca el
>   estilo como inmutable, `widgetStyle` se ignora. `preflight` debe comprobarlo, o el
>   paso 4 fallará en silencio y parecerá un bug del QStyle.
> - Existe `widgetStyleChanged`: si escribir `kdeglobals` no bastara para que las apps ya
>   abiertas se enteren, la notificación se puede disparar por D-Bus. En la práctica basta
>   con reiniciar las apps, porque el estilo se lee al arrancar cada proceso.

**Segundo hallazgo:** `~/.config/gtk-3.0/` y `~/.config/gtk-4.0/` **ya están gestionados
por `kde-gtk-config`** (`window_decorations.css` y `colors.css` los genera KDE). Y tienes
`gtk-font-name=Noto Sans, 10` y `gtk-theme-name=Breeze` en `settings.ini`. Es decir: el
eje tipográfico que pedías incluir **ya tiene un punto de aplicación existente** que hay
que respetar, no inventar.

**Tercer hallazgo:** `~/.local/share/flatpak/overrides/` ya existe con 7 apps. La vía para
inyectar entorno en Flatpak es `flatpak override --user --env=...`, mecanismo estándar y
soportado, no parcheo.

---

## 2. Principios de diseño del instalador

| Principio | Cómo se cumple |
|---|---|
| **Sin sudo** | Todo bajo `$HOME`. El instalador nunca invoca `sudo` ni escribe fuera de `~` |
| **Idempotente** | Ejecutarlo dos veces con el mismo commit produce **el mismo contenido**. Construcción en directorio temporal + `mv` atómico, nunca escritura en sitio |
| **Auditable** | `--dry-run` imprime la lista exacta de operaciones y diferencias, sin tocar nada |
| **Reversible** | Backup con fecha de cada fichero tocado, manifiesto en `~/.local/state/`, y `rollback` que restaura el estado previo |
| **Sin sorpresas** | `preflight` valida el entorno **antes** de tocar nada |
| **Portable** | Rutas XDG (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_STATE_HOME`), no rutas fijas. `~/.local` y `~/Documents` siguen siendo válidos por defecto, pero no se codifican |

Cambio respecto al brief: el brief fija «todo en `~/.local` y `~/Documents`». Se mantiene
como resultado por defecto, pero **el código usa variables XDG** — es gratis y es lo que
hace que el «instalador para cambiar de distro» funcione de verdad.

Sobre el formato de tokens: el brief propone `tokens.json`. Recomiendo **TOML o
`key=value`** en su lugar. El motivo es concreto: los tokens son para **leerlos y
diffearlos** en revisiones, y un TOML produce diffs de una línea por token mientras el
JSON produce diffs con comas, llaves y reindentación. Es la diferencia entre auditar y
adivinar. (Se puede generar `tokens.json` desde el TOML si alguna herramienta lo exige:
el TOML es la fuente, el JSON un derivado.)

---

## 3. Estructura del repositorio

```
kde-macos/
├── tokens/
│   ├── tokens.toml              <- FUENTE ÚNICA de verdad (radios, material, color, tipografía)
│   └── CHANGELOG.md             <- qué token cambió y cuándo (clave: Golden Gate está en beta)
├── tools/
│   ├── generar.py               <- tokens -> color schemes, CSS GTK, Tokens.h, manifiestos
│   └── capturar.sh              <- arnés de regresión visual (paso 0 del análisis)
├── style/                       <- el QStyle en C++
│   ├── CMakeLists.txt
│   ├── kdemacosstyle.cpp
│   └── Tokens.h                 <- GENERADO. No se edita a mano
├── kwin/
│   └── efecto-esquinas/         <- efecto KWin (esquinas + borde oscurecido + reflejo)
├── gtk/                         <- plantillas CSS (los valores vienen de los tokens)
├── fuentes/
│   └── LEEME.md                 <- qué fuente, licencia, y cómo se instala (no se redistribuye lo que no se puede)
├── instalar.sh                  <- el único punto de entrada
└── manifiestos/
    ├── ficheros.txt             <- qué ficheros del repo van a qué ruta del sistema
    └── apps.txt                 <- banco de apps representativas para las capturas
```

Y lo que **no** está en el repo, porque es estado del sistema:

```
~/.local/state/kde-macos/
├── manifest.tsv        <- ruta_tocada <TAB> hash_previo <TAB> backup <TAB> versión
├── backups/<fecha>/    <- copia literal de cada fichero antes de tocarlo
└── version             <- versión instalada (para comparar con el repo)
```

---

## 4. Destinos reales de instalación

Rutas verificadas en este equipo. El instalador detecta `lib` vs `lib64` en lugar de
asumirlo.

| Capa | Qué se instala | Destino | Cómo se activa |
|---|---|---|---|
| **QStyle** | `kdemacos.so` | `~/.local/lib/qt6/plugins/styles/` | `kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle kdemacos` |
| **Colores** | `KdeMacos.colors` (o dos: claro/oscuro) | `~/.local/share/color-schemes/` | `--group General --key ColorScheme` + `ColorSchemeHash` |
| **Tipografía** | Ficheros de fuente (previa validación de licencia) | `~/.local/share/fonts/` | `--key font` (y `fixed`), + `fc-cache -f` |
| **KWin: esquinas** | `.so` del efecto | `~/.local/lib/qt6/plugins/kwin/effects/` | `kwriteconfig6 --file kwinrc --group Plugins --key esquinasEnabled true` |
| **KWin: material** | mismo efecto | idem | idem |
| **GTK3** | `kde-macos.css` + import | `~/.local/share/themes/kde-macos/gtk-3.0/` | **vía `kde-gtk-config`**, no escribiendo `gtk-3.0/gtk.css` a mano |
| **GTK4** | `kde-macos.css` | `~/.local/share/themes/kde-macos/gtk-4.0/` | `gtk-4.0/gtk.css` del usuario (respetando el `@import` que ya existe) |
| **Flatpak** | variable de entorno | `~/.local/share/flatpak/overrides/<app>` | `flatpak override --user --env=GTK_THEME=kde-macos <app>` |
| **Electron** | `.desktop` propio | `~/.local/share/applications/` | flags por app; **lista de excepciones aceptadas** |

### Detalle crítico sobre GTK

En tu sistema, `~/.config/gtk-3.0/gtk.css` contiene exactamente `@import 'colors.css';` —
es decir, **`kde-gtk-config` ya posee ese fichero**. Si el instalador escribe ahí
directamente, la próxima vez que abras *Configuración del sistema → Apariencia → Estilo
GNOME/GTK* KDE lo sobrescribirá y perderás el trabajo.

Regla de diseño: **el instalador no posee los ficheros de `kde-gtk-config`, se engancha a
ellos.** Concretamente, instala el tema en `~/.local/share/themes/` y luego deja que KDE
lo seleccione mediante `kde-gtk-config`, en lugar de escribir CSS a mano en `~/.config`.
Este es el tipo de detalle que decide si el proyecto sobrevive a la siguiente sesión de
configuración del usuario.

---

## 5. El instalador: `instalar.sh`

Un solo punto de entrada con subcomandos. Nada de recordar diez scripts.

```bash
./instalar.sh preflight     # ¿está el entorno como espero? NO toca nada
./instalar.sh plan          # --dry-run: lista operaciones y diffs. NO toca nada
./instalar.sh instalar      # aplica (exige plan limpio)
./instalar.sh verificar     # capturas de regresión + checks funcionales
./instalar.sh estado        # qué está instalado, versión, diferencias con el repo
./instalar.sh rollback      # restaura el último backup (un comando)
./instalar.sh desinstalar   # revierte TODO y deja el sistema como estaba
```

### `preflight` — lo que se valida antes de tocar nada

```
1. Entorno:   $XDG_SESSION_TYPE=wayland, $XDG_CURRENT_DESKTOP=KDE, KDE_SESSION_VERSION=6
2. Herramientas: kwriteconfig6, kreadconfig6, fc-cache, qdbus6
   -> verificado: los cuatro presentes en este equipo
3. Qt:        localizar el directorio de plugins de estilos y COMPROBAR que
              ~/.local/lib/qt6/plugins es una ruta de búsqueda real de Qt6
              (si no lo es -> escribir QT_PLUGIN_PATH en ~/.config/environment.d/)
4. lib vs lib64: detectar cuál usa este sistema
5. Conflicto: ¿existe ya widgetStyle? ¿cuál? -> se guarda en el manifiesto
6. Colisión:  ¿existe ~/.local/share/themes/<nombre>? ¿de quién es?
7. Presupuesto: espacio y permisos de escritura en cada destino
8. Producción: cmake, ninja, headers Qt6 -> SOLO si se va a compilar el QStyle
```

El punto 3 es el único que **debe resolverse empíricamente** antes de escribir el
instalador definitivo: comprobar con `QT_DEBUG_PLUGINS=1` si Qt6 explora el directorio de
usuario. Si no lo hace, la línea `QT_PLUGIN_PATH` en `~/.config/environment.d/` es la
solución, y es una línea.

### `plan` — auditoría legible

Salida esperada, en este formato exacto:

```
[CREAR]   ~/.local/share/color-schemes/KdeMacos.colors          (nuevo)
[CREAR]   ~/.local/lib/qt6/plugins/styles/kdemacos.so           (nuevo)
[MODIFICAR] ~/.config/kdeglobals
            [KDE] widgetStyle: kvantum -> kdemacos
            [General] ColorScheme: Ant-Dark -> KdeMacos
            (backup -> ~/.local/state/kde-macos/backups/20251013-174500/kdeglobals)
[SIN CAMBIOS] ~/.config/gtk-4.0/gtk.css
[EXCEPCIÓN] no se toca: VS Code (Electron, CSD propia)
```

Un diff por clave, con el valor anterior y el nuevo. Esto es lo que hace el script
«auditable» de verdad: no declarativo en abstracto, sino **revisable antes de aplicar**.

### Idempotencia, en concreto

El error típico es «copiar ficheros y ya». La forma correcta:

```
1. Construir TODO en $XDG_CACHE_HOME/kde-macos/build-<hash-de-contenido>/
2. Comparar con lo instalado por hash
3. Si algo cambia: backup + mv atómico (nunca escritura parcial en sitio)
4. Regenerar el manifiesto
```

Consecuencia medible: ejecutar `instalar.sh instalar` dos veces con el mismo commit deja
`manifest.tsv` **idéntico**. Ese es el test de idempotencia, y se puede automatizar.

### Contención de daños

El riesgo real no es el QStyle (se aplica **por proceso**: una app mala se cierra y ya),
es `kdeglobals`, que comparten todos los procesos KDE/Qt. Mitigaciones, por orden:

1. Escribir `kdeglobals` **solo con `kwriteconfig6`**, nunca con `sed` ni reescribiendo el
   fichero. `kwriteconfig6` respeta el formato y evita corromperlo.
2. `backup` con fecha de `kdeglobals` **y** de `kwinrc` antes de cualquier cambio.
3. `rollback` = restaurar backup + `kwriteconfig6` de vuelta. Un comando.
4. **Vía de escape sin GUI**: si algo deja las apps Qt inservibles, cambiar a una TTY
   (`Ctrl+Alt+F3`), iniciar sesión y ejecutar `./instalar.sh rollback` o `desinstalar`
   desde texto. Esto funciona aunque no haya ni un solo diálogo usable. Es el seguro que
   hace aceptable probar el widget style en el sistema completo.

---

## 6. Despliegue por etapas (esto es el «cómo se aplica»)

Nunca aplicar las cuatro capas de golpe. El orden está pensado para que cada etapa
**valide** la siguiente y para saber exactamente qué rompió si algo rompe.

```
ETAPA 0 · preflight + plan
    no instala nada. Aquí se resuelve el punto 3 (rutas de plugins de Qt6).

ETAPA 1 · UN SOLO PROCESO (la prueba decisiva)
    QT_STYLE_OVERRIDE=kdemacos kate &
    -> verificar: no crashea, los controles se dibujan, las métricas son correctas
    -> si falla aquí, no se rompe NADA del sistema. Coste de fallo: cero.

ETAPA 2 · COLORES + TIPOGRAFÍA (bajo riesgo, impacto alto)
    color scheme + fuentes. Ambas son reversibles con rollback y no dependen
    de que el QStyle esté terminado.
    -> esto ya entrega valor visible con el QStyle a medio hacer.

ETAPA 3 · KWIN (esquinas + borde oscurecido)
    efecto KWin. Unifica las apps que nunca respetarán el QStyle.
    Solo afecta a la composición: un efecto malo se desactiva y listo.

ETAPA 4 · QSTYLE EN EL SISTEMA (el único paso con alcance global)
    widgetStyle=kdemacos en kdeglobals.
    -> precedido de `verificar` y seguido de `verificar`.

ETAPA 5 · GTK + FLATPAK (expectativas realistas, lista de excepciones)
```

La etapa 1 es la joya del diseño: **te da el 100 % de la información sobre el riesgo
mayor con el 0 % del riesgo**. Es un `&` en una línea.

---

## 7. Estado resultante en tu equipo

Tras instalar, tu `kdeglobals` tendrá (valores ilustrativos):

```ini
[KDE]
widgetStyle=kdemacos          # antes: kvantum
[General]
ColorScheme=KdeMacos
ColorSchemeHash=<hash>
font=Inter,10                 # antes: Noto Sans,  10  (nótese el doble espacio: KDE)
fixed=JetBrains Mono,10
```

Nota de valor añadido: hoy tu sistema está **incoherente entre capas** —
`LookAndFeelPackage=Ant-Dark` pero `widgetStyle=kvantum`, con tema GTK `Breeze` sin
`colors.css` de Kvantum. El proyecto no solo añade una capa nueva: **unifica lo que ya
está mezclado**. `instalar.sh estado` sirve además como herramienta para diagnosticar ese
tipo de desajustes, y eso vale incluso si el QStyle nunca se escribe.

---

## 8. Requisitos que el instalador NO puede satisfacer

Esto responde al matiz «nada de sudo, nada de AUR» del análisis (§4.3), en concreto:

| Necesidad | ¿Instalador? | Estado en este equipo |
|---|---|---|
| Compilar el QStyle y el efecto KWin | **No** — es tu entorno de desarrollo | `gcc` ✅, `g++` ✅, `pkg-config` ✅, headers Qt6 ✅, **`cmake` ❌**, **`ninja` ❌** |
| Ejecutar el instalador | Sí, con lo que ya hay | Todo presente ✅ |
| Cargar el QStyle en las apps | Sí | `kwriteconfig6` ✅ |

`cmake` y `ninja` **no están instalados** en este equipo. Son necesarios para compilar el
QStyle (paso 5 del plan) y se instalan con `pacman`, que requiere sudo y toca el sistema.

**Distinción que conviene fijar en el brief:**

```
El ENTREGABLE no usa sudo ni AUR.        <- cierto, y hay que mantenerlo
El DESARROLLO sí instala herramientas.   <- también cierto, y no contradice lo anterior
```

Redactarlo como «el instalador no usa sudo» en vez de «nada de sudo» evita bloquearte
tontamente en la fase de compilación sin debilitar la restricción que de verdad importa:
que el resultado sea reproducible en cualquier distro sin privilegios.

---

## 9. La tipografía, aplicada

Tu observación de que la tipografía merece incluirse se concreta así:

1. **Elección**: `Inter` como familia de UI (licencia SIL OFL, redistribuible). Para
   títulos con eje óptico, `Inter Display`. Monoespaciada: `JetBrains Mono` o
   `IBM Plex Mono`. **No se redistribuye SF Pro** (licencia de Apple) — se documenta como
   elección del usuario, no se empaqueta.
2. **Tokens nuevos** en `tokens.toml` (el eje que faltaba en el brief):

```toml
[tipografia]
familia_ui       = "Inter"
familia_titulos  = "Inter Display"
familia_mono     = "JetBrains Mono"
tamano_ui        = 10        # en puntos, como los espera KDE
tamano_barra     = 11
interlineado_escala = 1.15   # el «aire» de macOS no es el tamaño, es el interlineado
espaciado_control   = 8      # padding interno: lo que casi nadie ajusta y más se nota
```

3. **Punto de aplicación**: `kdeglobals` (`font`, `fixed`) para Qt/KDE, y
   `~/.config/gtk-4.0/settings.ini` (`gtk-font-name`) para GTK — donde hoy tienes
   `Noto Sans, 10`. Un cambio de familia pasa por el generador, no por tres sitios a mano.
4. **Verificación**: `fc-match "Inter"` debe resolver a la fuente instalada y no a un
   fallback silencioso a DejaVu. Es un chequeo de una línea que se añade a `preflight`, y
   detecta el fallo más común (fuente «instalada» que fontconfig ignora).

---

## 10. Resumen

**Cómo se instala:** un solo script `instalar.sh` con subcomandos, sin sudo, idempotente,
con `plan` para auditar antes y `rollback`/`desinstalar` para revertir. Construye en
caché, compara por hash y hace `mv` atómico. Todo el estado queda en
`~/.local/state/kde-macos/`.

**Cómo se aplica:** el hallazgo central es que **Plasma 6 acepta un QStyle de terceros
mediante una sola clave en `kdeglobals`** — tu Kvantum ya lo demuestra. Eso convierte el
riesgo principal del análisis (A2) en una línea de configuración. Se aplica en cinco
etapas, empezando por un único proceso con `QT_STYLE_OVERRIDE` (riesgo cero) y subiendo
hasta el alcance global, con vía de escape por TTY.

**Lo que cambia en el brief a raíz de esto:**

1. «El QStyle no se activa solo» → **se activa con `widgetStyle` en `kdeglobals`**, y hay
   precedente funcionando en este equipo. A2 queda resuelto a mejor.
2. Añadir el **eje tipográfico** al sistema de tokens (punto válido, confirmado).
3. **No escribir en los ficheros que posee `kde-gtk-config`**: engancharse a su mecanismo.
4. Reescribir «nada de sudo» como **«el instalador no usa sudo»**.
5. Usar **TOML** para los tokens, no JSON, por auditabilidad.
6. Incluir la **etapa 1 de prueba en un solo proceso** como paso obligatorio antes del
   despliegue global.

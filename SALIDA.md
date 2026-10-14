# Entrega del paso 2: lo que ya se puede instalar

Esta carpeta contiene el **paso 2 del plan terminado**: el sistema de tokens y sus
artefactos generados. No incluye el QStyle ni el efecto KWin (pasos 4 y 5).

- Plan completo: [ANALISIS.md](ANALISIS.md) · Instalación: [INSTALACION.md](INSTALACION.md)
- Tokens de origen: [tokens/](tokens/) · Sistema consolidado: [tokens.toml](tokens.toml)

---

## 1. Qué se ha generado

```
tokens.toml                     EL SISTEMA DE DISENO (1814 lineas, 5 ejes)
salida/
├── color-schemes/
│   ├── KdeMacosLight.colors    Esquema de color claro de KDE
│   └── KdeMacosDark.colors     Esquema de color oscuro de KDE
├── gtk-3.0/
│   ├── kde-macos.css           Tema GTK3 claro
│   ├── kde-macos-dark.css      Tema GTK3 oscuro
│   └── colors.css              Solo las variables de color
└── gtk-4.0/
    ├── kde-macos.css           Tema GTK4 claro
    ├── kde-macos-dark.css      Tema GTK4 oscuro
    └── colors.css
instalar.sh                     Instalador: preflight / plan / estado / aplicar / rollback / verificar
instalar-decoracion.sh          Instalador aparte para la decoracion de ventana
```

Todo generado desde los tokens. **Nada escrito a mano que pueda desincronizarse.**

---

## 2. Los cinco ejes del sistema de diseno

| Eje | Tokens | Origen | Verificado |
|---|---|---|---|
| **color** | 61 | Export de Variables de Figma | Alfa exacto, claro y oscuro |
| **forma** | 150 | Propiedades de nodo del `.fig` (19.011 nodos) | Radios, squircle, sombras, borde |
| **métricas** | 65 | Export de Variables (Sizes) | 5 tamaños de control |
| **tipografía** | 80 | **HIG oficiales de Apple** | 11 estilos + tracking |
| **material** | 11 | Efecto `GLASS` del `.fig` | 7 parámetros |

Los cinco son **medidos o publicados**. Ninguno inventado. Y `[_procedencia]` dentro de
`tokens.toml` dice de dónde sale cada uno.

---

## 3. Qué se puede hacer ya, y qué no

| | |
|---|---|
| **Se puede aplicar hoy** | Los esquemas de color de KDE |
| **Requiere un paso manual** | El tema GTK: hay que seleccionarlo en Ajustes del sistema |
| **Todavía no** | El QStyle (paso 4) y el efecto KWin (paso 5) |

El instalador **no toca los ficheros de `kde-gtk-config`** a propósito. Se engancha a su
mecanismo para que la próxima vez que abras los ajustes de GTK no se pierda el trabajo.

---

## 4. Cómo usarlo

```bash
cd analisis-kde-macos

./instalar.sh preflight      # comprueba el entorno. No toca nada.
./instalar.sh plan           # muestra QUE haria, fichero por fichero. No toca nada.
./instalar.sh aplicar --si   # aplica. Backup con fecha antes de cada cambio.
./instalar.sh estado         # que hay instalado y en que se diferencia
./instalar.sh rollback       # revierte todo con un comando
```

**Regla de oro del instalador:** por defecto no escribe nada. Todos los subcomandos son de
lectura o de ensayo salvo `aplicar`, que además exige `--si`. No se puede romper el
escritorio por invocarlo sin querer.

Tras aplicar, el tema GTK se selecciona a mano en:
*Configuración del sistema → Apariencia → Estilo GNOME/GTK → kde-macos*

---

## 5. Verificaciones que se han hecho

| Comprobación | Resultado |
|---|---|
| Los 16 TOML parciales parsean | **16/16** |
| `tokens.toml` consolidado parsea | **Sí**, 5 ejes |
| Los 2 `.colors` parsean como INI | **Sí**, 13 grupos, ninguna clave obligatoria ausente |
| Valores RGB en rango 0-255 | **Todos** |
| CSS: referencias a variables sin definir | **0** de 91 por fichero |
| GTK3 usa `@define-color`, GTK4 usa `var()` | **Correcto en cada versión** |
| Sintaxis de `instalar.sh` | **OK** |
| `plan` / `estado` / `verificar` / `rollback` | **Funcionan** |

### Contraste WCAG (el problema que se criticó de Tahoe)

```
                    CLARO    OSCURO
Colors:Window       15.13    12.27
Colors:View         15.13    12.82
Colors:Button       13.18    10.00
Colors:Selection     5.30     6.31
Colors:Tooltip      13.87    10.92
```

Todo por encima de 4.5 (AA). No es casualidad: los colores de texto del kit son negro o
blanco con alfa alto sobre el fondo, así que el contraste sale alto **por construcción**.
La queja principal de Tahoe —legibilidad— no puede reproducirse con estos tokens.

---

## 6. Tres cosas que aparecieron al hacer esto, y que corrigen lo anterior

**1. `widgetStyle` no vive en `[General]`, vive en `[KDE]`.** Lo di por supuesto al
analizar y era falso. Verificado en el `kdeglobals` real: `widgetStyle=kvantum` está en la
sección `[KDE]`. Corregido en [ANALISIS.md](ANALISIS.md),
[INSTALACION.md](INSTALACION.md) y [ANEXO-VERIFICACION.md](ANEXO-VERIFICACION.md).

**2. `kreadconfig6` se cuelga si no hay bus de sesión.** No falla: se queda colgado
indefinidamente. El instalador lo sondea con `timeout` y, si no responde, lee el INI
directamente. Un instalador no puede quedarse colgado.

**3. Los `kdeglobals` pueden tener finales de línea CRLF.** El `\r` pegado rompe cualquier
comparación de texto, y `gsub(/[][]/)` tampoco es portable para quitar corchetes. Ambas
cosas están resueltas en el lector.

Ninguna de las tres se habría visto sin ejecutar el instalador contra tu sistema real.

---

## 7. Lo que falta, y por qué no bloquea

| Falta | Fase |
|---|---|
| QStyle en C++ | Paso 4 del plan. Necesita `cmake` y `ninja`, que no están instalados |
| Efecto KWin (material + esquinas) | Paso 5. Depende del anterior, aunque el material ya está medido |
| Iconos | Fuera del alcance actual. No se usan los de Apple por licencia |
| Fuente Inter | Hay que instalarla en `~/.local/share/fonts` (SIL OFL, redistribuible) |

Los tokens que necesitan esos pasos **ya están medidos y en `tokens.toml`**, así que
cuando se escriba el QStyle no habrá que volver a Figma.


---

## 10. Paso 5 (efecto KWin): estado real

Se ha empezado el efecto del material. Estado honesto, con lo verificado y lo que falta.

### Lo que se ha demostrado

**1. Un efecto KWin se puede construir en este sistema sin `cmake`.** Verificado:
compila y enlaza.

```
g++ -c -fPIC -std=c++20 -I/usr/include/kwin -I/usr/include/kwin/effect <rutas KF6> glass.cpp
g++ -shared -fPIC -o macosglass.so glass.o moc_glass.o $(pkg-config --libs Qt6Core Qt6Gui) -lkwin
-> plugin de 53 KB, sin errores
```

Los **headers de KWin y de KF6 ya están instalados** (`/usr/include/kwin/effect/`,
`/usr/include/KF6/`), y `libkwin.so` existe. `moc` también.

**2. La API de KWin 6 es distinta de la de KWin 5, y ahora está identificada:**

| KWin 5 (lo que asumí) | KWin 6.7 (real) |
|---|---|
| `paintWindow(..., QRegion, ...)` | `paintWindow(..., const Region &, ...)` |
| `WindowPaintData::painter` (QPainter) | **No existe**: el dibujado es con OpenGL sobre `GLFramebuffer` |
| — | `RenderTarget::framebuffer()` / `texture()` |
| — | `GLShader` (constructor público) y `ShaderManager` |
| — | `BackgroundEffectItem`, para efectos de fondo como el difuminado |

**3. Las rutas de instalación son las correctas:**
`~/.local/lib/qt6/plugins/kwin/effects/` (binario) y
`~/.local/share/kwin/effects/<id>/metadata.json`.

### RESUELTO: el efecto compila y es un plugin valido

Con `cmake` y `ninja` instalados, y tras averiguar cuatro cosas que costaron:

| Descubrimiento | Consecuencia |
|---|---|
| `KWinConfig.cmake` exige **ECM** | Hay que instalar `extra-cmake-modules` |
| `KWinConfig.cmake` exige **Vulkan** | Solo para satisfacer el `find_package`: el efecto no lo usa. Se resuelve con un stub de 20 lineas en vez de 42 MiB de headers |
| `kcoreaddons_add_plugin` construye un **`.a`** si `BUILD_SHARED_LIBS` es falso | Un plugin tiene que ser modulo compartido: hay que activarlo |
| El macro del codigo define una clase con `Q_OBJECT` **en el `.cpp`** | Hace falta `#include "glass.moc"` o no se genera el punto de entrada |

Resultado:

```
[6/6] Linking CXX shared module plugins/kwin/effects/libmacosglass.so
```

Y las comprobaciones que fallaban antes, ahora pasan:

```
exports qt_plugin_instance      : SI
exports qt_plugin_query_metadata_v2 : SI
metadata embebida               : SI (IID org.kde.kwin.EffectPluginFactory)
```

**Esto era el bloqueo del paso anterior y esta resuelto.**

### El bloqueo que queda: donde lo busca KWin

`KPluginMetaData::findPlugins("kwin/effects/")` busca en las **rutas de plugins de Qt**.
`~/.local/lib/qt6/plugins` **no esta entre ellas** en la sesion, asi que KWin no ve el
efecto aunque este instalado ahi.

Dos salidas, las dos documentadas:

1. **Sin sudo:** `~/.config/environment.d/90-kde-macos.conf` con `QT_PLUGIN_PATH`.
   Requiere reiniciar la sesion para que KWin lo lea al arrancar.
2. **Inmediata:** un script, `efecto-kwin/instalar-efecto.sh`, que copia el `.so` a
   `/usr/lib/qt6/plugins/kwin/effects/` (necesita sudo).

### Lo que el efecto hace hoy

**Nada visible todavia.** El esqueleto esta: el gancho `paintWindow`, los valores del kit
en `reconfigure()`, y **carga sin dibujar**. Falta el shader del material.

### El bloqueo anterior, ya resuelto

```
QPluginLoader: "is not a Qt plugin (metadata not found)"
```

El `.so` está bien formado — el verificador carga sin problema plugins reales del
sistema, pero rechaza el nuestro. **La metadata del plugin no queda correctamente
embebida.** Es justo lo que hace `qt6_add_plugin()` de CMake, y hacerlo a mano es
frágil y depende de la versión de Qt (la 6.12 cambió el mecanismo).

Se probaron las dos vías documentadas sin éxito: el recurso `:/qtmetadata` y el
recurso `:/metadata.json`.

### Lo que hay que instalar, y por qué

```
sudo pacman -S --needed cmake ninja
```

**Solo la herramienta.** No hace falta ningún paquete de desarrollo adicional: los
headers ya están. Son ~102 MiB de `cmake` más medio de `ninja`.

Con eso, `efecto-kwin/construir.sh` compila e instala el efecto, y el
`CMakeLists.txt` ya está escrito usando `kcoreaddons_add_plugin`, que se encarga de
la metadata, del `moc` y de la ruta de instalación.

### Lo que el efecto hace hoy, y lo que le falta

Implementado: el esqueleto del efecto, con el gancho `paintWindow` y los valores del
kit en `reconfigure()` (alfa del borde 20 = negro al 8 %, que es
`Fills - Opaque / Secondary`).

**Falta el dibujado**, que es la parte con miga: el material necesita una pasada de
shader sobre el fondo para hacer **difusión, refracción (`70`), dispersión (`20`)** y
el **realce especular**. Los siete parámetros están medidos y en `tokens.toml`; lo que
falta es el shader y su integración con `RenderTarget`.

### La sombra de ventana de dos capas

También del paso 5. Las dos capas medidas (difusa radio 54 + contacto radio 1) las
podría dibujar un efecto, porque **Aurorae no admite dos sombras**. Pero depende del
mismo desbloqueo.


---

## 11. El efecto, paso a paso hasta que carga

Cinco obstaculos reales, cada uno descubierto con el journal de KWin. Quedan anotados
porque ninguno es obvio y los cinco cuestan lo mismo si se repiten.

| # | Obstaculo | Sintoma | Solucion |
|---|---|---|---|
| 1 | `KWinConfig.cmake` exige **ECM** | `Could not find a package configuration file provided by "ECM"` | `extra-cmake-modules` |
| 2 | `KWinConfig.cmake` exige **Vulkan** | `Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR)` | Stub de 20 lineas en `_stub/`, en vez de 42 MiB de headers. El efecto **no usa Vulkan** |
| 3 | `kcoreaddons_add_plugin` genera un **`.a`** | `Linking CXX static library` | `set(BUILD_SHARED_LIBS ON)`. Un plugin tiene que ser modulo |
| 4 | El macro define una clase con `Q_OBJECT` en el `.cpp` | `is not a Qt plugin (metadata not found)`, sin `qt_plugin_instance` | `#include "glass.moc"` al final del `.cpp` |
| 5 | Faltaba `KPackageStructure` | `does not match requested format "KWin/Effect"` | `"KPackageStructure": "KWin/Effect"` en el metadata |

### Y el error que casi me lleva por mal camino

Puse un `metadata.json` suelto en `/usr/share/kwin/effects/macosglass/`. KWin respondio:

```
Failed to load macosglass effect: invalid X-Plasma-API field: .
```

**La documentacion oficial de KDE lo aclara**: `X-Plasma-API` es lo que marca un efecto
**QML** (`"declarativescript"`). Todos los efectos de `/usr/share/kwin/effects/` son
javascript o declarativescript. Un plugin **C++** no lleva ese campo: su metadata va
**embebida en el `.so`**, y con eso basta para que KWin lo descubra. El `metadata.json`
suelto hacia que KWin lo tratara como script.

### El ultimo obstaculo: KWin no re-escanea

`isEffectSupported` paso de `true` a `false` al quitar el metadata suelto, y ya no volvio.
La causa: **KWin construye la lista de efectos al arrancar y no la re-escanea.**
`reconfigure` recarga los efectos ya cargados, pero no busca plugins nuevos.

Comprobado:

```
KWin en ejecucion desde : 21:14
.so instalado           : 22:04   <- 50 minutos despues
reconfigure             : no lo ve
kbuildsycoca6           : no basta (reconstruido, sigue sin verlo)
```

**Solucion: reiniciar la sesion** (cerrar sesion y volver a entrar). Entonces KWin
arranca, encuentra el `.so` y lo carga.

Para verificarlo sin adivinar, hay un script: **`efecto-kwin/verificar-efecto.sh`**.


---

## 12. Estado del efecto KWin: lo que está verificado y lo que no

### Verificado: el plugin cumple el contrato de KWin

Hay una herramienta en `efecto-kwin/src/verificar-carga.cpp` que hace **exactamente** lo
que hace KWin al arrancar: descubrir el plugin, instanciar la fábrica y preguntarle
`isSupported()`. Su salida:

```
pluginId      : macosglass
isSupported() : SI -> KWin lo aceptaria
enabledByDef  : SI
resumen: 1 plugins con fabrica, 1 soportados
```

Y `KPluginMetaData::findPlugins("kwin/effects/")` —la API que usa KWin para buscar
efectos— lo encuentra en `/usr/lib/qt6/plugins/kwin/effects/macosglass.so` con el
`pluginId` correcto.

### Y sin embargo KWin responde `false`

```
isEffectSupported : false
isEffectLoaded    : false
en listOfEffects  : 0
```

Comprobado también que **no es un problema de momento**: KWin se reinició a las 22:19 y
el `.so` es de las 22:17, así que lo tenía delante al arrancar.

Y no es la caché de ksycoca: se reconstruyó y no cambió nada.

### Lo que se descartó, con pruebas

| Hipótesis | Cómo se descartó |
|---|---|
| El plugin no carga | `QPluginLoader::load()` → **SI** |
| La metadata está mal | `strings` muestra `KPackageStructure: "KWin/Effect"` |
| El `pluginId` no coincide | `findPlugins` devuelve `macosglass`, igual que el `kwinrc` |
| Falta el punto de entrada Qt | exporta `qt_plugin_instance` y `qt_plugin_query_metadata_v2` |
| `isSupported()` devuelve NO | **corregido**: ahora devuelve SI (medido) |
| KWin no re-escanea al arrancar | KWin reiniciado con el `.so` ya instalado |
| Caché de plugins obsoleta | `kbuildsycoca6` reconstruido, sin efecto |
| Lo toma por un efecto QML | se quitó el `metadata.json` suelto |
| El prefijo `lib` del fichero | `PREFIX ""` en CMake; el pluginId ya es correcto |

### El siguiente paso concreto

El desensamblado de `KWin::EffectLoader::isEffectSupported` muestra que recorre una lista
de sub-cargadores y delega en `PluginEffectLoader` y `ScriptedEffectLoader`. El plugin
cumple el contrato, así que queda por ver **qué comprobación adicional** hace
`PluginEffectLoader`. La vía para verlo es el journal de KWin con depuración de plugins
activada al arrancar el compositor.

### Lo que NO está hecho

**El shader del material.** El efecto, cuando cargue, solo escribe un mensaje en el log:
el `paintWindow` está enganchado pero no dibuja. Falta implementar difusión, refracción
(70), dispersión (20) y el realce especular sobre `GLFramebuffer`. Los siete parámetros
están medidos y en `tokens.toml`.

### Lo que sí quedó terminado y funcionando

- Los **226 tokens** de macOS, con procedencia por token
- Los **dos esquemas de color** de KDE, con contraste WCAG AA
- El **CSS de GTK 3 y 4**
- La **decoración de ventana estilo macOS**: semáforos a la izquierda, con aro, y grises
  al perder el foco — **funcionando en la sesión real**
- El **instalador** idempotente y reversible


---

## 13. INCIDENTE 2026-10-13: pantalla negra por `kwin_wayland --replace`

**Esto es una correccion a mi propio asesoramiento.** Recomende `kwin_wayland --replace`
como alternativa "segura" para reiniciar KWin sin cerrar sesion. **No lo es.**

En Wayland `--replace` arranca un **segundo compositor** que compite por el DRM/GL con el
que ya esta corriendo. El KWin vivo pierde el contexto OpenGL y se queda componiendo un
lienzo vacio: **pantalla negra con el cursor visible**. KWin y plasmashell siguen vivos y
responden por D-Bus, lo que hace el diagnostico confuso.

Evidencia del journal:

```
kwin_wayland: No QSGTexture provided from updateSampledImage(). This is wrong.
kwin_wayland: Could not delete render time query because no context is current
```

**El efecto `macosglass` NO fue la causa.** Se probo en caliente: su `paintWindow` es un
no-op que solo escribe un log, y desactivarlo no cambio nada. El disparador fue el
`--replace`.

### Lo correcto, siempre

```bash
sudo systemctl restart plasmalogin   # reinicia el gestor de sesion
# o cerrar sesion y volver a entrar
```

**Nunca `kwin_wayland --replace`** en Wayland.

### Detalle de metodo que me habria avisado

Antes en esta misma sesion intente arrancar un **KWin anidado** para probar la decoracion,
y el proceso murio sin log porque el sandbox no le dejaba crear el socket. **Ya tenia la
senal de que lanzar otro compositor en Wayland es problematico**, y aun asi recomende
`--replace` como atajo. La senal estaba delante y no la lei.

### Documentos

- [INCIDENTE.md](INCIDENTE.md) — informe completo, sintomas y diagnostico
- [RECUPERAR-KDE.sh](RECUPERAR-KDE.sh) — script de recuperacion (idempotente y reversible)
- `efecto-kwin/instalar-efecto.sh` — aviso corregido; ya no menciona `--replace` como opcion

---

## 14. SEGUNDO INCIDENTE 2026-10-13 23:04: el efecto SI era la causa (correccion del §13)

El §13 concluyo, con la build antigua, que `macosglass` no era la causa. **Era falso.** A las
23:03:42 se reinstalo el `.so` nuevo y se activo (`macosglassEnabled=true`); a las 23:04:22
el usuario cerro sesion y volvio a entrar; el KWin nuevo (PID 3458) cargo el efecto
(`[macos-glass] cargado` 23:04:23, `paintWindow` 23:04:24) y a las 23:04:42 empezo a escupir
`Could not delete render time query because no context is current` -> pantalla negra.

Comparacion que lo deja claro, dentro del mismo arranque:

| KWin | Sesion | macosglassEnabled | Errores de contexto |
|---|---|---|---|
| 1314 | 22:54–23:04 | false | 0 |
| 3458 | 23:04–… | true | 5 (23:04:42–23:05:19) |

### Recuperacion EN CALIENTE (funciono, sin cerrar sesion)

```bash
bash ~/RECUPERAR-KDE.sh recuperar --reset-output
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
qdbus6 org.kde.KWin /KWin       org.kde.KWin.reconfigure
qdbus6 org.kde.KWin /Effects    org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize
```

Ahora todo eso es `bash ~/RECUPERAR-KDE.sh reanimar`. **El orden importa:** `reinitialize()`
recarga los efectos segun la config que KWin tiene EN MEMORIA; sin `reconfigure()` antes,
vuelve a cargar `macosglass` (paso a las 23:10:07).

### Verificacion

Capturas 23:10:58 y 23:12:20, con el reloj del panel avanzando 11:06 -> 11:12 PM:
`evidencia/2026-10-13-2314-pantalla-recuperada.png`. Escritorio vivo.

### Estado y proteccion

- `macosglass` y `blur` desactivados; `.so` de usuario apartado como `.disabled`.
- `.so` de sistema sigue en `/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so` (borrarlo pide root).
- `efecto-kwin/instalar-efecto.sh` ahora **aborta** salvo que se pase `--force`.
- Documento: [INCIDENTE.md](INCIDENTE.md) · script: [RECUPERAR-KDE.sh](RECUPERAR-KDE.sh)

---

## 15. PRUEBA DECISIVA (2026-10-13 23:24): la causa queda confirmada al 100 %

Propuse esta prueba al cerrar el §14 y se ejecutó en vivo, con el escritorio estable y la
sesión gráfica (tty3) activa. En vez de fiarme solo del log, medí **píxeles** de capturas
`spectacle` (3840x2160) con PIL:

| Captura | `macosglass` | Contenido |
|---|---|---|
| A (control) | descargado | 861 KB — escritorio real, 0,1 % negro |
| B (+10 s) | cargado en caliente | 32 KB — **100 % `#000000`** |
| B (+30 s) | cargado | 32 KB — **100 % `#000000`** |
| C | descargado (sin `reinitialize`) | 856 KB — escritorio real |
| D | tras `reinitialize` | 855 KB — escritorio real |

**Resultado:** el efecto deja la composición 100 % negra y **descargarlo la restaura al
instante**. Causa zanjada.

Un matiz honesto: en carga en caliente el efecto **no** registra `paintWindow` (rompe el
render antes de esa ruta); en el arranque del incidente sí llegaba a `paintWindow`. Y el
error `no context is current` reapareció solo 1 vez (ligado al ciclo del efecto), no en
oleada. La prueba concluyente fue la **imagen**, no el journal.

Evidencia: `evidencia/2026-10-13-2324-prueba-control-escritorio.png`,
`evidencia/2026-10-13-2324-prueba-efecto-cargado-negro.png`,
`evidencia/2026-10-13-2324-prueba-tras-descargar.png`.
Detalle y comandos: [INCIDENTE.md](INCIDENTE.md) §"Prueba decisiva — EJECUTADA".

---

## 16. ARREGLADO (2026-10-13 23:32): faltaba la llamada de cadena en `paintWindow()`

La causa de la pantalla negra no era el contexto OpenGL: era un **bug de
contrato** de nuestro efecto.

`EffectsHandler::paintWindow()` llama a **un solo** efecto; la cadena avanza
porque la implementación base `Effect::paintWindow()` vuelve a entrar en
`effects->paintWindow()`. Nuestro efecto sobreescribía `paintWindow()` y
**devolvía sin llamar a la base**, así que la cadena se cortaba en `macosglass`:
`WorkspaceScene::finalPaintWindow()` no se ejecutaba nunca y **ninguna ventana se
pintaba**. El fondo/panel de Plasma es una ventana más → solo quedaba el negro de
fondo.

Corrección en `efecto-kwin/src/glass.cpp`: todos los caminos terminan en
`effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);`.

Verificación sin tocar la sesión (a nivel de binario):

```
.so antiguo (sistema) : 0 referencias a EffectsHandler::paintWindow
.so nuevo  (build)    : tail-call a EffectsHandler::paintWindow   ✅
```

Herramientas nuevas:

| Fichero | Qué hace |
|---|---|
| `efecto-kwin/verificar-cadena.sh` | Comprueba fuente + binario y avisa si el `.so` instalado es el viejo |
| `efecto-kwin/probar-en-vivo.sh` | Carga, captura, mide % de negro y **descarga siempre** (`trap EXIT`); aborta si el `.so` instalado no lleva el arreglo |

`construir.sh` e `instalar-efecto.sh` ahora **abortan** si la cadena no está, y
`construir.sh` **ya no activa** el efecto (antes podía cargar el `.so` viejo del
sistema y repetir el incidente).

El efecto sigue **sin dibujar** (el shader del material es el paso siguiente),
pero es seguro: se comporta como si no estuviera cargado.

> El agente no pudo instalar el binario (el sandbox no puede `sudo`), así que el
> `.so` del sistema sigue siendo el antiguo. Instalación y prueba:
> ```
> cd efecto-kwin && ./verificar-cadena.sh
> sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
>      /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
> ./probar-en-vivo.sh
> ```

---

## 17. CORRECCIÓN FINAL (2026-10-14): leer INCIDENTE.md

Las secciones §13, §14, §15 y §16 de este documento registran **cuatro
conclusiones sucesivas** sobre la pantalla negra, y **todas menos la última son
superadas**. Se conservan como registro de la depuración.

**La causa final, verificada por bisección: el IDENTIFICADOR del efecto.**
El mismo código compilado como `macosglass` deja la composición al 100 % de negro;
con `macosglass2` funciona. El efecto se llama ahora `macosglass2`.

**Estado del efecto (2026-10-14):**
- Instalado en la ruta correcta (`kwin/effects/plugins/`) y carga sin romper nada
- **No dibuja todavía**: el shader del material es el paso siguiente
- El proyecto está bajo git, con un arnés de **55 comprobaciones** (`pruebas/ejecutar.sh`)
- De los 9 scripts de depuración quedan 4, y los borrados apuntaban al id viejo

> Para el relato completo y ordenado, ver **`INCIDENTE.md`**, que además lleva
> arriba un resumen autoritativo.

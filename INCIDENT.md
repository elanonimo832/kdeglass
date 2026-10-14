# INCIDENTE: pantalla negra en KDE Plasma (CachyOS) — 2026-10-13 / 14

> ## ⚠️ ESTE DOCUMENTO ES HISTÓRICO: contiene conclusiones SUPERADAS
>
> Se escribió a lo largo de dos sesiones, y cada vez que encontrábamos una causa
> nueva quedaba registrada sin borrar la anterior. Hay **cuatro conclusiones
> sucesivas** y solo la última es correcta.
>
> ## La causa, en una línea
>
> **El identificador del efecto.** El mismo código, byte a byte, compilado como
> `macosglass` dejaba la composición al **100 % de negro**, y con un id nuevo
> (`macosglass2`) funciona. Medido con capturas y análisis de píxeles.
> El efecto se llama ahora `macosglass2`.
>
> ## Lo que NO era la causa (aunque lo pareciera en su momento)
>
> | Conclusión que quedó escrita | Estado |
> |---|---|
> | «El efecto no era la causa» (build antigua) | **falso** |
> | «El contexto OpenGL / scene-graph» | síntoma, no causa |
> | «Faltaba la llamada de cadena en `paintWindow()`» | era **un fallo real**, pero no el que rompía |
> | «El identificador `macosglass`» | **✅ correcto** (lo confirma la bisección) |
>
> ## Lo que sí quedó arreglado y sigue vigente
>
> 1. **La cadena de pintado.** `paintWindow()` TIENE que llamar a
>    `effects->paintWindow()`. Es un fallo real y lo comprueba `verify-chain.sh`.
> 2. **`supported()`** devolvía `false` (`effects != nullptr`, el ejemplo de la doc
>    de KDE) y KWin descartaba el efecto EN SILENCIO.
> 3. **La ruta** es `kwin/effects/plugins/`, no `kwin/effects/`. Un nivel. Dos horas.
> 4. **El nombre del fichero define el pluginId**, sin prefijo `lib`.
> 5. **Nunca `kwin_wayland --replace`** en Wayland: deja la pantalla negra.
>
> ## Cómo recuperarse
>
> ```bash
> bash ~/RECOVER-KDE.sh reanimar     # en caliente, sin cerrar sesión
> ```
>
> ---
>
> *Lo que sigue es el registro histórico, en orden cronológico inverso al final.
> Las conclusiones antiguas se conservan a propósito: muestran cómo se llegó a la
> buena, y qué señales se leyeron mal.*



# ✅ ARREGLADO — 2026-10-13 23:32: causa raíz exacta y corrección

La causa **no** era el contexto OpenGL ni la compilación: era **una llamada que
faltaba** en `MacosGlassEffect::paintWindow()`.

## La regla de la cadena de pintado de KWin

El código de KWin 6.7.5 (`src/effect/effecthandler.cpp`) llama a **un solo**
efecto por invocación:

```cpp
void EffectsHandler::paintWindow(...)
{
    if (m_currentPaintWindowIterator != m_activeEffects.constEnd()) {
        (*m_currentPaintWindowIterator++)->paintWindow(...);  // UN efecto
    } else {
        m_scene->finalPaintWindow(...);                       // dibuja la ventana
    }
}
```

La cadena avanza porque la implementación **base** (`Effect::paintWindow`,
`src/effect/effect.cpp`) vuelve a entrar:

```cpp
void Effect::paintWindow(...)
{
    effects->paintWindow(...);   // -> siguiente efecto, o finalPaintWindow()
}
```

Nuestro efecto **sobreescribía `paintWindow()` y devolvía sin llamar a
`effects->paintWindow()`** en ningún camino. Cuando la cadena llegaba a
`macosglass`, se cortaba: `WorkspaceScene::finalPaintWindow()` no se ejecutaba
**nunca** y **ninguna ventana se dibujaba**. El fondo del escritorio de Plasma es
una ventana más, así que solo quedaba el color de fondo del compositor: **negro**.

Esto explica todos los síntomas: KWin y plasmashell vivos por D-Bus (el proceso no
se cae), `Compositing is active` (el compositor funciona), pero el scene-graph
nunca recibe la orden de pintar. El cursor lo pinta KWin por otra vía, de ahí que
se viera sobre el negro.

## La corrección

`effect-kwin/src/glass.cpp`: **todos** los caminos de `paintWindow()` terminan en

```cpp
effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
```

Comprobado a nivel de binario (sin cargarlo en la sesión):

```
.so antiguo (sistema) : 0 referencias a EffectsHandler::paintWindow   <- roto
.so nuevo  (build)    : tail-call a EffectsHandler::paintWindow       <- OK
```

## Qué hace ahora el efecto

Sigue **sin dibujar nada** (el shader del material es el paso siguiente). Pero ya
no rompe la cadena: a efectos de pintado se comporta como si no estuviera
cargado. `effect-kwin/verify-chain.sh` lo comprueba automáticamente (fuente +
binario) y `build.sh` / `install.sh` **abortan** si la cadena no está.

## Cómo probarlo

```bash
cd "~/Projects/Deepseek Harness/analisis-kde-macos/effect-kwin"
./verify-chain.sh                      # fuente + binario
sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
     /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
./probar-en-vivo.sh                        # carga, captura, mide y DESCARGA solo
```

`probar-en-vivo.sh` descarga el efecto **siempre** (`trap EXIT`) aunque el render
se rompiera, y se niega a empezar si el `.so` instalado no lleva el arreglo. Si
algo fuera mal de todos modos: `bash ~/RECOVER-KDE.sh reanimar`.

> Nota: el agente no pudo instalar el `.so` (el sandbox no puede `sudo`), así que
> el binario del sistema **sigue siendo el antiguo** hasta que se ejecute el
> `sudo install` de arriba. El `.so` arreglado está en
> `effect-kwin/build/plugins/kwin/effects/macosglass.so`.

## Resumen en una línea
Se carga el efecto KWin propio `macosglass` (build compilada por nosotros) y la sesión
Plasma queda en **pantalla negra con el cursor visible**. KWin y plasmashell **siguen
vivos** (responden por D-Bus) y el compositor incluso dice `Compositing is active`,
pero deja de renderizar por un fallo del **contexto OpenGL / scene-graph**.

---

# ACTUALIZACIÓN 2026-10-13 23:12 — SEGUNDO INCIDENTE

## Qué volvió a pasar (cronología exacta)
| Hora | Hecho |
|---|---|
| 22:54 | Arranque (boot 0). Sesión gráfica **con `macosglassEnabled=false`**: funcionó (KWin 1314, **0** errores de contexto). |
| 23:03:42 | El usuario reinstala el `.so` nuevo: `sudo install build/plugins/kwin/effects/macosglass.so /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`. `kwinrc` queda con `macosglassEnabled=true`. |
| 23:04:22 | Logout/login. Nueva sesión Wayland (sesión 5, **tty3**). `startplasma-wayland`. |
| 23:04:23 | KWin **3458** arranca y carga el efecto: `[macos-glass] cargado. Borde oscurecido activo, alfa 20`. |
| 23:04:24 | `[macos-glass] paintWindow alcanzado para ""`. El efecto entra en la ruta de pintado. |
| 23:04:42–23:05:19 | 5× `kwin_wayland[3458]: Could not delete render time query because no context is current` → **pantalla negra**. |
| 23:05:54 | El usuario entra a tty2 (sesión 6) para hablar con el agente. |
| 23:10:01 | `RECOVER-KDE.sh recuperar --reset-output` (backup `20261013-231001`). |
| 23:10:07 | `Compositing.reinitialize()` → recrea el backend GL y **vuelve a cargar** macosglass (config en memoria). |
| 23:10:32 | `reconfigure()` + `unloadEffect macosglass` → efecto fuera, `macosglassEnabled=false` en disco. |
| 23:10:58 / 23:12:20 | Capturas: escritorio **renderizado y vivo** (el reloj del panel avanza 11:06 → 11:12 PM). |

## Recuperación EN CALIENTE (funcionó; no hizo falta reiniciar)
```bash
bash ~/RECOVER-KDE.sh recuperar --reset-output      # backup + desactiva macosglass/blur
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

qdbus6 org.kde.KWin /KWin     org.kde.KWin.reconfigure                  # que KWin relea kwinrc
qdbus6 org.kde.KWin /Effects  org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize   # recrea el contexto GL
```
O, en una línea, `bash ~/RECOVER-KDE.sh reanimar` (nuevo comando del script).

**Orden importa:** `reinitialize()` **recarga los efectos según la configuración que KWin
tiene EN MEMORIA**. Si no se ha llamado antes a `reconfigure()`, KWin todavía cree que
`macosglassEnabled=true` y **vuelve a cargar el efecto** (así pasó a las 23:10:07).
Por eso: `reconfigure` → `unloadEffect` → (y si hace falta) `reinitialize`.

## Evidencia de que `macosglass` es el disparador (esto CORRIGE la conclusión anterior)
- KWin **1314** (sesión de 22:54–23:04, `macosglassEnabled=false`): **0** errores de contexto, escritorio OK.
- KWin **3458** (sesión de 23:04, `macosglassEnabled=true`): `[macos-glass] cargado` → `paintWindow` → **5** `no context is current` en 37 s.
- Es el único efecto no estándar cargado; con él descargado y el backend recreado, los errores **desaparecen**.

> **Corrección honesta:** en la primera sesión (22:40+) escribí «El efecto `macosglass`
> NO fue la causa; su `paintWindow` es un no-op». Eso era cierto para la build antigua y
> para el proceso ya roto, pero **la conclusión era errónea**: el segundo incidente
> demuestra que cargar el efecto es lo que rompe el render. Su `paintWindow` es un no-op,
> pero el plugin (compilado contra KWin 6.7.5 / Qt 6.12) deja el contexto OpenGL inválido
> al entrar en la ruta de pintado.

## Prueba decisiva — EJECUTADA (2026-10-13 23:24–23:26): CAUSA CONFIRMADA

Se ejecutó en vivo con el escritorio estable y la sesión gráfica (**tty3**) activa, usando
capturas `spectacle` (3840x2160) como testigo objetivo y análisis de píxeles con PIL.

| Captura | Estado de `macosglass` | Contenido medido |
|---|---|---|
| A (control) | **descargado** | 861 KB — escritorio real, **0,1 %** de píxeles negros |
| B (+10 s) | **cargado** en caliente | 32 KB — **100 % `#000000`** |
| B (+30 s) | **cargado** | 32 KB — **100 % `#000000`** |
| C | recién **descargado** (sin `reinitialize`) | 856 KB — escritorio real |
| D | tras `reinitialize` | 855 KB — escritorio real |

**Conclusión (zanjado):** cargar `macosglass` en el KWin vivo **deja la composición en negro
al 100 %** — la misma pantalla negra del incidente — y **descargarlo la restaura al
instante**, sin cerrar sesión ni `reinitialize`. El efecto es la causa, sin ambigüedad.

Matiz que corrige/afina lo anterior: en carga en caliente `[macos-glass] paintWindow`
**no** llega a registrarse (el render se rompe antes de esa ruta); en el arranque del
incidente sí se registraba (23:04:24). La línea `Could not delete render time query because
no context is current` reapareció, pero de forma **esporádica** (1 vez, ligada al ciclo del
efecto / `reinitialize`), no en oleada como al arrancar. Por eso la prueba de fuego es la
**captura**, no el log.

Evidencia en `analisis-kde-macos/evidence/`:
`2026-10-13-2324-prueba-control-escritorio.png`,
`2026-10-13-2324-prueba-efecto-cargado-negro.png`,
`2026-10-13-2324-prueba-tras-descargar.png`.

### Reproducir la prueba
```bash
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
loginctl activate 5                     # activar la sesión gráfica (tty3)
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect macosglass   # -> pantalla negra
# comparar capturas (spectacle -b -n -o /tmp/a.png): la primera ya sale negra
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass # -> restaura YA
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize    # opcional
```

---

# DOCUMENTO ORIGINAL (primer incidente, 22:19–22:54)

## Síntoma
- Pantalla negra, cursor del ratón visible y moviéndose.
- `loginctl`: la sesión gráfica está `online`; KWin (6.7.5) y plasmashell responden en el bus.
- KWin ve bien la salida: HDMI-A-1, 3840x2160, scale 1, `Compositing is active`,
  OpenGL sobre AMD Radeon 780M (radeonsi, Mesa 26.2.4).

## Disparadores conocidos (los dos que rompieron)
1. **`kwin_wayland --replace`** en Wayland (primer incidente, 22:19:49). Arranca un
   **segundo compositor** que compite por el DRM/GL. En el arranque anterior dejó:
   ```
   Failed to find a working output layer configuration!
   Applying output configuration failed!
   ```
2. **Cargar el efecto `macosglass`** en una sesión nueva (segundo incidente, 23:04).
   Ver la actualización de arriba.

## Evidencia clave (journal de la sesión de usuario)
Al forzar un re-render (cambiar tema/esquema), a las 22:50:05 KWin empezó a inundar
el journal con:
```
kwin_wayland[1315]: No QSGTexture provided from updateSampledImage(). This is wrong.
kwin_wayland[1315]: Could not delete render time query because no context is current
```
=> **El contexto OpenGL no está activo durante el render**: KWin compone un lienzo
vacío (negro). Es un estado del proceso KWin.

Otras pistas:
- `kwin_wayland[1069]: Failed to create framebuffer: Invalid argument` (greeter, 1 vez).
- `atomic commit failed: Permission denied` => **ruido benigno** de cambios de VT
  (tty2 <-> tty3); también sale al ejecutar `loginctl activate`. NO es la causa.
- `plasmashell[1450]: The requested buffer size is too big, ignoring` => viene de
  `libQt6Svg`; secundario.

## Limitación importante del agente (DSH) — no te fíes a ciegas de las capturas
El sandbox de comandos usa `bwrap ... --dev /dev`, por lo que:
- **`/dev/dri` NO existe** dentro del sandbox (sin GPU / render node).
- `/dev/shm` a veces es de solo lectura (en esta sesión del 23:06 sí era escribible).
- KWin normalmente deniega `org.kde.KWin.ScreenShot2` a procesos no autorizados.
=> Las capturas con `spectacle` lanzadas por el agente **pueden** salir negras aunque la
pantalla esté bien. La fuente de verdad final es lo que ve el usuario. **Pero** una captura
que muestra contenido y cuyo reloj avanza sí es prueba positiva de que el escritorio renderiza
(eso pasó a las 23:10:58 y 23:12:20).

## Estado que dejé (2026-10-13 23:12)
`~/.config/kwinrc`:
- `[Plugins] macosglassEnabled=false`, `blurEnabled=false`
- `[org.kde.kdecoration2]` sin `theme`/`library` (decoración por defecto)
`~/.config/kdeglobals`:
- `ColorScheme=BreezeDark`
`~/.config/kwinoutputconfig.json`:
- Apartado a `~/.local/state/kde-macos/incidente-recuperacion/20261013-231001/` (KWin lo regenera).
Efecto:
- **Descargado en caliente** del KWin vivo (`isEffectLoaded=false`, activo `activeEffects` vacío).
- `.so` de usuario apartado: `~/.local/lib/plugins/kwin/effects/libmacosglass.so.disabled-20261013-231244`.
- `.so` de sistema **sigue instalado** (borrarlo requiere root):
  `/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`. Es inerte mientras esté desactivado.
- Para quitarlo del todo (lo más recomendable):
  `sudo rm /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`
Backups:
- `~/.cache/kwinrc.before-exp-<epoch>`
- `~/.local/state/kde-macos/incidente-recuperacion/` (incluye `20261013-231001/`)
Otros cambios del proyecto (reversibles): temas aurorae/GTK/esquemas en `~/.local/share/…`.

## Pasos de recuperación (en orden)
0. **Recuperación en caliente, sin cerrar sesión** (probada el 2026-10-13 23:12):
   ```
   bash ~/RECOVER-KDE.sh reanimar
   ```
   Si el script no está, los 4 comandos de "Recuperación EN CALIENTE" de arriba.
1. Si sigue negro, cambiar a la sesión gráfica con **Ctrl+Alt+F<n>**, donde `<n>` es la
   TTY de la sesión *wayland* (el 23:04 era **tty3**, no tty2; el script lo calcula solo):
   ```
   loginctl list-sessions            # busca la de TYPE=wayland y mira su TTY
   ```
2. Si sigue negro, reiniciar el gestor de sesión o el equipo:
   ```
   sudo systemctl restart plasmalogin     # cierra la sesión; vuelve el login
   # o
   sudo reboot
   ```
   Con `macosglass` y `blur` ya desactivados, KWin arranca sin ellos.
3. Si tras reiniciar sigue negro:
   ```
   bash ~/RECOVER-KDE.sh recuperar --reset-output
   sudo reboot
   ```
4. Si aun así sigue negro, probar con un **usuario nuevo** (config limpia) para
   descartar `~/.config`:
   ```
   sudo useradd -m prueba && sudo passwd prueba
   ```
   Si con el usuario nuevo se ve bien => el problema está en la config de `jracosta`.
   Renombrar/restaurar: `~/.config/kwinrc`, `~/.config/kdeglobals`,
   `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, `~/.config/kwinoutputconfig.json`.

## Rehabilitar el aspecto macOS
El efecto `macosglass` **ya no rompe la sesión** (arreglado 2026-10-13 23:32; ver
la sección de arriba). Aun así **todavía no dibuja nada**: es seguro, pero inerte.

Lo que sí cambia el aspecto y no toca el render:
```
cd "/home/jracosta/Projects/Deepseek Harness/analisis-kde-macos"
./install-decoration.sh aplicar --si --activar
# Color:  Ajustes -> Apariencia -> Colores -> KdeMacosLight/Dark
```
Si quieres volver a probar el efecto (ya arreglado), instala el binario nuevo y
usa la prueba con red de seguridad (**nunca** `kwin_wayland --replace`):
```
cd effect-kwin
./verify-chain.sh
sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
     /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
./probar-en-vivo.sh          # carga, mide y descarga solo
```
`RECOVER-KDE.sh revertir` reaplica todo de golpe (bajo tu riesgo).

## Comandos de diagnóstico útiles
```
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation | sed -n '/Compositing/,/Effect Settings/p'
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass
qdbus6 org.kde.KWin /Compositor org.freedesktop.DBus.Properties.Get org.kde.kwin.Compositing openGLIsBroken
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
kscreen-doctor -o                        # desde el sandbox puede abortar (core dumped); es normal
loginctl list-sessions; loginctl show-session <id> -p Type -p TTY -p Active
journalctl --user -b | grep -iE 'macos-glass|QSGTexture|context is current|atomic|kwin|plasmashell'
ls -la /dev/dri /dev/shm                 # dentro del sandbox /dev/dri no existe
```

## Cronología
**Primer incidente**
- 21:12 instalador de esquemas de color (kdeglobals)
- 21:36 decoración KdeMacOS
- 21:52–22:25 compilación e instalación del efecto macosglass
- 22:19:49 `kwin_wayland --replace` -> rompe la sesión
- 22:27 reboot
- 22:28 login -> pantalla negra
- 22:34–22:38 sesión de diagnóstico previa (no cambió nada)
- 22:40+ sesión de diagnóstico y cambios reversibles (origen de este documento)
- 22:54 reboot con `macosglassEnabled=false`

**Segundo incidente**
- 22:54–23:04 boot 0, sesión con el efecto desactivado: funcionó (KWin 1314, 0 errores)
- 23:03:42 sudo install del `.so` nuevo; `macosglassEnabled=true`
- 23:04:22 logout/login en **tty3**; KWin 3458
- 23:04:23 `[macos-glass] cargado`; 23:04:24 `paintWindow` alcanzado
- 23:04:42–23:05:19 5× `no context is current` -> pantalla negra
- 23:05:54 login en tty2 (sesión 6) para usar DSH
- 23:10:01 `RECOVER-KDE.sh recuperar --reset-output` (backup `20261013-231001`)
- 23:10:07 `reinitialize()` (recarga macosglass), 23:10:32 `reconfigure`+`unloadEffect`
- 23:10:58 / 23:12:20 capturas: escritorio recuperado y **vivo** (reloj avanzando)
- 23:12:44 `.so` de usuario apartado como `.disabled-20261013-231244`

---

# RESUELTO — 2026-10-14: la causa era el IDENTIFICADOR del efecto

## El hallazgo

Bisección con un **efecto mínimo** (una clase que solo se carga y no hace nada) y
medición objetiva del negro en pantalla (capturas `spectacle` + PIL):

| Variante | Código | id del plugin | negro en pantalla |
|---|---|---|---|
| `bisect.so` | mínimo | `bisect` | **0 %** ✅ |
| `testglass2.so` | mínimo | `testglass2` | **0 %** ✅ |
| `macosglass` (completo) | implementación completa | `macosglass` | **100 %** ❌ |
| `macosglass` sin `paintWindow` | menos código | `macosglass` | **100 %** ❌ |
| `macosglass` sin `Q_PROPERTY` | clase casi vacía | `macosglass` | **100 %** ❌ |
| `macosglass` **con el código del mínimo** | **el mismo que funciona** | `macosglass` | **100 %** ❌ |
| implementación completa renombrada | **completo** | **`macosglass2`** | **0 %** ✅ |

**El mismo código, byte a byte, funciona con un id y rompe con otro.**

## La conclusión

**No era el código.** Ni `paintWindow`, ni la llamada de cadena, ni los `Q_PROPERTY`,
ni los miembros, ni el `.h`/`.cpp`, ni el CMake, ni las dependencias (los `.so` tienen
las **mismas 23** en los dos casos), ni la ruta de instalación.

Era **el identificador `macosglass`** — que venía de toda la cadena de intentos fallidos
de esta sesión (plugin sin metadata, con el `Id` declarado, con nombre `libmacosglass`,
instalado en la ruta equivocada...).

## El arreglo

El efecto se instala como **`macosglass2`**. `install.sh` limpia los restos del
id viejo y de los plugins de prueba.

## Lo que NO puedo explicar

**Por qué** un id concreto rompe el render. El estado observable era idéntico al del id
que funciona: misma metadata embebida (`KPackageStructure: "KWin/Effect"`), mismo
`isSupported()`, mismo `enabledByDefault`, misma ruta. No he encontrado la diferencia.

Es un dato para el equipo de KWin: *«un plugin de efecto con id X deja la composición al
100 % de negro, y el mismo binario renombrado a Y funciona»*. Queda anotado como
observación reproducible, no como diagnóstico.

## Lo que queda arreglado de verdad

- La **cadena de pintado**: el efecto **tiene** que llamar a `effects->paintWindow()`.
  Era un fallo real (y sigue siéndolo si alguien lo quita). Ver `verify-chain.sh`.
- `supported()` devolvía `false` porque usaba `effects != nullptr` (el ejemplo de la doc
  de KDE), y KWin descartaba el efecto en silencio.
- La ruta de instalación es `kwin/effects/plugins/` (KWin::PluginEffectLoader).
- El nombre del fichero define el pluginId: sin prefijo `lib`.
- **Nunca `kwin_wayland --replace`**: deja la pantalla negra.

## Estado final

El efecto `macosglass2` carga **sin romper nada** y está enganchado a la cadena de
pintado. **No dibuja todavía**: el shader del material (difusión, refracción 70,
dispersión 20, realce especular) es el paso siguiente. Los siete parámetros están medidos
en `tokens.toml`.


---

# VERIFICADO — 2026-10-14 00:XX: el efecto funciona en un arranque limpio

Tras reiniciar el equipo (sudo restaurado), con **solo `macosglass2.so`** en la ruta de
KWin y los tres plugins de prueba eliminados:

```
control          : negro=  0.0%
macosglass2      : negro=  0.0%   <- EL EFECTO FUNCIONA
tras-descargar   : negro=  0.0%
VEREDICTO: NO lo rompe
```

El script `test-installed.sh` lo hace sin sudo (no reinstala nada: carga, mide y
descarga con `trap EXIT`).

## Estado final del efecto

```
.plugin        : /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
tamano         : 38824 bytes
cadena pintado : 3 referencias a EffectsHandler::paintWindow
pluginId       : macosglass2            (el nombre del fichero manda)
isEffectSupported : true
kwinrc         : [Plugins] macosglass2Enabled=true, blurEnabled=false
```

## Otro fallo propio, corregido: `grep -q` en un pipe

La comprobacion de seguridad de `install.sh` (`objdump | grep -q`) daba un
resultado **NO DETERMINISTA** con `set -o pipefail`: `grep -q` aborta al encontrar la
coincidencia y cierra el pipe, y el estado del pipe varia. Llegaba a **abortar la
instalacion de un `.so` correcto** (paso dos veces).

Corregido en `install.sh`, `verify-chain.sh` y `probar-en-vivo.sh`:
`grep -c ... >/dev/null` en lugar de `grep -q`. Leer toda la entrada es determinista.
Comprobado 8/8 y 15/15.

Leccion: una comprobacion de seguridad que da falsos positivos es peor que no tenerla,
porque hace dudar de algo que esta bien.

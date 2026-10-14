# Anexo · Verificación de supuestos del brief

Registro de qué se comprobó, con qué evidencia y con qué grado de confianza. Se
mantiene separado del [ANALISIS.md](ANALISIS.md) para que las conclusiones no dependan
de enlaces externos.

**Niveles de confianza usados:**

- **Confirmado** — hay fuente externa citada que lo sostiene.
- **Conocimiento del dominio** — se apoya en cómo funcionan Qt/KDE/GTK, sin fuente
  citada en este documento. Verificable en el propio sistema con los comandos indicados.
- **Inferencia** — razonamiento a partir de lo anterior, no un hecho comprobado.

---

## 1. Estado de macOS 27 «Golden Gate»

| Supuesto del brief | Confianza | Evidencia |
|---|---|---|
| macOS 27 se llama «Golden Gate» | **Confirmado** | [Gigazine](https://gigazine.net/news/20260609-apple-wwdc26-macos-27/) lo reporta como nombre en clave con WWDC26 de fondo; [Macwelt](https://www.macwelt.de/article/3167570/golden-gate-der-letzte-spitzname-fur-macos.html) lo trata como el posible último apodo |
| macOS 27 corrige los defectos de Liquid Glass | **Confirmado** | [RTBF](https://beta.rtbf.be/article/macos-27-apple-va-revoir-son-interface-liquid-glass-pour-repondre-aux-critiques-11722252), [iPhoneSoft](https://iphonesoft.fr/2026/05/10/macos-27-corriger-defauts-liquid-glass-mac) y [HWUpgrade](https://www.hwupgrade.it/news/apple/macos-27-apple-corregge-il-tiro-sul-liquid-glass-e-risolvere-i-difetti-grafici_153427.html) lo enmarcan explícitamente como respuesta a las críticas |
| Tahoe / macOS 26 fue el Liquid Glass inicial y muy criticado | **Confirmado** | Las mismas fuentes describen las críticas de contraste y legibilidad |
| Los tokens concretos del brief (radios, opacidades) | **No verificado** | Ninguna fuente consultada confirma los valores numéricos ni que las correcciones sean exactamente las siete listadas. El brief los presenta como hechos; son plausibles pero **no cotejados** |

**Implicación:** el brief es correcto en el marco general y no verificado en el detalle.
Los valores de tokens deben tratarse como **borrador a validar contra el sistema final**,
no como especificación. Esto refuerza la recomendación de versionar los tokens (§4.4 del
análisis).

---

## 2. Recorte de esquinas en KWin

| Supuesto | Confianza | Evidencia |
|---|---|---|
| Existe un efecto KWin que redondea esquinas de todas las ventanas | **Confirmado** | [LightlyShaders](https://github.com/a-parhom/LightlyShaders) (esquinas + contorno) y su [puerto a Plasma 6](https://github.com/walterfang12/LightlyShaders-Plasma6); [kwin-effect-rounded-corners](https://github.com/ekaaty/kwin-effect-rounded-corners); [paquete en Launchpad](https://launchpad.net/~matinlotfali/+archive/ubuntu/kde-rounded-corners) |
| El efecto se aplica a ventanas de apps ajenas (GTK incluidas) | **Confirmado** (por la existencia y uso de esos proyectos) | Los efectos KWin actúan en la fase de composición, con independencia del toolkit del cliente |
| «Redondear» y «recortar» son lo mismo | **Falso** | Inferencia directa del mecanismo: redondear pinta transparencia fuera de la forma; recortar elimina píxeles dibujados. Ver §3 A4 del análisis |
| El radio será único para todas las ventanas | **No garantizable** | El efecto solo controla el borde exterior; un cliente con decoración propia (CSD) aporta su propio radio interno |

**Implicación:** la parte del brief que más escepticismo merecía es, de hecho, **la más
respaldada por precedentes**. El efecto KWin sube de prioridad.

---

## 3. QStyle propio en Plasma 6

**Actualización:** este apartado era el de **menor respaldo documental** del análisis
(era una ausencia, y las ausencias no se citan bien en la web). Tras verificar
directamente el sistema, es ahora **el mejor confirmado**. Evidencia directa:

```
kcm_style.so presente en /usr/lib/qt6/plugins/plasma/kcms/systemsettings/
cadenas internas del binario:
    settingName: "widgetStyle"
    widgetStyle / WidgetStyle / widgetStyleChanged / defaultWidgetStyleValue
    isWidgetStyleImmutable
~/.config/kdeglobals            ->  [KDE] widgetStyle=kvantum
/usr/lib/qt6/plugins/styles/    ->  breeze6.so, libkvantum.so
```

| Supuesto | Confianza | Cómo verificarlo en tu sistema |
|---|---|---|
| El estilo se selecciona con la clave `widgetStyle` de `kdeglobals`, en la seccion **[KDE]** | **Confirmado** en el kdeglobals real (no en `[General]`, como supuse al principio) | `kreadconfig6 --file kdeglobals --group KDE --key widgetStyle` |
| Plasma 6 conserva el KCM «Estilo de las aplicaciones» | **Confirmado** | *Configuración del sistema → Apariencia*; `kcm_style.so` presente |
| Plasma 6 **no ofrece estilo por aplicación** (a diferencia de Plasma 5) | **Conocimiento del dominio** | No hay selector por app en el KCM; el mecanismo es una clave global |
| Un QStyle de terceros puede estar activo **sin** `QT_STYLE_OVERRIDE` | **Confirmado** | Kvantum está activo en este equipo y `env` no muestra `QT_STYLE_OVERRIDE` |
| Existe `isWidgetStyleImmutable`, que puede anular la clave | **Confirmado** (cadena en el binario) | Si el paso 4 falla en silencio, comprobar esto antes que el QStyle |
| Qt 6 carga plugins de estilo desde un directorio de plugins | **Conocimiento del dominio** | `/usr/lib/qt6/plugins/styles` existe; **falta comprobar** si Qt6 explora `~/.local/lib/qt6/plugins` (ver §6) |
| Un QStyle no se puede generar desde JSON | **Conocimiento del dominio** | `QStyle` es una clase C++ con métodos virtuales de dibujo y métricas |
| El brief no menciona el mecanismo de activación | **Confirmado por lectura** | El brief no contiene `widgetStyle`, `QT_STYLE_OVERRIDE`, `.desktop` ni `environment.d` |

**Corrección de mi propio análisis:** en la primera versión afirmé que hacía falta
`QT_STYLE_OVERRIDE` más un mecanismo de lanzamiento. Era **demasiado pesimista**: el
requisito (el brief ignoraba la activación) era cierto, pero la solución es **una clave
de configuración**. El apartado A2 de [`ANALISIS.md`](ANALISIS.md) lleva la nota de
corrección, y el diseño correcto está en [`INSTALACION.md`](INSTALACION.md) §1.

---

## 4. GTK4 y `libdecor`

| Supuesto | Confianza | Evidencia |
|---|---|---|
| `libdecor` es una biblioteca **del cliente** para decoración híbrida, no un mecanismo para forzar decoración del servidor | **Conocimiento del dominio** | Ejemplo de integración cliente: [variante libdecor de un ejemplo de decoraciones Wayland](https://raw.githubusercontent.com/PetarKirov/sparkles/refs/heads/main/docs/research/window-system-integration/os-apis/wayland/examples/f13-decorations/libdecor-variant/app.d) |
| GTK4 no usa `libdecor` | **Conocimiento del dominio** | GTK4 gestiona sus propias CSD en Wayland |
| `kde-gtk-config` aplica el tema a GTK3 | **Conocimiento del dominio** | Es su función; el brief lo cita correctamente |
| Los temas estilo WhiteSur «no cambian la estructura» y fallan en muchas apps | **Confirmado** (parcial) | [Issue en nixpkgs](https://github.com/NixOS/nixpkgs/issues/366254) reporta que `whitesur-gtk-theme` «no funciona con la mayoría de las apps» |
| Apps Electron/Flatpak/libadwaita se resisten al tema | **Inferencia sólida** | Se deduce del modelo de empaquetado y de las CSD; el brief acierta al anticiparlo |

**Implicación:** la afirmación del brief sobre `libdecor` («la app cede el dibujo al
compositor») describe `xdg-decoration` en modo server-side, no `libdecor`. Corregir la
redacción; la conclusión práctica del brief (GTK es lo último y con expectativas
realistas) se mantiene intacta.

---

## 6. Sondeo del equipo (13/10/2025)

Hechos leídos directamente de este sistema, no de fuentes externas. Son la base de
[`INSTALACION.md`](INSTALACION.md).

### Entorno

| Dato | Valor |
|---|---|
| SO | CachyOS Linux (`ID=cachyos`, `ID_LIKE=arch`), rolling |
| Sesión | `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=KDE`, `KDE_SESSION_VERSION=6` |
| Compositor | `kwin_wayland` presente |
| Estilo activo | `widgetStyle=kvantum` en `kdeglobals` |
| Tema global | `LookAndFeelPackage=Ant-Dark` |
| Kvantum | `~/.config/Kvantum/kvantum.kvconfig` → `theme=Ant-Dark` |
| GTK | `gtk-theme-name=Breeze`, `gtk-font-name=Noto Sans, 10` |
| Plugins de estilo | `/usr/lib/qt6/plugins/styles/` → `breeze6.so`, `libkvantum.so` |
| Plugins de estilo (2ª ruta) | `/usr/lib64/qt6/plugins/styles` también existe → **detectar `lib` vs `lib64`** |

**Observación de coherencia:** el sistema mezcla capas (`LookAndFeelPackage=Ant-Dark` con
`widgetStyle=kvantum` y GTK en `Breeze`). El proyecto unificaría ese estado, y el
subcomando `estado` sirve además como herramienta de diagnóstico de este tipo de desajuste.

### Herramientas presentes

```
kwriteconfig6  kreadconfig6  kded6  qdbus6  gdbus  update-desktop-database
gcc  g++  pkg-config  fc-cache
/usr/include/qt6/QtWidgets   (headers Qt6 de desarrollo)
```

### Herramientas ausentes

```
qtpaths6   -> no instalado (no se puede consultar la ruta de plugins por esta vía)
cmake      -> AUSENTE. Necesario para compilar el QStyle
ninja      -> AUSENTE. Idem
```

`cmake` y `ninja` son requisito de **desarrollo**, no del instalador. Se instalan con
`pacman` (sudo, sistema), lo que confirma la distinción del brief: *el entregable no usa
sudo; el desarrollo sí instala herramientas*.

### Rutas que el instalador debe resolver empíricamente

1. **¿Explora Qt6 `~/.local/lib/qt6/plugins`?** No se pudo comprobar aquí: `qtpaths6` no
   está instalado y la sesión no tiene bus de usuario systemd. `~/.local/lib` **no
   existe** todavía. Se resuelve en `preflight` con `QT_DEBUG_PLUGINS=1`; si no está en la
   ruta de búsqueda, la solución es `QT_PLUGIN_PATH` en `~/.config/environment.d/`
   (directorio que **tampoco existe** aún y habría que crear).
2. **`lib` vs `lib64`:** ambas rutas de plugins existen en el sistema. El instalador debe
   detectar cuál usa y no asumir `lib`.
3. **KWin no tiene efectos de usuario** (`~/.local/lib/*/kwin/effects` no existe): hay que
   crear la ruta. El directorio de plugins de KWin para efectos no se pudo confirmar desde
   este shell y debe verificarse antes de la etapa 3.

### Mecanismos ya en uso que el proyecto puede reutilizar

| Mecanismo | Evidencia |
|---|---|
| `kde-gtk-config` gestiona GTK | `~/.config/gtk-3.0/window_decorations.css` y `colors.css` existen, generados por KDE; `gtk.css` contiene solo `@import 'colors.css';` |
| Flatpak recibe configuración por override | 7 ficheros en `~/.local/share/flatpak/overrides/` (Chrome, Chromium, Firefox, LibreWolf, Waterfox…). **Contenido actual: solo política de bus de sesión**, sin variables de tema → la vía `flatpak override --user --env=` queda libre para el proyecto |
| Fuentes de usuario | `fc-cache` presente; `~/.local/share/fonts` no existe aún (se crea) |

**Conclusión del sondeo:** el sistema soporta el proyecto **sin ninguna pieza nueva del
sistema operativo** salvo las herramientas de compilación del QStyle (`cmake`, `ninja`).
Todo lo que el instalador necesita para aplicar color, tipografía, estilo Qt, efecto KWin,
GTK y Flatpak **ya está instalado**.

---

## 7. Fuentes consultadas

Búsquedas realizadas el 13/10/2025. Se listan solo las fuentes efectivamente usadas.

**macOS 27 / Liquid Glass**
- [Golden Gate – der letzte Spitzname für macOS? — Macwelt](https://www.macwelt.de/article/3167570/golden-gate-der-letzte-spitzname-fur-macos.html)
- [macOS 27 : Apple va revoir son interface Liquid Glass — RTBF](https://beta.rtbf.be/article/macos-27-apple-va-revoir-son-interface-liquid-glass-pour-repondre-aux-critiques-11722252)
- [macOS 27 va corriger les défauts du Liquid Glass sur Mac — iPhoneSoft](https://iphonesoft.fr/2026/05/10/macos-27-corriger-defauts-liquid-glass-mac)
- [macOS 27: Apple corregge il tiro sul Liquid Glass — HWUpgrade](https://www.hwupgrade.it/news/apple/macos-27-apple-corregge-il-tiro-sul-liquid-glass-e-risolvere-i-difetti-grafici_153427.html)
- [macOS 27のコードネームは「Golden Gate」 — Gigazine](https://gigazine.net/news/20260609-apple-wwdc26-macos-27/)

**KWin / esquinas redondeadas**
- [a-parhom/LightlyShaders — GitHub](https://github.com/a-parhom/LightlyShaders)
- [walterfang12/LightlyShaders-Plasma6 — GitHub](https://github.com/walterfang12/LightlyShaders-Plasma6)
- [guiodic/LightlyShaders — GitHub](https://github.com/guiodic/LightlyShaders)
- [ekaaty/kwin-effect-rounded-corners — GitHub](https://github.com/ekaaty/kwin-effect-rounded-corners)
- [KDE-Rounded-Corners — Launchpad](https://launchpad.net/~matinlotfali/+archive/ubuntu/kde-rounded-corners)

**Temas / GTK**
- [The pkg whitesur-gtk-theme doesnt work with most apps — nixpkgs #366254](https://github.com/NixOS/nixpkgs/issues/366254)

**Wayland / decoraciones**
- [Ejemplo de decoraciones con variante libdecor](https://raw.githubusercontent.com/PetarKirov/sparkles/refs/heads/main/docs/research/window-system-integration/os-apis/wayland/examples/f13-decorations/libdecor-variant/app.d)

**KDE (referencia general)**
- [KDE Stack Overview and How It All Fit Together (Akademy/conf.kde.org, PDF)](https://conf.kde.org/event/5/contributions/161/attachments/98/119/kde-stack-overview-training-2023-edition.pdf)
- [Bug 476536 — animaciones de gestos en overview](https://bugs.kde.org/show_bug.cgi?id=476536)

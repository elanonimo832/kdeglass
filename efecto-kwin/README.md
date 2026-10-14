# Efecto KWin: material estilo macOS

Efecto del compositor que engancha el borde de las ventanas a la cadena de pintado
de KWin. **Todavía no dibuja el material**: eso es el paso siguiente.

## Estado

| | |
|---|---|
| Carga sin romper el render | ✅ verificado con capturas (`negro=0.0%`) |
| Se engancha a la cadena de pintado | ✅ |
| **Dibuja el material** | ❌ **pendiente: el shader** |

## Los tres comandos

```bash
./construir.sh              # compila y verifica la cadena de pintado
./instalar-efecto.sh        # instala y activa (pide tu contraseña)
./probar-ya-instalado.sh    # prueba en vivo: carga, mide y DESCARGA solo
```

`probar-ya-instalado.sh` es el banco de pruebas: **no cierra sesión**, no
reinstala nada, y descarga el efecto siempre con `trap EXIT` aunque el render
falle. Tarda unos 15 segundos.

Para que el efecto quede cargado **de forma permanente**, cierra sesión.

> ⚠️ **NUNCA `kwin_wayland --replace`.** En Wayland arranca un segundo compositor
> que compite por el DRM/GL, mata el contexto OpenGL del KWin vivo y deja la
> pantalla **negra con el cursor visible**. Ocurrió dos veces; ver `../INCIDENTE.md`.

## Recuperación

Si algo dejara la pantalla negra:

```bash
bash ~/RECUPERAR-KDE.sh reanimar     # en caliente, sin cerrar sesión
```

## Las cuatro cosas que hay que respetar

Las cuatro costaron horas. `verificar-cadena.sh` y el arnés de pruebas las vigilan.

**1. La ruta.** KWin busca en `<plugins Qt>/kwin/effects/plugins/`, **no** en
`kwin/effects/`. Un nivel más arriba KWin no lo ve, y **en silencio**.
*(Fuente: `PluginEffectLoader`, `m_pluginSubDirectory = "kwin/effects/plugins"`.)*

**2. El nombre del fichero es el pluginId.** `macosglass.so` → id `macosglass`.
El prefijo `lib` de CMake lo rompe (`PREFIX ""` lo evita).

**3. La cadena de pintado.** `EffectsHandler::paintWindow()` llama a **un solo**
efecto por invocación, y la cadena avanza porque `Effect::paintWindow()` —la base—
vuelve a entrar. Si un efecto la sobreescribe y **no llama a la base**, la cadena se
corta, `finalPaintWindow()` no se ejecuta y **no se dibuja ninguna ventana**: el
fondo del escritorio de Plasma es una ventana más, así que solo queda negro.

Todo camino de `paintWindow()` tiene que acabar así:

```cpp
effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
```

**4. `supported()`.** Tiene que devolver `true` de verdad. Si devuelve `false`, KWin
descarta el efecto **sin ningún mensaje**. (La versión que usaba
`effects != nullptr`, el ejemplo de la doc de KDE, devolvía `false`.)

## El identificador `macosglass` (por qué el plugin se llama `macosglass2`)

El mismo código, byte a byte, **funciona con un id y rompe con otro**:

| id | negro en pantalla |
|---|---|
| `bisect` (código mínimo) | 0 % ✅ |
| `testglass2` (código mínimo) | 0 % ✅ |
| `macosglass` (código completo) | **100 %** ❌ |
| `macosglass` (código mínimo) | **100 %** ❌ |
| `macosglass2` (código completo) | 0 % ✅ |

**No sé explicar por qué.** El estado observable era idéntico (misma metadata, mismo
`isSupported()`, misma ruta). Es una observación reproducible, no un diagnóstico.
Anotado para el equipo de KWin en `../INCIDENTE.md`.

## Herramientas de diagnóstico

```bash
./verificar-cadena.sh    # ¿la cadena de pintado está intacta? (fuente + binario)
```

Compilables a mano si hacen falta (usan las cabeceras de KWin y KF6 ya instaladas;
`_stub/vulkan` evita los 42 MiB de `vulkan-headers`):

| Fichero | Para qué |
|---|---|
| `src/diagnostico.cpp` | reproduce el descubrimiento de plugins de KWin |
| `src/probar-fabrica.cpp` | instancia la fábrica y pregunta `isSupported()` |
| `src/verificar-carga.cpp` | hace lo mismo que KWin al arrancar |

Estas tres responden «¿por qué KWin no carga mi efecto?» en segundos, que es lo que
me habría ahorrado la mitad del incidente.

## El paso siguiente: el shader del material

Parámetros medidos en `../tokens.toml` (del kit de Figma):

| Parámetro | Valor |
|---|---|
| refracción | 70 |
| dispersión | 20 |
| difusión (frost) | 6 / 16 / 16 |
| ángulo de luz | 0 |
| opacidad | 25 |
| profundidad | 30 |
| borde oscurecido | alfa 20 (negro al 8 %) |

Se dibujará con OpenGL sobre `GLFramebuffer` en `paintWindow()`, en pasos pequeños y
cada uno medido con `probar-ya-instalado.sh`.

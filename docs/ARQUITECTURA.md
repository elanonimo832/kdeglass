# Arquitectura del proyecto

## Qué es

Una capa de escritorio con el aspecto de **macOS nativo** sobre KDE Plasma 6
(Wayland). No es un tema suelto: son piezas que se complementan, todas derivadas de
**una sola fuente de verdad** (los tokens medidos del kit de Figma de Apple).

## Estructura

```
.
├── PROYECTO-KDE-MACOS.md    Encargo original. NO se modifica.
├── README.md                Entrada del proyecto
│
├── docs/                    Documentación de proceso
│   ├── ARQUITECTURA.md      este fichero
│   ├── METODOLOGIA.md       cómo trabajamos y por qué
│   └── ROADMAP.md           qué falta, por hitos, con criterio de "hecho"
│
├── tokens.toml              Fuente de verdad CONSOLIDADA (5 ejes)
├── tokens/                  32 colecciones extraídas del kit de Figma
│   ├── tokens-colors.toml       color (primitivos)
│   ├── tokens-sizes.toml        métricas
│   ├── tokens-tipografia_*.toml tipografía
│   ├── tokens-forma-*.toml      forma y efectos
│   └── referencia/              13 colecciones NO aplicables (Material, iOS…)
│
├── herramientas/            Generadores: tokens -> artefactos
│   ├── figma/               extracción desde el kit (Node + Python)
│   ├── generar-esquemas-kde.py
│   ├── generar-gtk-css.py
│   ├── generar-decoracion-macos.py
│   └── consolidar-tokens.py
│
├── salida/                  Artefactos GENERADOS (no se editan a mano)
│   ├── color-schemes/       KdeMacosLight/Dark.colors
│   ├── gtk-3.0/ gtk-4.0/    CSS
│   └── aurorae/KdeMacOS/    decoración (semáforos) + vistas previas
│
├── efecto-kwin/             Efecto del compositor (C++ / OpenGL)
│   ├── src/glass.h/.cpp     el efecto
│   ├── src/diagnostico.cpp  herramientas de diagnóstico (ver su README)
│   ├── _stub/vulkan/        stub para no instalar 42 MiB de vulkan-headers
│   └── README.md
│
├── pruebas/                 Arnés de verificación
│   ├── ejecutar.sh          punto de entrada
│   ├── lib.sh               aserciones
│   └── prueba-*.sh          por área: artefactos, efecto, scripts, documentación
│
├── evidencia/               Capturas de NUESTRO escritorio (no de Apple)
└── INCIDENTE.md             Incidente de pantalla negra: historia y causa
```

## El flujo de datos

```
   kit de Figma de Apple  (NO se versiona: es material de Apple)
              │
              │  herramientas/figma/       extracción
              ▼
      tokens/  +  tokens.toml              FUENTE DE VERDAD
              │
              │  herramientas/generar-*.py  generación
              ▼
   salida/  (esquemas, CSS, decoración)    ARTEFACTOS
              │
              │  instalar*.sh               instalación
              ▼
        ~/.local/share/...                 SISTEMA
```

**Regla:** los artefactos de `salida/` **no se editan a mano**. Se cambia el token
y se regenera. Una prueba comprueba que regenerar da un fichero **idéntico**.

## Por qué los tokens son la fuente de verdad

El encargo pedía fidelidad a macOS. La fidelidad no se consigue copiando valores a
mano repartidos en ficheros: se consigue teniendo **un** sitio del que salen todos.

Cada token lleva su **procedencia** (de qué colección del kit salió), así que
cualquier valor se puede rastrear hasta su origen. Y cuando un valor se corrige, se
corrige en un sitio y baja a todos los artefactos.

## Decisiones documentadas

| Decisión | Por qué |
|---|---|
| Tres radios de forma (control, ventana, icono), no uno | macOS los distingue; el kit los da por separado |
| Valores del **kit** ganan sobre los medidos en pantalla | macOS renderiza un 18/255 más apagado; usar el kit mantiene coherencia entre piezas |
| Tipografía: Inter en vez de SF Pro | SF Pro no es redistribuible; Inter es SIL OFL |
| El texto es negro/blanco con **alfa decreciente**, no grises | Es el patrón de velo de Apple (85/55/25/10/5/3 %) |
| `_stub/vulkan` en vez de `vulkan-headers` | Solo hacen falta las cabeceras para compilar; ahorra 42 MiB |

## Lo que NO está

- **El shader del material** del efecto (difusión, refracción, dispersión). Es lo
  único grande que falta; ver `docs/ROADMAP.md`.
- Verificación del CSS de GTK en una aplicación real.
- Geometría squircle de los iconos de carpeta.

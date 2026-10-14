# Metodología

No es teoría: cada regla de este documento salió de un fallo real de este proyecto,
y la mayoría costaron horas. Están ordenadas por lo que costaron.

## Las cinco reglas

### 1. Medir antes de razonar

**El coste de ignorarla:** nueve hipótesis descartadas sobre la pantalla negra. Todas
eran fallos reales —ECM, Vulkan, `BUILD_SHARED_LIBS`, `glass.moc`,
`KPackageStructure`, el prefijo `lib`, `isSupported()`, la metadata suelta, la ruta
de instalación— y **ninguna era la causa**. La causa era una constante de cadena en
el código de KWin que nunca se me ocurrió cuestionar.

En tres ocasiones mi razonamiento fue correcto en abstracto y el sistema dijo lo
contrario. Las tres las resolvió **medir**:

| Razonamiento | Realidad medida |
|---|---|
| «`loadEffect` no pasa por `readConfig», así que el estado guardado no importa» | importaba |
| «si `isSupported()` devuelve true, KWin lo carga» | no lo cargaba |
| «el mismo código no puede comportarse distinto» | con otro id, sí |

**Regla práctica:** cuando algo no cuadre, construye la medición más pequeña que
pueda desmentirte. No busques la causa: busca el experimento que la descarte.

### 2. Aislar con un caso mínimo

**El coste de ignorarla:** la mitad del incidente. El **efecto mínimo** —una clase que
solo se carga y no hace nada— resolvió en dos ejecuciones lo que nueve hipótesis no
resolvieron: descartó de golpe la compilación, el enlace, la ruta y `isSupported()`.

Después, la bisección encontró que **el mismo código byte a byte** funcionaba con un
id y rompía con otro.

**Regla práctica:** ante un fallo con muchas variables, reduce hasta que solo quede
una. Si el mínimo también falla, el problema no está donde crees.

### 3. Ninguna prueba vale hasta verla fallar

**El coste de ignorarla:** dos falsos «ABORTADO» que te hicieron dudar de un `.so`
correcto, y una prueba que pasaba en verde **con el código roto**.

```
La prueba buscaba `effects->paintWindow` en el fichero.
Lo quitamos del CÓDIGO.
La prueba siguió en verde: el patrón estaba en el COMENTARIO que lo explica.
```

Es el mismo error que me hizo perseguir el fallo equivocado durante horas: **leer una
mención y creer que es una implementación**.

Dos consecuencias incorporadas al arnés:
- Las aserciones sobre código **ignoran los comentarios** (`afirmar_codigo`).
- Toda prueba se comprueba **rompiendo a propósito** lo que vigila.

### 4. Verificar la herramienta antes que el objeto

**El coste de ignorarla:** la comprobación de seguridad de `instalar-efecto.sh`
abortaba la instalación de un `.so` correcto, de forma **no determinista**.

```bash
objdump -d --demangle "$SO" | grep -qE 'EffectsHandler::paintWindow'
# grep -q aborta al encontrar la coincidencia y cierra el pipe.
# Con `set -o pipefail`, el resultado VARÍA.
```

Cuando lo probaba yo, pasaba. Cuando lo ejecutabas tú, fallaba. Y yo te dije **dos
veces** que era «la seguridad funcionando bien». No lo era: era un bug mío.

**Regla práctica:** una comprobación que da falsos positivos es **peor que no
tenerla**, porque hace dudar de algo que está bien. Antes de fiarte de una
herramienta, comprueba que es determinista y que falla cuando debe.

### 5. Nunca destruir el estado sin poder volver

**El coste de ignorarla:** dos pantallas negras, una sesión perdida, y horas de
recuperación desde una TTY.

| Error | Lección |
|---|---|
| `kwin_wayland --replace` recomendado como «seguro» | En Wayland arranca un segundo compositor que compite por el DRM/GL. **Nunca.** |
| Proyecto 26 horas sin git | Sin red, cada cambio es irreversible |
| Scripts que cargaban el id viejo | Ejecutarlos habría vuelto a romper el render |

**Regla práctica:**
- Toda operación con riesgo tiene que ser **reversible** y tener **trampa de salida**
  (el `trap EXIT` de `probar-ya-instalado.sh` descarga el efecto siempre).
- Antes de tocar algo, saber cómo se deshace.
- **Commit antes de cada cambio arriesgado.**

## El ciclo de trabajo

```
   escribir la prueba  ──►  ROJO   (falla: aun no está hecho)
          │
          ▼
   implementar         ──►  VERDE  (pasa)
          │
          ▼
   romper a propósito  ──►  ROJO   (¿la prueba lo detecta de verdad?)
          │
          ▼
   restaurar           ──►  VERDE
          │
          ▼
        commit  ──►  pequeño, con el porqué en el mensaje
```

El paso «romper a propósito» no es opcional: es lo que distingue una prueba que
verifica de una que solo decora.

## Las puertas de calidad

Antes de dar algo por hecho:

| Puerta | Cómo se comprueba |
|---|---|
| El arnés pasa | `pruebas/ejecutar.sh` |
| La prueba detecta la rotura | romper a propósito y verla fallar |
| El sistema no se rompe | `probar-ya-instalado.sh` (carga, mide, descarga) |
| Es reproducible | regenerar y comparar (byte a byte) |
| Está documentado | la documentación no se contradice (hay prueba) |

## Gestión del conocimiento

**Los fallos se documentan; no se esconden.** `INCIDENTE.md` conserva las cuatro
conclusiones erróneas **a propósito**: muestran qué señales se leyeron mal y por qué.
Un documento que solo tiene la respuesta buena no enseña nada.

**Un solo sitio para cada cosa.** Cuando `SALIDA.md` y `INCIDENTE.md` se
contradijeron, el problema no era la contradicción: era que **no se sabía cuál
mandaba**. Ahora hay un resumen autoritativo y el resto queda marcado como histórico.

**Los mensajes de commit explican el porqué.** El qué ya está en el diff. Lo que se
pierde con el tiempo es la razón.

## Lo que no hacemos

- **No editar los artefactos generados a mano.** Se cambia el token y se regenera.
- **No commitear material de Apple.** El kit, las fuentes SF Pro y los `.fig` están
  en `.gitignore`. Lo que se versiona es lo derivado, y con la procedencia anotada.
- **No guardar credenciales en el repo.** Ni en `.env`, ni en un fichero de config.
  Un token en el historial de git es permanente.
- **No dar por bueno un «funciona en mi máquina».** Se mide, y la medición se queda
  en el proyecto como prueba.

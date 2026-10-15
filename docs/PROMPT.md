# PROMPT.md — what to paste into a new session

Copy everything inside the block below. It tells a fresh session where the work lives, forbids it from
creating anywhere else, and makes it verify that before it touches anything.

---

```
Trabaja EXCLUSIVAMENTE dentro de este repositorio, en esta ruta absoluta:

    /home/jracosta/Projects/Deepseek Harness/analisis-kde-macos

(ojo: hay un espacio en "Deepseek Harness", cita siempre la ruta entre comillas)

NO crees ninguna carpeta nueva: ni un clon, ni un checkout aparte, ni un directorio de trabajo
distinto, ni un "proyecto nuevo" para reorganizar nada. Todo —código, tests, documentación y
herramientas— vive ya en esa ruta y su estructura está descrita en `docs/`. Si crees que
necesitas una carpeta nueva, no la crees: escribe en la que ya existe, o pregunta antes.

ANTES DE NADA, verifica dónde estás y léelo en este orden:

    1. pwd                                  y confirma que es la ruta de arriba
    2. docs/NEXT.md                         ← EMPIEZA AQUÍ: estado, qué sigue y en qué orden,
                                              la caja de herramientas y las reglas
    3. docs/METHODOLOGY.md                  ← las formas en que este trabajo se torció y la regla
                                              que salió de cada una
    4. docs/HANDOFF.md                      ← el registro largo; §9u es el runbook de emergencia
                                              y §9v la auditoría con fichero:línea
    5. effect-kwin/README.md                ← la tabla de estado y los mandos
    6. ROADMAP.md                           ← los hitos M1..M6, y docs/ARCHITECTURE.md

ESTADO QUE HAY QUE COMPROBAR, no suponer:

    cd "/home/jracosta/Projects/Deepseek Harness/analisis-kde-macos"
    git log --oneline -1 && git status --short
    bash tests/run.sh                       # la red completa, unos segundos: tiene que estar verde
    md5sum effect-kwin/build/plugins/kwin/effects/macosglass2.so
    md5sum /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so

Si esos dos md5sum difieren, hay un install pendiente: `cd effect-kwin && ./install.sh` y después
cerrar y abrir sesión — o probar primero la recarga en caliente, que ha funcionado dos veces sin
reiniciar:

    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass2
    qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect   macosglass2

(con XDG_RUNTIME_DIR y DBUS_SESSION_BUS_ADDRESS del usuario; el runbook completo está en §9u)

CÓMO SE TRABAJA AQUÍ — son acuerdos, no sugerencias:

  - La conversación con el usuario, en español. TODO lo que entra al repositorio, en inglés.
  - TDD: primero el test o el instrumento, y míralo fallar antes de que pase.
  - Commits pequeños, que expliquen POR QUÉ y no qué.
  - Nunca escribas "suite verde" sin haberlo visto pasar:
        bash tests/run.sh && git commit ...
  - Después de CADA edición, verifica el fichero (grep) y no el "ok" del parche: en una sola
    sesión, cinco ediciones multiparte se aplicaron a medias.
  - El shader (effect-kwin/src/glass.cpp) y effect-kwin/simulate.py son DOS implementaciones de la
    misma fórmula: se cambian JUNTAS, o se separan en silencio.
  - No cambies el aspecto por velocidad sin medirlo. `simulate.py` existe para juzgar un valor sin
    relogin, con todos los mandos como opciones y los defectos leídos de src/glass.h.
  - Antes de tocar el shader, lee la lista de "no tocar" del §9v: son decisiones MEDIDAS y cada una
    lleva su número al lado.

ANTES DE TOCAR M2, LEE `docs/HANDOFF.md` §10c. Es el trabajo que sigue y ya se intentó UNA VEZ
MAL: la curva que hay en el árbol (una superelipse centrada en el vértice con una calibración
inventada, `n = 2 + 5*smoothing`) NO es la construcción de Apple y deja la esquina casi cuadrada
-- a y=5 el círculo tiene su borde en x=6.8 y esa curva en x=20.0, y el usuario lo vio en pantalla
antes que yo en los números. La construcción correcta es un arco reducido a `r*(1-s)` más dos
transiciones Bézier tangentes, y abulta 0.23 px donde la mía abultaba 4.62. Sustituirla toca
`simulate.py` Y el shader a la vez, y rompe la premisa de la búsqueda del punto más cercano
(tabla en Python, gruesa+refinado en GLSL), porque una curva por tramos no es una paramétrica
simple: eso hay que decidirlo y medirlo.

  Y EL INSTRUMENTO DE FORMA, PRIMERO. En la sesión anterior se intentó tres veces y se borró;
  los tres modos de fallo están en §10c. Se construye contra una esquina SINTÉTICA de respuesta
  conocida antes de mirar una captura del usuario.

QUÉ HACER:

  Lee `docs/NEXT.md` y propón el orden de los siguientes pasos citando ese documento, en vez de
  improvisar uno. El primero es M2 (las esquinas, con el aviso de arriba). Después: la auditoría
  #1 (capturar solo la banda en vez de la ventana entera, ~30x menos tráfico, esfuerzo alto y
  merece su propia sesión) y los pequeños y seguros #4, #7 y #8.

  Si algo no cuadra —los hashes, la suite, lo que ves en pantalla—, dilo antes de cambiar nada.
```

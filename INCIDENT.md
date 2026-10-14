# INCIDENT: black screen on KDE Plasma (CachyOS) — 2026-10-13 / 14

> ## ⚠️ THIS DOCUMENT IS HISTORICAL: it contains SUPERSEDED conclusions
>
> It was written across two sessions, and each time we found a new cause
> it was recorded without deleting the previous one. There are **four successive
> conclusions** and only the last one is correct.
>
> ## The cause, in one line
>
> **The effect's identifier.** The same code, byte for byte, compiled as
> `macosglass` left the composition at **100 % black**, and with a new id
> (`macosglass2`) it works. Measured with screenshots and pixel analysis.
> The effect is now called `macosglass2`.
>
> ## What was NOT the cause (even though it seemed so at the time)
>
> | Conclusion that was written down | Status |
> |---|---|
> | "The effect was not the cause" (old build) | **false** |
> | "The OpenGL context / scene-graph" | symptom, not cause |
> | "The chain call was missing in `paintWindow()`" | it was **a real fault**, but not the one that broke it |
> | "The `macosglass` identifier" | **✅ correct** (bisection confirms it) |
>
> ## What did get fixed and is still valid
>
> 1. **The paint chain.** `paintWindow()` HAS to call
>    `effects->paintWindow()`. It is a real fault and `verify-chain.sh` checks it.
> 2. **`supported()`** returned `false` (`effects != nullptr`, the example in KDE's
>    doc) and KWin discarded the effect SILENTLY.
> 3. **The path** is `kwin/effects/plugins/`, not `kwin/effects/`. One level. Two hours.
> 4. **The file name defines the pluginId**, with no `lib` prefix.
> 5. **Never `kwin_wayland --replace`** on Wayland: it leaves the screen black.
>
> ## How to recover
>
> ```bash
> bash ~/RECOVER-KDE.sh reanimar     # on the fly, without logging out
> ```
>
> ---
>
> *What follows is the historical record, in reverse chronological order at the end.
> The old conclusions are kept on purpose: they show how we got to the
> right one, and which signals were misread.*



# ✅ FIXED — 2026-10-13 23:32: exact root cause and fix

The cause was **not** the OpenGL context or the compilation: it was **a call that
was missing** in `MacosGlassEffect::paintWindow()`.

## The KWin paint chain rule

KWin 6.7.5's code (`src/effect/effecthandler.cpp`) calls **a single**
effect per invocation:

```cpp
void EffectsHandler::paintWindow(...)
{
    if (m_currentPaintWindowIterator != m_activeEffects.constEnd()) {
        (*m_currentPaintWindowIterator++)->paintWindow(...);  // ONE effect
    } else {
        m_scene->finalPaintWindow(...);                       // draws the window
    }
}
```

The chain advances because the **base** implementation (`Effect::paintWindow`,
`src/effect/effect.cpp`) re-enters:

```cpp
void Effect::paintWindow(...)
{
    effects->paintWindow(...);   // -> next effect, or finalPaintWindow()
}
```

Our effect **overrode `paintWindow()` and returned without calling
`effects->paintWindow()`** on any path. When the chain reached
`macosglass`, it was cut: `WorkspaceScene::finalPaintWindow()` never ran
and **no window was drawn**. The Plasma desktop background is
one more window, so only the compositor's background color was left: **black**.

This explains all the symptoms: KWin and plasmashell alive over D-Bus (the process does
not crash), `Compositing is active` (the compositor works), but the scene-graph
never receives the paint order. The cursor is painted by KWin through another path, which is why
it was visible over the black.

## The fix

`effect-kwin/src/glass.cpp`: **all** the paths of `paintWindow()` end in

```cpp
effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);
```

Verified at binary level (without loading it into the session):

```
old .so (system) : 0 references to EffectsHandler::paintWindow   <- broken
new .so (build)  : tail-call to EffectsHandler::paintWindow      <- OK
```

## What the effect does now

It still **draws nothing** (the material shader is the next step). But it no
longer breaks the chain: for painting purposes it behaves as if it were not
loaded. `effect-kwin/verify-chain.sh` checks it automatically (source +
binary) and `build.sh` / `install.sh` **abort** if the chain is not there.

## How to test it

```bash
cd "~/Projects/Deepseek Harness/analisis-kde-macos/effect-kwin"
./verify-chain.sh                      # source + binary
sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
     /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
./probar-en-vivo.sh                        # loads, captures, measures and ONLY unloads
```

`probar-en-vivo.sh` unloads the effect **always** (`trap EXIT`) even if the render
broke, and it refuses to start if the installed `.so` does not carry the fix. If
something went wrong anyway: `bash ~/RECOVER-KDE.sh reanimar`.

> Note: the agent could not install the `.so` (the sandbox cannot `sudo`), so
> the system binary **is still the old one** until the `sudo install` above is run.
> The fixed `.so` is in
> `effect-kwin/build/plugins/kwin/effects/macosglass.so`.

## One-line summary
Our own KWin effect `macosglass` is loaded (a build we compiled ourselves) and the Plasma
session ends up on a **black screen with the cursor visible**. KWin and plasmashell **stay
alive** (they answer over D-Bus) and the compositor even says `Compositing is active`,
but it stops rendering because of a failure of the **OpenGL context / scene-graph**.

---

# UPDATE 2026-10-13 23:12 — SECOND INCIDENT

## What happened again (exact timeline)
| Time | Event |
|---|---|
| 22:54 | Boot (boot 0). Graphical session **with `macosglassEnabled=false`**: it worked (KWin 1314, **0** context errors). |
| 23:03:42 | The user reinstalls the new `.so`: `sudo install build/plugins/kwin/effects/macosglass.so /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`. `kwinrc` ends up with `macosglassEnabled=true`. |
| 23:04:22 | Logout/login. New Wayland session (session 5, **tty3**). `startplasma-wayland`. |
| 23:04:23 | KWin **3458** starts and loads the effect: `[macos-glass] cargado. Borde oscurecido activo, alfa 20`. |
| 23:04:24 | `[macos-glass] paintWindow alcanzado para ""`. The effect enters the paint path. |
| 23:04:42–23:05:19 | 5× `kwin_wayland[3458]: Could not delete render time query because no context is current` → **black screen**. |
| 23:05:54 | The user goes into tty2 (session 6) to talk to the agent. |
| 23:10:01 | `RECOVER-KDE.sh recuperar --reset-output` (backup `20261013-231001`). |
| 23:10:07 | `Compositing.reinitialize()` → recreates the GL backend and **loads macosglass again** (config in memory). |
| 23:10:32 | `reconfigure()` + `unloadEffect macosglass` → effect out, `macosglassEnabled=false` on disk. |
| 23:10:58 / 23:12:20 | Screenshots: desktop **rendered and alive** (the panel clock advances 11:06 → 11:12 PM). |

## HOT recovery (it worked; no reboot was needed)
```bash
bash ~/RECOVER-KDE.sh recuperar --reset-output      # backup + disables macosglass/blur
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

qdbus6 org.kde.KWin /KWin     org.kde.KWin.reconfigure                  # make KWin re-read kwinrc
qdbus6 org.kde.KWin /Effects  org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize   # recreates the GL context
```
Or, in one line, `bash ~/RECOVER-KDE.sh reanimar` (a new command in the script).

**Order matters:** `reinitialize()` **reloads the effects according to the configuration KWin
has IN MEMORY**. If `reconfigure()` has not been called first, KWin still believes that
`macosglassEnabled=true` and **loads the effect again** (that is what happened at 23:10:07).
Hence: `reconfigure` → `unloadEffect` → (and if needed) `reinitialize`.

## Evidence that `macosglass` is the trigger (this CORRECTS the previous conclusion)
- KWin **1314** (session 22:54–23:04, `macosglassEnabled=false`): **0** context errors, desktop OK.
- KWin **3458** (session 23:04, `macosglassEnabled=true`): `[macos-glass] cargado` → `paintWindow` → **5** `no context is current` in 37 s.
- It is the only non-standard effect loaded; with it unloaded and the backend recreated, the errors **disappear**.

> **Honest correction:** in the first session (22:40+) I wrote "The `macosglass`
> effect was NOT the cause; its `paintWindow` is a no-op". That was true for the old build and
> for the already broken process, but **the conclusion was wrong**: the second incident
> shows that loading the effect is what breaks the render. Its `paintWindow` is a no-op,
> but the plugin (compiled against KWin 6.7.5 / Qt 6.12) leaves the OpenGL context invalid
> when it enters the paint path.

## Decisive test — EXECUTED (2026-10-13 23:24–23:26): CAUSE CONFIRMED

It was executed live with the desktop stable and the graphical session (**tty3**) active, using
`spectacle` screenshots (3840x2160) as an objective witness and pixel analysis with PIL.

| Screenshot | `macosglass` state | Measured content |
|---|---|---|
| A (control) | **unloaded** | 861 KB — real desktop, **0,1 %** black pixels |
| B (+10 s) | **loaded** live | 32 KB — **100 % `#000000`** |
| B (+30 s) | **loaded** | 32 KB — **100 % `#000000`** |
| C | just **unloaded** (without `reinitialize`) | 856 KB — real desktop |
| D | after `reinitialize` | 855 KB — real desktop |

**Conclusion (settled):** loading `macosglass` in the live KWin **leaves the composition 100 %
black** — the same black screen as the incident — and **unloading it restores it
instantly**, without logging out or `reinitialize`. The effect is the cause, unambiguously.

Nuance that corrects/refines the above: on live load `[macos-glass] paintWindow`
does **not** get logged (the render breaks before that path); on the incident boot
it was logged (23:04:24). The line `Could not delete render time query because
no context is current` reappeared, but **sporadically** (1 time, tied to the effect
cycle / `reinitialize`), not in a wave as on boot. That is why the acid test is the
**screenshot**, not the log.

Evidence in `analisis-kde-macos/evidence/`:
`2026-10-13-2324-prueba-control-escritorio.png`,
`2026-10-13-2324-prueba-efecto-cargado-negro.png`,
`2026-10-13-2324-prueba-tras-descargar.png`.

### Reproducing the test
```bash
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
loginctl activate 5                     # activate the graphical session (tty3)
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect macosglass   # -> black screen
# compare screenshots (spectacle -b -n -o /tmp/a.png): the first one is already black
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass # -> restores NOW
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize    # optional
```

---

# ORIGINAL DOCUMENT (first incident, 22:19–22:54)

## Symptom
- Black screen, mouse cursor visible and moving.
- `loginctl`: the graphical session is `online`; KWin (6.7.5) and plasmashell answer on the bus.
- KWin sees the output correctly: HDMI-A-1, 3840x2160, scale 1, `Compositing is active`,
  OpenGL on AMD Radeon 780M (radeonsi, Mesa 26.2.4).

## Known triggers (the two that broke it)
1. **`kwin_wayland --replace`** on Wayland (first incident, 22:19:49). It starts a
   **second compositor** that competes for the DRM/GL. On the previous boot it left:
   ```
   Failed to find a working output layer configuration!
   Applying output configuration failed!
   ```
2. **Loading the `macosglass` effect** in a new session (second incident, 23:04).
   See the update above.

## Key evidence (user session journal)
When forcing a re-render (changing theme/scheme), at 22:50:05 KWin began to flood
the journal with:
```
kwin_wayland[1315]: No QSGTexture provided from updateSampledImage(). This is wrong.
kwin_wayland[1315]: Could not delete render time query because no context is current
```
=> **The OpenGL context is not active during the render**: KWin composites an empty
canvas (black). It is a state of the KWin process.

Other clues:
- `kwin_wayland[1069]: Failed to create framebuffer: Invalid argument` (greeter, 1 time).
- `atomic commit failed: Permission denied` => **benign noise** from VT changes
  (tty2 <-> tty3); it also appears when running `loginctl activate`. It is NOT the cause.
- `plasmashell[1450]: The requested buffer size is too big, ignoring` => it comes from
  `libQt6Svg`; secondary.

## Important limitation of the agent (DSH) — do not blindly trust the screenshots
The command sandbox uses `bwrap ... --dev /dev`, so:
- **`/dev/dri` does NOT exist** inside the sandbox (no GPU / render node).
- `/dev/shm` is sometimes read-only (in this session at 23:06 it was writable).
- KWin normally denies `org.kde.KWin.ScreenShot2` to unauthorized processes.
=> Screenshots with `spectacle` launched by the agent **may** come out black even if the
screen is fine. The final source of truth is what the user sees. **But** a screenshot
that shows content and whose clock advances is positive proof that the desktop renders
(that happened at 23:10:58 and 23:12:20).

## State I left behind (2026-10-13 23:12)
`~/.config/kwinrc`:
- `[Plugins] macosglassEnabled=false`, `blurEnabled=false`
- `[org.kde.kdecoration2]` without `theme`/`library` (default decoration)
`~/.config/kdeglobals`:
- `ColorScheme=BreezeDark`
`~/.config/kwinoutputconfig.json`:
- Moved aside to `~/.local/state/kde-macos/incidente-recuperacion/20261013-231001/` (KWin regenerates it).
Effect:
- **Unloaded live** from the live KWin (`isEffectLoaded=false`, active `activeEffects` empty).
- User `.so` set aside: `~/.local/lib/plugins/kwin/effects/libmacosglass.so.disabled-20261013-231244`.
- System `.so` **is still installed** (deleting it requires root):
  `/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`. It is inert as long as it is disabled.
- To remove it completely (the most advisable):
  `sudo rm /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so`
Backups:
- `~/.cache/kwinrc.before-exp-<epoch>`
- `~/.local/state/kde-macos/incidente-recuperacion/` (includes `20261013-231001/`)
Other project changes (reversible): aurorae/GTK/scheme themes in `~/.local/share/…`.

## Recovery steps (in order)
0. **Hot recovery, without logging out** (tested on 2026-10-13 23:12):
   ```
   bash ~/RECOVER-KDE.sh reanimar
   ```
   If the script is not there, the 4 commands of "HOT recovery" above.
1. If it is still black, switch to the graphical session with **Ctrl+Alt+F<n>**, where `<n>` is the
   TTY of the *wayland* session (at 23:04 it was **tty3**, not tty2; the script works it out itself):
   ```
   loginctl list-sessions            # look for the one with TYPE=wayland and check its TTY
   ```
2. If it is still black, restart the session manager or the machine:
   ```
   sudo systemctl restart plasmalogin     # closes the session; you get the login back
   # or
   sudo reboot
   ```
   With `macosglass` and `blur` already disabled, KWin starts without them.
3. If after rebooting it is still black:
   ```
   bash ~/RECOVER-KDE.sh recuperar --reset-output
   sudo reboot
   ```
4. If it is still black even then, try a **new user** (clean config) to
   rule out `~/.config`:
   ```
   sudo useradd -m prueba && sudo passwd prueba
   ```
   If it looks fine with the new user => the problem is in `jracosta`'s config.
   Rename/restore: `~/.config/kwinrc`, `~/.config/kdeglobals`,
   `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, `~/.config/kwinoutputconfig.json`.

## Re-enabling the macOS look
The `macosglass` effect **no longer breaks the session** (fixed 2026-10-13 23:32; see
the section above). Even so it **still draws nothing**: it is safe, but inert.

What does change the look and does not touch the render:
```
cd "/home/jracosta/Projects/Deepseek Harness/analisis-kde-macos"
./install-decoration.sh aplicar --si --activar
# Color:  Settings -> Appearance -> Colors -> KdeMacosLight/Dark
```
If you want to test the effect again (already fixed), install the new binary and
use the test with a safety net (**never** `kwin_wayland --replace`):
```
cd effect-kwin
./verify-chain.sh
sudo install -Dm755 build/plugins/kwin/effects/macosglass.so \
     /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass.so
./probar-en-vivo.sh          # loads, measures and only unloads
```
`RECOVER-KDE.sh revertir` re-applies everything at once (at your own risk).

## Useful diagnostic commands
```
export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus

qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation | sed -n '/Compositing/,/Effect Settings/p'
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded macosglass
qdbus6 org.kde.KWin /Compositor org.freedesktop.DBus.Properties.Get org.kde.kwin.Compositing openGLIsBroken
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
kscreen-doctor -o                        # from the sandbox it may abort (core dumped); that is normal
loginctl list-sessions; loginctl show-session <id> -p Type -p TTY -p Active
journalctl --user -b | grep -iE 'macos-glass|QSGTexture|context is current|atomic|kwin|plasmashell'
ls -la /dev/dri /dev/shm                 # inside the sandbox /dev/dri does not exist
```

## Timeline
**First incident**
- 21:12 color scheme installer (kdeglobals)
- 21:36 KdeMacOS decoration
- 21:52–22:25 compilation and installation of the macosglass effect
- 22:19:49 `kwin_wayland --replace` -> breaks the session
- 22:27 reboot
- 22:28 login -> black screen
- 22:34–22:38 previous diagnostic session (changed nothing)
- 22:40+ diagnostic session and reversible changes (origin of this document)
- 22:54 reboot with `macosglassEnabled=false`

**Second incident**
- 22:54–23:04 boot 0, session with the effect disabled: it worked (KWin 1314, 0 errors)
- 23:03:42 sudo install of the new `.so`; `macosglassEnabled=true`
- 23:04:22 logout/login on **tty3**; KWin 3458
- 23:04:23 `[macos-glass] cargado`; 23:04:24 `paintWindow` reached
- 23:04:42–23:05:19 5× `no context is current` -> black screen
- 23:05:54 login on tty2 (session 6) to use DSH
- 23:10:01 `RECOVER-KDE.sh recuperar --reset-output` (backup `20261013-231001`)
- 23:10:07 `reinitialize()` (reloads macosglass), 23:10:32 `reconfigure`+`unloadEffect`
- 23:10:58 / 23:12:20 screenshots: desktop recovered and **alive** (clock advancing)
- 23:12:44 user `.so` set aside as `.disabled-20261013-231244`

---

# RESOLVED — 2026-10-14: the cause was the effect's IDENTIFIER

## The finding

Bisection with a **minimal effect** (a class that only loads and does nothing) and
objective measurement of black on screen (`spectacle` screenshots + PIL):

| Variant | Code | plugin id | black on screen |
|---|---|---|---|
| `bisect.so` | minimal | `bisect` | **0 %** ✅ |
| `testglass2.so` | minimal | `testglass2` | **0 %** ✅ |
| `macosglass` (full) | complete implementation | `macosglass` | **100 %** ❌ |
| `macosglass` without `paintWindow` | less code | `macosglass` | **100 %** ❌ |
| `macosglass` without `Q_PROPERTY` | almost empty class | `macosglass` | **100 %** ❌ |
| `macosglass` **with the minimal code** | **the same one that works** | `macosglass` | **100 %** ❌ |
| complete implementation renamed | **complete** | **`macosglass2`** | **0 %** ✅ |

**The same code, byte for byte, works with one id and breaks with another.**

## The conclusion

**It was not the code.** Not `paintWindow`, nor the chain call, nor the `Q_PROPERTY`s,
nor the members, nor the `.h`/`.cpp`, nor the CMake, nor the dependencies (the `.so` files have
the **same 23** in both cases), nor the installation path.

It was **the `macosglass` identifier** — which came from the whole chain of failed attempts
in this session (plugin without metadata, with the `Id` declared, named `libmacosglass`,
installed in the wrong path...).

## The fix

The effect is installed as **`macosglass2`**. `install.sh` cleans up the remains of the
old id and of the test plugins.

## What I CANNOT explain

**Why** a specific id breaks the render. The observable state was identical to that of the id
that works: same embedded metadata (`KPackageStructure: "KWin/Effect"`), same
`isSupported()`, same `enabledByDefault`, same path. I have not found the difference.

It is a data point for the KWin team: *"an effect plugin with id X leaves the composition 100 %
black, and the same binary renamed to Y works"*. It is noted down as a reproducible
observation, not as a diagnosis.

## What is genuinely fixed

- The **paint chain**: the effect **has** to call `effects->paintWindow()`.
  It was a real fault (and still is if someone removes it). See `verify-chain.sh`.
- `supported()` returned `false` because it used `effects != nullptr` (the example in KDE's
  doc), and KWin discarded the effect silently.
- The installation path is `kwin/effects/plugins/` (KWin::PluginEffectLoader).
- The file name defines the pluginId: with no `lib` prefix.
- **Never `kwin_wayland --replace`**: it leaves the screen black.

## Final status

The `macosglass2` effect loads **without breaking anything** and is hooked into the paint
chain. **It does not draw yet**: the material shader (diffusion, refraction 70,
dispersion 20, specular highlight) is the next step. The seven parameters are measured
in `tokens.toml`.


---

# VERIFIED — 2026-10-14 00:XX: the effect works on a clean boot

After rebooting the machine (sudo restored), with **only `macosglass2.so`** in the KWin
path and the three test plugins removed:

```
control          : black=  0.0%
macosglass2      : black=  0.0%   <- THE EFFECT WORKS
tras-descargar   : black=  0.0%
VERDICT: it does NOT break it
```

The script `test-installed.sh` does it without sudo (it reinstalls nothing: it loads, measures and
unloads with `trap EXIT`).

## Final effect status

```
.plugin        : /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
size           : 38824 bytes
paint chain    : 3 references to EffectsHandler::paintWindow
pluginId       : macosglass2            (the file name is what counts)
isEffectSupported : true
kwinrc         : [Plugins] macosglass2Enabled=true, blurEnabled=false
```

## Another fault of my own, fixed: `grep -q` in a pipe

The safety check in `install.sh` (`objdump | grep -q`) gave a
**NON-DETERMINISTIC** result with `set -o pipefail`: `grep -q` aborts when it finds the
match and closes the pipe, and the pipe status varies. It even got to **abort the
installation of a correct `.so`** (it happened twice).

Fixed in `install.sh`, `verify-chain.sh` and `probar-en-vivo.sh`:
`grep -c ... >/dev/null` instead of `grep -q`. Reading all the input is deterministic.
Verified 8/8 and 15/15.

Lesson: a safety check that gives false positives is worse than not having it,
because it makes you doubt something that is fine.

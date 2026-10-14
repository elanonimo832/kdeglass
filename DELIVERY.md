# Step 2 delivery: what can already be installed

This folder contains **step 2 of the plan, finished**: the token system and its
generated artifacts. It does not include the QStyle or the KWin effect (steps 4 and 5).

- Full plan: [ANALYSIS.md](ANALYSIS.md) · Installation: [INSTALLATION.md](INSTALLATION.md)
- Source tokens: [tokens/](tokens/) · Consolidated system: [tokens.toml](tokens.toml)

---

## 1. What has been generated

```
tokens.toml                     THE DESIGN SYSTEM (1813 lines, 5 axes)
output/
├── color-schemes/
│   ├── KdeMacosLight.colors    KDE light color scheme
│   └── KdeMacosDark.colors     KDE dark color scheme
├── gtk-3.0/
│   ├── kde-macos.css           Light GTK3 theme
│   ├── kde-macos-dark.css      Dark GTK3 theme
│   └── colors.css              Only the color variables
└── gtk-4.0/
    ├── kde-macos.css           Light GTK4 theme
    ├── kde-macos-dark.css      Dark GTK4 theme
    └── colors.css
install.sh                     Installer: preflight / plan / estado / aplicar / rollback / verificar
install-decoration.sh          Separate installer for the window decoration
```

All generated from the tokens. **Nothing written by hand that can fall out of sync.**

---

## 2. The five axes of the design system

| Axis | Tokens | Origin | Verified |
|---|---|---|---|
| **color** | 61 | Figma Variables export | Exact alpha, light and dark |
| **shape** | 150 | `.fig` node properties (19.011 nodes) | Radii, squircle, shadows, border |
| **metrics** | 65 | Variables export (Sizes) | 5 control sizes |
| **typography** | 80 | **Apple's official HIG** | 11 styles + tracking |
| **material** | 11 | `GLASS` effect in the `.fig` | 7 parameters |

All five are **measured or published**. None invented. And `[_procedencia]` inside
`tokens.toml` says where each one comes from.

---

## 3. What can be done now, and what cannot

| | |
|---|---|
| **Can be applied today** | KDE color schemes |
| **Requires a manual step** | The GTK theme: it has to be selected in System Settings |
| **Not yet** | The QStyle (step 4) and the KWin effect (step 5) |

The installer **does not touch the `kde-gtk-config` files** on purpose. It hooks into its
mechanism so that the next time you open the GTK settings the work is not lost.

---

## 4. How to use it

```bash
cd analisis-kde-macos

./install.sh preflight      # checks the environment. Touches nothing.
./install.sh plan           # shows WHAT it would do, file by file. Touches nothing.
./install.sh aplicar --si   # applies. Dated backup before each change.
./install.sh estado         # what is installed and how it differs
./install.sh rollback       # reverts everything with one command
```

**Golden rule of the installer:** by default it writes nothing. All the subcommands are
read-only or dry-run except `aplicar`, which also requires `--si`. You cannot break the
desktop by invoking it unintentionally.

After applying, the GTK theme is selected by hand in:
*System Settings → Appearance → GNOME/GTK Style → kde-macos*

---

## 5. Verifications that have been done

| Check | Result |
|---|---|
| The 18 partial TOMLs parse | **18/18** |
| `tokens.toml` consolidated parses | **Yes**, 5 axes |
| The 2 `.colors` parse as INI | **Yes**, 13 groups, no mandatory key missing |
| RGB values in the 0-255 range | **All** |
| CSS: references to undefined variables | **0** out of 91 per file |
| GTK3 uses `@define-color`, GTK4 uses `var()` | **Correct in each version** |
| `install.sh` syntax | **OK** |
| `plan` / `estado` / `verificar` / `rollback` | **They work** |

### WCAG contrast (the problem criticized in Tahoe)

```
                    LIGHT    DARK
Colors:Window       15.13    12.27
Colors:View         15.13    12.82
Colors:Button       13.18    10.00
Colors:Selection     5.30     6.31
Colors:Tooltip      13.87    10.92
```

Everything above 4.5 (AA). It is not a coincidence: the kit's text colors are black or
white with high alpha over the background, so the contrast comes out high **by construction**.
Tahoe's main complaint —legibility— cannot be reproduced with these tokens.

---

## 6. Three things that came up while doing this, and that correct the above

**1. `widgetStyle` does not live in `[General]`, it lives in `[KDE]`.** I took it for granted while
analyzing and it was false. Verified in the real `kdeglobals`: `widgetStyle=kvantum` is in the
`[KDE]` section. Corrected in [ANALYSIS.md](ANALYSIS.md),
[INSTALLATION.md](INSTALLATION.md) and [VERIFICATION-ANNEX.md](VERIFICATION-ANNEX.md).

**2. `kreadconfig6` hangs if there is no session bus.** It does not fail: it hangs
indefinitely. The installer probes it with `timeout` and, if it does not respond, reads the INI
directly. An installer cannot hang.

**3. `kdeglobals` files can have CRLF line endings.** The trailing `\r` breaks any
text comparison, and `gsub(/[][]/)` is not portable for stripping brackets either. Both
things are solved in the reader.

None of the three would have been seen without running the installer against your real system.

---

## 7. What is missing, and why it does not block

| Missing | Phase |
|---|---|
| QStyle in C++ | Step 4 of the plan. Not written yet; the `cmake` and `ninja` it needs are installed (see §10) |
| KWin effect (material + corners) | Step 5. It depends on the previous one, although the material is already measured |
| Icons | Outside the current scope. Apple's are not used for license reasons |
| Inter font | It has to be installed in `~/.local/share/fonts` (SIL OFL, redistributable) |

The tokens those steps need **are already measured and in `tokens.toml`**, so
when the QStyle is written there will be no need to go back to Figma.


---

## 10. Step 5 (KWin effect): real status

The material effect has been started. Honest status, with what was verified and what is missing.

### What has been demonstrated

**1. A KWin effect can be built on this system without `cmake`.** Verified:
it compiles and links.

> **HISTORICAL (hand-rolled `g++` build, old id `macosglass`).** The commands below
> record the manual build done at the time; they produced `macosglass.so`. The
> current build uses `cmake` and emits `macosglass2.so` (see "RESOLVED" below).

```
g++ -c -fPIC -std=c++20 -I/usr/include/kwin -I/usr/include/kwin/effect <rutas KF6> glass.cpp
g++ -shared -fPIC -o macosglass.so glass.o moc_glass.o $(pkg-config --libs Qt6Core Qt6Gui) -lkwin
-> plugin of 53 KB, no errors
```

The **KWin and KF6 headers are already installed** (`/usr/include/kwin/effect/`,
`/usr/include/KF6/`), and `libkwin.so` exists. `moc` too.

**2. The KWin 6 API is different from KWin 5's, and it is now identified:**

| KWin 5 (what I assumed) | KWin 6.7 (real) |
|---|---|
| `paintWindow(..., QRegion, ...)` | `paintWindow(..., const Region &, ...)` |
| `WindowPaintData::painter` (QPainter) | **It does not exist**: drawing is done with OpenGL over `GLFramebuffer` |
| — | `RenderTarget::framebuffer()` / `texture()` |
| — | `GLShader` (public constructor) and `ShaderManager` |
| — | `BackgroundEffectItem`, for background effects such as blur |

**3. The installation paths are the correct ones:**
`~/.local/lib/qt6/plugins/kwin/effects/` (binary) and
`~/.local/share/kwin/effects/<id>/metadata.json`.

### RESOLVED: the effect compiles and is a valid plugin

With `cmake` and `ninja` installed, and after figuring out four things that cost dearly:

| Discovery | Consequence |
|---|---|
| `KWinConfig.cmake` requires **ECM** | `extra-cmake-modules` has to be installed |
| `KWinConfig.cmake` requires **Vulkan** | Only to satisfy `find_package`: the effect does not use it. It is solved with a 20-line stub instead of 42 MiB of headers |
| `kcoreaddons_add_plugin` builds an **`.a`** if `BUILD_SHARED_LIBS` is false | A plugin has to be a shared module: it has to be enabled |
| The code macro defines a class with `Q_OBJECT` **in the `.cpp`** | `#include "glass.moc"` is needed or the entry point is not generated |

Result:

```
[6/6] Linking CXX shared module plugins/kwin/effects/macosglass2.so
```

And the checks that failed before now pass:

```
exports qt_plugin_instance      : YES
exports qt_plugin_query_metadata_v2 : YES
metadata embedded               : YES (IID org.kde.kwin.EffectPluginFactory)
```

**This was the blocker of the previous step and it is resolved.**

### The remaining blocker: where KWin looks for it

`KPluginMetaData::findPlugins("kwin/effects/")` searches the **Qt plugin paths**.
`~/.local/lib/qt6/plugins` **is not among them** in the session, so KWin does not see the
effect even if it is installed there.

Two ways out, both documented:

1. **Without sudo:** `~/.config/environment.d/90-kde-macos.conf` with `QT_PLUGIN_PATH`.
   It requires restarting the session for KWin to read it on startup.
2. **Immediate:** a script, `effect-kwin/install.sh`, that copies the `.so` to
   `/usr/lib/qt6/plugins/kwin/effects/` (needs sudo).

### What the effect does today

**Nothing visible yet.** The skeleton is there: the `paintWindow` hook, the kit values
in `reconfigure()`, and **it loads without drawing**. The material shader is missing.

### The previous blocker, already resolved

```
QPluginLoader: "is not a Qt plugin (metadata not found)"
```

The `.so` is well formed — the verifier loads real system plugins without a problem,
but it rejects ours. **The plugin metadata is not correctly
embedded.** It is exactly what CMake's `qt6_add_plugin()` does, and doing it by hand is
fragile and depends on the Qt version (6.12 changed the mechanism).

Both documented ways were tried without success: the `:/qtmetadata` resource and the
`:/metadata.json` resource.

### What has to be installed, and why

```
sudo pacman -S --needed cmake ninja
```

**Only the tool.** No additional development package is needed: the
headers are already there. It is ~102 MiB for `cmake` plus half that for `ninja`.

With that, `effect-kwin/build.sh` compiles and installs the effect, and the
`CMakeLists.txt` is already written using `kcoreaddons_add_plugin`, which takes care of
the metadata, the `moc` and the installation path.

### What the effect does today, and what it is missing

Implemented: the effect skeleton, with the `paintWindow` hook and the kit values
in `reconfigure()` (border alpha 20 = black at 8 %, which is
`Fills - Opaque / Secondary`).

**Drawing is missing**, which is the meaty part: the material needs a shader
pass over the background to do **diffusion, refraction (`70`), dispersion (`20`)** and
the **specular highlight**. The seven parameters are measured and in `tokens.toml`; what is
missing is the shader and its integration with `RenderTarget`.

### The two-layer window shadow

Also from step 5. The two measured layers (diffuse radius 54 + contact radius 1) could
be drawn by an effect, because **Aurorae does not support two shadows**. But it depends on the
same unblocking.


---

## 11. The effect, step by step until it loads

Five real obstacles, each one discovered with the KWin journal. They are noted down
because none is obvious and all five cost the same if they are repeated.

| # | Obstacle | Symptom | Solution |
|---|---|---|---|
| 1 | `KWinConfig.cmake` requires **ECM** | `Could not find a package configuration file provided by "ECM"` | `extra-cmake-modules` |
| 2 | `KWinConfig.cmake` requires **Vulkan** | `Could NOT find Vulkan (missing: Vulkan_INCLUDE_DIR)` | 20-line stub in `_stub/`, instead of 42 MiB of headers. The effect **does not use Vulkan** |
| 3 | `kcoreaddons_add_plugin` generates an **`.a`** | `Linking CXX static library` | `set(BUILD_SHARED_LIBS ON)`. A plugin has to be a module |
| 4 | The macro defines a class with `Q_OBJECT` in the `.cpp` | `is not a Qt plugin (metadata not found)`, without `qt_plugin_instance` | `#include "glass.moc"` at the end of the `.cpp` |
| 5 | `KPackageStructure` was missing | `does not match requested format "KWin/Effect"` | `"KPackageStructure": "KWin/Effect"` in the metadata |

### And the error that almost led me astray

I put a loose `metadata.json` in `/usr/share/kwin/effects/macosglass/`. KWin answered:

```
Failed to load macosglass effect: invalid X-Plasma-API field: .
```

**KDE's official documentation clarifies it**: `X-Plasma-API` is what marks a
**QML** effect (`"declarativescript"`). All the effects in `/usr/share/kwin/effects/` are
javascript or declarativescript. A **C++** plugin does not carry that field: its metadata goes
**embedded in the `.so`**, and that is enough for KWin to discover it. The loose `metadata.json`
made KWin treat it as a script.

### The last obstacle: KWin does not rescan

`isEffectSupported` went from `true` to `false` when the loose metadata was removed, and it never came back.
The cause: **KWin builds the effect list on startup and does not rescan it.**
`reconfigure` reloads the effects already loaded, but it does not look for new plugins.

Verified:

```
KWin running since       : 21:14
.so installed            : 22:04   <- 50 minutes later
reconfigure              : does not see it
kbuildsycoca6            : not enough (rebuilt, still does not see it)
```

**Solution: restart the session** (log out and back in). Then KWin
starts, finds the `.so` and loads it.

To verify it without guessing, there is a script: **`effect-kwin/verify-chain.sh`**.


---

## 12. KWin effect status: what is verified and what is not

> **HISTORICAL (old id `macosglass`).** This section records the state before the
> identifier was identified as the cause. The effect is now `macosglass2`, it is
> installed as `macosglass2.so` and KWin reports `isEffectSupported : true`
> (see §16, §17 and INCIDENT.md).

### Verified: the plugin fulfills the KWin contract

There is a tool in `effect-kwin/src/verify-load.cpp` that does **exactly** what
KWin does on startup: discover the plugin, instantiate the factory and ask it
`isSupported()`. Its output:

```
pluginId      : macosglass
isSupported() : YES -> KWin would accept it
enabledByDef  : YES
summary: 1 plugins with factory, 1 supported
```

And `KPluginMetaData::findPlugins("kwin/effects/")` —the API KWin uses to search for
effects— finds it in `/usr/lib/qt6/plugins/kwin/effects/macosglass.so` with the
correct `pluginId`.

### And yet KWin answers `false`

```
isEffectSupported : false
isEffectLoaded    : false
in listOfEffects  : 0
```

Also verified that **it is not a timing problem**: KWin was restarted at 22:19 and
the `.so` is from 22:17, so it had it in front of it on startup.

And it is not the ksycoca cache: it was rebuilt and nothing changed.

### What was ruled out, with tests

| Hypothesis | How it was ruled out |
|---|---|
| The plugin does not load | `QPluginLoader::load()` → **YES** |
| The metadata is wrong | `strings` shows `KPackageStructure: "KWin/Effect"` |
| The `pluginId` does not match | `findPlugins` returns `macosglass`, same as the `kwinrc` |
| The Qt entry point is missing | it exports `qt_plugin_instance` and `qt_plugin_query_metadata_v2` |
| `isSupported()` returns NO | **corrected**: now it returns YES (measured) |
| KWin does not rescan on startup | KWin restarted with the `.so` already installed |
| Stale plugin cache | `kbuildsycoca6` rebuilt, no effect |
| It takes it for a QML effect | the loose `metadata.json` was removed |
| The file's `lib` prefix | `PREFIX ""` in CMake; the pluginId is already correct |

### The next concrete step

The disassembly of `KWin::EffectLoader::isEffectSupported` shows that it walks a list
of sub-loaders and delegates to `PluginEffectLoader` and `ScriptedEffectLoader`. The plugin
fulfills the contract, so it remains to be seen **what additional check**
`PluginEffectLoader` performs. The way to see it is the KWin journal with plugin debugging
enabled when the compositor starts.

### What is NOT done

**The material shader.** The effect, when it loads, only writes a message to the log:
`paintWindow` is hooked but it does not draw. Diffusion, refraction
(70), dispersion (20) and the specular highlight over `GLFramebuffer` remain to be implemented. The seven parameters
are measured and in `tokens.toml`.

### What did get finished and working

- The **226 macOS tokens**, with provenance per token
- The **two KDE color schemes**, with WCAG AA contrast
- The **GTK 3 and 4 CSS**
- The **macOS-style window decoration**: traffic lights on the left, with a ring, and gray
  when losing focus — **working in the real session**
- The **installer**, idempotent and reversible


---

## 13. INCIDENT 2026-10-13: black screen from `kwin_wayland --replace`

**This is a correction to my own advice.** I recommended `kwin_wayland --replace`
as a "safe" alternative to restart KWin without logging out. **It is not.**

In Wayland `--replace` starts a **second compositor** that competes for the DRM/GL with the
one already running. The live KWin loses the OpenGL context and ends up compositing an
empty canvas: **black screen with the cursor visible**. KWin and plasmashell are still alive and
they respond over D-Bus, which makes the diagnosis confusing.

Evidence from the journal:

```
kwin_wayland: No QSGTexture provided from updateSampledImage(). This is wrong.
kwin_wayland: Could not delete render time query because no context is current
```

**The `macosglass` effect was NOT the cause.** It was tested live: its `paintWindow` is a
no-op that only writes a log, and disabling it changed nothing. The trigger was
`--replace`.

### The correct thing, always

```bash
sudo systemctl restart plasmalogin   # restarts the session manager
# or log out and back in
```

**Never `kwin_wayland --replace`** on Wayland.

### Method detail that would have warned me

Earlier in this same session I tried to start a **nested KWin** to test the decoration,
and the process died without a log because the sandbox would not let it create the socket. **I already had the
signal that launching another compositor on Wayland is problematic**, and even so I recommended
`--replace` as a shortcut. The signal was right there and I did not read it.

### Documents

- [INCIDENT.md](INCIDENT.md) — full report, symptoms and diagnosis
- [RECOVER-KDE.sh](RECOVER-KDE.sh) — recovery script (idempotent and reversible)
- `effect-kwin/install.sh` — corrected warning; it no longer mentions `--replace` as an option

---

## 14. SECOND INCIDENT 2026-10-13 23:04: the effect WAS the cause (correction to §13)

§13 concluded, with the old build, that `macosglass` was not the cause. **That was false.** At
23:03:42 the new `.so` was reinstalled and enabled (`macosglassEnabled=true`); at 23:04:22
the user logged out and back in; the new KWin (PID 3458) loaded the effect
(`[macos-glass] cargado` 23:04:23, `paintWindow` 23:04:24) and at 23:04:42 it started spewing
`Could not delete render time query because no context is current` -> black screen.

Comparison that makes it clear, within the same boot:

| KWin | Session | macosglassEnabled | Context errors |
|---|---|---|---|
| 1314 | 22:54–23:04 | false | 0 |
| 3458 | 23:04–… | true | 5 (23:04:42–23:05:19) |

### HOT recovery (it worked, without logging out)

```bash
bash ~/RECOVER-KDE.sh recuperar --reset-output
export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
qdbus6 org.kde.KWin /KWin       org.kde.KWin.reconfigure
qdbus6 org.kde.KWin /Effects    org.kde.kwin.Effects.unloadEffect macosglass
qdbus6 org.kde.KWin /Compositor org.kde.kwin.Compositing.reinitialize
```

Now all of that is `bash ~/RECOVER-KDE.sh reanimar`. **The order matters:** `reinitialize()`
reloads the effects according to the config KWin has IN MEMORY; without `reconfigure()` before it,
it loads `macosglass` again (it happened at 23:10:07).

### Verification

Screenshots 23:10:58 and 23:12:20, with the panel clock advancing 11:06 -> 11:12 PM:
`evidence/2026-10-13-2314-pantalla-recuperada.png`. Desktop alive.

### Status and protection

- `macosglass` and `blur` disabled; user `.so` set aside as `.disabled`.
- The system `.so` is still in `/usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so` (the old id at the time was `macosglass.so`; deleting it requires root).
- `effect-kwin/install.sh` now **aborts** unless `--force` is passed.
- Document: [INCIDENT.md](INCIDENT.md) · script: [RECOVER-KDE.sh](RECOVER-KDE.sh)

---

## 15. DECISIVE TEST (2026-10-13 23:24): the cause is confirmed 100 %

I proposed this test when closing §14 and it was executed live, with the desktop stable and the
graphical session (tty3) active. Instead of trusting only the log, I measured **pixels** from `spectacle`
screenshots (3840x2160) with PIL:

| Screenshot | `macosglass` | Content |
|---|---|---|
| A (control) | unloaded | 861 KB — real desktop, 0,1 % black |
| B (+10 s) | loaded live | 32 KB — **100 % `#000000`** |
| B (+30 s) | loaded | 32 KB — **100 % `#000000`** |
| C | unloaded (without `reinitialize`) | 856 KB — real desktop |
| D | after `reinitialize` | 855 KB — real desktop |

**Result:** the effect leaves the composition 100 % black and **unloading it restores it
instantly**. Cause settled.

An honest nuance: on live load the effect does **not** log `paintWindow` (it breaks the
render before that path); on the incident boot it did reach `paintWindow`. And the
error `no context is current` reappeared only 1 time (tied to the effect cycle), not in
a wave. The conclusive test was the **image**, not the journal.

Evidence: `evidence/2026-10-13-2324-prueba-control-escritorio.png`,
`evidence/2026-10-13-2324-test-effect-loaded-black.png`,
`evidence/2026-10-13-2324-prueba-tras-descargar.png`.
Detail and commands: [INCIDENT.md](INCIDENT.md) §"Decisive test — EXECUTED".

---

## 16. FIXED (2026-10-13 23:32): the chain call was missing in `paintWindow()`

The cause of the black screen was not the OpenGL context: it was a **contract
bug** in our effect.

`EffectsHandler::paintWindow()` calls **a single** effect; the chain advances
because the base implementation `Effect::paintWindow()` re-enters
`effects->paintWindow()`. Our effect overrode `paintWindow()` and
**returned without calling the base**, so the chain was cut at `macosglass`:
`WorkspaceScene::finalPaintWindow()` never ran and **no window was
painted**. The Plasma background/panel is one more window → only the black
background was left.

Fix in `effect-kwin/src/glass.cpp`: all paths end in
`effects->paintWindow(renderTarget, viewport, w, mask, deviceRegion, data);`.

Verification without touching the session (at binary level):

```
old .so (system) : 0 references to EffectsHandler::paintWindow
new .so (build)  : tail-call to EffectsHandler::paintWindow   ✅
```

New tools:

| File | What it does |
|---|---|
| `effect-kwin/verify-chain.sh` | Checks source + binary and warns if the installed `.so` is the old one |
| `effect-kwin/test-installed.sh` | Loads the installed effect, captures, measures % black and **always unloads** (`trap EXIT`); it installs nothing and needs no `sudo`. It does **not** verify the paint chain — that is `verify-chain.sh`'s job |

`build.sh` and `install.sh` now **abort** if the chain is not there, and
`build.sh` **no longer activates** the effect (before it could load the old system
`.so` and repeat the incident).

The effect still **does not draw** (the material shader is the next step),
but it is safe: it behaves as if it were not loaded.

> **HISTORICAL (2026-10-13, old id `macosglass`):** the agent could not install the
> binary (the sandbox cannot `sudo`), so at that time the system `.so` was still the
> old one. Installation and test with the current id:
> ```
> cd effect-kwin && ./verify-chain.sh
> sudo install -Dm755 build/plugins/kwin/effects/macosglass2.so \
>      /usr/lib/qt6/plugins/kwin/effects/plugins/macosglass2.so
> ./test-installed.sh
> ```

---

## 17. FINAL CORRECTION (2026-10-14): read INCIDENT.md

Sections §13, §14, §15 and §16 of this document record **four
successive conclusions** about the black screen, and **all but the last are
superseded**. They are kept as a record of the debugging.

**The final cause, verified by bisection: the effect's IDENTIFIER.**
The same code compiled as `macosglass` leaves the composition 100 % black;
with `macosglass2` it works. The effect is now called `macosglass2`.

**Effect status (2026-10-14):**
- Installed in the correct path (`kwin/effects/plugins/`) and it loads without breaking anything
- **It does not draw yet**: the material shader is the next step
- The project is under git, with a full test harness (`tests/run.sh`)
- Of the 9 debugging scripts, 4 remain, and the deleted ones pointed to the old id

> For the complete, ordered account, see **`INCIDENT.md`**, which also carries
> an authoritative summary at the top.

# Annex · Verification of the brief's assumptions

Record of what was checked, with what evidence and with what degree of confidence. It is
kept separate from [ANALYSIS.md](ANALYSIS.md) so that the conclusions do not depend
on external links.

**Confidence levels used:**

- **Confirmed** — there is a cited external source that backs it.
- **Domain knowledge** — it rests on how Qt/KDE/GTK work, without a source
  cited in this document. Verifiable on the system itself with the commands given.
- **Inference** — reasoning from the above, not a verified fact.

---

## 1. Status of macOS 27 "Golden Gate"

| Assumption in the brief | Confidence | Evidence |
|---|---|---|
| macOS 27 is called "Golden Gate" | **Confirmed** | [Gigazine](https://gigazine.net/news/20260609-apple-wwdc26-macos-27/) reports it as a codename with WWDC26 in the background; [Macwelt](https://www.macwelt.de/article/3167570/golden-gate-der-letzte-spitzname-fur-macos.html) treats it as the possible last nickname |
| macOS 27 fixes the defects of Liquid Glass | **Confirmed** | [RTBF](https://beta.rtbf.be/article/macos-27-apple-va-revoir-son-interface-liquid-glass-pour-repondre-aux-critiques-11722252), [iPhoneSoft](https://iphonesoft.fr/2026/05/10/macos-27-corriger-defauts-liquid-glass-mac) and [HWUpgrade](https://www.hwupgrade.it/news/apple/macos-27-apple-corregge-il-tiro-sul-liquid-glass-e-risolvere-i-difetti-grafici_153427.html) explicitly frame it as a response to the criticism |
| Tahoe / macOS 26 was the initial and heavily criticized Liquid Glass | **Confirmed** | The same sources describe the contrast and legibility criticism |
| The specific tokens in the brief (radii, opacities) | **Not verified** | No source consulted confirms the numeric values nor that the corrections are exactly the seven listed. The brief presents them as facts; they are plausible but **not cross-checked** |

**Implication:** the brief is correct in the general framing and unverified in the detail.
The token values must be treated as a **draft to validate against the final system**,
not as a specification. This reinforces the recommendation to version the tokens (§4.4 of the
analysis).

---

## 2. Corner clipping in KWin

| Assumption | Confidence | Evidence |
|---|---|---|
| There is a KWin effect that rounds the corners of all windows | **Confirmed** | [LightlyShaders](https://github.com/a-parhom/LightlyShaders) (corners + outline) and its [port to Plasma 6](https://github.com/walterfang12/LightlyShaders-Plasma6); [kwin-effect-rounded-corners](https://github.com/ekaaty/kwin-effect-rounded-corners); [package on Launchpad](https://launchpad.net/~matinlotfali/+archive/ubuntu/kde-rounded-corners) |
| The effect applies to windows of foreign apps (GTK included) | **Confirmed** (by the existence and use of those projects) | KWin effects act in the compositing phase, independently of the client's toolkit |
| "Rounding" and "clipping" are the same thing | **False** | Direct inference from the mechanism: rounding paints transparency outside the shape; clipping removes drawn pixels. See §3 A4 of the analysis |
| The radius will be single for all windows | **Not guaranteed** | The effect only controls the outer border; a client with its own decoration (CSD) contributes its own inner radius |

**Implication:** the part of the brief that deserved the most skepticism is, in fact, **the
most backed by precedents**. The KWin effect goes up in priority.

---

## 3. Custom QStyle in Plasma 6

**Update:** this section was the one with the **least documentary support** in the analysis
(it was an absence, and absences are not cited well on the web). After verifying
the system directly, it is now **the best confirmed**. Direct evidence:

```
kcm_style.so present in /usr/lib/qt6/plugins/plasma/kcms/systemsettings/
internal strings of the binary:
    settingName: "widgetStyle"
    widgetStyle / WidgetStyle / widgetStyleChanged / defaultWidgetStyleValue
    isWidgetStyleImmutable
~/.config/kdeglobals            ->  [KDE] widgetStyle=kvantum
/usr/lib/qt6/plugins/styles/    ->  breeze6.so, libkvantum.so
```

| Assumption | Confidence | How to verify it on your system |
|---|---|---|
| The style is selected with the `widgetStyle` key of `kdeglobals`, in the **[KDE]** section | **Confirmed** in the real kdeglobals (not in `[General]`, as I assumed at first) | `kreadconfig6 --file kdeglobals --group KDE --key widgetStyle` |
| Plasma 6 keeps the "Application Style" KCM | **Confirmed** | *System Settings → Appearance*; `kcm_style.so` present |
| Plasma 6 **does not offer per-application style** (unlike Plasma 5) | **Domain knowledge** | There is no per-app selector in the KCM; the mechanism is a global key |
| A third-party QStyle can be active **without** `QT_STYLE_OVERRIDE` | **Confirmed** | Kvantum is active on this machine and `env` does not show `QT_STYLE_OVERRIDE` |
| `isWidgetStyleImmutable` exists, which can override the key | **Confirmed** (string in the binary) | If step 4 fails silently, check this before the QStyle |
| Qt 6 loads style plugins from a plugins directory | **Domain knowledge** | `/usr/lib/qt6/plugins/styles` exists; **still to check** whether Qt6 scans `~/.local/lib/qt6/plugins` (see §6) |
| A QStyle cannot be generated from JSON | **Domain knowledge** | `QStyle` is a C++ class with virtual drawing and metric methods |
| The brief does not mention the activation mechanism | **Confirmed by reading** | The brief does not contain `widgetStyle`, `QT_STYLE_OVERRIDE`, `.desktop` or `environment.d` |

**Correction of my own analysis:** in the first version I stated that `QT_STYLE_OVERRIDE` plus a
launch mechanism was needed. That was **too pessimistic**: the requirement (the brief ignored
activation) was true, but the solution is **a configuration key**. Section A2 of
[`ANALYSIS.md`](ANALYSIS.md) carries the correction note, and the correct design is in
[`INSTALLATION.md`](INSTALLATION.md) §1.

---

## 4. GTK4 and `libdecor`

| Assumption | Confidence | Evidence |
|---|---|---|
| `libdecor` is a **client** library for hybrid decoration, not a mechanism to force server-side decoration | **Domain knowledge** | Client integration example: [libdecor variant of a Wayland decorations example](https://raw.githubusercontent.com/PetarKirov/sparkles/refs/heads/main/docs/research/window-system-integration/os-apis/wayland/examples/f13-decorations/libdecor-variant/app.d) |
| GTK4 does not use `libdecor` | **Domain knowledge** | GTK4 manages its own CSDs on Wayland |
| `kde-gtk-config` applies the theme to GTK3 | **Domain knowledge** | That is its function; the brief cites it correctly |
| WhiteSur-style themes "do not change the structure" and fail in many apps | **Confirmed** (partial) | [Issue in nixpkgs](https://github.com/NixOS/nixpkgs/issues/366254) reports that `whitesur-gtk-theme` "does not work with most apps" |
| Electron/Flatpak/libadwaita apps resist the theme | **Strong inference** | It follows from the packaging model and from CSDs; the brief is right to anticipate it |

**Implication:** the brief's claim about `libdecor` ("the app yields drawing to the
compositor") describes `xdg-decoration` in server-side mode, not `libdecor`. Correct the
wording; the brief's practical conclusion (GTK is last and with realistic expectations) holds
intact.

---

## 6. Machine survey (13/10/2025)

Facts read directly from this system, not from external sources. They are the basis of
[`INSTALLATION.md`](INSTALLATION.md).

### Environment

| Item | Value |
|---|---|
| OS | CachyOS Linux (`ID=cachyos`, `ID_LIKE=arch`), rolling |
| Session | `XDG_SESSION_TYPE=wayland`, `XDG_CURRENT_DESKTOP=KDE`, `KDE_SESSION_VERSION=6` |
| Compositor | `kwin_wayland` present |
| Active style | `widgetStyle=kvantum` in `kdeglobals` |
| Global theme | `LookAndFeelPackage=Ant-Dark` |
| Kvantum | `~/.config/Kvantum/kvantum.kvconfig` → `theme=Ant-Dark` |
| GTK | `gtk-theme-name=Breeze`, `gtk-font-name=Noto Sans, 10` |
| Style plugins | `/usr/lib/qt6/plugins/styles/` → `breeze6.so`, `libkvantum.so` |
| Style plugins (2nd path) | `/usr/lib64/qt6/plugins/styles` also exists → **detect `lib` vs `lib64`** |

**Coherence observation:** the system mixes layers (`LookAndFeelPackage=Ant-Dark` with
`widgetStyle=kvantum` and GTK in `Breeze`). The project would unify that state, and the
`estado` subcommand also serves as a diagnostic tool for this kind of mismatch.

### Tools present

```
kwriteconfig6  kreadconfig6  kded6  qdbus6  gdbus  update-desktop-database
gcc  g++  pkg-config  fc-cache
/usr/include/qt6/QtWidgets   (Qt6 development headers)
```

### Tools absent

```
qtpaths6   -> not installed (the plugin path cannot be queried this way)
cmake      -> ABSENT. Needed to compile the QStyle
ninja      -> ABSENT. Ditto
```

`cmake` and `ninja` are a **development** requirement, not an installer one. They are installed with
`pacman` (sudo, system), which confirms the brief's distinction: *the deliverable does not use
sudo; development does install tools*.

### Paths the installer must resolve empirically

1. **Does Qt6 scan `~/.local/lib/qt6/plugins`?** It could not be checked here: `qtpaths6` is not
   installed and the session has no systemd user bus. `~/.local/lib` **does not
   exist** yet. It is resolved in `preflight` with `QT_DEBUG_PLUGINS=1`; if it is not in the
   search path, the solution is `QT_PLUGIN_PATH` in `~/.config/environment.d/`
   (a directory that **also does not exist** yet and would have to be created).
2. **`lib` vs `lib64`:** both plugin paths exist on the system. The installer must
   detect which one it uses and not assume `lib`.
3. **KWin has no user effects** (`~/.local/lib/*/kwin/effects` does not exist): the path must be
   created. The KWin plugin directory for effects could not be confirmed from
   this shell and must be verified before stage 3.

### Mechanisms already in use that the project can reuse

| Mechanism | Evidence |
|---|---|
| `kde-gtk-config` manages GTK | `~/.config/gtk-3.0/window_decorations.css` and `colors.css` exist, generated by KDE; `gtk.css` contains only `@import 'colors.css';` |
| Flatpak receives configuration by override | 7 files in `~/.local/share/flatpak/overrides/` (Chrome, Chromium, Firefox, LibreWolf, Waterfox…). **Current content: session bus policy only**, without theme variables → the `flatpak override --user --env=` route is free for the project |
| User fonts | `fc-cache` present; `~/.local/share/fonts` does not exist yet (it is created) |

**Survey conclusion:** the system supports the project **without any new operating system
piece** except the QStyle compilation tools (`cmake`, `ninja`).
Everything the installer needs to apply color, typography, Qt style, KWin effect,
GTK and Flatpak **is already installed**.

---

## 7. Sources consulted

Searches performed on 13/10/2025. Only the sources actually used are listed.

**macOS 27 / Liquid Glass**
- [Golden Gate – der letzte Spitzname für macOS? — Macwelt](https://www.macwelt.de/article/3167570/golden-gate-der-letzte-spitzname-fur-macos.html)
- [macOS 27 : Apple va revoir son interface Liquid Glass — RTBF](https://beta.rtbf.be/article/macos-27-apple-va-revoir-son-interface-liquid-glass-pour-repondre-aux-critiques-11722252)
- [macOS 27 va corriger les défauts du Liquid Glass sur Mac — iPhoneSoft](https://iphonesoft.fr/2026/05/10/macos-27-corriger-defauts-liquid-glass-mac)
- [macOS 27: Apple corregge il tiro sul Liquid Glass — HWUpgrade](https://www.hwupgrade.it/news/apple/macos-27-apple-corregge-il-tiro-sul-liquid-glass-e-risolvere-i-difetti-grafici_153427.html)
- [macOS 27のコードネームは「Golden Gate」 — Gigazine](https://gigazine.net/news/20260609-apple-wwdc26-macos-27/)

**KWin / rounded corners**
- [a-parhom/LightlyShaders — GitHub](https://github.com/a-parhom/LightlyShaders)
- [walterfang12/LightlyShaders-Plasma6 — GitHub](https://github.com/walterfang12/LightlyShaders-Plasma6)
- [guiodic/LightlyShaders — GitHub](https://github.com/guiodic/LightlyShaders)
- [ekaaty/kwin-effect-rounded-corners — GitHub](https://github.com/ekaaty/kwin-effect-rounded-corners)
- [KDE-Rounded-Corners — Launchpad](https://launchpad.net/~matinlotfali/+archive/ubuntu/kde-rounded-corners)

**Themes / GTK**
- [The pkg whitesur-gtk-theme doesnt work with most apps — nixpkgs #366254](https://github.com/NixOS/nixpkgs/issues/366254)

**Wayland / decorations**
- [Example of decorations with a libdecor variant](https://raw.githubusercontent.com/PetarKirov/sparkles/refs/heads/main/docs/research/window-system-integration/os-apis/wayland/examples/f13-decorations/libdecor-variant/app.d)

**KDE (general reference)**
- [KDE Stack Overview and How It All Fit Together (Akademy/conf.kde.org, PDF)](https://conf.kde.org/event/5/contributions/161/attachments/98/119/kde-stack-overview-training-2023-edition.pdf)
- [Bug 476536 — gesture animations in overview](https://bugs.kde.org/show_bug.cgi?id=476536)

# Analysis · "macOS-style" desktop layer for Linux

Analysis folder for the brief [`BRIEF-ORIGINAL.md`](BRIEF-ORIGINAL.md): a
Linux desktop with the look of **native** macOS (QStyle + KWin effect + tokens), not
a theme.

## Contents

| File | What it is |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | **How the project is structured** and why |
| [`docs/METHODOLOGY.md`](docs/METHODOLOGY.md) | **How we work**: the five rules, each one born from a real failure |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | **What is missing**, by milestone, with a "done" criterion |
| [`BRIEF-ORIGINAL.md`](BRIEF-ORIGINAL.md) | The original brief, as is (3551 bytes, `sha256:1f95c523…`). Unmodified |
| [`ANALYSIS.md`](ANALYSIS.md) | The analysis: verdict, technical corrections, omissions and reordered plan |
| [`INSTALLATION.md`](INSTALLATION.md) | How it is installed and how it is applied: repo, real destinations, deployment stages and rollback |
| [`DESIGN-REFERENCES.md`](DESIGN-REFERENCES.md) | Where the numbers come from: Apple's official kit, provisional values and how to measure screenshots |
| [`FIGMA-INVENTORY.md`](FIGMA-INVENTORY.md) | What the Figma exports contain, what was extracted and what is missing |
| [`MISSING-TRACES.md`](MISSING-TRACES.md) | What data is missing, why it is not in Figma and how to get it |
| [`fuentes/`](fuentes/) | Raw answers from the official sources (Apple HIG) that back the tokens |
| [`tokens/`](tokens/) | Extracted macOS tokens, by axis |
| [`tokens.toml`](tokens.toml) | **The consolidated design system** (5 axes) |
| [`DELIVERY.md`](DELIVERY.md) | **Step 2 delivery**: what is generated, how it is installed and what was verified |
| [`SCREEN-VERIFICATION.md`](SCREEN-VERIFICATION.md) | Measurement of the real screenshot: what was applied matches what was generated |
| [`INCIDENT.md`](INCIDENT.md) | **Black-screen incident**: what caused it and how to recover |
| [`RECOVER-KDE.sh`](RECOVER-KDE.sh) | Recovery script, idempotent and reversible |
| `output/` | Generated KDE color schemes and GTK CSS |
| `install.sh` | Idempotent and reversible installer (writes nothing without `--si`) |
| `install-decoration.sh` | Installer for the adjusted window decoration |
| [`VERIFICATION-ANNEX.md`](VERIFICATION-ANNEX.md) | Which assumption in the brief was checked, with what evidence and with what confidence |
| `README.md` | This index |

## Analysis summary

**The plan is solid.** It gets the diagnosis right (a theme repaints, it does not
re-architect), it rules out the wrong solutions (themes, `LD_PRELOAD`, a fork of Plasma) and the
portable deliverable from step 2 has value on its own even if the QStyle is never
finished.

**Four operational assumptions to correct before writing code:**

1. **The QStyle is not generated from tokens.** Colors, CSS, assets and
   `Tokens.h` are generated; the C++ QStyle is written. Generator and implementation must be separated.
2. **The QStyle does not activate on its own.** The requirement was real, but when verifying the system it
   was resolved **for the better**: Plasma 6 selects the style with **one key in `kdeglobals`**
   (`[KDE] widgetStyle`), and this machine already proves it with Kvantum active. There is no
   need to force the style per process. See [`INSTALLATION.md`](INSTALLATION.md) §1.
3. **`libdecor` is not the way for GTK4.** It is a client library, and GTK4 does not use it.
   The irreducible percentage of GTK4 is higher than the estimated 10 %.
4. **Rounding corners ≠ clipping them.** Rounding is viable and is backed by
   precedents (LightlyShaders); clipping removes content drawn in the corners.

**Two omissions that weigh more than any technical decision:**

- **Typography.** The brief devotes all its detail to the material and none to the font,
  and without equivalent typographic metrics the result will not look like macOS.
- **Measurement.** There is no definition of "done" nor visual regression tests, which
  in a purely aesthetic project are the only test that makes sense.

**Proposed reordering:** a step 0 of infrastructure and measurement, the KWin
corner effect moved from step 5 to 3 (it is the biggest visual impact per line of code), and
HDR explicitly to v3.

> Full detail and table of the 12 actions on the brief: [`ANALYSIS.md`](ANALYSIS.md).

---

## How to verify that everything is still fine

```bash
tests/run.sh            # the full harness (~30 s)
tests/run.sh efecto     # only one area: artefactos|efecto|scripts|documentacion
```

The harness watches the invariants that have cost the most, not the formatting:

- the **tokens** are valid TOML and regenerating a scheme yields an **identical** file
- the **effect** calls `effects->paintWindow()` (without that, black screen)
- the plugin path is `kwin/effects/plugins` (**one level** of difference, 2 hours)
- the id is `macosglass2`, **not** `macosglass` (with that id the render broke)
- no script **runs** `kwin_wayland --replace` (it leaves the screen black)

> Assertions about code **ignore comments**, and no test is taken as
> good until it is checked that it **fails** when the code is broken. Both rules came from
> real errors: a test that passed because of a comment, and another that did not detect
> the breakage.

---

## Credentials: this repository stores none

**Never put a token, password or key in the repository.** `.env`, `.pem`, `.key`
and similar files are in `.gitignore`, but that is a net, not a guarantee: **a secret
that enters the git history is permanent** even if it is deleted later, and GitHub
revokes the ones it detects as leaked —publishing them in the process—.

To upload the project, the token stays on your machine:

```bash
# Option A: GitHub CLI (logs in once, stores the token in the keyring)
sudo pacman -S --needed github-cli
gh auth login
gh repo create <nombre> --public --source=. --push

# Option B: git with credential helper
git config --global credential.helper libsecret
git remote add origin https://github.com/<usuario>/<repo>.git
git push -u origin master
```

If one is ever leaked: **revoke it first** on GitHub and then clean the
history. Revoking is the urgent part; the history can wait.

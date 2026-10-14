# Methodology

This is not theory: every rule in this document came out of a real failure in this
project, and most of them cost hours. They are ordered by what they cost.

## The five rules

### 1. Measure before reasoning

**The cost of ignoring it:** nine discarded hypotheses about the black screen. All of
them were real failures —ECM, Vulkan, `BUILD_SHARED_LIBS`, `glass.moc`,
`KPackageStructure`, the `lib` prefix, `isSupported()`, the loose metadata, the
installation path— and **none of them was the cause**. The cause was a string constant
in KWin's code that it never occurred to me to question.

On three occasions my reasoning was correct in the abstract and the system said
otherwise. All three were resolved by **measuring**:

| Reasoning | Measured reality |
|---|---|
| «`loadEffect` does not go through `readConfig», so the saved state does not matter» | it did matter |
| «if `isSupported()` returns true, KWin loads it» | it did not load it |
| «the same code cannot behave differently» | with another id, it does |

**Practical rule:** when something does not add up, build the smallest measurement
that can prove you wrong. Do not look for the cause: look for the experiment that
rules it out.

### 2. Isolate with a minimal case

**The cost of ignoring it:** half the incident. The **minimal effect** —a class that
only loads and does nothing— resolved in two runs what nine hypotheses did not
resolve: it ruled out compilation, linking, the path and `isSupported()` in one go.

Afterwards, bisection found that **the same code, byte for byte** worked with one id
and broke with another.

**Practical rule:** faced with a failure with many variables, reduce until only one is
left. If the minimum also fails, the problem is not where you think it is.

### 3. No test is worth anything until you see it fail

**The cost of ignoring it:** two false «ABORTADO» that made you doubt a correct `.so`,
and a test that passed green **with the code broken**.

```
The test looked for `effects->paintWindow` in the file.
We removed it from the CODE.
The test stayed green: the pattern was in the COMMENT that explains it.
```

It is the same mistake that made me chase the wrong failure for hours: **reading a
mention and believing it is an implementation**.

Two consequences built into the harness:
- Assertions about code **ignore comments** (`afirmar_codigo`).
- Every test is checked by **deliberately breaking** what it watches.

### 4. Verify the tool before the object

**The cost of ignoring it:** the safety check in `install.sh` aborted the installation
of a correct `.so`, in a **non-deterministic** way.

```bash
objdump -d --demangle "$SO" | grep -qE 'EffectsHandler::paintWindow'
# grep -q aborts when it finds the match and closes the pipe.
# With `set -o pipefail`, the result VARIES.
```

When I tested it, it passed. When you ran it, it failed. And I told you **twice** that
it was «the safety working properly». It was not: it was a bug of mine.

**Practical rule:** a check that gives false positives is **worse than not having
it**, because it makes you doubt something that is fine. Before trusting a tool,
check that it is deterministic and that it fails when it should.

### 5. Never destroy state without being able to go back

**The cost of ignoring it:** two black screens, one lost session, and hours of
recovery from a TTY.

| Mistake | Lesson |
|---|---|
| `kwin_wayland --replace` recommended as «safe» | On Wayland it starts a second compositor that competes for DRM/GL. **Never.** |
| Project 26 hours without git | With no net, every change is irreversible |
| Scripts that loaded the old id | Running them would have broken rendering again |

**Practical rule:**
- Every risky operation must be **reversible** and have an **escape hatch**
  (the `trap EXIT` in `test-installed.sh` always unloads the effect).
- Before touching anything, know how to undo it.
- **Commit before every risky change.**

## The work cycle

```
   write the test       ──►  RED    (fails: not done yet)
          │
          ▼
   implement            ──►  GREEN  (passes)
          │
          ▼
   break it on purpose  ──►  RED    (does the test really catch it?)
          │
          ▼
   restore              ──►  GREEN
          │
          ▼
        commit  ──►  small, with the why in the message
```

The «break it on purpose» step is not optional: it is what distinguishes a test that
verifies from one that only decorates.

## The quality gates

Before calling anything done:

| Gate | How it is checked |
|---|---|
| The harness passes | `tests/run.sh` |
| The test catches the break | break it on purpose and watch it fail |
| The system does not break | `test-installed.sh` (loads, measures, unloads) |
| It is reproducible | regenerate and compare (byte for byte) |
| It is documented | the documentation does not contradict itself (there is a test) |

## Knowledge management

**Failures are documented; they are not hidden.** `INCIDENT.md` keeps the four wrong
conclusions **on purpose**: they show which signals were misread and why. A document
that only holds the right answer teaches nothing.

**One place for each thing.** When `DELIVERY.md` and `INCIDENT.md` contradicted each
other, the problem was not the contradiction: it was that **nobody knew which one
won**. Now there is an authoritative summary and the rest is marked as historical.

**Commit messages explain the why.** The what is already in the diff. What gets lost
over time is the reason.

## What we do not do

- **Do not edit generated artifacts by hand.** You change the token and regenerate.
- **Do not commit Apple material.** The kit, the SF Pro fonts and the `.fig` files are
  in `.gitignore`. What is versioned is the derived work, with its provenance noted.
- **Do not store credentials in the repo.** Not in `.env`, not in a config file.
  A token in git history is permanent.
- **Do not accept «it works on my machine».** It is measured, and the measurement
  stays in the project as a test.

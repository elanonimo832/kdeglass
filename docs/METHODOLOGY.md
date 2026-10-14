# Methodology

This is not theory: every rule in this document came out of a real failure in this
project, and most of them cost hours. They are ordered by what they cost.

## The six rules

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

**The same bug, a second time, in the tool that runs every test.** `afirmar_codigo`
in `tests/lib.sh` stripped comments with `grep -vE ... | grep -qE`. On the real
14 KB `glass.cpp` that produced **1 false failure in 200 calls**; on a 500 KiB file,
**200 in 200**. It made `bash tests/run.sh` return 148, 149 or 150 on the same tree,
and three sessions of assertions were patched one by one because of it.

A race cannot be tested by waiting for it. **Make it certain:** a file larger than
the pipe buffer means the producer is always still writing when `grep -q` exits, so
the bug becomes a deterministic failure. `tests/test-harness.sh` does exactly that,
and carries the case for stripping comments too, because the cheap fix for the race
is to stop stripping them and match comments -- the false positive of rule 3.

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
  (the `trap EXIT` in `tests/archive/test-installed.sh` always unloads the effect).
- Before touching anything, know how to undo it.
- **Commit before every risky change.**

### 6. Every test file runs in its own shell

**The cost of ignoring it:** three sessions in which the failures of this suite
"moved between files". The real cause was the race of rule 4, but the reason it
could not be placed was the runner: `tests/run.sh` **`source`d every test file into
one shell**, so a variable, a function, a `set` flag or an `exit` in one file
reached the next. Measured, not deduced: `test-offscreen.sh` sets `CABECERA`, and it
was still set when `test-harness.sh` ran.

**Practical rule:**
- A runner must not execute the test files inside its own process. One file, one
  process (`tests/run-one.sh`), with the counters written from an `EXIT` trap so a
  file that dies halfway still reports what it did check.
- **Bound every file with a `timeout`.** A run that "did not finish" and a run
  whose output was truncated look identical from outside; two runs ended with no
  summary and it was read as a hang. A hang must become a *named failure*, never a
  silence.
- A rule enforced on the code must also cover the tool that verifies the code.
  `grep -q` in a pipe was forbidden in `effect-kwin/*.sh` and used nine times inside
  `tests/`, including in the helper that runs every assertion. The scan now covers
  both.
- **A file that dies halfway reports nothing, and a counter cannot tell it from a file that
  finished.** The harness's per-file EXIT trap writes the counter even when the file is
  killed mid-way -- which is deliberate, so a file that dies still contributes the checks it
  ran -- and that made a dead check invisible: `tests/test-scripts.sh` referenced an
  undefined variable, `set -u` killed it, and the suite printed ALL PASS with a check that
  never ran. `run-one.sh` now writes a marker after the file returns and `run.sh` requires
  it, so "finished" and "died" are different verdicts. The marker is a separate file because
  the counter is written with `>` from the trap.
- **A backup taken after the first break contains the first break.** The rule above says to
  break a copy; this is how that rule goes wrong. A break-check appended two lines to a live
  script, the copy was refreshed at the START of the next break-check -- which already
  contained the first debris -- and the restore brought both back. It sat at the end of a
  live script, after `exit`, for a round: unreachable, harmless, and invisible to the suite
  because the suite does not run live scripts. Verify the restore (`git diff` on the file, or
  read its tail) before trusting it.
- **A deliberate break must not be able to destroy uncommitted work.** While checking that
  the eviction guard caught the regression it was written for, the break was reverted with
  `git checkout`, which restored the file to the last COMMIT and took ten uncommitted fixes
  with it. They were re-applied from the patch text, but the cheap rule is the one to keep:
  commit first, or break a copy (`cp file /tmp/file.bak`, break, restore from the copy).
- **An API behaviour written down is a claim; only the header is evidence.** The handoff
  listed "GL objects are destroyed without making the context current" as a known leak for
  two rounds, with a proposed fix (make the capture per window) that would have been real
  work. KWin's own `Effect` documentation guarantees the opposite in one paragraph: the
  context is current when the effect is created, destroyed or reconfigured. The claim had
  never been read anywhere -- it was inferred from `GLFramebuffer`'s warning, which is
  about a situation that does not arise. The item is now struck through in the handoff
  rather than deleted, because the shape of the mistake is the one this project pays for
  most often.
- **A diagnostic that floods the log destroys what it is for.** `prePaintWindow` raised
  its counter only while it was below six and then gated the message on `pre <= 6`, so once
  the counter stopped the message went out on every paint of every window: thousands of
  identical lines a second, found in the real journal. The log stopped being readable
  exactly when somebody needed to read it. One gate, one counter, and the gate is the same
  one that increments.
- **An assertion on a name is not an assertion on the wiring.** Three times in one
  session a test asserted that an identifier appeared in the source, and passed while the
  term was disconnected from the result: `discard;` that could never run, a corner test
  replaced by `if (false)`, and a chroma term that was declared and never used. Each was
  written against the *name* because the name was easy to grep. Assert the expression
  that decides -- `max(porDesviacion, porColor)`, `dot(esquina, esquina) > r * r` -- or the
  test is pinning a word, not a behaviour.

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
| The system does not break | `tests/archive/test-installed.sh` (loads, measures, unloads) -- retired, kept as the record |
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

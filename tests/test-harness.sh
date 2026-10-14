# The harness auditS ITSELF.
#
# Why this file exists: five consecutive runs of `bash tests/run.sh` gave
# pass=148, 149, 149 and two runs with no summary at all. The failures moved
# between files on successive runs, which looked exactly like state leaking from
# one test file into the next, and that is how it was written down.
#
# The measured cause is narrower: afirmar_codigo stripped comments with
# `grep -vE ... | grep -qE`. `grep -q` exits at the first match and closes the
# pipe; the producer then dies of SIGPIPE; with `set -o pipefail` (set by run.sh)
# the PIPELINE reports 141 even though the match WAS found. Whether the producer
# is still writing when `grep -q` exits depends on scheduling, so the same
# assertion on the same file passed here and failed there. The rule was already
# written in docs/METHODOLOGY.md and already enforced on effect-kwin/*.sh; the
# file that runs every assertion was the one exception.
#
# A race cannot be tested by waiting for it. The two checks below remove the
# timing: a file larger than the pipe buffer makes SIGPIPE certain, so the bug is
# a deterministic failure here instead of an intermittent one in somebody else's
# test file.

echo "  -- an assertion on an unchanging file must not depend on timing --"
# 500 KiB of code, the pattern in a real line, and a comment that mentions it too.
# Larger than the 64 KiB pipe buffer, so the comment-stripper is still writing
# when the matcher exits: with the broken helper this FAILS every time.
GRANDE="$(mktemp)"
python3 - > "$GRANDE" <<'PYEOF'
print("uTitleBarHeight = 26.0f;")
print("// a comment that also mentions uTitleBarHeight")
for i in range(20000):
    print(f"int filler_{i} = {i};")
PYEOF
afirmar_codigo "a 500 KiB file does not lose its match to SIGPIPE" "$GRANDE" 'uTitleBarHeight'
rm -f "$GRANDE"

echo "  -- and stripping comments must not turn into 'never matching' --"
# The cheap fix for the race is to drop the filter and match comments as well,
# which is the reverse bug: an assertion passes on code that only MENTIONS the
# pattern in a comment. That trap already cost this project a real regression.
COMENTADO="$(mktemp)"
printf '// uGlassAlpha is mentioned here and nowhere else\nint x = 1;\n' > "$COMENTADO"
# `declare -F` first: a missing predicate would make the `if` fail for the wrong
# reason and the check would pass while testing nothing.
if ! declare -F codigo_contiene >/dev/null; then
  fallo "the pure predicate codigo_contiene does not exist (lib.sh)"
elif codigo_contiene "$COMENTADO" 'uGlassAlpha'; then
  fallo "a pattern that only appears in a comment was accepted as code"
else
  ok "a pattern that only appears in a comment is rejected"
fi
rm -f "$COMENTADO"

echo "  -- the harness obeys the rule it enforces on the effect scripts --"
# test-scripts.sh forbids `grep -q` in a pipe for effect-kwin/*.sh. The harness
# did it in six places. A rule that does not cover the tool that verifies the
# rule protects nothing, so the scan covers tests/ too.
malos=$(python3 - "$PROY/tests" <<'PYEOF'
import glob, os, re, sys
tests = sys.argv[1]
bad = []


def sin_cadenas_y_comentario(linea):
    """Drop '...' and "..." spans and # comments: their | is not a shell pipe."""
    fuera, i, n = [], 0, len(linea)
    while i < n:
        c = linea[i]
        if c in "'\"":
            i += 1
            while i < n and linea[i] != c:
                i += 2 if linea[i] == '\\' else 1
            i += 1
            continue
        if c == '#' and (i == 0 or linea[i - 1] in ' \t;&|('):
            break
        fuera.append(c)
        i += 1
    return ''.join(fuera)


for path in sorted(glob.glob(os.path.join(tests, '*.sh'))):
    for n, linea in enumerate(open(path, encoding='utf-8'), 1):
        if re.search(r'\|[^|]*grep[^|]*-q', sin_cadenas_y_comentario(linea)):
            bad.append(f"{os.path.basename(path)}:{n}: {linea.strip()}")
for b in bad:
    print(f"      -> {b}")
print(len(bad))
PYEOF
)
n="${malos##*$'\n'}"
afirmar_igual "no 'grep -q' inside a pipeline in tests/" "0" "$n"

echo "  -- each test file gets its own shell --"
# run.sh used to `source` every test file into ONE shell, so a variable, a
# function or a `set` flag from one file reached the next, and an `exit` anywhere
# ended the whole suite. This check is behavioural on purpose: CABECERA is set by
# test-diffusion.sh, which runs before this file alphabetically. If the state
# leaked, it would be visible here.
negar "state from an earlier test file does not reach this one" test -n "${CABECERA:-}"
afirmar_contiene "run.sh runs each file through run-one.sh" "$PROY/tests/run.sh" 'run-one[.]sh'
negar "run.sh does not source the test files into its own shell" \
  grep -qE 'source[[:space:]]+"[$]f"' "$PROY/tests/run.sh"
afirmar_existe "tests/run-one.sh exists" "$PROY/tests/run-one.sh"

echo "  -- a test that hangs cannot silently truncate the run --"
# Two of the five runs produced no summary at all: the output simply stopped.
# Truncation and a hang look the same from outside, so the runner now bounds each
# file and reports the timeout as a failure of that file.
afirmar_contiene "run.sh bounds every test file with a timeout" "$PROY/tests/run.sh" 'timeout'
afirmar_contiene "run.sh reports a timed-out file as a failure" "$PROY/tests/run.sh" 'TIMED OUT'

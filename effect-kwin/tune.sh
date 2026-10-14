#!/usr/bin/env bash
# Sets the effect's live settings, and applies them in ONE call.
#
#   ./tune.sh                              what is set right now
#   ./tune.sh GlassAlpha=0.25 Vibrancy=0  set those keys and apply them
#   ./tune.sh --preset apple               the numbers in tokens/tokens-kit.toml
#   ./tune.sh --reset                      back to the effect's own defaults
#
# WHY THIS EXISTS, and it is not convenience. `/KWin reconfigure` looks like the obvious
# command and does NOT reach an effect's reconfigure(): it re-parses kwinrc and calls
# Workspace::slotReconfigure, while `configChanged` only reacts to [Plugins]. The command that
# works is `qdbus6 ... Effects.reconfigureEffect <id>`, and the failure mode of the wrong one
# is the worst kind: the value is written, the command reports success, the effect keeps its
# old value. Three keys therefore meant four commands with one silent trap in the middle.
# This writes them and calls the right method once, then reads the journal back to confirm
# that the effect re-read them -- so "applied" means measured, not assumed.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$HERE/src/glass.cpp"
ID=macosglass2
KWRITE=kwriteconfig6
KREAD=kreadconfig6
QDBUS=qdbus6

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

for cmd in "$KWRITE" "$KREAD" "$QDBUS"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "MISSING: $cmd"
        echo "  sudo pacman -S --needed kwallet kconfig   # provides kwriteconfig6/kreadconfig6"
        exit 1
    fi
done

# The keys the effect actually reads, straight from the source. A typo here is a key the
# effect never looks at: written, reported as success, and ignored.
known_keys() {
    grep -oE 'readEntry\("[A-Za-z]+"' "$SOURCE" | sed 's/readEntry("//; s/"$//' | sort -u
}

# The default is whatever the source says, and reading it the same way keeps this honest when
# a default changes.
default_of() { # default_of <Key>
    grep -oE "(k$1 = |cfg.readEntry\(\"$1\", )[^;]*" "$SOURCE" >/dev/null 2>&1
    grep -A 1 -E "k$1 =" "$SOURCE" | grep -oE '= *[^;]+' | head -1 | sed 's/= *//'
}

show() {
    echo "settings for [$ID] in ~/.config/kwinrc"
    echo
    local k v
    for k in $(known_keys); do
        v=$("$KREAD" --file kwinrc --group "Effect-$ID" --key "$k" --default "" 2>/dev/null)
        if [ -z "$v" ]; then
            printf '  %-20s %s\n' "$k" "(default)"
        else
            printf '  %-20s %s\n' "$k" "$v"
        fi
    done
    echo
    echo "what the effect last reported reading:"
    timeout 20 journalctl --user --since '10 min ago' -o cat 2>/dev/null \
        | grep 'reconfigure:' | grep -v systemd-run | tail -1 | sed 's/^/  /' || true
}

apply() { # apply <key=value>...
    local par k v
    for par in "$@"; do
        k="${par%%=*}"
        v="${par#*=}"
        if [ "$k" = "$par" ] || [ -z "$v" ]; then
            echo "BAD ARGUMENT: $par (expected Key=Value)"
            return 2
        fi
        # Here-string, not a pipe into grep -q: under pipefail the early exit closes the pipe
        # and can report failure on a match. The suite scans for exactly this shape.
        if ! grep -qx "$k" <<< "$(known_keys)"; then
            echo "UNKNOWN KEY: $k"
            echo "  the effect reads: $(known_keys | tr '\n' ' ')"
            return 2
        fi
        "$KWRITE" --file kwinrc --group "Effect-$ID" --key "$k" "$v"
        printf '  %-20s = %s\n' "$k" "$v"
    done
    # The one command that reaches an effect's reconfigure(), and only once.
    "$QDBUS" org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect "$ID" >/dev/null 2>&1
    sleep 1
    local linea
    linea=$(timeout 20 journalctl --user --since '20 sec ago' -o cat 2>/dev/null \
            | grep 'reconfigure:' | grep -v systemd-run | tail -1)
    if [ -z "$linea" ]; then
        echo
        echo "  WARNING: the effect reported no 'reconfigure:' line. It may not be loaded:"
        echo "           qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect $ID"
        return 1
    fi
    echo
    echo "  the effect reports: $linea"
}

case "${1:-}" in
    "" | --show)
        show
        ;;
    --preset)
        case "${2:-}" in
            apple)
                # tokens/tokens-kit.toml, [liquid_glass]: opacity = 25, frost_regular 6,
                # frost_medium 16. Vibrancy has no token because it is a behaviour, not a
                # value: it is the companion of a low opacity, and 0.35 is the contrast
                # below which achromatic chrome is pushed away from the glass.
                echo "preset apple (from tokens/tokens-kit.toml [liquid_glass]):"
                apply GlassAlpha=0.25 BackgroundRadius=16 Vibrancy=0.35
                ;;
            *)
                echo "UNKNOWN PRESET: ${2:-}"
                echo "  apple"
                exit 2
                ;;
        esac
        ;;
    --reset)
        for k in $(known_keys); do
            "$KWRITE" --file kwinrc --group "Effect-$ID" --key "$k" --delete >/dev/null 2>&1
        done
        echo "back to the effect's defaults:"
        "$QDBUS" org.kde.KWin /Effects org.kde.kwin.Effects.reconfigureEffect "$ID" >/dev/null 2>&1
        sleep 1
        timeout 20 journalctl --user --since '20 sec ago' -o cat 2>/dev/null \
            | grep 'reconfigure:' | grep -v systemd-run | tail -1 | sed 's/^/  /'
        ;;
    *)
        apply "$@"
        ;;
esac

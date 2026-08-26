#!/bin/sh
# decent-yt-dlp wrapper — auto-update gate then exec real yt-dlp
# POSIX sh, works on macOS and Linux.
# Config priority: env DECENT_YT_DLP_UPDATE_INTERVAL > config file > default 1d
# Human intervals: 30s, 10m, 12h, 1d, 7d/1w, 0/never/off/disable
# Wrapper messages go to stderr so stdout (e.g. -J, --print) is not polluted.
set -eu

# XDG fallbacks (also respected by uv)
: "${XDG_CACHE_HOME:=$HOME/.cache}"
: "${XDG_CONFIG_HOME:=$HOME/.config}"

CACHE_DIR="${DECENT_YT_DLP_CACHE_DIR:-$XDG_CACHE_HOME/decent-yt-dlp}"
CONFIG_FILE="${DECENT_YT_DLP_CONFIG:-$XDG_CONFIG_HOME/decent-yt-dlp/config}"
REAL_BIN="${DECENT_YT_DLP_BIN:-$HOME/.local/share/uv/tools/yt-dlp/bin/yt-dlp}"

# Fallback locations for real binary (covers custom BIN_DIR installs)
if [ ! -x "$REAL_BIN" ]; then
    if [ -x "$HOME/.local/bin/yt-dlp.real" ]; then
        REAL_BIN="$HOME/.local/bin/yt-dlp.real"
    elif [ -x "$HOME/.local/share/uv/tools/yt-dlp/bin/yt-dlp" ]; then
        REAL_BIN="$HOME/.local/share/uv/tools/yt-dlp/bin/yt-dlp"
    else
        REAL_BIN=""
    fi
fi

# Also allow wrapper to find uv for fallback exec
find_uv() {
    if command -v uv >/dev/null 2>&1; then
        command -v uv
        return 0
    fi
    for p in "$HOME/.local/bin/uv" "$HOME/.cargo/bin/uv" "/opt/homebrew/bin/uv" "/usr/local/bin/uv"; do
        if [ -x "$p" ]; then
            printf '%s' "$p"
            return 0
        fi
    done
    return 1
}

# Human-readable interval -> seconds. Unknown -> default 86400.
parse_interval() {
    _in="$1"
    # trim whitespace
    _in=$(printf '%s' "$_in" | tr -d '[:space:]')
    case "$_in" in
        "" ) echo 86400; return ;;
        0|off|never|disable|no|none) echo 0; return ;;
    esac
    # lower case
    _in=$(printf '%s' "$_in" | tr '[:upper:]' '[:lower:]')
    case "$_in" in
        *s)
            _num=${_in%s}
            case "$_num" in *[!0-9]*) echo 86400;; *) echo "$_num";; esac
            ;;
        *m)
            _num=${_in%m}
            case "$_num" in *[!0-9]*) echo 86400;; *) echo $((_num * 60));; esac
            ;;
        *h)
            _num=${_in%h}
            case "$_num" in *[!0-9]*) echo 86400;; *) echo $((_num * 3600));; esac
            ;;
        *d)
            _num=${_in%d}
            case "$_num" in *[!0-9]*) echo 86400;; *) echo $((_num * 86400));; esac
            ;;
        *w)
            _num=${_in%w}
            case "$_num" in *[!0-9]*) echo 86400;; *) echo $((_num * 604800));; esac
            ;;
        *)
            case "$_in" in *[!0-9]*) echo 86400;; *) echo "$_in";; esac
            ;;
    esac
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Save env value so config cannot clobber it (env > file)
        _saved_interval="${DECENT_YT_DLP_UPDATE_INTERVAL-__UNSET__}"
        # shellcheck disable=SC1090
        . "$CONFIG_FILE"
        if [ "${_saved_interval}" != "__UNSET__" ]; then
            DECENT_YT_DLP_UPDATE_INTERVAL="$_saved_interval"
        fi
        unset _saved_interval
    fi
}

# Load config before deciding interval; env wins over file.
load_config

# Default 1d if not set (env or file)
: "${DECENT_YT_DLP_UPDATE_INTERVAL:=1d}"
INTERVAL_S=$(parse_interval "$DECENT_YT_DLP_UPDATE_INTERVAL")

should_check() {
    # 0 means disabled
    if [ "$INTERVAL_S" -eq 0 ]; then
        return 1
    fi
    if [ "${DECENT_YT_DLP_NO_UPDATE:-0}" = "1" ]; then
        return 1
    fi
    # also support --no-update-check stripped? not needed; env is enough
    last_file="$CACHE_DIR/last_update_check"
    if [ ! -f "$last_file" ]; then
        return 0
    fi
    last=$(cat "$last_file" 2>/dev/null || echo 0)
    last=$(printf '%s' "$last" | tr -d '[:space:]')
    case "$last" in ""|*[!0-9]*) return 0;; esac
    now=$(date +%s 2>/dev/null || echo 0)
    case "$now" in *[!0-9]*) return 0;; esac
    elapsed=$((now - last))
    if [ "$elapsed" -ge "$INTERVAL_S" ]; then
        return 0
    else
        return 1
    fi
}

get_version() {
    _bin="$1"
    if [ -n "$_bin" ] && [ -x "$_bin" ]; then
        "$_bin" --version 2>/dev/null || echo "unknown"
    else
        _uv=$(find_uv 2>/dev/null || true)
        if [ -n "${_uv:-}" ]; then
            "$_uv" tool run --with curl_cffi --with cffi yt-dlp -- --version 2>/dev/null || echo "unknown"
        else
            echo "unknown"
        fi
    fi
}

do_update() {
    echo "[decent-yt-dlp] Checking for yt-dlp updates..." >&2
    lockdir="$CACHE_DIR/update.lock"
    if ! mkdir "$lockdir" 2>/dev/null; then
        echo "[decent-yt-dlp] Another update in progress, skipping" >&2
        return 0
    fi
    # ensure lock removal on exit
    trap 'rmdir "$lockdir" 2>/dev/null || true' EXIT INT TERM

    _uv=$(find_uv 2>/dev/null || true)
    if [ -z "${_uv:-}" ]; then
        echo "[decent-yt-dlp] uv not found, skipping update" >&2
        date +%s > "$CACHE_DIR/last_update_check" 2>/dev/null || true
        rmdir "$lockdir" 2>/dev/null || true
        trap - EXIT INT TERM
        return 0
    fi

    if [ -n "$REAL_BIN" ] && [ -x "$REAL_BIN" ]; then
        old_ver=$("$REAL_BIN" --version 2>/dev/null || echo "unknown")
    else
        old_ver=$(get_version "$REAL_BIN")
    fi

    # uv tool upgrade retains the additional packages recorded at install time.
    # Unlike `tool install`, it does not accept --with.
    set +e
    "$_uv" tool upgrade yt-dlp 2>&1
    _rc=$?
    set -e

    if [ $_rc -ne 0 ]; then
        echo "[decent-yt-dlp] Update failed (network or uv error), continuing with $old_ver" >&2
    else
        new_ver=$(get_version "$REAL_BIN")
        if [ "$old_ver" != "$new_ver" ] && [ "$new_ver" != "unknown" ]; then
            echo "[decent-yt-dlp] Updated yt-dlp $old_ver -> $new_ver" >&2
        else
            echo "[decent-yt-dlp] yt-dlp is up to date ($old_ver)" >&2
        fi
    fi

    date +%s > "$CACHE_DIR/last_update_check" 2>/dev/null || true
    rmdir "$lockdir" 2>/dev/null || true
    trap - EXIT INT TERM
}

# Ensure cache dir exists before any check
mkdir -p "$CACHE_DIR" 2>/dev/null || true

if should_check; then
    do_update
fi

# Exec real yt-dlp; preserve args, signals, tty.
if [ -n "$REAL_BIN" ] && [ -x "$REAL_BIN" ]; then
    exec "$REAL_BIN" "$@"
else
    _uv=$(find_uv 2>/dev/null || true)
    if [ -n "${_uv:-}" ]; then
        exec "$_uv" tool run --with curl_cffi --with cffi yt-dlp -- "$@"
    else
        echo "[decent-yt-dlp] ERROR: yt-dlp not found at $REAL_BIN and uv not available" >&2
        echo "  Run install.sh again or set DECENT_YT_DLP_BIN" >&2
        exit 127
    fi
fi

#!/bin/sh
# decent-yt-dlp installer — macOS + Linux, POSIX sh
# - Aborts if yt-dlp already in PATH (user must uninstall manually)
# - Bootstraps uv if missing
# - Installs yt-dlp via `uv tool install yt-dlp --with curl_cffi --with cffi`
# - Deploys wrapper to BIN_DIR (default ~/.local/bin, overridable)
set -eu

# ---- defaults ----
DEFAULT_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
# allow env override
BIN_DIR="${DECENT_YT_DLP_BIN_DIR:-$DEFAULT_BIN_DIR}"
# allow explicit no-prompt for scripts? not needed, but keep
FORCE=0

usage() {
    cat <<EOF
Usage: $0 [--bin-dir DIR] [--force] [--help]

Installs yt-dlp via uv (with cffi/curl_cffi) and a wrapper that auto-updates
once a day (configurable).

Options:
  --bin-dir DIR   Install wrapper to DIR (default: \$HOME/.local/bin or \$XDG_BIN_HOME)
                  Env: DECENT_YT_DLP_BIN_DIR
  --force         (reserved) do not use with yt-dlp detection — still aborts
  --help          Show this help

Env:
  DECENT_YT_DLP_BIN_DIR  Override install directory
  XDG_BIN_HOME           XDG bin dir fallback

After install, configure update interval:
  ~/.config/decent-yt-dlp/config  ->  DECENT_YT_DLP_UPDATE_INTERVAL=1d
  or env DECENT_YT_DLP_UPDATE_INTERVAL=12h  (30s, 10m, 1d, 7d, 0/never)
EOF
}

# ---- arg parsing (POSIX) ----
while [ $# -gt 0 ]; do
    case "$1" in
        --bin-dir)
            if [ $# -lt 2 ]; then echo "Missing value for --bin-dir" >&2; exit 2; fi
            BIN_DIR="$2"
            shift 2
            ;;
        --bin-dir=*)
            BIN_DIR="${1#--bin-dir=}"
            shift
            ;;
        --force)
            FORCE=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

# Resolve script dir to find wrapper.sh co-located with installer
SCRIPT_DIR=""
case "$0" in
    /*) SCRIPT_DIR=$(dirname "$0") ;;
    */*) SCRIPT_DIR=$(dirname "$PWD/$0") ;;
    *) SCRIPT_DIR="$PWD" ;;
esac
# normalize
SCRIPT_DIR=$(cd "$SCRIPT_DIR" 2>/dev/null && pwd || echo "$PWD")

# If wrapper.sh not next to install.sh (curl pipe case), try to fetch or use embedded fallback
WRAPPER_SRC="$SCRIPT_DIR/wrapper.sh"
if [ ! -f "$WRAPPER_SRC" ]; then
    if [ -f "$PWD/wrapper.sh" ]; then
        WRAPPER_SRC="$PWD/wrapper.sh"
    else
        # Try fetching from GitHub raw (best effort) before falling back to embedded
        _fetched=""
        if command -v curl >/dev/null 2>&1; then
            for _url in "https://raw.githubusercontent.com/lurepheonix/decent-yt-dlp/main/wrapper.sh" ; do
                _tmp_w="/tmp/decent-yt-dlp-wrapper-$$.sh"
                if curl -LsSf "$_url" -o "$_tmp_w" 2>/dev/null && [ -s "$_tmp_w" ] && grep -q "decent-yt-dlp wrapper" "$_tmp_w" 2>/dev/null; then
                    WRAPPER_SRC="$_tmp_w"
                    _fetched="1"
                    break
                fi
                rm -f "$_tmp_w" 2>/dev/null || true
            done
        fi
        if [ -z "$_fetched" ]; then
            echo "[decent-yt-dlp] ERROR: wrapper.sh not found next to install.sh" >&2
            echo "  Clone the repo first:" >&2
            echo "    git clone <repo> && cd decent-yt-dlp && ./install.sh" >&2
            echo "  Or ensure wrapper.sh is alongside install.sh when piping." >&2
            exit 1
        fi
    fi
fi

echo "[decent-yt-dlp] BIN_DIR=$BIN_DIR"

# ---- 1. Abort if yt-dlp already in PATH ----
# Check command -v, which -a, and common locations
FOUND=""
FOUND_LIST=""

# command -v (POSIX)
if command -v yt-dlp >/dev/null 2>&1; then
    FOUND=$(command -v yt-dlp 2>/dev/null || true)
    FOUND_LIST="$FOUND"
fi

# which -a style: try command -v -a if supported, else which
if command -v which >/dev/null 2>&1; then
    for p in $(which -a yt-dlp 2>/dev/null || true); do
        case " $FOUND_LIST " in *" $p "*) ;; *) FOUND_LIST="$FOUND_LIST $p";; esac
        if [ -z "$FOUND" ]; then FOUND="$p"; fi
    done
fi

# Common locations even if not in PATH
for p in "$HOME/bin/yt-dlp" "/opt/homebrew/bin/yt-dlp" "/usr/local/bin/yt-dlp" "$BIN_DIR/yt-dlp"; do
    if [ -x "$p" ]; then
        case " $FOUND_LIST " in *" $p "*) ;; *) FOUND_LIST="$FOUND_LIST $p";; esac
        if [ -z "$FOUND" ]; then FOUND="$p"; fi
    fi
done

# If wrapper already installed by us, allow re-install (upgrade) — detect by marker
if [ -n "$FOUND" ]; then
    # If the found binary is our wrapper, allow reinstall
    if [ -f "$FOUND" ] && grep -q "decent-yt-dlp wrapper" "$FOUND" 2>/dev/null; then
        echo "[decent-yt-dlp] Existing decent-yt-dlp wrapper found at $FOUND — will upgrade in place." >&2
        FOUND=""
        FOUND_LIST=""
    fi
fi

if [ -n "$FOUND" ]; then
    echo "" >&2
    echo "[decent-yt-dlp] ERROR: yt-dlp already installed — please uninstall it yourself and re-run." >&2
    echo "" >&2
    echo "  Found:" >&2
    for p in $FOUND_LIST; do
        echo "    - $p" >&2
        # try to hint source
        if [ -L "$p" ]; then
            echo "      -> $(readlink "$p" 2>/dev/null || true)" >&2
        fi
        ls -l "$p" 2>/dev/null | sed 's/^/      /' >&2 || true
    done
    echo "" >&2
    echo "  How to remove (pick yours):" >&2
    echo "    brew uninstall yt-dlp        # Homebrew" >&2
    echo "    sudo pacman -R yt-dlp        # Arch" >&2
    echo "    pip uninstall yt-dlp / pipx uninstall yt-dlp" >&2
    echo "    rm \"$FOUND\"                 # manual binary/symlink" >&2
    if [ -x "$HOME/bin/yt-dlp" ]; then
        echo "    rm ~/bin/yt-dlp              # you have ~/bin/yt-dlp" >&2
    fi
    echo "" >&2
    echo "  Then re-run:" >&2
    echo "    ./install.sh --bin-dir \"$BIN_DIR\"" >&2
    echo "" >&2
    exit 1
fi

# ---- 2. Ensure uv ----
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

UV_BIN=""
if UV_BIN=$(find_uv 2>/dev/null); then
    echo "[decent-yt-dlp] Found uv at $UV_BIN ($("$UV_BIN" --version 2>/dev/null || echo uv))"
else
    echo "[decent-yt-dlp] uv not found — installing via https://astral.sh/uv/install.sh ..." >&2
    if ! command -v curl >/dev/null 2>&1; then
        echo "[decent-yt-dlp] ERROR: curl required to install uv" >&2
        exit 1
    fi
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # re-check
    if UV_BIN=$(find_uv 2>/dev/null); then
        echo "[decent-yt-dlp] Installed uv at $UV_BIN"
    else
        # try adding to PATH for this session
        export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
        if UV_BIN=$(find_uv 2>/dev/null); then
            echo "[decent-yt-dlp] Installed uv at $UV_BIN (added to PATH for this session)"
        else
            echo "[decent-yt-dlp] ERROR: uv install reported success but not found" >&2
            echo "  Check ~/.local/bin/uv exists and add ~/.local/bin to PATH" >&2
            exit 1
        fi
    fi
fi

# Ensure UV_BIN is in PATH for subsequent `uv` calls
case ":$PATH:" in
    *":$(dirname "$UV_BIN"):"*) ;;
    *) export PATH="$(dirname "$UV_BIN"):$PATH" ;;
esac

echo "[decent-yt-dlp] Using uv: $UV_BIN ($("$UV_BIN" --version))"

# ---- 3. Install yt-dlp with cffi ----
echo "[decent-yt-dlp] Installing yt-dlp with cffi/curl_cffi via uv tool..."

# uv tool list grep needs to handle not installed
set +e
"$UV_BIN" tool list 2>/dev/null | grep -q "^yt-dlp "
_already=$?
set -e

if [ $_already -eq 0 ]; then
    echo "[decent-yt-dlp] yt-dlp already managed by uv — upgrading..."
    "$UV_BIN" tool upgrade yt-dlp --with curl_cffi --with cffi
else
    "$UV_BIN" tool install yt-dlp --with curl_cffi --with cffi
fi

# Smoke test cffi/curl_cffi present
echo "[decent-yt-dlp] Verifying cffi + curl_cffi..."
if "$UV_BIN" tool run --with curl_cffi --with cffi python -c "import cffi, curl_cffi; print(f\"cffi {cffi.__version__} curl_cffi {curl_cffi.__version__}\")" 2>&1; then
    echo "[decent-yt-dlp] cffi/curl_cffi OK"
else
    echo "[decent-yt-dlp] WARNING: cffi check failed — yt-dlp may still work but impersonation may be broken" >&2
fi

# Verify yt-dlp runs
REAL_BIN="$HOME/.local/share/uv/tools/yt-dlp/bin/yt-dlp"
if [ -x "$REAL_BIN" ]; then
    echo "[decent-yt-dlp] yt-dlp version: $("$REAL_BIN" --version 2>/dev/null || echo unknown)"
else
    echo "[decent-yt-dlp] yt-dlp at $REAL_BIN not found, trying uv tool run..."
    "$UV_BIN" tool run yt-dlp -- --version
fi

# ---- 4. Deploy wrapper ----
mkdir -p "$BIN_DIR"

# If BIN_DIR/yt-dlp is a uv shim, preserve it
if [ -f "$BIN_DIR/yt-dlp" ]; then
    if head -n 5 "$BIN_DIR/yt-dlp" 2>/dev/null | grep -q "uv" || grep -q "uv tool" "$BIN_DIR/yt-dlp" 2>/dev/null; then
        echo "[decent-yt-dlp] Preserving existing uv shim as $BIN_DIR/yt-dlp.real"
        mv -f "$BIN_DIR/yt-dlp" "$BIN_DIR/yt-dlp.real"
    else
        # shouldn't happen due to abort, but if re-installing our wrapper
        if grep -q "decent-yt-dlp wrapper" "$BIN_DIR/yt-dlp" 2>/dev/null; then
            echo "[decent-yt-dlp] Updating existing wrapper at $BIN_DIR/yt-dlp"
        else
            echo "[decent-yt-dlp] Backing up $BIN_DIR/yt-dlp to $BIN_DIR/yt-dlp.bak"
            mv -f "$BIN_DIR/yt-dlp" "$BIN_DIR/yt-dlp.bak"
        fi
    fi
fi

echo "[decent-yt-dlp] Installing wrapper to $BIN_DIR/yt-dlp"
cp "$WRAPPER_SRC" "$BIN_DIR/yt-dlp"
chmod +x "$BIN_DIR/yt-dlp"

# ---- 5. Cache/config ----
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/decent-yt-dlp"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/decent-yt-dlp"
CONFIG_FILE="$CONFIG_DIR/config"
mkdir -p "$CACHE_DIR" "$CONFIG_DIR"
if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'CONFEOF'
# decent-yt-dlp config — sourced as sh
# Update check interval: human-readable
# Examples: 30s, 10m, 1h, 12h, 1d (default), 7d, 1w, 0/never/off to disable
DECENT_YT_DLP_UPDATE_INTERVAL=1d
CONFEOF
    echo "[decent-yt-dlp] Created config at $CONFIG_FILE"
else
    echo "[decent-yt-dlp] Config already exists at $CONFIG_FILE (not overwritten)"
fi

# ---- 6. PATH hint & done ----
echo ""
echo "[decent-yt-dlp] Install complete."
echo "  Wrapper: $BIN_DIR/yt-dlp"
echo "  Real:    $REAL_BIN"
echo "  Config:  $CONFIG_FILE"
echo "  Cache:   $CACHE_DIR/last_update_check"
echo ""
case ":$PATH:" in
    *":$BIN_DIR:"*)
        echo "  Run: yt-dlp --version"
        ;;
    *)
        echo "  NOTE: $BIN_DIR is not in your PATH." >&2
        echo "  Add to ~/.zshrc or ~/.bashrc:" >&2
        echo "    export PATH=\"$BIN_DIR:\$PATH\"" >&2
        echo "  Then: yt-dlp --version" >&2
        ;;
esac
echo ""
echo "  Interval: edit $CONFIG_FILE or set DECENT_YT_DLP_UPDATE_INTERVAL=12h"
echo "  Skip once: DECENT_YT_DLP_NO_UPDATE=1 yt-dlp <args>"
echo "  Uninstall: ./uninstall.sh --bin-dir \"$BIN_DIR\""

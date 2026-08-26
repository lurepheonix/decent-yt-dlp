#!/bin/sh
# decent-yt-dlp uninstall — POSIX sh, macOS + Linux
set -eu

DEFAULT_BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
BIN_DIR="${DECENT_YT_DLP_BIN_DIR:-$DEFAULT_BIN_DIR}"
PURGE=0

usage() {
    cat <<EOF
Usage: $0 [--bin-dir DIR] [--purge] [--help]

Removes decent-yt-dlp wrapper and uv-managed yt-dlp.

Options:
  --bin-dir DIR  Wrapper location (default: \$HOME/.local/bin or \$XDG_BIN_HOME)
                 Env: DECENT_YT_DLP_BIN_DIR
  --purge        Also remove cache and config (~/.cache/decent-yt-dlp, ~/.config/decent-yt-dlp)
  --help         Show this help
EOF
}

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
        --purge)
            PURGE=1
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

echo "[decent-yt-dlp] BIN_DIR=$BIN_DIR"

# Find uv
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

# 1. Remove wrapper
for f in "$BIN_DIR/yt-dlp" "$BIN_DIR/yt-dlp.real" "$BIN_DIR/yt-dlp.bak"; do
    if [ -e "$f" ] || [ -L "$f" ]; then
        if [ "$f" = "$BIN_DIR/yt-dlp" ] && [ -f "$f" ] && ! grep -q "decent-yt-dlp" "$f" 2>/dev/null; then
            echo "[decent-yt-dlp] Skipping $f — not a decent-yt-dlp wrapper (not removing)" >&2
            continue
        fi
        echo "[decent-yt-dlp] Removing $f"
        rm -f "$f"
    fi
done

# 2. uv tool uninstall
if UV_BIN=$(find_uv 2>/dev/null); then
    echo "[decent-yt-dlp] Found uv at $UV_BIN"
    if "$UV_BIN" tool list 2>/dev/null | grep -q "^yt-dlp "; then
        echo "[decent-yt-dlp] Uninstalling yt-dlp via uv tool uninstall..."
        "$UV_BIN" tool uninstall yt-dlp || true
    else
        echo "[decent-yt-dlp] yt-dlp not managed by uv (nothing to uninstall)"
    fi
else
    echo "[decent-yt-dlp] uv not found — skipping uv tool uninstall"
    echo "  If yt-dlp was installed via uv, remove manually:"
    echo "    rm -rf ~/.local/share/uv/tools/yt-dlp"
fi

# 3. Cache/config
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/decent-yt-dlp"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/decent-yt-dlp"

if [ "$PURGE" -eq 1 ]; then
    echo "[decent-yt-dlp] --purge: removing $CACHE_DIR and $CONFIG_DIR"
    rm -rf "$CACHE_DIR" "$CONFIG_DIR"
else
    echo "[decent-yt-dlp] Keeping cache/config:"
    echo "  $CACHE_DIR"
    echo "  $CONFIG_DIR"
    echo "  Use --purge to remove them, or:"
    echo "    rm -rf \"$CACHE_DIR\" \"$CONFIG_DIR\""
fi

echo ""
echo "[decent-yt-dlp] Uninstall complete."
echo "  To reinstall: ./install.sh --bin-dir \"$BIN_DIR\""

# decent-yt-dlp

Wrapper that installs and auto-updates `yt-dlp` via [`uv`](https://docs.astral.sh/uv/) with `cffi`/`curl_cffi`.

Works on **macOS** and **Linux**. POSIX `sh` only. 

Auto-updates once a day by default.

## Why

When homebrew and arch packages and even the official release are broken (each differently), it so happens there is a pressing need for a custom solution that actually works.

## Install

### One-liner (requires git clone for wrapper)

```sh
git clone https://github.com/lurepheonix/decent-yt-dlp.git
cd decent-yt-dlp
./install.sh
# custom dir:
./install.sh --bin-dir ~/.local/bin   # default
./install.sh --bin-dir ~/bin
DECENT_YT_DLP_BIN_DIR=~/bin ./install.sh
```

`install.sh` will:

1. Abort if `yt-dlp` already exists in `PATH` (e.g. Homebrew, `/usr/bin/yt-dlp`, `pipx`). Uninstall it yourself first — avoids silently shadowing system installs.
2. Bootstrap `uv` if missing (`https://astral.sh/uv/install.sh`).
3. Run `uv tool install yt-dlp --with curl_cffi --with cffi` (or `upgrade` if already managed).
4. Verify `cffi` + `curl_cffi` import.
5. Deploy wrapper to `BIN_DIR/yt-dlp` (default `~/.local/bin/yt-dlp`, `XDG_BIN_HOME` respected).
6. Create `~/.config/decent-yt-dlp/config` and `~/.cache/decent-yt-dlp/`.

Ensure `BIN_DIR` is on `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"  # add to ~/.zshrc / ~/.bashrc
yt-dlp --version
```

## How it works

`~/.local/bin/yt-dlp` is a `sh` wrapper, real binary lives at `~/.local/share/uv/tools/yt-dlp/bin/yt-dlp`.

On every invocation:

- If update interval elapsed (default `1d`), wrapper runs `uv tool upgrade yt-dlp --with curl_cffi --with cffi`, prints `Checking for updates...` + `Updated ...` / `is up to date` to **stderr**, then `exec`s real `yt-dlp`.
- If interval not elapsed, wrapper `exec`s immediately (~5ms overhead: one `date +%s` + file read).

`stdout` is never polluted — `yt-dlp -J URL > out.json` stays clean.

Concurrent runs are serialized via `mkdir` lock (`~/.cache/decent-yt-dlp/update.lock`, no `flock` needed on macOS).

## Configuration

Priority: **env > config file > default**.

### Config file

`~/.config/decent-yt-dlp/config` (or `$XDG_CONFIG_HOME/decent-yt-dlp/config`), sourced as `sh`:

```sh
# Interval for update checks — human-readable
# 30s, 10m, 1h, 12h, 1d (default), 7d, 1w, 0/never/off to disable
DECENT_YT_DLP_UPDATE_INTERVAL=1d
```

### Environment

```sh
DECENT_YT_DLP_UPDATE_INTERVAL=12h yt-dlp <args>  # one-shot
DECENT_YT_DLP_UPDATE_INTERVAL=0 yt-dlp <args>     # disable
DECENT_YT_DLP_NO_UPDATE=1 yt-dlp <args>           # skip once
DECENT_YT_DLP_BIN=/custom/path/yt-dlp yt-dlp ...  # override real bin
DECENT_YT_DLP_CACHE_DIR=/tmp/cache yt-dlp ...     # override cache
```

Interval formats:

| Value                                   | Meaning     |
| --------------------------------------- | ----------- |
| `30s` `10m` `12h` `1d` `7d` `1w`        | human       |
| `86400`                                 | raw seconds |
| `0` `never` `off` `disable` `no` `none` | disable     |

## Uninstall

```sh
./uninstall.sh                 # removes wrapper + uv tool
./uninstall.sh --bin-dir ~/bin
./uninstall.sh --purge         # also removes cache + config
DECENT_YT_DLP_BIN_DIR=~/bin ./uninstall.sh
```

Keeps `~/.cache/decent-yt-dlp` and `~/.config/decent-yt-dlp` unless `--purge`.

## Troubleshooting

- `install.sh` says `yt-dlp already installed` — remove the existing one:
  ```sh
  brew uninstall yt-dlp
  sudo pacman -R yt-dlp
  pip uninstall yt-dlp; pipx uninstall yt-dlp
  rm ~/bin/yt-dlp  # if manual symlink
  ```
  Then re-run `install.sh`.
- `uv not found` after install — add `~/.local/bin` to `PATH`.
- Update fails (offline) — wrapper prints warning and runs existing `yt-dlp` anyway.

## License

MIT / Unlicense

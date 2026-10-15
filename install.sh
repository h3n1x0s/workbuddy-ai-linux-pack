#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
APP_NAME="workbuddy-ai"
APP_DST="$PREFIX/opt/$APP_NAME"
BIN_DST="$PREFIX/bin/$APP_NAME"
DESKTOP_DIR="$PREFIX/share/applications"
DESKTOP_DST="$DESKTOP_DIR/$APP_NAME.desktop"
ICON_DST="$PREFIX/share/icons/hicolor/256x256/apps/$APP_NAME.png"
MIME_PKG_DIR="$PREFIX/share/mime/packages"

log() { printf '\033[32m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[warn]\033[0m %s\n' "$*"; }
die() { printf '\033[31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  log "removing WorkBuddy AI from $PREFIX"
  rm -rf "$APP_DST"
  rm -f "$BIN_DST" "$DESKTOP_DST" "$ICON_DST" "$MIME_PKG_DIR/$APP_NAME.xml"
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
  command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$PREFIX/share/mime" 2>/dev/null || true
  log "done. User data in ~/.workbuddy-ai was left untouched."
  exit 0
fi

APP_ARCHIVE=""
if [ -f "$HERE/files/workbuddy-ai-app.tar.gz" ]; then
  APP_ARCHIVE="$HERE/files/workbuddy-ai-app.tar.gz"
elif [ -f "$HERE/files/workbuddy-ai-app.tar.zst" ]; then
  APP_ARCHIVE="$HERE/files/workbuddy-ai-app.tar.zst"
else
  die "missing files/workbuddy-ai-app.tar.gz"
fi
command -v tar >/dev/null || die "tar is required"

install_missing_deps() {
  command -v apt-get >/dev/null 2>&1 || return 0
  command -v dpkg-query >/dev/null 2>&1 || return 0

  local missing=() chosen

  add_dep() {
    local installed=0 candidate="" pkg
    for pkg in "$@"; do
      if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        installed=1
        break
      fi
      if [ -z "$candidate" ] && apt-cache show "$pkg" >/dev/null 2>&1; then
        candidate="$pkg"
      fi
    done
    if [ "$installed" -eq 0 ] && [ -n "$candidate" ]; then
      missing+=("$candidate")
    fi
  }

  add_dep libasound2t64 libasound2
  add_dep libatk-bridge2.0-0
  add_dep libatk1.0-0
  add_dep libayatana-appindicator3-1
  add_dep libcairo2
  add_dep libcups2t64 libcups2
  add_dep libdbus-1-3
  add_dep libdrm2
  add_dep libgbm1
  add_dep libgtk-3-0t64 libgtk-3-0
  add_dep libnspr4
  add_dep libnss3
  add_dep libpango-1.0-0
  add_dep libsecret-1-0
  add_dep libx11-6
  add_dep libx11-xcb1
  add_dep libxcb-dri3-0
  add_dep libxcb1
  add_dep libxcomposite1
  add_dep libxdamage1
  add_dep libxext6
  add_dep libxfixes3
  add_dep libxkbcommon0
  add_dep libxrandr2
  add_dep libxss1
  add_dep xdg-utils
  add_dep shared-mime-info
  add_dep desktop-file-utils
  add_dep ca-certificates

  if [ "${#missing[@]}" -gt 0 ]; then
    warn "missing runtime packages: ${missing[*]}"
    if command -v sudo >/dev/null 2>&1; then
      if [ -t 0 ]; then
        log "installing missing runtime packages with apt (sudo may prompt)"
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
      elif sudo -n true >/dev/null 2>&1; then
        log "installing missing runtime packages with apt"
        sudo -n apt-get update
        sudo -n apt-get install -y "${missing[@]}"
      else
        warn "cannot prompt for sudo in this shell. Run again from a terminal, or install: ${missing[*]}"
      fi
    else
      warn "sudo not found. If launch fails, install: ${missing[*]}"
    fi
  fi
}

log "installing WorkBuddy AI international edition"
log "prefix: $PREFIX"
mkdir -p "$APP_DST" "$PREFIX/bin" "$DESKTOP_DIR" "$(dirname "$ICON_DST")" "$MIME_PKG_DIR"

log "1/5 checking runtime dependencies and extracting application (~1 GB installed)"
install_missing_deps
rm -rf "$APP_DST"
mkdir -p "$APP_DST"
case "$APP_ARCHIVE" in
  *.tar.gz)  tar -xzf "$APP_ARCHIVE" -C "$APP_DST" ;;
  *.tar.zst) command -v zstd >/dev/null || die "zstd is required for this archive. Install it or use the .tar.gz package."; tar --zstd -xf "$APP_ARCHIVE" -C "$APP_DST" ;;
  *) die "unsupported app archive: $APP_ARCHIVE" ;;
esac
chmod +x "$APP_DST/start.sh" "$APP_DST/electron" 2>/dev/null || true

# Remove the stale .desktop file baked into the payload by the packager's
# build machine — it contains a hardcoded absolute path (e.g.
# /home/henix/.../start.sh) that is invalid on the target system.  This
# installer writes its own correct desktop entry below, so the leftover is
# pure dead weight.
rm -f "$APP_DST/.workbuddy-linux/workbuddy-ai.desktop"

log "2/5 writing launcher $BIN_DST"
cat > "$BIN_DST" <<EOF
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$APP_DST"
[ -x "\$APP_DIR/start.sh" ] || { echo "WorkBuddy AI is not installed correctly: \$APP_DIR/start.sh missing" >&2; exit 1; }
unset ELECTRON_RUN_AS_NODE || true
exec "\$APP_DIR/start.sh" "\$@"
EOF
chmod +x "$BIN_DST"

log "3/5 installing icon and desktop entry"
ICON_SRC=""
for candidate in \
  "$APP_DST/workbuddy-ai.png" \
  "$APP_DST/.workbuddy-linux/workbuddy-ai.png" \
  "$APP_DST/resources/app.asar.unpacked/resources/icon.png"
do
  [ -f "$candidate" ] && { ICON_SRC="$candidate"; break; }
done
[ -n "$ICON_SRC" ] && cp -f "$ICON_SRC" "$ICON_DST" || warn "icon not found; app still launches"
cat > "$DESKTOP_DST" <<EOF
[Desktop Entry]
Name=WorkBuddy AI
Comment=Run WorkBuddy AI on Linux
Exec=$BIN_DST %u
Icon=$APP_NAME
Terminal=false
Type=Application
Categories=Development;
MimeType=x-scheme-handler/workbuddy-ai;x-scheme-handler/workbuddy;
Keywords=workbuddy;ai;agent;coding;
StartupNotify=true
StartupWMClass=WorkBuddy AI
X-GNOME-WMClass=WorkBuddy AI
Actions=new-window;

[Desktop Action new-window]
Name=New Window
Exec=$BIN_DST --new-instance
EOF

log "4/5 registering URI schemes for browser login callback"
cat > "$MIME_PKG_DIR/$APP_NAME.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="x-scheme-handler/workbuddy-ai">
    <comment>WorkBuddy AI protocol (OAuth callback)</comment>
  </mime-type>
  <mime-type type="x-scheme-handler/workbuddy">
    <comment>WorkBuddy deep link protocol</comment>
  </mime-type>
</mime-info>
EOF
command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$PREFIX/share/mime" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
if command -v xdg-mime >/dev/null 2>&1; then
  xdg-mime default "$APP_NAME.desktop" x-scheme-handler/workbuddy-ai 2>/dev/null || true
  xdg-mime default "$APP_NAME.desktop" x-scheme-handler/workbuddy 2>/dev/null || true
fi

log "5/5 self-check"
FAIL=0
[ -x "$APP_DST/start.sh" ] || { warn "start.sh missing"; FAIL=1; }
[ -x "$APP_DST/electron" ] || { warn "electron missing"; FAIL=1; }
[ -f "$APP_DST/resources/app.asar" ] || { warn "app.asar missing"; FAIL=1; }
[ -x "$BIN_DST" ] || { warn "launcher missing"; FAIL=1; }
for S in workbuddy-ai workbuddy; do
  handler="$(xdg-mime query default "x-scheme-handler/$S" 2>/dev/null || true)"
  [ "$handler" = "$APP_NAME.desktop" ] && log "  x-scheme-handler/$S -> $handler" || warn "  x-scheme-handler/$S -> ${handler:-<unregistered>}"
done
[ "$FAIL" -eq 0 ] || die "self-check failed"

log "install complete"
printf '\nLaunch:\n  %s\n  app menu -> WorkBuddy AI\n\nUninstall:\n  %s --uninstall\n' "$BIN_DST" "$HERE/install.sh"

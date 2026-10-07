#!/bin/sh
#
# MAC-LIMPO — build from source and install, on your own Mac.
#
#     curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh | sh
#
# Why build instead of downloading an app: MAC-LIMPO is not signed with an
# Apple Developer ID (a paid certificate). macOS interrogates apps that arrive
# from the internet carrying the quarantine flag (com.apple.quarantine), and an
# unsigned download is blocked with "cannot verify that it is free of malware".
# An app that comes out of the compiler on this Mac never had that flag, so it
# opens on the first double-click — no trip to System Settings.
#
# Options (with `curl | sh`, pass them after `sh -s --`):
#
#     curl -fsSL <url> | sh -s -- --version main      build the latest code
#     curl -fsSL <url> | sh -s -- --dest ~/Applications
#     curl -fsSL <url> | sh -s -- --dry-run           show what would happen
#     curl -fsSL <url> | sh -s -- --uninstall         remove MAC-LIMPO
#
# Reading a script before running it is a good habit:
#
#     curl -fsSL https://alexkads.github.io/MAC-LIMPO/install.sh -o install.sh
#     less install.sh && sh install.sh
#
# SPDX-License-Identifier: GPL-3.0-or-later

set -eu

OWNER="alexkads"
REPO="MAC-LIMPO"
APP_NAME="MAC-LIMPO"
SITE="https://alexkads.github.io/MAC-LIMPO/"
MIN_MACOS_MAJOR=26
MIN_MACOS_MINOR=6
MIN_SWIFT_MAJOR=6
MIN_SWIFT_MINOR=4

# Source and the compiler cache live here, so the next update is much faster.
HOME_DIR="${MACLIMPO_HOME:-$HOME/Library/Caches/MAC-LIMPO-build}"
SOURCE="$HOME_DIR/source"

REF=""; DEST=""; DRY=0; UNINSTALL=0; OPEN_AFTER=1

if [ -t 1 ]; then
  C='\033[1;36m'; G='\033[1;32m'; Y='\033[1;33m'; R='\033[1;31m'; B='\033[1m'; Z='\033[0m'
else
  C=''; G=''; Y=''; R=''; B=''; Z=''
fi

step() { printf "\n${C}▸ %s${Z}\n" "$*"; }
ok()   { printf "${G}✓ %s${Z}\n" "$*"; }
warn() { printf "${Y}! %s${Z}\n" "$*"; }
fail() { printf "${R}✗ %s${Z}\n" "$*" >&2; }
run()  { if [ "$DRY" -eq 1 ]; then echo "   [dry-run] $*"; else "$@"; fi; }

# A copy installed by the .pkg belongs to root: /Applications is writable by an
# admin, but the bundle inside it is not — so check the bundle, not its folder.
remove_app() {
  [ -e "$1" ] || return 0
  if [ -w "$(dirname "$1")" ] && [ -z "$(find "$1" ! -user "$(id -un)" -print -quit 2>/dev/null)" ]; then
    run rm -rf "$1"
  else
    warn "$1 belongs to another user (installed by the .pkg?) — sudo will ask for your password"
    run sudo rm -rf "$1" || { fail "could not remove $1"; exit 1; }
  fi
}

# The help text lives here, not read from this file: under `curl | sh` the
# script is not on disk ($0 is just "sh").
usage() {
  cat <<HELP
MAC-LIMPO — build from source and install on this Mac.

  curl -fsSL ${SITE}install.sh | sh

Why: MAC-LIMPO is not signed with a paid Apple Developer ID, so a downloaded
app is blocked by Gatekeeper. An app built on this Mac opens normally.

Options (with curl | sh, pass them after \`sh -s --\`):
  --version <ref>   tag (v1.3.13) or branch (main). Default: latest release
  --dest <folder>   where to install the app. Default: /Applications
                    (falls back to ~/Applications if not writable)
  --no-open         don't launch the app at the end
  --dry-run         show what would happen, change nothing
  --uninstall       remove the app and the build cache
  --help            this text

Needs macOS ${MIN_MACOS_MAJOR}.${MIN_MACOS_MINOR}+ on Apple silicon, the Command Line Tools (or Xcode) with Swift ${MIN_SWIFT_MAJOR}.${MIN_SWIFT_MINOR}+,
an internet connection and ~2 GB free. Takes 2–5 minutes the first time.
HELP
}

missing() { fail "$1 needs a value, e.g. $1 $2"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --version)   [ $# -ge 2 ] || missing --version v1.3.13; REF="$2"; shift 2 ;;
    --version=*) REF="${1#*=}"; shift ;;
    --dest)      [ $# -ge 2 ] || missing --dest /Applications; DEST="$2"; shift 2 ;;
    --dest=*)    DEST="${1#*=}"; shift ;;
    --no-open)   OPEN_AFTER=0; shift ;;
    --dry-run)   DRY=1; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) fail "unknown option: $1"; echo "   available: --version, --dest, --no-open, --dry-run, --uninstall, --help"; exit 1 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  fail "MAC-LIMPO is a macOS app — this installer only runs on a Mac."
  exit 1
fi

quit_running_app() {
  if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    step "quitting the running MAC-LIMPO"
    run osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
    sleep 1
    run pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  fi
}

# ── Uninstall ────────────────────────────────────────────────────────────────
if [ "$UNINSTALL" -eq 1 ]; then
  quit_running_app
  step "removing MAC-LIMPO"
  for app in "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app" ${DEST:+"$DEST/$APP_NAME.app"}; do
    if [ -d "$app" ]; then
      remove_app "$app"
      ok "removed $app"
    fi
  done
  [ -d "$HOME_DIR" ] && run rm -rf "$HOME_DIR" && ok "removed the build cache ($HOME_DIR)"
  ok "done. Your files were not touched."
  exit 0
fi

# ── Requirements, all checked before compiling ───────────────────────────────
step "checking this Mac"

MACOS="$(sw_vers -productVersion)"
MACOS_MAJOR="${MACOS%%.*}"
MACOS_MINOR=0
case "$MACOS" in *.*) MACOS_MINOR="${MACOS#*.}"; MACOS_MINOR="${MACOS_MINOR%%.*}" ;; esac
# Xcode 27 (Swift 6.4) itself needs macOS 26.6, so that is the floor for building here.
if [ "$MACOS_MAJOR" -lt "$MIN_MACOS_MAJOR" ] ||
   { [ "$MACOS_MAJOR" -eq "$MIN_MACOS_MAJOR" ] && [ "$MACOS_MINOR" -lt "$MIN_MACOS_MINOR" ]; }; then
  fail "MAC-LIMPO needs macOS ${MIN_MACOS_MAJOR}.${MIN_MACOS_MINOR} or later — this Mac has ${MACOS}."
  [ "$MACOS_MAJOR" -eq "$MIN_MACOS_MAJOR" ] && echo "   It is a free update: System Settings › General › Software Update."
  exit 1
fi
# sysctl, not uname -m: a Terminal running under Rosetta reports x86_64.
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]; then
  fail "MAC-LIMPO needs a Mac with Apple silicon (Xcode 27 does not run on Intel)."
  exit 1
fi
ok "macOS ${MACOS}"

for tool in curl tar rsync; do
  command -v "$tool" >/dev/null 2>&1 || { fail "'$tool' is missing — it ships with macOS, so something is off."; exit 1; }
done

if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  fail "the Command Line Tools are not installed (they provide the Swift compiler)."
  echo
  echo "   Install them (free, about 5 minutes):"
  printf '      %bxcode-select --install%b\n' "$B" "$Z"
  echo "   Then run this installer again."
  exit 1
fi

SWIFT_VERSION="$(swift --version 2>/dev/null | sed -n 's/.*Swift version \([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p' | head -1)"
SWIFT_MAJOR="${SWIFT_VERSION%%.*}"
SWIFT_MINOR="${SWIFT_VERSION#*.}"
if [ -z "$SWIFT_VERSION" ] || [ "$SWIFT_MAJOR" -lt "$MIN_SWIFT_MAJOR" ] ||
   { [ "$SWIFT_MAJOR" -eq "$MIN_SWIFT_MAJOR" ] && [ "$SWIFT_MINOR" -lt "$MIN_SWIFT_MINOR" ]; }; then
  fail "MAC-LIMPO needs Swift ${MIN_SWIFT_MAJOR}.${MIN_SWIFT_MINOR}+ — found ${SWIFT_VERSION:-none} ($(xcode-select -p))."
  echo
  echo "   Update the Command Line Tools in System Settings › General › Software Update,"
  echo "   or install the latest Xcode from the App Store and run:"
  printf '      %bsudo xcode-select -s /Applications/Xcode.app%b\n' "$B" "$Z"
  exit 1
fi
ok "Swift ${SWIFT_VERSION} ($(xcode-select -p))"

FREE_GB="$(df -g "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"
case "$FREE_GB" in
  ''|*[!0-9]*) : ;;
  *) if [ "$FREE_GB" -lt 2 ]; then
       fail "only ${FREE_GB} GB free — the build needs about 2 GB."
       exit 1
     fi
     ok "${FREE_GB} GB free" ;;
esac

# ── Which version ────────────────────────────────────────────────────────────
if [ -z "$REF" ]; then
  REF="$(curl -fsSL "https://api.github.com/repos/$OWNER/$REPO/releases/latest" 2>/dev/null |
         sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$REF" ] || REF="main"
fi
ok "version: $REF"

# ── Download ─────────────────────────────────────────────────────────────────
step "downloading the source ($REF)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
run curl -fsSL "https://codeload.github.com/$OWNER/$REPO/tar.gz/$REF" -o "$TMP/source.tar.gz"
if [ "$DRY" -eq 0 ]; then
  tar -xzf "$TMP/source.tar.gz" -C "$TMP"
  EXTRACTED="$(find "$TMP" -mindepth 1 -maxdepth 1 -type d | head -1)"
  mkdir -p "$SOURCE"
  # Keep .build (the compiler cache) so updates only rebuild what changed.
  rsync -a --delete --exclude ".build" "$EXTRACTED/" "$SOURCE/"
fi
ok "source in $SOURCE"

# ── Build ────────────────────────────────────────────────────────────────────
step "building (2–5 minutes the first time)"
if [ "$DRY" -eq 1 ]; then
  echo "   [dry-run] (cd $SOURCE && ./Scripts/bundle-app.sh)"
else
  (cd "$SOURCE" && ./Scripts/bundle-app.sh) > "$HOME_DIR/build.log" 2>&1 || {
    fail "the build failed. The last lines of the log:"
    tail -25 "$HOME_DIR/build.log" >&2
    echo
    echo "   Full log: $HOME_DIR/build.log"
    echo "   Please open an issue with it: https://github.com/$OWNER/$REPO/issues/new/choose"
    exit 1
  }
fi
BUILT="$SOURCE/build/app/$APP_NAME.app"
ok "built $APP_NAME.app"

# ── Install ──────────────────────────────────────────────────────────────────
if [ -z "$DEST" ]; then
  if [ -w /Applications ]; then DEST="/Applications"; else DEST="$HOME/Applications"; fi
fi
step "installing into $DEST"
quit_running_app
run mkdir -p "$DEST"
remove_app "$DEST/$APP_NAME.app"
run ditto "$BUILT" "$DEST/$APP_NAME.app"
# Built here, so there is no quarantine flag — removing it is just belt and braces.
run xattr -dr com.apple.quarantine "$DEST/$APP_NAME.app" 2>/dev/null || true
ok "installed $DEST/$APP_NAME.app"

if [ "$OPEN_AFTER" -eq 1 ]; then
  run open "$DEST/$APP_NAME.app"
  echo
  printf '%bMAC-LIMPO is running — look for its icon in the menu bar.%b\n' "$B" "$Z"
fi

echo
echo "   Update later:  run the same command again (it reuses the build cache)."
echo "   Uninstall:     curl -fsSL ${SITE}install.sh | sh -s -- --uninstall"
echo "   Docs:          $SITE"

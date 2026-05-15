#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HDCV Viewer"
TARGET_NAME="hdcv_viewer_app"
CONFIG="Release"
ARCHS="${HDCV_ARCHS:-arm64}"
BUILD_DIR=""
DIST_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARIZE=0
CLEAN=0
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

usage() {
  cat <<'EOF'
Usage: scripts/package_macos.sh [options]

Builds a shareable macOS HDCV Viewer package.

Options:
  --identity NAME        Developer ID Application identity for distribution signing.
                         Defaults to CODE_SIGN_IDENTITY. Without it, ad-hoc signing is used.
  --notary-profile NAME  notarytool keychain profile. Defaults to NOTARY_PROFILE.
  --notarize            Submit app ZIP and DMG to Apple's notary service and staple tickets.
  --universal           Build arm64+x86_64 instead of arm64 only.
  --archs LIST          CMake architecture list, for example "arm64" or "arm64;x86_64".
  --build-dir DIR       Build directory. Defaults to build-package-<arch>.
  --dist-dir DIR        Distribution output directory. Defaults to dist/.
  --clean               Remove the package build directory and dist output before building.
  -h, --help            Show this help.

Examples:
  scripts/package_macos.sh --clean
  scripts/package_macos.sh --clean \
    --identity "Developer ID Application: Your Name (TEAMID)" \
    --notary-profile hdcv-notary \
    --notarize

Before notarizing, create a notarytool profile once:
  xcrun notarytool store-credentials hdcv-notary --apple-id you@example.com --team-id TEAMID --password APP_SPECIFIC_PASSWORD
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

log() {
  printf '\n==> %s\n' "$*"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)
      [[ $# -ge 2 ]] || die "--identity requires a value"
      SIGN_IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      [[ $# -ge 2 ]] || die "--notary-profile requires a value"
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --notarize)
      NOTARIZE=1
      shift
      ;;
    --universal)
      ARCHS="arm64;x86_64"
      shift
      ;;
    --archs)
      [[ $# -ge 2 ]] || die "--archs requires a value"
      ARCHS="$2"
      shift 2
      ;;
    --build-dir)
      [[ $# -ge 2 ]] || die "--build-dir requires a value"
      BUILD_DIR="$2"
      shift 2
      ;;
    --dist-dir)
      [[ $# -ge 2 ]] || die "--dist-dir requires a value"
      DIST_DIR="$2"
      shift 2
      ;;
    --clean)
      CLEAN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

command -v cmake >/dev/null || die "cmake is required"
command -v codesign >/dev/null || die "codesign is required"
command -v hdiutil >/dev/null || die "hdiutil is required"
command -v ditto >/dev/null || die "ditto is required"

VERSION="$(awk '/MACOSX_BUNDLE_SHORT_VERSION_STRING/ { gsub(/"/, "", $2); print $2; exit }' "$ROOT_DIR/CMakeLists.txt")"
[[ -n "$VERSION" ]] || VERSION="0.1.0"

ARCH_LABEL="$(printf '%s' "$ARCHS" | tr ';' '-')"
[[ -n "$BUILD_DIR" ]] || BUILD_DIR="$ROOT_DIR/build-package-$ARCH_LABEL"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_ZIP="$DIST_DIR/HDCV_Viewer-$VERSION-$ARCH_LABEL.app.zip"
DMG_PATH="$DIST_DIR/HDCV_Viewer-$VERSION-$ARCH_LABEL.dmg"
DMG_ROOT="$DIST_DIR/dmg-root"
ICON_PATH="$ROOT_DIR/resources/HDCVViewer.icns"

[[ -f "$ICON_PATH" ]] || die "missing app icon: $ICON_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  [[ -n "$SIGN_IDENTITY" ]] || die "--notarize requires --identity or CODE_SIGN_IDENTITY"
  [[ -n "$NOTARY_PROFILE" ]] || die "--notarize requires --notary-profile or NOTARY_PROFILE"
  command -v xcrun >/dev/null || die "xcrun is required for notarization"
fi

if [[ "$CLEAN" -eq 1 ]]; then
  log "Cleaning package outputs"
  rm -rf "$BUILD_DIR" "$DIST_DIR"
fi

mkdir -p "$DIST_DIR"

log "Configuring $CONFIG build for $ARCH_LABEL"
cmake -S "$ROOT_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE="$CONFIG" \
  -DCMAKE_OSX_ARCHITECTURES="$ARCHS" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0

log "Building $APP_NAME.app"
cmake --build "$BUILD_DIR" --target "$TARGET_NAME" -j "$JOBS"

[[ -d "$APP_BUNDLE" ]] || die "expected app bundle was not built: $APP_BUNDLE"

log "Removing transient metadata"
xattr -cr "$APP_BUNDLE" || true

if [[ -n "$SIGN_IDENTITY" ]]; then
  SIGN_ARGS=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
  log "Signing with Developer ID identity: $SIGN_IDENTITY"
else
  SIGN_ARGS=(--force --sign -)
  log "Signing ad-hoc for local testing"
fi

if [[ -x "$APP_BUNDLE/Contents/Resources/bin/hdcv" ]]; then
  codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/Resources/bin/hdcv"
fi
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"
codesign --verify --strict --deep --verbose=2 "$APP_BUNDLE"

log "Creating app ZIP"
rm -f "$APP_ZIP"
(cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_ZIP")

if [[ "$NOTARIZE" -eq 1 ]]; then
  log "Notarizing app ZIP"
  xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"

  log "Recreating ZIP with stapled app"
  rm -f "$APP_ZIP"
  (cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME.app" "$APP_ZIP")
fi

log "Creating DMG"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP_BUNDLE" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG_PATH" >/dev/null
rm -rf "$DMG_ROOT"

if [[ -n "$SIGN_IDENTITY" ]]; then
  log "Signing DMG"
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  log "Notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

log "Package outputs"
ls -lh "$APP_ZIP" "$DMG_PATH"

if [[ "$NOTARIZE" -eq 0 ]]; then
  cat <<EOF

Built an ad-hoc/local test package. For public sharing without Gatekeeper warnings,
rerun with a Developer ID Application identity and --notarize.
EOF
fi

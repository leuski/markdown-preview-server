#!/usr/bin/env bash
#
# Phase 1 release: build an unsigned (or ad-hoc / free-team-signed) .app,
# zip it, and publish a GitHub release.
#
# Usage:
#   scripts/release.sh v0.1.0
#
# Requirements: Xcode, gh CLI authenticated, clean git tree.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <tag>   e.g. $0 v0.1.0" >&2
  exit 1
fi

TAG="$1"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty. commit or stash first." >&2
  exit 1
fi

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: tag must look like v1.2.3 (got '$TAG')" >&2
  exit 1
fi

MARKETING_VERSION="${TAG#v}"
BUILD_NUMBER="$(git rev-list --count HEAD)"

SCHEME="MarkdownPreviewer"
APP_NAME="Markdown Preview Server.app"
BUILD_DIR="$PROJECT_ROOT/build/release"
ARCHIVE_PATH="$BUILD_DIR/MarkdownPreviewer.xcarchive"
ZIP_PATH="$BUILD_DIR/MarkdownPreviewer-$TAG.zip"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving $SCHEME ($TAG, build $BUILD_NUMBER)"
xcodebuild \
  -project MarkdownPreviewer.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$MARKETING_VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

APP_SRC="$ARCHIVE_PATH/Products/Applications/$APP_NAME"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: built app not found at $APP_SRC" >&2
  exit 1
fi

echo "==> Zipping $APP_NAME"
ditto -c -k --keepParent --sequesterRsrc "$APP_SRC" "$ZIP_PATH"

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

echo "==> Creating GitHub release $TAG"
NOTES_FILE="$BUILD_DIR/NOTES.md"
cat > "$NOTES_FILE" <<EOF
## $TAG

**Unsigned build** — macOS Gatekeeper will block this on first launch.

To open:
1. Download and unzip.
2. Move \`Markdown Preview Server.app\` to \`/Applications\`.
3. Right-click the app → **Open** → confirm.

(Or in Terminal: \`xattr -dr com.apple.quarantine "/Applications/Markdown Preview Server.app"\`.)
EOF

gh release create "$TAG" "$ZIP_PATH" \
  --title "$TAG" \
  --notes-file "$NOTES_FILE"

echo "==> Done: $ZIP_PATH"

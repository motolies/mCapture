#!/usr/bin/env bash
# mCapture.app 번들을 조립하고 서명한다.
# 사용법: ./scripts/build-app.sh [debug|release]
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/mCapture.app"
IDENTITY="${MCAPTURE_SIGN_IDENTITY:-mCapture Dev}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/mCapture" "$APP/Contents/MacOS/mCapture"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# 아이콘을 바꾸려면 scripts/make-icon.swift를 고친 뒤 swift scripts/make-icon.swift 로 다시 생성한다
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 같은 인증서로 서명해야 화면 기록 권한이 재빌드 후에도 유지된다
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier com.motolies.mcapture "$APP"
    echo "✅ 서명: $IDENTITY"
else
    codesign --force --sign - --identifier com.motolies.mcapture "$APP"
    echo "⚠️  '$IDENTITY' 인증서가 없어 임시 서명했습니다. 재빌드마다 화면 기록 권한을 다시 허용해야 합니다."
    echo "    ./scripts/create-signing-identity.sh 를 한 번 실행하세요."
fi

echo "📦 $APP"

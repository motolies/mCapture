#!/usr/bin/env bash
# mCapture 앱 번들을 조립하고 서명한다.
# 사용법: [MCAPTURE_VARIANT=dev|production] ./scripts/build-app.sh [debug|release]
#
# MCAPTURE_VARIANT (기본 dev)
#   dev        → build/mCapture-dev.app (com.motolies.mcapture.dev, mcapture-dev://)
#                사용 중인 mCapture와 설정·단축키·URL·저장 폴더가 겹치지 않아 함께 띄워 둘 수 있다
#   production → build/mCapture.app (com.motolies.mcapture). 배포용, make-dmg.sh가 쓴다
set -euo pipefail

CONFIG="${1:-debug}"
VARIANT="${MCAPTURE_VARIANT:-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${MCAPTURE_SIGN_IDENTITY:-mCapture Dev}"
PLIST_BUDDY=/usr/libexec/PlistBuddy

# 변형별 값. Swift 쪽 AppVariant(Sources/MCaptureCore/Support/AppVariant.swift)와 같아야 한다
case "$VARIANT" in
    dev)
        APP="$ROOT/build/mCapture-dev.app"
        BUNDLE_ID=com.motolies.mcapture.dev
        NAME="mCapture Dev"
        EXECUTABLE=mCaptureDev
        SCHEME=mcapture-dev
        ;;
    production)
        APP="$ROOT/build/mCapture.app"
        BUNDLE_ID=com.motolies.mcapture
        NAME=mCapture
        EXECUTABLE=mCapture
        SCHEME=mcapture
        ;;
    *)
        echo "❌ MCAPTURE_VARIANT는 dev 또는 production이어야 합니다: $VARIANT" >&2
        exit 1
        ;;
esac

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# 실행 파일 이름을 나눠 두면 pkill -x로 한쪽만 끌 수 있다
cp "$BIN_DIR/mCapture" "$APP/Contents/MacOS/$EXECUTABLE"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# 아이콘을 바꾸려면 scripts/make-icon.swift를 고친 뒤 swift scripts/make-icon.swift 로 다시 생성한다
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Resources/Info.plist는 production 값이다. 변형 값으로 덮어쓴다 (production이면 같은 값이라 그대로)
"$PLIST_BUDDY" \
    -c "Set :CFBundleIdentifier $BUNDLE_ID" \
    -c "Set :CFBundleName $NAME" \
    -c "Set :CFBundleDisplayName $NAME" \
    -c "Set :CFBundleExecutable $EXECUTABLE" \
    -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID" \
    -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $SCHEME" \
    "$APP/Contents/Info.plist"

# 같은 인증서로 서명해야 화면 기록 권한이 재빌드 후에도 유지된다
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "✅ 서명: $IDENTITY"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "⚠️  '$IDENTITY' 인증서가 없어 임시 서명했습니다. 재빌드마다 화면 기록 권한을 다시 허용해야 합니다."
    echo "    ./scripts/create-signing-identity.sh 를 한 번 실행하세요."
fi

echo "📦 $APP ($VARIANT, $CONFIG)"

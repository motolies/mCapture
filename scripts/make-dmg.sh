#!/usr/bin/env bash
# 배포용 DMG를 만든다: release 빌드한 mCapture.app + Applications 바로가기 + 설치 안내.
# 사용법: ./scripts/make-dmg.sh
# 결과: build/mCapture-<버전>.dmg (버전은 Resources/Info.plist의 CFBundleShortVersionString)
# Apple 공증 없이 배포하므로 받는 사람은 docs/설치-안내.md의 첫 실행 절차를 거쳐야 한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/mCapture.app"
STAGE="$ROOT/build/dmg"
GUIDE="$ROOT/docs/설치-안내.md"

trap 'rm -rf "$STAGE"' EXIT

"$ROOT/scripts/build-app.sh" release

# 임시 서명은 빌드마다 서명이 바뀌어 받는 사람이 업데이트할 때마다 화면 기록 권한을 다시 허용해야 한다.
# pipefail에서 grep -q가 일찍 끝나면 codesign이 SIGPIPE로 실패할 수 있어 출력을 먼저 받아 둔다.
SIGN_INFO="$(codesign -dvv "$APP" 2>&1)"
if ! grep -q '^Authority=' <<<"$SIGN_INFO"; then
    echo "❌ 임시 서명으로 빌드되어 DMG를 만들지 않습니다." >&2
    echo "   이전에 배포한 적이 있으면 그때 쓴 서명 인증서를 키체인에 복원하고," >&2
    echo "   처음이면 ./scripts/create-signing-identity.sh 를 실행한 뒤 다시 시도하세요." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$ROOT/build/mCapture-$VERSION.dmg"

# DMG 창에 보일 항목: 앱, 끌어다 놓을 Applications 바로가기, 설치 안내
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/mCapture.app"
ln -s /Applications "$STAGE/Applications"
cp "$GUIDE" "$STAGE/설치-안내.md"

# 최신 macOS에서는 hdiutil create가 deprecated라 diskutil image가 있으면 그쪽을 쓴다
rm -f "$DMG"
if diskutil image create from --help >/dev/null 2>&1; then
    # 진행률 출력이 길어 성공하면 숨기고 실패할 때만 보여준다
    if ! LOG="$(diskutil image create from --format UDZO --volumeName "mCapture $VERSION" "$STAGE" "$DMG" 2>&1)"; then
        echo "$LOG" >&2
        exit 1
    fi
else
    hdiutil create -volname "mCapture $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG" >/dev/null
fi

echo "📀 $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' '))"

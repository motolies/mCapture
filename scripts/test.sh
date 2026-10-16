#!/usr/bin/env bash
# 단위 테스트 실행.
# Command Line Tools 환경의 swift test는 증분 빌드 때 Testing 매크로 플러그인 경로를 빠뜨려
# 실행할 때마다 성공/실패가 번갈아 나온다. 활성 툴체인의 플러그인 경로를 직접 넘겨 회피한다.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLCHAIN_BIN="$(dirname "$(xcrun --find swift)")"
PLUGINS="$TOOLCHAIN_BIN/../lib/swift/host/plugins/testing"

cd "$ROOT"
if [ -d "$PLUGINS" ]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$(cd "$PLUGINS" && pwd)" "$@"
else
    swift test "$@"
fi

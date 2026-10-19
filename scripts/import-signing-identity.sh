#!/usr/bin/env bash
# export-signing-identity.swift로 백업한 mCapture 서명 인증서(.p12)를 로그인 키체인에 복원한다.
# 사용법: ./scripts/import-signing-identity.sh <백업.p12>
# 여러 컴퓨터에서 배포할 때 모두 같은 인증서로 서명해야 받는 사람의 화면 기록 권한이 유지된다.
# 이름이 같은 다른 인증서가 있으면 codesign이 하나를 고르지 못하므로, 확인을 받고 지운 뒤 복원한다.
set -euo pipefail

NAME="${MCAPTURE_SIGN_IDENTITY:-mCapture}"
KEYCHAIN="${MCAPTURE_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl   # macOS 기본 LibreSSL (키체인이 만든 PKCS#12를 별도 옵션 없이 읽는다)
P12="${1:-}"

if [ -z "$P12" ] || [ ! -f "$P12" ]; then
    echo "사용법: $0 <백업.p12>" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# openssl에는 암호를 환경 변수로 넘긴다. security import는 명령줄(-P)로만 받아 가져오는 동안 ps에 보인다
read -r -s -p "p12 암호: " P12_PASS
echo
export P12_PASS

# 암호 확인을 겸해 인증서만 꺼내 이름과 지문을 본다
if ! "$OPENSSL" pkcs12 -in "$P12" -clcerts -nokeys -passin env:P12_PASS -out "$WORK/cert.pem" 2>/dev/null; then
    echo "❌ 암호가 틀렸거나 p12 파일이 아닙니다." >&2
    exit 1
fi
# LibreSSL은 "subject= CN=..."처럼 = 뒤에 공백을 넣는다
SUBJECT="$("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -subject -nameopt RFC2253 | sed 's/^subject= *//')"
if [ "$SUBJECT" != "CN=$NAME" ]; then
    echo "❌ '$NAME' 인증서가 아닙니다: $SUBJECT" >&2
    exit 1
fi
SHA1="$("$OPENSSL" x509 -in "$WORK/cert.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d : | tr 'a-f' 'A-F')"
echo "복원할 인증서: $NAME (SHA-1 $SHA1)"

# 키체인에 이미 있는 같은 이름의 서명 정체성 (find-identity는 같은 항목을 두 번 출력해 중복을 없앤다)
EXISTING="$(security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null \
    | awk -v name="\"$NAME\"" 'index($0, name) { print $2 }' | sort -u)"
OTHERS="$(grep -vx "$SHA1" <<<"$EXISTING" || true)"

if [ -z "$OTHERS" ] && grep -qx "$SHA1" <<<"$EXISTING"; then
    echo "✅ 이미 복원되어 있습니다."
    exit 0
fi

if [ -n "$OTHERS" ]; then
    echo
    echo "⚠️  이 키체인에 다른 '$NAME' 인증서가 있습니다:"
    sed 's/^/   /' <<<"$OTHERS"
    echo "   지우면 되돌릴 수 없습니다. 필요하면 먼저 ./scripts/export-signing-identity.swift 로 백업하세요."
    read -r -p "   지우고 복원할까요? [y/N] " ANSWER
    if [ "$ANSWER" != "y" ] && [ "$ANSWER" != "Y" ]; then
        echo "취소했습니다."
        exit 1
    fi
    while read -r OLD; do
        # -t: 그 인증서에 준 신뢰 설정도 함께 지운다
        security delete-identity -Z "$OLD" -t "$KEYCHAIN"
    done <<<"$OTHERS"
fi

# create-signing-identity.sh와 같은 상태로 만든다: codesign은 묻지 않고 키를 쓰고, 코드 서명 용도로 신뢰한다
# 신뢰 설정은 p12에 들어 있지 않아 다시 넣는다. macOS가 암호를 물어볼 수 있다
security import "$P12" -k "$KEYCHAIN" -f pkcs12 -P "$P12_PASS" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "✅ '$NAME' 인증서를 복원했습니다."
security find-identity -p codesigning "$KEYCHAIN" | grep "$SHA1" | sort -u

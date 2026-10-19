#!/usr/bin/env bash
# 로그인 키체인에 mCapture 전용 자체 서명 코드 서명 인증서를 만든다 (최초 1회).
# 인증서를 신뢰 목록에 추가할 때 macOS가 암호를 물어볼 수 있다.
set -euo pipefail

NAME="${MCAPTURE_SIGN_IDENTITY:-mCapture}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # macOS 기본 LibreSSL (키체인 호환 PKCS#12 생성)
# 만료되면 codesign이 "no identity found"로 서명을 거부하고, 새 인증서는 지문이 달라 받는 사람이 권한을 다시 줘야 한다.
# 갱신할 일이 없도록 100년으로 둔다
DAYS=36500

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
    echo "이미 '$NAME' 인증서가 있습니다."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = ext
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days "$DAYS" \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout pass:mcapture

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P mcapture -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "✅ '$NAME' 인증서를 만들었습니다."
security find-identity -p codesigning | grep "\"$NAME\"" | sort -u
"$OPENSSL" x509 -in "$WORK/cert.pem" -noout -enddate
echo "   ./scripts/export-signing-identity.swift 로 바로 백업해 두세요."

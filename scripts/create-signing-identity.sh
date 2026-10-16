#!/usr/bin/env bash
# 로그인 키체인에 mCapture 전용 자체 서명 코드 서명 인증서를 만든다 (최초 1회).
# 인증서를 신뢰 목록에 추가할 때 macOS가 암호를 물어볼 수 있다.
set -euo pipefail

NAME="${MCAPTURE_SIGN_IDENTITY:-mCapture Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl   # macOS 기본 LibreSSL (키체인 호환 PKCS#12 생성)

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

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -out "$WORK/identity.p12" -passout pass:mcapture

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P mcapture -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo "✅ '$NAME' 인증서를 만들었습니다."
security find-identity -p codesigning | grep "$NAME"

#!/bin/zsh
set -euo pipefail

KEYCHAIN_PATH="${1:?missing keychain path}"
CERT_NAME="${2:?missing certificate common name}"
WORK_DIR="${3:?missing work directory}"
P12_PASSWORD="${P12_PASSWORD:?P12_PASSWORD env var not set}"

KEY_PATH="$WORK_DIR/voicewink-local-codesign.key"
CERT_PATH="$WORK_DIR/voicewink-local-codesign.crt"
P12_PATH="$WORK_DIR/voicewink-local-codesign.p12"

mkdir -p "$WORK_DIR"

if ! security show-keychain-info "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    security create-keychain -p "" "$KEYCHAIN_PATH"
    security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "" "$KEYCHAIN_PATH"

CURRENT_KEYCHAINS=("${(@f)$(security list-keychains -d user | sed 's/^[[:space:]]*//' | tr -d '"')}")
if [[ ${#CURRENT_KEYCHAINS[@]} -eq 0 ]]; then
    security list-keychains -d user -s "$KEYCHAIN_PATH"
elif [[ ! " ${CURRENT_KEYCHAINS[*]} " =~ " $KEYCHAIN_PATH " ]]; then
    security list-keychains -d user -s "$KEYCHAIN_PATH" "${CURRENT_KEYCHAINS[@]}"
fi

if ! security find-certificate -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
    rm -f "$KEY_PATH" "$CERT_PATH" "$P12_PATH"

    openssl req \
        -x509 \
        -newkey rsa:2048 \
        -sha256 \
        -days 3650 \
        -nodes \
        -subj "/CN=$CERT_NAME" \
        -addext "keyUsage = critical, digitalSignature" \
        -addext "extendedKeyUsage = critical, codeSigning" \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH"

    openssl pkcs12 \
        -export \
        -legacy \
        -inkey "$KEY_PATH" \
        -in "$CERT_PATH" \
        -out "$P12_PATH" \
        -passout "pass:$P12_PASSWORD"

    security import "$P12_PATH" \
        -k "$KEYCHAIN_PATH" \
        -P "$P12_PASSWORD" \
        -A \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    security add-trusted-cert \
        -d \
        -r trustRoot \
        -k "$KEYCHAIN_PATH" \
        "$CERT_PATH"
fi

security unlock-keychain -p "" "$KEYCHAIN_PATH"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN_PATH" >/dev/null
echo "Local codesign identity ready: $CERT_NAME"

#!/usr/bin/env bash
# Cria android/key.properties com o keystore de upload que o Codemagic
# disponibiliza (Code signing identities > Android keystores). O
# android/app/build.gradle.kts usa esse arquivo no build release.
set -euo pipefail

: "${CM_KEYSTORE_PATH:?keystore nao configurado: adicione android_signing no workflow}"

cat > android/key.properties <<EOF
storeFile=$CM_KEYSTORE_PATH
storePassword=$CM_KEYSTORE_PASSWORD
keyAlias=$CM_KEY_ALIAS
keyPassword=$CM_KEY_PASSWORD
EOF
echo "android/key.properties criado (alias $CM_KEY_ALIAS)"

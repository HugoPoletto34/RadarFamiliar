#!/usr/bin/env bash
# Gera env/<flavor>.json (lido pelo --dart-define-from-file e pelo Gradle) e
# ios/Flutter/Secrets.xcconfig (chave do Google Maps no iOS) a partir das
# variáveis do Codemagic. Nada disso vai para o git.
#
# Uso: bash scripts/ci/write_env.sh prod
set -euo pipefail

FLAVOR="${1:?informe o flavor (dev ou prod)}"

: "${SUPABASE_URL:?defina SUPABASE_URL no grupo de variáveis do Codemagic}"
: "${SUPABASE_PUBLISHABLE_KEY:?defina SUPABASE_PUBLISHABLE_KEY no grupo de variáveis do Codemagic}"

case "$SUPABASE_URL" in
  https://*) ;;
  *) [ "$FLAVOR" = "prod" ] && { echo "ERRO: SUPABASE_URL de prod precisa ser https://" >&2; exit 1; } ;;
esac

mkdir -p env
FLAVOR="$FLAVOR" python3 - > "env/$FLAVOR.json" <<'PY'
import json, os
print(json.dumps({
    "FLAVOR": os.environ["FLAVOR"],
    "SUPABASE_URL": os.environ["SUPABASE_URL"],
    "SUPABASE_PUBLISHABLE_KEY": os.environ["SUPABASE_PUBLISHABLE_KEY"],
    "GOOGLE_MAPS_API_KEY": os.environ.get("GOOGLE_MAPS_API_KEY", ""),
}, indent=2))
PY

printf 'GOOGLE_MAPS_API_KEY=%s\n' "${GOOGLE_MAPS_API_KEY:-}" > ios/Flutter/Secrets.xcconfig

echo "env/$FLAVOR.json gerado (SUPABASE_URL=$SUPABASE_URL, Google Maps: $([ -n "${GOOGLE_MAPS_API_KEY:-}" ] && echo sim || echo nao))"

#!/usr/bin/env bash
# Funções auxiliares de versionamento dos workflows Android e iOS do
# codemagic.yaml (mesma lógica do ilover-mobile). Ver docs/codemagic.md.
#
# Uso:
#   source scripts/ci/version_helpers.sh
#
# Convenção de versão: <MAJOR>.<MINOR>.<N>+<N>, ou <MAJOR>.<MINOR>.<N>-beta+<N>
# com IS_BETA=true
# onde N é sempre o build number (versionCode/CFBundleVersion), nunca um
# valor fixo. Isso garante que o "build name" (versionName /
# CFBundleShortVersionString) também mude a cada build, evitando confusão
# entre versões diferentes com o mesmo nome.

set -u

# as_int VALUE
# Retorna VALUE se for um inteiro não-negativo, senão "0".
as_int() {
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$1"
  else
    printf '0'
  fi
}

# max_int VALUE...
# Retorna o maior valor inteiro entre os argumentos (trata não-inteiros como 0).
max_int() {
  local best=0 n
  for n in "$@"; do
    n=$(as_int "$n")
    if [ "$n" -gt "$best" ]; then
      best="$n"
    fi
  done
  printf '%s' "$best"
}

# get_pubspec_version_line
# Lê a linha "version:" do pubspec.yaml (ex.: "3.0.43-beta+43").
get_pubspec_version_line() {
  grep '^version:' pubspec.yaml | awk '{print $2}'
}

# get_pubspec_build
# Extrai o build number (parte após o "+") do pubspec.yaml.
get_pubspec_build() {
  local version_line
  version_line="$(get_pubspec_version_line)"
  as_int "${version_line##*+}"
}

# get_major_minor
# Extrai "MAJOR.MINOR" a partir do pubspec.yaml, ignorando patch, sufixo
# "-beta" e build number. Ex.: "3.0.43-beta+43" -> "3.0".
get_major_minor() {
  local version_line base major minor
  version_line="$(get_pubspec_version_line)"
  base="${version_line%%+*}"   # remove "+BUILD"
  base="${base%%-*}"           # remove "-beta" (ou qualquer outro sufixo)
  major="$(printf '%s' "$base" | cut -d. -f1)"
  minor="$(printf '%s' "$base" | cut -d. -f2)"
  printf '%s.%s' "${major:-0}" "${minor:-0}"
}

# build_name_for NEW_BUILD_NUMBER [IS_BETA]
# Monta o build name (versionName / CFBundleShortVersionString) no formato
# esperado. IS_BETA (padrão "true") controla o sufixo "-beta".
# Ex.: build_name_for 44 true  -> "3.0.44-beta"
#      build_name_for 44 false -> "3.0.44"
build_name_for() {
  local new_build_number="$1"
  local is_beta="${2:-true}"
  local major_minor
  major_minor="$(get_major_minor)"
  if [ "$is_beta" = "true" ]; then
    printf '%s.%s-beta' "$major_minor" "$new_build_number"
  else
    printf '%s.%s' "$major_minor" "$new_build_number"
  fi
}

# resolve_apple_id BUNDLE_ID
# Resolve o Apple ID numérico (ex.: "1234567890") de um app no App Store
# Connect a partir do seu bundle identifier, usando `app-store-connect apps
# list`. As ações `get-latest-testflight-build-number` e
# `get-latest-app-store-build-number` do CLI exigem esse ID numérico — NÃO
# aceitam o bundle identifier (ex.: "br.com.radarfamiliar"). Passar o
# bundle id diretamente resulta em 404 silencioso, fazendo o cálculo do
# build number ignorar builds já publicados.
# Retorna vazio (string) se não conseguir resolver.
resolve_apple_id() {
  local bundle_id="$1"
  local raw
  raw=$(app-store-connect apps list \
    --bundle-id-identifier "$bundle_id" \
    --strict-match-identifier \
    --json 2>/dev/null || true)
  printf '%s' "$raw" \
    | grep -o '"id"[[:space:]]*:[[:space:]]*"[0-9]*"' \
    | head -n 1 \
    | grep -o '[0-9]*'
}

# validate_build_number NEW_BUILD_NUMBER LATEST_PUBLISHED_BUILD_NUMBER
# Falha explicitamente (exit 1) se o build number calculado não for
# estritamente maior que o maior já publicado em qualquer loja/trilha.
validate_build_number() {
  local new_build_number latest_published
  new_build_number="$(as_int "${1:-0}")"
  latest_published="$(as_int "${2:-0}")"
  if [ "$new_build_number" -le "$latest_published" ]; then
    echo "ERRO: build number calculado ($new_build_number) é menor ou igual ao maior já publicado ($latest_published). Abortando build." >&2
    exit 1
  fi
}

<#
  Liga o provedor Google no Auth de produção (supabase-prod/supabase/config.toml).

  Variáveis nesta sessão (não vão pro git):
    SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID  — OAuth Web, *.apps.googleusercontent.com
    SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET     — GOCSPX-...

  Uso (na raiz do repositório):
    powershell -ExecutionPolicy Bypass -File scripts\supabase\push-prod-google.ps1
#>
param(
  [string] $Ref = 'xccwmeuubelmopifwtpk'
)
$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot)
$workdir = Join-Path $root 'supabase-prod'
$config = [IO.File]::ReadAllText((Join-Path $workdir 'supabase\config.toml'))

if ($config -notmatch '(?m)^\[auth\.external\.google\]') {
  throw 'Bloco [auth.external.google] ausente em supabase-prod/supabase/config.toml.'
}
if ($config -notmatch '(?ms)\[auth\.external\.google\][^\[]*enabled = true') {
  throw '[auth.external.google] deve ter enabled = true.'
}

if (-not $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID) {
  $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID = Read-Host 'Google OAuth Client ID (Web)'
}
if (-not $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET) {
  $s = Read-Host 'Google OAuth Client secret' -AsSecureString
  $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  )
}
if (-not $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_CLIENT_ID -or -not $env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET) {
  throw 'Client ID e secret do Google são obrigatórios.'
}

try {
  supabase config diff --workdir $workdir --remote=$Ref
  if ((Read-Host "Aplicar Google Auth no projeto $Ref? (s/N)") -ne 's') { 'Cancelado.'; return }
  supabase config push --workdir $workdir --remote=$Ref --yes
  if ($LASTEXITCODE -ne 0) { throw "config push falhou (codigo $LASTEXITCODE)." }
} finally {
  Remove-Item Env:SUPABASE_AUTH_EXTERNAL_GOOGLE_SECRET -ErrorAction SilentlyContinue
}

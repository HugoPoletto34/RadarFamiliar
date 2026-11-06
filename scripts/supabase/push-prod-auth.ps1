<#
  Aplica supabase-prod/supabase/config.toml no projeto de producao.

  Etapa 1 (-Etapa smtp):      so o SMTP (sem templates).
  Etapa 2 (-Etapa templates): tudo, incluindo os templates magic_link e confirmation.

  A senha SMTP fica so nesta sessao do PowerShell ($env:SUPABASE_AUTH_SMTP_PASS);
  se nao existir, o script pede com Read-Host. Mostra o diff e pede confirmacao
  antes de cada push.

  Uso (na raiz do repositorio):
    powershell -ExecutionPolicy Bypass -File scripts\supabase\push-prod-auth.ps1 -Etapa smtp
    powershell -ExecutionPolicy Bypass -File scripts\supabase\push-prod-auth.ps1 -Etapa templates
#>
param(
  [Parameter(Mandatory)] [ValidateSet('smtp', 'templates')] [string] $Etapa,
  [string] $Ref = 'xccwmeuubelmopifwtpk'
)
$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot)
$workdir = Join-Path $root 'supabase-prod'
$config = [IO.File]::ReadAllText((Join-Path $workdir 'supabase\config.toml'))

if ($config -notmatch '(?m)^\[auth\.email\.smtp\]') { throw 'Bloco [auth.email.smtp] ausente ou comentado em supabase-prod/supabase/config.toml.' }
if ($config -notmatch '(?m)^pass = "env\(SUPABASE_AUTH_SMTP_PASS\)"') { throw 'Use pass = "env(SUPABASE_AUTH_SMTP_PASS)" no bloco SMTP; a senha nunca vai no arquivo.' }
$admin = [regex]::Match($config, '(?m)^admin_email = "([^"]*)"').Groups[1].Value
if (-not $admin -or $admin -match 'SEU-DOMINIO') { throw 'Preencha admin_email com o remetente verificado no provedor (ex.: nao-responda@seudominio.com.br).' }
if ($admin -match '@(gmail|hotmail|outlook|yahoo|icloud)\.') { throw "admin_email '$admin' e de um provedor gratuito: o Resend/Brevo nao enviam por esse dominio. Use um dominio verificado." }

if (-not $env:SUPABASE_AUTH_SMTP_PASS) {
  $s = Read-Host 'Chave SMTP (API key do Resend ou SMTP key do Brevo)' -AsSecureString
  $env:SUPABASE_AUTH_SMTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}
if (-not $env:SUPABASE_AUTH_SMTP_PASS) { throw 'Chave SMTP vazia.' }

$target = $workdir
if ($Etapa -eq 'smtp') {
  $target = Join-Path ([IO.Path]::GetTempPath()) 'radar-supabase-prod-smtp'
  Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force (Join-Path $target 'supabase') | Out-Null
  $i = $config.IndexOf('[auth.email.template.')
  [IO.File]::WriteAllText((Join-Path $target 'supabase\config.toml'), $(if ($i -ge 0) { $config.Substring(0, $i) } else { $config }))
}

try {
  supabase config diff --workdir $target --remote=$Ref
  if ((Read-Host "Aplicar no projeto $Ref? (s/N)") -ne 's') { 'Cancelado.'; return }
  supabase config push --workdir $target --remote=$Ref --yes
  if ($LASTEXITCODE -ne 0) { throw "config push falhou (codigo $LASTEXITCODE). Veja docs/supabase-prod.md, secao 'Erros comuns'." }
} finally {
  if ($Etapa -eq 'smtp') { Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue }
}

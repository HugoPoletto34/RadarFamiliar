<#
  Cria (ou atualiza) a conta de revisor da App Store no Auth de producao.

  Chave: Supabase Dashboard -> Settings -> API Keys -> **secret** (`sb_secret_...`)
  ou legado **service_role** (JWT que comeca com eyJ). NAO use publishable/anon.

  Uso (na raiz do repositorio):
    $env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."
    $env:APPLE_REVIEWER_PASSWORD = "sua-senha"
    powershell -ExecutionPolicy Bypass -File scripts\supabase\create-apple-reviewer.ps1
#>
param(
  [string] $Ref = 'xccwmeuubelmopifwtpk',
  [string] $Email = 'revisor.apple@radarfamiliar.com',
  [string] $Password,
  [string] $DisplayName = 'Revisor Apple',
  [string] $BirthDate = '1990-01-01'
)
$ErrorActionPreference = 'Stop'

$base = "https://$Ref.supabase.co"
$key = $env:SUPABASE_SERVICE_ROLE_KEY
if (-not $key) {
  throw @'
Defina SUPABASE_SERVICE_ROLE_KEY com a chave SECRET do projeto:
  Dashboard -> Settings -> API Keys -> secret (Reveal) -> sb_secret_...
Ou a legada service_role (JWT eyJ...). NAO use sb_publishable_ nem anon.
'@
}
$key = $key.Trim().Trim('"').Trim("'")

if ($key -match '^sb_publishable_') {
  throw @'
Voce colou a chave PUBLISHABLE (sb_publishable_...) — e a mesma do app/Codemagic (SUPABASE_PUBLISHABLE_KEY).

Para este script, use a chave SECRET:
  1. https://supabase.com/dashboard/project/xccwmeuubelmopifwtpk/settings/api
  2. Aba "API Keys"
  3. Linha "secret" (nao "publishable") -> Reveal -> copiar sb_secret_...
  4. Ou, em "Legacy API Keys", a service_role (JWT eyJ...) se ainda estiver ativa

  $env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."   # troque aqui

Nunca committe nem coloque sb_secret no app.
'@
}

$headers = @{
  apikey         = $key
  'Content-Type' = 'application/json'
}
# Chaves novas (sb_secret_) nao sao JWT: Bearer gera 401. So apikey.
# JWT legado service_role: apikey + Bearer.
if ($key -match '^eyJ') {
  $headers['Authorization'] = "Bearer $key"
} elseif ($key -notmatch '^sb_secret_') {
  Write-Warning 'Formato de chave incomum; tentando so com header apikey.'
}

if (-not $Password) { $Password = $env:APPLE_REVIEWER_PASSWORD }
if (-not $Password) {
  $s = Read-Host "Senha da conta $Email" -AsSecureString
  $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  )
}
if (-not $Password) { throw 'Senha vazia.' }

function Invoke-SupabaseAuth($Method, $Path, $Body) {
  $uri = "$base/auth/v1$Path"
  $params = @{ Method = $Method; Uri = $uri; Headers = $headers }
  if ($null -ne $Body) {
    $params['Body'] = ($Body | ConvertTo-Json -Compress -Depth 5)
  }
  try {
    return Invoke-RestMethod @params
  } catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) {
      throw @"
401 no Authorization: confira a chave SECRET (sb_secret_...) no painel.
Se voce usa sb_secret_, nao defina Authorization manualmente — o script ja trata isso.
Se o projeto so tem chaves novas e POST ainda falhar, crie o usuario no painel:
  Authentication -> Users -> Add user
"@
    }
    throw
  }
}

function Invoke-SupabaseRest($Method, $Path, $Body) {
  $uri = "$base/rest/v1$Path"
  $h = $headers.Clone()
  $h['Prefer'] = 'return=minimal'
  $params = @{ Method = $Method; Uri = $uri; Headers = $h }
  if ($null -ne $Body) {
    $params['Body'] = ($Body | ConvertTo-Json -Compress -Depth 5)
  }
  Invoke-RestMethod @params
}

Write-Host "Procurando usuario $Email..." -ForegroundColor Cyan
$list = Invoke-SupabaseAuth GET '/admin/users?per_page=200' $null
$existing = $list.users | Where-Object { $_.email -eq $Email } | Select-Object -First 1

$userId = $null
if ($existing) {
  $userId = $existing.id
  Write-Host "Usuario ja existe ($userId). Atualizando senha e confirmacao..." -ForegroundColor Yellow
  Invoke-SupabaseAuth PUT "/admin/users/$userId" @{
    password      = $Password
    email_confirm = $true
    user_metadata = @{ full_name = $DisplayName }
  }
} else {
  Write-Host 'Criando usuario...' -ForegroundColor Cyan
  $created = Invoke-SupabaseAuth POST '/admin/users' @{
    email         = $Email
    password      = $Password
    email_confirm = $true
    user_metadata = @{ full_name = $DisplayName }
  }
  $userId = $created.id
}

Write-Host 'Ajustando perfil (data de nascimento para convites)...' -ForegroundColor Cyan
Invoke-SupabaseRest PATCH "/profiles?id=eq.$userId" @{
  display_name = $DisplayName
  birth_date   = $BirthDate
}

Write-Host "Pronto. Revisor: $Email (id=$userId)" -ForegroundColor Green
Write-Host 'Login no app: e-mail e senha (sem codigo OTP).'

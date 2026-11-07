<#
  Cria (ou atualiza) a conta de revisor da App Store no Auth de producao.

  Nunca commite a service_role. Obtenha em:
  Supabase Dashboard -> Settings -> API Keys -> secret (service_role)

  Uso (na raiz do repositorio):
    $env:SUPABASE_SERVICE_ROLE_KEY = "sb_secret_..."   # ou legada service_role JWT
    $env:APPLE_REVIEWER_PASSWORD = "sua-senha"
    powershell -ExecutionPolicy Bypass -File scripts\supabase\create-apple-reviewer.ps1

  Ou informe a senha quando o script pedir.
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
  throw 'Defina SUPABASE_SERVICE_ROLE_KEY (secret do projeto no painel Supabase).'
}
if (-not $Password) {
  $Password = $env:APPLE_REVIEWER_PASSWORD
}
if (-not $Password) {
  $s = Read-Host "Senha da conta $Email" -AsSecureString
  $Password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
  )
}
if (-not $Password) { throw 'Senha vazia.' }

$headers = @{
  apikey        = $key
  Authorization = "Bearer $key"
  'Content-Type' = 'application/json'
}

function Invoke-SupabaseAuth($Method, $Path, $Body) {
  $uri = "$base/auth/v1$Path"
  $json = if ($Body) { $Body | ConvertTo-Json -Compress -Depth 5 } else { $null }
  Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $json
}

function Invoke-SupabaseRest($Method, $Path, $Body) {
  $uri = "$base/rest/v1$Path"
  $json = if ($Body) { $Body | ConvertTo-Json -Compress -Depth 5 } else { $null }
  $h = $headers.Clone()
  $h['Prefer'] = 'return=minimal'
  Invoke-RestMethod -Method $Method -Uri $uri -Headers $h -Body $json
}

Write-Host "Procurando usuario $Email..." -ForegroundColor Cyan
$list = Invoke-SupabaseAuth GET "/admin/users?per_page=200" $null
$existing = $list.users | Where-Object { $_.email -eq $Email } | Select-Object -First 1

$userId = $null
if ($existing) {
  $userId = $existing.id
  Write-Host "Usuario ja existe ($userId). Atualizando senha e confirmacao..." -ForegroundColor Yellow
  Invoke-SupabaseAuth PUT "/admin/users/$userId" @{
    password                 = $Password
    email_confirm            = $true
    user_metadata            = @{ full_name = $DisplayName }
  }
} else {
  Write-Host 'Criando usuario...' -ForegroundColor Cyan
  $created = Invoke-SupabaseAuth POST '/admin/users' @{
    email                    = $Email
    password                 = $Password
    email_confirm            = $true
    user_metadata            = @{ full_name = $DisplayName }
  }
  $userId = $created.id
}

Write-Host 'Ajustando perfil (data de nascimento para convites)...' -ForegroundColor Cyan
Invoke-SupabaseRest PATCH "/profiles?id=eq.$userId" @{
  display_name = $DisplayName
  birth_date   = $BirthDate
}

Write-Host "Pronto. Revisor: $Email (id=$userId)" -ForegroundColor Green
Write-Host 'Login no app: e-mail e senha (sem codigo OTP). Cole essas credenciais nas notas do revisor no App Store Connect.'

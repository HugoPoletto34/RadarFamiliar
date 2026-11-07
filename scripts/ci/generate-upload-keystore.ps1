# Gera o keystore de upload Android fora do git (android/upload-keystore.jks).
# Rode uma vez na sua máquina; depois faça upload no Codemagic como radar_upload.
# Requer JDK (keytool no PATH). Nao commite o .jks.

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$keystorePath = Join-Path $repoRoot 'android\upload-keystore.jks'

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    Write-Error 'keytool nao encontrado no PATH. Instale um JDK e abra um terminal novo.'
}

Write-Host ''
Write-Host 'Geracao do upload keystore (Radar Familiar)' -ForegroundColor Cyan
Write-Host "Destino: $keystorePath"
Write-Host ''

if (Test-Path -LiteralPath $keystorePath) {
    Write-Host 'Ja existe um arquivo nesse caminho.' -ForegroundColor Yellow
    $overwrite = Read-Host 'Sobrescrever? (s/N)'
    if ($overwrite -notmatch '^[sS]') {
        Write-Host 'Cancelado.'
        exit 0
    }
}

$storePassword = Read-Host 'Senha do keystore (store password)'
if ([string]::IsNullOrWhiteSpace($storePassword)) {
    Write-Error 'Senha do keystore nao pode ser vazia.'
}

$keyPassword = Read-Host 'Senha da chave (key password; Enter = mesma do keystore)'
if ([string]::IsNullOrWhiteSpace($keyPassword)) {
    $keyPassword = $storePassword
}

$defaultAlias = 'upload'
$aliasInput = Read-Host "Alias da chave [padrao: $defaultAlias]"
$keyAlias = if ([string]::IsNullOrWhiteSpace($aliasInput)) { $defaultAlias } else { $aliasInput.Trim() }

$defaultCn = 'Radar Familiar'
$cnInput = Read-Host "Nome do certificado (CN) [$defaultCn]"
$cn = if ([string]::IsNullOrWhiteSpace($cnInput)) { $defaultCn } else { $cnInput.Trim() }
$dname = "CN=$cn, OU=Mobile, O=Radar Familiar, L=Sao Paulo, ST=SP, C=BR"

$androidDir = Split-Path -Parent $keystorePath
if (-not (Test-Path -LiteralPath $androidDir)) {
    New-Item -ItemType Directory -Path $androidDir | Out-Null
}

Write-Host ''
Write-Host 'Executando keytool...' -ForegroundColor Cyan

& keytool -genkey -v `
    -keystore $keystorePath `
    -storetype JKS `
    -alias $keyAlias `
    -keyalg RSA `
    -keysize 2048 `
    -validity 10000 `
    -storepass $storePassword `
    -keypass $keyPassword `
    -dname $dname

if ($LASTEXITCODE -ne 0) {
    Write-Error "keytool falhou com codigo $LASTEXITCODE"
}

Write-Host ''
Write-Host 'Keystore criado com sucesso.' -ForegroundColor Green
Write-Host ''
Write-Host 'Proximos passos:' -ForegroundColor Cyan
Write-Host '  1. Faca backup seguro do arquivo .jks e das senhas (o Codemagic nao permite baixar o keystore de volta).'
Write-Host "  2. Arquivo local: $keystorePath"
Write-Host '  3. Codemagic: Teams > codemagic.yaml settings > Code signing identities > Android keystores > Add.'
Write-Host '     Reference name: radar_upload (exatamente, como no codemagic.yaml).'
Write-Host '     Envie este .jks e use o mesmo alias e senhas que voce digitou aqui.'
Write-Host '  4. (Opcional) Para release local, copie os valores para android/key.properties (fora do git).'
Write-Host ''
